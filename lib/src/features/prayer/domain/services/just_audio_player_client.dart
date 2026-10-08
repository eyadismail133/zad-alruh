import 'dart:async';
import 'package:just_audio/just_audio.dart';
import 'adhan_audio_player_client.dart';
import 'adhan_audio_session.dart';
import 'native_prayer_audio_control.dart';

typedef AudioPlayerFactory = AudioPlayer Function();

/// Default production factory producing an [AudioPlayer] with automatic session
/// activation and automatic interruption auto-resumes disabled.
AudioPlayer createDefaultAudioPlayer() {
  return AudioPlayer(
    handleInterruptions: false,
    handleAudioSessionActivation: false,
  );
}

class _ActivePlayback {
  final int generation;
  final String requestToken;
  final AudioPlayer player;
  final List<StreamSubscription<dynamic>> subscriptions = [];
  AdhanPlaybackStatus status = AdhanPlaybackStatus.loading;
  bool isRetired = false;
  bool isStopConfirmed = false;
  bool isDisposeConfirmed = false;
  Duration? duration;
  String? leaseToken;

  _ActivePlayback({
    required this.generation,
    required this.requestToken,
    required this.player,
    this.leaseToken,
  });

  bool get isPlaying => status == AdhanPlaybackStatus.playing;

  void cancelSubscriptions() {
    isRetired = true;
    for (final sub in subscriptions) {
      sub.cancel();
    }
    subscriptions.clear();
  }
}

/// Production implementation of [AdhanAudioPlayerClient] and [OnlineAudioPlayerClient].
///
/// Architecture principles:
/// - Single physical-operation Future queue serializing play/stop/retirement/dispose/session operations.
/// - Synchronous latest intent generation invalidating old logical requests immediately.
/// - Queued physical cleanup barrier: awaits actual old player stop/dispose BEFORE new source.
/// - Unconfirmed/failed stops preserve `_activeOp` barrier to block new playback and keep failure retryable.
/// - Shared session lease tracking: late activation completion cleans up unowned focus when idle
///   and preserves active lease when newer operation is playing.
/// - Operation status tracked explicitly: position and duration listeners preserve actual lifecycle status,
///   never promoting loading/completed/error states to playing.
/// - SDK error messages mapped to stable user-facing Arabic text.
class JustAudioPlayerClient implements AdhanAudioPlayerClient, OnlineAudioPlayerClient {
  final AudioPlayerFactory _playerFactory;
  final AdhanAudioSession _audioSession;
  final NativePrayerAudioControl _nativeAudioControl;
  final bool Function()? _isResetBarrierActive;
  final int Function()? _getResetGeneration;
  final Duration _loadTimeout;
  final Duration _remoteLoadTimeout;
  final Duration _activationTimeout;

  final StreamController<AdhanPlaybackEvent> _eventController =
      StreamController<AdhanPlaybackEvent>.broadcast();

  StreamSubscription<void>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  int _intentGeneration = 0;
  String _latestRequestToken = '';
  bool _isDisposed = false;

  /// The single physical operation Future queue.
  Future<void> _physicalQueue = Future<void>.value();

  /// Currently active playback or unconfirmed unstopped player barrier.
  _ActivePlayback? _activeOp;

  /// Orphan native lease token awaiting retryable confirmed release.
  /// Retained without allocating any SDK player if late cancellation occurs after acquire.
  String? _orphanLeaseToken;

  /// Exposes current orphan lease token for testing and verification.
  String? get orphanLeaseToken => _orphanLeaseToken;

  /// Generation token of the operation holding the active OS audio session lease.
  int _sessionLeaseGeneration = 0;

  JustAudioPlayerClient({
    AudioPlayerFactory? playerFactory,
    AdhanAudioSession? audioSession,
    NativePrayerAudioControl? nativeAudioControl,
    bool Function()? isResetBarrierActive,
    int Function()? getResetGeneration,
    Duration? loadTimeout,
    Duration? remoteLoadTimeout,
    Duration? activationTimeout,
  })  : _playerFactory = playerFactory ?? createDefaultAudioPlayer,
        _audioSession = audioSession ?? DefaultAdhanAudioSession(),
        _nativeAudioControl = nativeAudioControl ?? MethodChannelNativePrayerAudioControl(),
        _isResetBarrierActive = isResetBarrierActive,
        _getResetGeneration = getResetGeneration,
        _loadTimeout = loadTimeout ?? const Duration(seconds: 5),
        _remoteLoadTimeout = remoteLoadTimeout ?? const Duration(seconds: 15),
        _activationTimeout = activationTimeout ?? const Duration(seconds: 3) {
    _interruptionSub = _audioSession.interruptionStream.listen((_) {
      stop().catchError((_) {});
    });
    _noisySub = _audioSession.becomingNoisyStream.listen((_) {
      stop().catchError((_) {});
    });
  }

  bool _isResetCancelled(int? initialResetGen) {
    if (_isResetBarrierActive?.call() == true) return true;
    if (_getResetGeneration != null && initialResetGen != null) {
      if (_getResetGeneration() != initialResetGen) return true;
    }
    return false;
  }

  Future<T> _enqueuePhysicalOp<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _physicalQueue = _physicalQueue.catchError((_) {}).then((_) async {
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  /// Releases [leaseToken] safely on the native boundary.
  /// Returns `true` if released or if [leaseToken] is empty; returns `false` on failure.
  Future<bool> _releaseLeaseSafe(String leaseToken) async {
    if (leaseToken.isEmpty) return true;
    try {
      return await _nativeAudioControl.releaseManualPlaybackLease(
        leaseToken: leaseToken,
      );
    } catch (_) {
      return false;
    }
  }

  /// Drains and releases orphan lease token retained from a late-cancelled start.
  /// Retried through the single physical queue before any new start, in stop, and in dispose.
  /// Throws [StateError] on failure to block new starts and keeps token retryable.
  Future<void> _drainOrphanLease() async {
    final token = _orphanLeaseToken;
    if (token == null) return;
    final released = await _releaseLeaseSafe(token);
    if (!released) {
      throw StateError('تعذر تحرير إذن التشغيل المعلق في النظام');
    }
    if (_orphanLeaseToken == token) {
      _orphanLeaseToken = null;
    }
  }

  /// Smallest shared confirmed retirement and lease cleanup helper reused across:
  /// physical stop, retire, supersession, dispose, and failed startup.
  ///
  /// Invariants:
  /// - Stop failure retains SDK player and native lease in [_activeOp], blocking future starts.
  /// - Successful stop marks [isStopConfirmed = true] and is never repeated on future retries.
  /// - Failed dispose retains the active player, native lease, and barrier in [_activeOp],
  ///   and retries dispose() only.
  /// - Release failure retains retryable token in [_activeOp] even when player is already disposed.
  /// - Stale cleanup can never clear a newer owner's token or state.
  /// - Owner [_activeOp] is cleared ONLY after physical stop, dispose, and lease release succeed.
  Future<void> _cleanupAndRetirePlayback(
    _ActivePlayback op, {
    required bool deactivateSession,
  }) async {
    op.cancelSubscriptions();

    // 1. Physical player stop (skipped on retry if already confirmed)
    if (!op.isStopConfirmed) {
      try {
        await op.player.stop();
        op.isStopConfirmed = true;
      } catch (e) {
        // Physical stop failed: retain op in _activeOp as unconfirmed barrier!
        // Lease remains held on native side.
        if (identical(_activeOp, op) || _activeOp == null) {
          _activeOp = op;
        }
        rethrow;
      }
    }

    // 2. Physical player dispose (retried if previous attempt failed)
    if (!op.isDisposeConfirmed) {
      try {
        await op.player.dispose();
        op.isDisposeConfirmed = true;
      } catch (e) {
        // Dispose failed: retain op in _activeOp as unconfirmed barrier!
        // Stop is already confirmed, so subsequent retries only call dispose().
        if (identical(_activeOp, op) || _activeOp == null) {
          _activeOp = op;
        }
        rethrow;
      }
    }

    // 3. Confirmed native lease release
    if (op.leaseToken != null) {
      final tokenToRelease = op.leaseToken!;
      final released = await _releaseLeaseSafe(tokenToRelease);

      if (!released) {
        // Release failed: retain retryable token and keep op as barrier!
        if (identical(_activeOp, op) || _activeOp == null) {
          _activeOp = op;
        }
        throw StateError('تعذر تحرير إذن التشغيل في النظام');
      }

      // Confirmed release ack: clear token
      if (op.leaseToken == tokenToRelease) {
        op.leaseToken = null;
      }
    }

    // 4. Clear owner only after BOTH physical stop/dispose and lease release succeeded
    if (identical(_activeOp, op)) {
      _activeOp = null;
    }

    // 5. Deactivate session if owned and requested
    if (deactivateSession && _sessionLeaseGeneration == op.generation) {
      _sessionLeaseGeneration = 0;
      try {
        await _audioSession.deactivate();
      } catch (_) {}
    }
  }

  @override
  Stream<AdhanPlaybackEvent> get playbackEventStream => _eventController.stream;

  @override
  Stream<Duration> get positionStream =>
      _eventController.stream.map((e) => e.position);

  @override
  Stream<Duration?> get durationStream =>
      _eventController.stream.map((e) => e.duration);

  @override
  Stream<bool> get playingStream =>
      _eventController.stream.map((e) => e.status == AdhanPlaybackStatus.playing);

  @override
  Stream<bool> get completedStream => _eventController.stream
      .where((e) => e.status == AdhanPlaybackStatus.completed)
      .map((_) => true);

  @override
  Stream<String> get errorStream => _eventController.stream
      .where((e) => e.status == AdhanPlaybackStatus.error && e.errorMessage != null)
      .map((e) => e.errorMessage!);

  @override
  Future<PlaybackStartupResult> playAsset(
    String assetPath, {
    String? requestToken,
  }) {
    if (_isDisposed) {
      return Future.value(PlaybackStartupResult.cancelled);
    }

    final int? initialResetGen = _getResetGeneration?.call();
    if (_isResetBarrierActive?.call() == true) {
      final String fallbackToken = requestToken ?? 'blocked';
      _emitEvent(AdhanPlaybackEvent(
        requestToken: fallbackToken,
        status: AdhanPlaybackStatus.error,
        errorMessage: 'لا يمكن بدء التشغيل أثناء إعادة الضبط',
      ));
      throw StateError('لا يمكن بدء التشغيل أثناء إعادة الضبط');
    }

    // 1. Synchronously claim intent generation and request token
    final int opGen = ++_intentGeneration;
    final String opToken = requestToken ?? 'tok_$opGen';
    _latestRequestToken = opToken;

    // Synchronously emit loading state for this token
    _emitEvent(AdhanPlaybackEvent(
      requestToken: opToken,
      status: AdhanPlaybackStatus.loading,
    ));

    return _enqueuePhysicalOp<PlaybackStartupResult>(() async {
      // 2. Check cancellation before queue execution begins
      if (_isDisposed || _intentGeneration != opGen || _isResetCancelled(initialResetGen)) {
        return PlaybackStartupResult.cancelled;
      }

      // 3. Physical cleanup barrier: await stop & dispose of old player and release lease
      if (_activeOp != null) {
        final oldOp = _activeOp!;
        try {
          await _cleanupAndRetirePlayback(oldOp, deactivateSession: false);
        } catch (e) {
          // Preserve failed player/lease in _activeOp barrier: blocks new play and remains retryable!
          _emitEvent(AdhanPlaybackEvent(
            requestToken: oldOp.requestToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر إيقاف التشغيل السابق',
          ));
          rethrow;
        }

        // If old op held session lease and this request was cancelled during stop:
        if ((_intentGeneration != opGen || _isResetCancelled(initialResetGen)) &&
            _sessionLeaseGeneration == oldOp.generation) {
          _sessionLeaseGeneration = 0;
          try {
            await _audioSession.deactivate();
          } catch (_) {}
          return PlaybackStartupResult.cancelled;
        }
      }

      // Retry matching orphan release via SAME physical queue before any new acquire/start
      await _drainOrphanLease();

      // 4. Recheck intent after awaiting old player cleanup and orphan release
      if (_isDisposed || _intentGeneration != opGen || _isResetCancelled(initialResetGen)) {
        if (_sessionLeaseGeneration != 0 && _activeOp == null) {
          _sessionLeaseGeneration = 0;
          try {
            await _audioSession.deactivate();
          } catch (_) {}
        }
        return PlaybackStartupResult.cancelled;
      }

      // 4b. Acquire CONFIRMED native manual playback lease BEFORE OS session activation/physical start
      final String leaseReqId = generateUniqueLeaseRequestId();
      final leaseResult = await _nativeAudioControl.acquireManualPlaybackLease(
        requestId: leaseReqId,
      );
      if (!leaseResult.acquired ||
          leaseResult.leaseToken == null ||
          leaseResult.leaseToken!.isEmpty) {
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          final errorMsg = leaseResult.errorMessageAr ??
              'تعذر الحصول على إذن التشغيل من النظام لوجود تشغيل نشط آخر';
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: errorMsg,
          ));
          throw StateError(errorMsg);
        }
        return PlaybackStartupResult.cancelled;
      }

      final acquiredLeaseToken = leaseResult.leaseToken!;

      // Recheck cancellation after acquire
      if (_isDisposed || _intentGeneration != opGen || _isResetCancelled(initialResetGen)) {
        final released = await _releaseLeaseSafe(acquiredLeaseToken);
        if (!released) {
          _orphanLeaseToken = acquiredLeaseToken;
        }
        return PlaybackStartupResult.cancelled;
      }

      // 5. Allocate fresh AudioPlayer
      final freshPlayer = _playerFactory();
      final op = _ActivePlayback(
        generation: opGen,
        requestToken: opToken,
        player: freshPlayer,
        leaseToken: acquiredLeaseToken,
      );
      _activeOp = op;

      // 6. Attach event listeners capturing op, opGen, opToken
      // Position update preserves current lifecycle status; completion/error/loading cannot become playing!
      op.subscriptions.add(freshPlayer.positionStream.listen((pos) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed) return;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: op.status,
          position: pos,
          duration: op.duration,
        ));
      }));

      // Duration update preserves current lifecycle status
      op.subscriptions.add(freshPlayer.durationStream.listen((dur) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed || dur == null) return;
        op.duration = dur;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: op.status,
          position: Duration.zero,
          duration: dur,
        ));
      }));

      op.subscriptions.add(freshPlayer.playerStateStream.listen((state) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed) return;
        if (state.processingState == ProcessingState.completed) {
          op.status = AdhanPlaybackStatus.completed;
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.completed,
            position: Duration.zero,
            duration: op.duration,
          ));
          if (op.leaseToken != null) {
            final tokenToRelease = op.leaseToken!;
            _enqueuePhysicalOp<void>(() async {
              if (op.isRetired || _activeOp != op || op.leaseToken != tokenToRelease) return;
              final released = await _releaseLeaseSafe(tokenToRelease);
              if (released && _activeOp == op && op.leaseToken == tokenToRelease) {
                op.leaseToken = null;
              }
              if (_sessionLeaseGeneration == opGen) {
                _sessionLeaseGeneration = 0;
                try {
                  await _audioSession.deactivate();
                } catch (_) {}
              }
            });
          }
        }
      }));

      // Map SDK errors to stable Arabic text; no raw err.message leaked directly to UI
      op.subscriptions.add(freshPlayer.errorStream.listen((_) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed) return;
        op.status = AdhanPlaybackStatus.error;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: AdhanPlaybackStatus.error,
          errorMessage: 'خطأ أثناء تشغيل التسجيل الصوتي',
        ));
      }));

      // 7. Bounded asset load
      try {
        await freshPlayer.setAsset(assetPath).timeout(_loadTimeout);
      } catch (e) {
        await _retireOp(op, deactivateSession: false);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر تحميل التسجيل الصوتي',
          ));
          rethrow;
        }
        return PlaybackStartupResult.cancelled;
      }

      // Recheck cancellation after asset load
      if (op.isRetired || _intentGeneration != opGen || _isDisposed || _isResetCancelled(initialResetGen)) {
        await _retireOp(op, deactivateSession: false);
        return PlaybackStartupResult.cancelled;
      }

      // 8. Explicit OS Audio Session Activation BEFORE calling play
      final activateFuture = _audioSession.activate();
      bool granted = false;
      try {
        granted = await activateFuture.timeout(_activationTimeout);
      } catch (e) {
        // Abandoned activation Future tracking: schedule serialized idle cleanup when it completes late
        unawaited(
          activateFuture.then((lateGranted) {
            if (lateGranted) {
              _enqueuePhysicalOp<void>(() async {
                // If focus was granted late while system is idle with no active playback or newer lease:
                if (_activeOp == null && _sessionLeaseGeneration == 0) {
                  try {
                    await _audioSession.deactivate();
                  } catch (_) {}
                }
              });
            }
          }).catchError((_) {}),
        );

        await _retireOp(op, deactivateSession: false);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر تفعيل الجلسة الصوتية في النظام',
          ));
          throw StateError('تعذر تفعيل الجلسة الصوتية في النظام');
        }
        return PlaybackStartupResult.cancelled;
      }

      if (!granted) {
        await _retireOp(op, deactivateSession: false);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تم رفض تفعيل الجلسة الصوتية من النظام',
          ));
          throw StateError('تم رفض تفعيل الجلسة الصوتية من النظام');
        }
        return PlaybackStartupResult.cancelled;
      }

      // Successfully activated: claim session lease
      _sessionLeaseGeneration = opGen;

      // Final cancellation check before physical play
      if (op.isRetired || _intentGeneration != opGen || _isDisposed || _isResetCancelled(initialResetGen)) {
        await _retireOp(op, deactivateSession: true);
        return PlaybackStartupResult.cancelled;
      }

      // 9. Physical play invocation
      try {
        final playFuture = freshPlayer.play();
        unawaited(
          playFuture.catchError((Object err) {
            if (!op.isRetired &&
                _intentGeneration == opGen &&
                !_isDisposed &&
                _activeOp == op) {
              op.status = AdhanPlaybackStatus.error;
              _emitEvent(AdhanPlaybackEvent(
                requestToken: opToken,
                status: AdhanPlaybackStatus.error,
                errorMessage: 'خطأ أثناء تشغيل التسجيل الصوتي',
              ));
            }
          }),
        );
        op.status = AdhanPlaybackStatus.playing;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: AdhanPlaybackStatus.playing,
          duration: op.duration,
        ));
        return PlaybackStartupResult.started;
      } catch (e) {
        await _retireOp(op, deactivateSession: true);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر بدء تشغيل التسجيل الصوتي',
          ));
          rethrow;
        }
        return PlaybackStartupResult.cancelled;
      }
    });
  }

  @override
  Future<PlaybackStartupResult> playUrl(
    String url, {
    String? requestToken,
  }) {
    if (_isDisposed) {
      return Future.value(PlaybackStartupResult.cancelled);
    }

    final int? initialResetGen = _getResetGeneration?.call();
    if (_isResetBarrierActive?.call() == true) {
      final String fallbackToken = requestToken ?? 'blocked';
      _emitEvent(AdhanPlaybackEvent(
        requestToken: fallbackToken,
        status: AdhanPlaybackStatus.error,
        errorMessage: 'لا يمكن بدء التشغيل أثناء إعادة الضبط',
      ));
      throw StateError('لا يمكن بدء التشغيل أثناء إعادة الضبط');
    }

    // 1. Synchronously claim intent generation and request token
    final int opGen = ++_intentGeneration;
    final String opToken = requestToken ?? 'url_$opGen';
    _latestRequestToken = opToken;

    // Synchronously emit loading state for this token
    _emitEvent(AdhanPlaybackEvent(
      requestToken: opToken,
      status: AdhanPlaybackStatus.loading,
    ));

    return _enqueuePhysicalOp<PlaybackStartupResult>(() async {
      // 2. Check cancellation before queue execution begins
      if (_isDisposed || _intentGeneration != opGen || _isResetCancelled(initialResetGen)) {
        return PlaybackStartupResult.cancelled;
      }

      // 3. Physical cleanup barrier: await stop & dispose of old player and release lease
      if (_activeOp != null) {
        final oldOp = _activeOp!;
        try {
          await _cleanupAndRetirePlayback(oldOp, deactivateSession: false);
        } catch (e) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: oldOp.requestToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر إيقاف التشغيل السابق',
          ));
          rethrow;
        }

        if ((_intentGeneration != opGen || _isResetCancelled(initialResetGen)) &&
            _sessionLeaseGeneration == oldOp.generation) {
          _sessionLeaseGeneration = 0;
          try {
            await _audioSession.deactivate();
          } catch (_) {}
          return PlaybackStartupResult.cancelled;
        }
      }

      // Retry matching orphan release via SAME physical queue before any new acquire/start
      await _drainOrphanLease();

      // 4. Recheck intent after awaiting old player cleanup and orphan release
      if (_isDisposed || _intentGeneration != opGen || _isResetCancelled(initialResetGen)) {
        if (_sessionLeaseGeneration != 0 && _activeOp == null) {
          _sessionLeaseGeneration = 0;
          try {
            await _audioSession.deactivate();
          } catch (_) {}
        }
        return PlaybackStartupResult.cancelled;
      }

      // 4b. Acquire CONFIRMED native manual playback lease BEFORE OS session activation/physical start
      final String leaseReqId = generateUniqueLeaseRequestId();
      final leaseResult = await _nativeAudioControl.acquireManualPlaybackLease(
        requestId: leaseReqId,
      );
      if (!leaseResult.acquired ||
          leaseResult.leaseToken == null ||
          leaseResult.leaseToken!.isEmpty) {
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          final errorMsg = leaseResult.errorMessageAr ??
              'تعذر الحصول على إذن التشغيل من النظام لوجود تشغيل نشط آخر';
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: errorMsg,
          ));
          throw StateError(errorMsg);
        }
        return PlaybackStartupResult.cancelled;
      }

      final acquiredLeaseToken = leaseResult.leaseToken!;

      // Recheck cancellation after acquire
      if (_isDisposed || _intentGeneration != opGen || _isResetCancelled(initialResetGen)) {
        final released = await _releaseLeaseSafe(acquiredLeaseToken);
        if (!released) {
          _orphanLeaseToken = acquiredLeaseToken;
        }
        return PlaybackStartupResult.cancelled;
      }

      // 5. Allocate fresh AudioPlayer
      final freshPlayer = _playerFactory();
      final op = _ActivePlayback(
        generation: opGen,
        requestToken: opToken,
        player: freshPlayer,
        leaseToken: acquiredLeaseToken,
      );
      _activeOp = op;

      // 6. Attach event listeners capturing op, opGen, opToken
      op.subscriptions.add(freshPlayer.positionStream.listen((pos) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed) return;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: op.status,
          position: pos,
          duration: op.duration,
        ));
      }));

      op.subscriptions.add(freshPlayer.durationStream.listen((dur) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed || dur == null) return;
        op.duration = dur;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: op.status,
          position: Duration.zero,
          duration: dur,
        ));
      }));

      op.subscriptions.add(freshPlayer.playerStateStream.listen((state) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed) return;
        if (state.processingState == ProcessingState.completed) {
          op.status = AdhanPlaybackStatus.completed;
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.completed,
            position: Duration.zero,
            duration: op.duration,
          ));
          if (op.leaseToken != null) {
            final tokenToRelease = op.leaseToken!;
            _enqueuePhysicalOp<void>(() async {
              if (op.isRetired || _activeOp != op || op.leaseToken != tokenToRelease) return;
              final released = await _releaseLeaseSafe(tokenToRelease);
              if (released && _activeOp == op && op.leaseToken == tokenToRelease) {
                op.leaseToken = null;
              }
              if (_sessionLeaseGeneration == opGen) {
                _sessionLeaseGeneration = 0;
                try {
                  await _audioSession.deactivate();
                } catch (_) {}
              }
            });
          }
        } else if (state.processingState == ProcessingState.buffering &&
            op.status != AdhanPlaybackStatus.completed &&
            op.status != AdhanPlaybackStatus.error) {
          op.status = AdhanPlaybackStatus.buffering;
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.buffering,
            duration: op.duration,
          ));
        } else if (state.processingState == ProcessingState.ready &&
            op.status != AdhanPlaybackStatus.completed &&
            op.status != AdhanPlaybackStatus.error) {
          if (state.playing && op.status != AdhanPlaybackStatus.playing) {
            op.status = AdhanPlaybackStatus.playing;
            _emitEvent(AdhanPlaybackEvent(
              requestToken: opToken,
              status: AdhanPlaybackStatus.playing,
              duration: op.duration,
            ));
          } else if (!state.playing &&
              (op.status == AdhanPlaybackStatus.playing ||
                  op.status == AdhanPlaybackStatus.buffering)) {
            op.status = AdhanPlaybackStatus.paused;
            _emitEvent(AdhanPlaybackEvent(
              requestToken: opToken,
              status: AdhanPlaybackStatus.paused,
              duration: op.duration,
            ));
          }
        }
      }));

      op.subscriptions.add(freshPlayer.errorStream.listen((_) {
        if (op.isRetired || _intentGeneration != opGen || _isDisposed) return;
        op.status = AdhanPlaybackStatus.error;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: AdhanPlaybackStatus.error,
          errorMessage: 'خطأ أثناء تشغيل التسجيل الصوتي',
        ));
      }));

      // 7. Bounded remote URL load
      try {
        await freshPlayer.setUrl(url).timeout(_remoteLoadTimeout);
      } catch (e) {
        await _retireOp(op, deactivateSession: false);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر تحميل التلاوة. يرجى التحقق من الاتصال بالإنترنت والمحاولة مجدداً.',
          ));
          rethrow;
        }
        return PlaybackStartupResult.cancelled;
      }

      // Recheck cancellation after remote load
      if (op.isRetired || _intentGeneration != opGen || _isDisposed || _isResetCancelled(initialResetGen)) {
        await _retireOp(op, deactivateSession: false);
        return PlaybackStartupResult.cancelled;
      }

      // 8. Explicit OS Audio Session Activation BEFORE calling play
      final activateFuture = _audioSession.activate();
      bool granted = false;
      try {
        granted = await activateFuture.timeout(_activationTimeout);
      } catch (e) {
        unawaited(
          activateFuture.then((lateGranted) {
            if (lateGranted) {
              _enqueuePhysicalOp<void>(() async {
                if (_activeOp == null && _sessionLeaseGeneration == 0) {
                  try {
                    await _audioSession.deactivate();
                  } catch (_) {}
                }
              });
            }
          }).catchError((_) {}),
        );

        await _retireOp(op, deactivateSession: false);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر تفعيل الجلسة الصوتية في النظام',
          ));
          throw StateError('تعذر تفعيل الجلسة الصوتية في النظام');
        }
        return PlaybackStartupResult.cancelled;
      }

      if (!granted) {
        await _retireOp(op, deactivateSession: false);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تم رفض تفعيل الجلسة الصوتية من النظام',
          ));
          throw StateError('تم رفض تفعيل الجلسة الصوتية من النظام');
        }
        return PlaybackStartupResult.cancelled;
      }

      // Successfully activated: claim session lease
      _sessionLeaseGeneration = opGen;

      // Final cancellation check before physical play
      if (op.isRetired || _intentGeneration != opGen || _isDisposed || _isResetCancelled(initialResetGen)) {
        await _retireOp(op, deactivateSession: true);
        return PlaybackStartupResult.cancelled;
      }

      // 9. Physical play invocation (do not await completion!)
      try {
        final playFuture = freshPlayer.play();
        unawaited(
          playFuture.catchError((Object err) {
            if (!op.isRetired &&
                _intentGeneration == opGen &&
                !_isDisposed &&
                _activeOp == op) {
              op.status = AdhanPlaybackStatus.error;
              _emitEvent(AdhanPlaybackEvent(
                requestToken: opToken,
                status: AdhanPlaybackStatus.error,
                errorMessage: 'خطأ أثناء تشغيل التسجيل الصوتي',
              ));
            }
          }),
        );
        op.status = AdhanPlaybackStatus.playing;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: AdhanPlaybackStatus.playing,
          duration: op.duration,
        ));
        return PlaybackStartupResult.started;
      } catch (e) {
        await _retireOp(op, deactivateSession: true);
        if (_intentGeneration == opGen && !_isDisposed && !_isResetCancelled(initialResetGen)) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر بدء تشغيل التسجيل الصوتي',
          ));
          rethrow;
        }
        return PlaybackStartupResult.cancelled;
      }
    });
  }

  @override
  Future<bool> pause({String? requestToken}) {
    final targetOp = _activeOp;
    if (targetOp == null) {
      return Future.value(false);
    }
    final targetGen = _intentGeneration;
    final targetToken = requestToken ?? targetOp.requestToken;
    final op = targetOp;

    return _enqueuePhysicalOp<bool>(() async {
      // Check BEFORE await:
      if (_isDisposed ||
          _activeOp == null ||
          _activeOp != op ||
          _intentGeneration != targetGen ||
          op.isRetired ||
          op.requestToken != targetToken ||
          (!op.isPlaying && op.status != AdhanPlaybackStatus.buffering)) {
        return false;
      }

      try {
        await op.player.pause();
        // Check AFTER await:
        if (_isDisposed ||
            _activeOp != op ||
            _intentGeneration != targetGen ||
            op.isRetired) {
          return false;
        }

        // Deactivate manual session/focus appropriately:
        if (_sessionLeaseGeneration == op.generation) {
          _sessionLeaseGeneration = 0;
          try {
            await _audioSession.deactivate();
          } catch (_) {}
        }

        // Release matching manual lease so future Athans are not silenced:
        if (op.leaseToken != null) {
          final tokenToRelease = op.leaseToken!;
          try {
            final released =
                await _nativeAudioControl.releaseManualPlaybackLease(
              leaseToken: tokenToRelease,
            );
            if (released) {
              op.leaseToken = null;
            } else {
              _emitEvent(AdhanPlaybackEvent(
                requestToken: op.requestToken,
                status: AdhanPlaybackStatus.error,
                errorMessage:
                    'تعذر تحرير الإذن الصوتي في النظام عند الإيقاف المؤقت',
              ));
              throw StateError(
                  'تعذر تحرير الإذن الصوتي في النظام عند الإيقاف المؤقت');
            }
          } catch (e) {
            if (e is StateError) rethrow;
            _emitEvent(AdhanPlaybackEvent(
              requestToken: op.requestToken,
              status: AdhanPlaybackStatus.error,
              errorMessage:
                  'تعذر تحرير الإذن الصوتي في النظام عند الإيقاف المؤقت',
            ));
            throw StateError(
                'تعذر تحرير الإذن الصوتي في النظام عند الإيقاف المؤقت');
          }
        }

        op.status = AdhanPlaybackStatus.paused;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: op.requestToken,
          status: AdhanPlaybackStatus.paused,
          position: op.player.position,
          duration: op.duration,
        ));
        return true;
      } catch (e) {
        if (!_isDisposed &&
            _activeOp == op &&
            _intentGeneration == targetGen &&
            !op.isRetired) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: op.requestToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر إيقاف التشغيل مؤقتاً',
          ));
        }
        rethrow;
      }
    });
  }

  @override
  Future<bool> resume({String? requestToken}) {
    final targetOp = _activeOp;
    if (targetOp == null) {
      return Future.value(false);
    }
    final int? initialResetGen = _getResetGeneration?.call();
    if (_isResetBarrierActive?.call() == true) {
      return Future.value(false);
    }
    final targetGen = _intentGeneration;
    final targetToken = requestToken ?? targetOp.requestToken;
    final op = targetOp;
    final opGen = targetGen;
    final opToken = op.requestToken;

    return _enqueuePhysicalOp<bool>(() async {
      // Check BEFORE await:
      if (_isDisposed ||
          _activeOp != op ||
          _intentGeneration != targetGen ||
          op.isRetired ||
          op.requestToken != targetToken ||
          op.status != AdhanPlaybackStatus.paused ||
          _isResetCancelled(initialResetGen)) {
        return false;
      }

      // Retry matching orphan release via SAME physical queue before re-acquire
      await _drainOrphanLease();

      // Re-acquire CONFIRMED native lease BEFORE session activation / physical resume
      final String leaseReqId = generateUniqueLeaseRequestId();
      final leaseResult = await _nativeAudioControl.acquireManualPlaybackLease(
        requestId: leaseReqId,
      );
      if (!leaseResult.acquired ||
          leaseResult.leaseToken == null ||
          leaseResult.leaseToken!.isEmpty) {
        if (!_isDisposed &&
            _activeOp == op &&
            _intentGeneration == opGen &&
            !op.isRetired &&
            !_isResetCancelled(initialResetGen)) {
          op.status = AdhanPlaybackStatus.error;
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: leaseResult.errorMessageAr ??
                'تعذر استئناف التشغيل لوجود تشغيل نشط آخر في النظام',
          ));
        }
        return false;
      }

      final acquiredLeaseToken = leaseResult.leaseToken!;

      if (_isDisposed ||
          _activeOp != op ||
          _intentGeneration != targetGen ||
          op.isRetired ||
          _isResetCancelled(initialResetGen)) {
        final released = await _releaseLeaseSafe(acquiredLeaseToken);
        if (!released && op.leaseToken == null) {
          op.leaseToken = acquiredLeaseToken;
        }
        return false;
      }

      op.leaseToken = acquiredLeaseToken;

      // Session activation
      bool granted = false;
      try {
        granted = await _audioSession.activate().timeout(
          _activationTimeout,
          onTimeout: () => false,
        );
      } catch (_) {
        granted = false;
      }

      if (_isDisposed ||
          _activeOp != op ||
          _intentGeneration != targetGen ||
          op.isRetired ||
          _isResetCancelled(initialResetGen) ||
          !granted) {
        if (op.leaseToken != null) {
          final t = op.leaseToken!;
          final released = await _releaseLeaseSafe(t);
          if (released && op.leaseToken == t) {
            op.leaseToken = null;
          }
        }
        if (!_isDisposed &&
            _activeOp == op &&
            _intentGeneration == opGen &&
            !op.isRetired &&
            !_isResetCancelled(initialResetGen)) {
          op.status = AdhanPlaybackStatus.error;
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage:
                'تعذر تفعيل الجلسة الصوتية في النظام لاستئناف التشغيل',
          ));
        }
        return false;
      }

      _sessionLeaseGeneration = opGen;

      if (_isDisposed ||
          _activeOp != op ||
          _intentGeneration != targetGen ||
          op.isRetired ||
          _isResetCancelled(initialResetGen)) {
        if (op.leaseToken != null) {
          final t = op.leaseToken!;
          final released = await _releaseLeaseSafe(t);
          if (released && op.leaseToken == t) {
            op.leaseToken = null;
          }
        }
        return false;
      }

      try {
        final playFuture = op.player.play();
        unawaited(
          playFuture.catchError((Object err) {
            // Sol Finding 1: Capture invocation operation/requestToken/generation,
            // reject retired/superseded/disposed callback!
            if (!_isDisposed &&
                _activeOp == op &&
                _intentGeneration == opGen &&
                !op.isRetired) {
              op.status = AdhanPlaybackStatus.error;
              _emitEvent(AdhanPlaybackEvent(
                requestToken: opToken,
                status: AdhanPlaybackStatus.error,
                errorMessage: 'خطأ أثناء استئناف التشغيل',
              ));
            }
          }),
        );

        // Check AFTER calling play:
        if (_isDisposed ||
            _activeOp != op ||
            _intentGeneration != opGen ||
            op.isRetired ||
            _isResetCancelled(initialResetGen)) {
          return false;
        }

        op.status = AdhanPlaybackStatus.playing;
        _emitEvent(AdhanPlaybackEvent(
          requestToken: opToken,
          status: AdhanPlaybackStatus.playing,
          position: op.player.position,
          duration: op.duration,
        ));
        return true;
      } catch (e) {
        if (op.leaseToken != null) {
          final t = op.leaseToken!;
          final released = await _releaseLeaseSafe(t);
          if (released && op.leaseToken == t) {
            op.leaseToken = null;
          }
        }
        if (!_isDisposed &&
            _activeOp == op &&
            _intentGeneration == opGen &&
            !op.isRetired) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: opToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر استئناف التشغيل',
          ));
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> seek(Duration position, {String? requestToken}) {
    final targetOp = _activeOp;
    if (targetOp == null) {
      return Future.value();
    }
    final targetGen = _intentGeneration;
    final targetToken = requestToken ?? targetOp.requestToken;
    final op = targetOp;

    return _enqueuePhysicalOp<void>(() async {
      if (_isDisposed ||
          _activeOp == null ||
          _activeOp != op ||
          _intentGeneration != targetGen ||
          op.isRetired ||
          op.requestToken != targetToken) {
        return;
      }
      try {
        await op.player.seek(position);
      } catch (_) {}
    });
  }

  @override
  Future<void> stop() {
    // 1. Synchronously invalidate any in-flight load/activation
    final int opGen = ++_intentGeneration;
    final String currentToken = _latestRequestToken;

    return _enqueuePhysicalOp<void>(() async {
      if (_activeOp != null) {
        final active = _activeOp!;
        try {
          await _cleanupAndRetirePlayback(active, deactivateSession: true);
        } catch (e) {
          _emitEvent(AdhanPlaybackEvent(
            requestToken: active.requestToken,
            status: AdhanPlaybackStatus.error,
            errorMessage: 'تعذر إيقاف التشغيل الصوتي',
          ));
          // Preserve active player in _activeOp as unconfirmed barrier for retry!
          rethrow;
        }
      }

      // Retry matching orphan release via SAME physical queue
      await _drainOrphanLease();

      // Deactivate session if owned and no newer intent needs it
      if (_sessionLeaseGeneration != 0 && (_activeOp == null || _intentGeneration == opGen)) {
        _sessionLeaseGeneration = 0;
        await _audioSession.deactivate();
      }

      if (_intentGeneration == opGen) {
        _emitEvent(AdhanPlaybackEvent(
          requestToken: currentToken,
          status: AdhanPlaybackStatus.stopped,
          position: Duration.zero,
        ));
      }
    });
  }

  Future<void> _retireOp(_ActivePlayback op, {required bool deactivateSession}) {
    return _cleanupAndRetirePlayback(op, deactivateSession: deactivateSession);
  }

  void _emitEvent(AdhanPlaybackEvent event) {
    if (!_isDisposed && !_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    ++_intentGeneration;

    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _noisySub?.cancel();
    _noisySub = null;

    await _enqueuePhysicalOp<void>(() async {
      if (_activeOp != null) {
        final active = _activeOp!;
        // Do not swallow cleanup failures; if physical stop/dispose fails,
        // it throws, preventing session mutation/disposal below and retaining native suppression!
        await _cleanupAndRetirePlayback(active, deactivateSession: true);
      }

      // Retry matching orphan release via SAME physical queue
      await _drainOrphanLease();

      if (_sessionLeaseGeneration != 0) {
        _sessionLeaseGeneration = 0;
        try {
          await _audioSession.deactivate();
        } catch (_) {}
      }
      try {
        await _audioSession.dispose();
      } catch (_) {}
    });

    if (!_eventController.isClosed) {
      await _eventController.close();
    }
  }
}
