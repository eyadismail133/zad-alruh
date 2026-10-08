import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/services/native_alarm_reset_boundary.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/adhan_voice.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_session.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/just_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/native_prayer_audio_control.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/adhan_audio_controller.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/domain/models/quran_audio_source.dart';

// =============================================================================
// Test Doubles
// =============================================================================

class MockAudioPlayer extends Fake implements AudioPlayer {
  final _positionSubject = StreamController<Duration>.broadcast();
  final _durationSubject = StreamController<Duration?>.broadcast();
  final _playingSubject = StreamController<bool>.broadcast();
  final _playerStateSubject = StreamController<PlayerState>.broadcast();
  final _errorSubject = StreamController<PlayerException>.broadcast();
  final _playbackEventSubject = StreamController<PlaybackEvent>.broadcast();

  String? currentUrl;
  String? currentAsset;
  bool isPlaying = false;
  bool isCompleted = false;
  bool isDisposed = false;

  int playCallCount = 0;
  int stopCallCount = 0;
  int pauseCallCount = 0;
  int seekCallCount = 0;
  int setUrlCallCount = 0;
  int setAssetCallCount = 0;
  int disposeCallCount = 0;

  Completer<void>? setUrlEnteredCompleter;
  Completer<void>? setUrlGateCompleter;
  Completer<void>? playEnteredCompleter;
  Completer<void>? playGateCompleter;

  bool throwOnSetUrl = false;
  bool throwOnSetAsset = false;
  bool throwOnPlay = false;
  bool throwOnStop = false;
  bool throwOnDispose = false;

  @override
  Stream<Duration> get positionStream => _positionSubject.stream;

  @override
  Stream<Duration?> get durationStream => _durationSubject.stream;

  @override
  Stream<bool> get playingStream => _playingSubject.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateSubject.stream;

  @override
  Stream<PlayerException> get errorStream => _errorSubject.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _playbackEventSubject.stream;

  @override
  bool get playing => isPlaying;

  @override
  ProcessingState get processingState => isCompleted
      ? ProcessingState.completed
      : (isPlaying ? ProcessingState.ready : ProcessingState.idle);

  @override
  Duration get position => Duration.zero;

  @override
  Duration? get duration => const Duration(minutes: 5);

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    setUrlCallCount++;
    currentUrl = url;
    setUrlEnteredCompleter?.complete();
    if (setUrlGateCompleter != null) {
      await setUrlGateCompleter!.future;
    }
    if (throwOnSetUrl) {
      throw Exception('Simulated setUrl network failure');
    }
    _durationSubject.add(const Duration(minutes: 5));
    _playerStateSubject.add(PlayerState(false, ProcessingState.ready));
    return const Duration(minutes: 5);
  }

  @override
  Future<Duration?> setAsset(
    String asset, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async {
    setAssetCallCount++;
    currentAsset = asset;
    if (throwOnSetAsset) {
      throw Exception('Simulated setAsset load failure');
    }
    _durationSubject.add(const Duration(seconds: 120));
    _playerStateSubject.add(PlayerState(false, ProcessingState.ready));
    return const Duration(seconds: 120);
  }

  @override
  Future<void> play() async {
    playCallCount++;
    playEnteredCompleter?.complete();
    if (playGateCompleter != null) {
      await playGateCompleter!.future;
    }
    if (throwOnPlay) {
      isPlaying = false;
      _playingSubject.add(false);
      _playerStateSubject.add(PlayerState(false, ProcessingState.idle));
      throw Exception('Simulated play execution failure');
    }
    isPlaying = true;
    _playingSubject.add(true);
    _playerStateSubject.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    isPlaying = false;
    _playingSubject.add(false);
    _playerStateSubject.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (throwOnStop) {
      throw Exception('Simulated stop execution failure');
    }
    isPlaying = false;
    _playingSubject.add(false);
    _playerStateSubject.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCallCount++;
    if (position != null) {
      _positionSubject.add(position);
    }
  }

  void completeNaturally() {
    isPlaying = false;
    isCompleted = true;
    _playingSubject.add(false);
    _playerStateSubject.add(PlayerState(false, ProcessingState.completed));
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    if (throwOnDispose) {
      throw Exception('Simulated dispose failure');
    }
    isDisposed = true;
    try {
      await stop();
    } catch (_) {}
    await _positionSubject.close();
    await _durationSubject.close();
    await _playingSubject.close();
    await _playerStateSubject.close();
    await _errorSubject.close();
    await _playbackEventSubject.close();
  }
}

class FakeAdhanAudioSession implements AdhanAudioSession {
  final _interruptionController = StreamController<void>.broadcast();
  final _noisyController = StreamController<void>.broadcast();

  bool isActivated = false;
  bool isDeactivated = false;
  bool simulateActivationDenial = false;
  int activateCallCount = 0;
  int deactivateCallCount = 0;

  @override
  Stream<void> get interruptionStream => _interruptionController.stream;

  @override
  Stream<void> get becomingNoisyStream => _noisyController.stream;

  @override
  Future<bool> activate() async {
    activateCallCount++;
    if (simulateActivationDenial) return false;
    isActivated = true;
    return true;
  }

  @override
  Future<void> deactivate() async {
    deactivateCallCount++;
    isActivated = false;
    isDeactivated = true;
  }

  @override
  Future<void> dispose() async {
    await _interruptionController.close();
    await _noisyController.close();
  }
}

class FakeNativePrayerAudioControl implements NativePrayerAudioControl {
  bool nextStopResult = true;
  int stopCallCount = 0;

  bool nextAcquireResult = true;
  int acquireCallCount = 0;
  final List<String> acquiredRequestIds = [];
  String? activeLeaseToken;
  String? errorMessageAr;
  void Function(String requestId)? onAcquire;

  bool nextReleaseResult = true;
  int releaseCallCount = 0;
  final List<String> releasedTokens = [];
  Completer<void>? releaseEnteredCompleter;
  Completer<void>? releaseGateCompleter;
  void Function(String leaseToken)? onRelease;

  @override
  Future<bool> stopActivePlayback() async {
    stopCallCount++;
    return nextStopResult;
  }

  @override
  Future<ManualPlaybackLeaseResult> acquireManualPlaybackLease({
    required String requestId,
  }) async {
    acquireCallCount++;
    acquiredRequestIds.add(requestId);
    onAcquire?.call(requestId);
    if (!nextAcquireResult) {
      return ManualPlaybackLeaseResult(
        acquired: false,
        errorCode: 'LEASE_DENIED',
        errorMessageAr:
            errorMessageAr ?? 'تعذر الحصول على إذن التشغيل من النظام',
      );
    }
    final token = 'mock_lease_${requestId}_$acquireCallCount';
    activeLeaseToken = token;
    return ManualPlaybackLeaseResult(
      acquired: true,
      leaseToken: token,
    );
  }

  @override
  Future<bool> releaseManualPlaybackLease({
    required String leaseToken,
  }) async {
    releaseCallCount++;
    releasedTokens.add(leaseToken);
    if (releaseEnteredCompleter != null && !releaseEnteredCompleter!.isCompleted) {
      releaseEnteredCompleter!.complete();
      releaseEnteredCompleter = null;
    }
    onRelease?.call(leaseToken);
    if (releaseGateCompleter != null) {
      await releaseGateCompleter!.future;
    }
    if (!nextReleaseResult) {
      return false;
    }
    if (activeLeaseToken == leaseToken) {
      activeLeaseToken = null;
    }
    return true;
  }

  @override
  Future<bool> isManualPlaybackLeaseActive() async {
    return activeLeaseToken != null;
  }
}

class FakeNativeAlarmResetBoundary implements NativeAlarmResetBoundary {
  int resetAllCallCount = 0;
  bool nextResetResult = true;
  bool wasAudioStoppedWhenResetCalled = false;
  bool Function()? isAudioActiveCheck;

  @override
  Future<void> prepareReset() async {}

  @override
  Future<bool> resetAll() async {
    resetAllCallCount++;
    if (isAudioActiveCheck != null) {
      wasAudioStoppedWhenResetCalled = !isAudioActiveCheck!();
    }
    return nextResetResult;
  }
}

// =============================================================================
// Integration Tests Suite
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'stopActivePlayback') {
          return {'stopped': true};
        }
        if (methodCall.method == 'acquireManualPlaybackLease') {
          return {
            'acquired': true,
            'leaseToken': 'test_channel_lease',
          };
        }
        if (methodCall.method == 'releaseManualPlaybackLease') {
          return {
            'released': true,
            'cleared': true,
          };
        }
        if (methodCall.method == 'getState') {
          return {
            'isManualPlaybackLeaseActive': false,
            'isServiceRunning': false,
          };
        }
        return null;
      },
    );
  });

  group('Manual Audio Lease Lifecycle & Bidirectional Exclusivity', () {
    test('1. Normal stop releases manual playback lease confirmed', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );
      addTearDown(client.dispose);

      await client.playUrl(
        QuranAudioSource.getSurahAudioUrl(1),
        requestToken: 'q1',
      );
      expect(mockPlayer.isPlaying, isTrue);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);
      expect(fakeNative.acquireCallCount, 1);

      await client.stop();
      expect(mockPlayer.isPlaying, isFalse);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
      expect(fakeNative.releaseCallCount, 1);
    });

    test('2. Natural completion releases manual playback lease and session', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final releaseGate = Completer<void>();
      fakeNative.onRelease = (_) {
        if (!releaseGate.isCompleted) {
          releaseGate.complete();
        }
      };

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );
      addTearDown(client.dispose);

      await client.playUrl(
        QuranAudioSource.getSurahAudioUrl(1),
        requestToken: 'q1',
      );
      expect(mockPlayer.isPlaying, isTrue);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

      // Simulate player naturally reaching completion and await explicit release gate
      mockPlayer.completeNaturally();
      await releaseGate.future.timeout(const Duration(seconds: 3));

      expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
      expect(fakeNative.releaseCallCount, 1);
      expect(mockSession.isActivated, isFalse);
    });

    test('3. Failed load (timeout/network) releases manual playback lease without leak', () async {
      final mockPlayer = MockAudioPlayer();
      mockPlayer.throwOnSetUrl = true; // Throws on load
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.playUrl(QuranAudioSource.getSurahAudioUrl(1), requestToken: 'q_fail'),
        throwsA(anything),
      );

      // Acquired during start attempt, but released when setUrl threw
      expect(fakeNative.acquireCallCount, 1);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
      expect(fakeNative.releaseCallCount, 1);
      expect(mockPlayer.playCallCount, 0, reason: 'Must never physically play on load failure');
    });

    test('4. Failed SDK stop keeps lease and blocks future starts as unconfirmed barrier', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );

      try {
        await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q1',
        );
        expect(mockPlayer.isPlaying, isTrue);
        final activeLease = fakeNative.activeLeaseToken;
        expect(activeLease, isNotNull);

        // Make player.stop() throw
        mockPlayer.throwOnStop = true;

        await expectLater(client.stop(), throwsA(anything));

        // Lease must remain held on native side because stop was unconfirmed!
        expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);
        expect(fakeNative.activeLeaseToken, activeLease);

        // Subsequent attempt to start new playback must be blocked by old uncleaned player!
        await expectLater(
          client.playUrl(QuranAudioSource.getSurahAudioUrl(2), requestToken: 'q2'),
          throwsA(anything),
        );
        expect(mockPlayer.playCallCount, 1, reason: 'New play must not start while old stop is unconfirmed');
      } finally {
        mockPlayer.throwOnStop = false;
        fakeNative.nextReleaseResult = true;
        if (fakeNative.releaseGateCompleter != null && !fakeNative.releaseGateCompleter!.isCompleted) {
          fakeNative.releaseGateCompleter!.complete();
        }
        await client.dispose().timeout(const Duration(seconds: 3));
      }
    });

    test('5. Release failure retains retryable token; player disposed once; subsequent retry releases', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );

      try {
        await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q1',
        );
        expect(mockPlayer.isPlaying, isTrue);

        // Simulate native release failure on first attempt
        fakeNative.nextReleaseResult = false;

        await expectLater(client.stop(), throwsA(isA<StateError>()));

        // Player was physically stopped and marked disposed
        expect(mockPlayer.isDisposed, isTrue);
        // SDK AudioPlayer.dispose() internally calls stop, so stopCallCount is 2 (adapter stop + SDK dispose stop)
        expect(mockPlayer.stopCallCount, 2, reason: 'SDK AudioPlayer.dispose() internally calls stop');
        expect(mockPlayer.disposeCallCount, 1);

        // But lease was NOT released and token remains retained in _activeOp
        expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

        // Capture baseline after physical dispose
        final baselineStopCalls = mockPlayer.stopCallCount; // 2
        final baselineDisposeCalls = mockPlayer.disposeCallCount; // 1

        // Now native release will succeed
        fakeNative.nextReleaseResult = true;

        // Retry stop(): skips player.stop() and player.dispose() because both are confirmed, retries release!
        await client.stop();

        // Later lease-release retry/stop must NOT increase baseline!
        expect(mockPlayer.stopCallCount, baselineStopCalls, reason: 'Retry stop does not increase baseline stop count');
        expect(mockPlayer.disposeCallCount, baselineDisposeCalls, reason: 'Retry stop does not increase baseline dispose count');
        expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
        expect(fakeNative.releaseCallCount, 2);
      } finally {
        fakeNative.nextReleaseResult = true;
        await client.dispose().timeout(const Duration(seconds: 3));
      }
    });

    test('6. Confirmed pause releases manual lease; resume re-acquires fresh unique lease', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );
      addTearDown(client.dispose);

      await client.playUrl(
        QuranAudioSource.getSurahAudioUrl(1),
        requestToken: 'q1',
      );
      expect(mockPlayer.isPlaying, isTrue);
      final initialLease = fakeNative.activeLeaseToken;
      expect(initialLease, isNotNull);

      // Pause releases the lease so scheduled athans can sound
      final paused = await client.pause(requestToken: 'q1');
      expect(paused, isTrue);
      expect(mockPlayer.isPlaying, isFalse);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
      expect(fakeNative.releaseCallCount, 1);

      // Resume re-acquires a fresh lease
      final resumed = await client.resume(requestToken: 'q1');
      expect(resumed, isTrue);
      expect(mockPlayer.isPlaying, isTrue);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);
      expect(fakeNative.acquireCallCount, 2);
      expect(fakeNative.activeLeaseToken, isNot(initialLease));
    });

    test('7. Failed native acquire results in ZERO SDK play and throws StateError', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();
      fakeNative.nextAcquireResult = false; // Deny lease
      fakeNative.errorMessageAr = 'يوجد إذن تشغيل نشط آخر في النظام';

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.playUrl(QuranAudioSource.getSurahAudioUrl(1)),
        throwsA(isA<StateError>()),
      );

      expect(mockPlayer.playCallCount, 0, reason: 'Zero SDK play when acquire fails');
      expect(mockSession.activateCallCount, 0, reason: 'Audio session must not activate');
    });

    test('8. Monotonic unique request IDs across multiple client instances', () async {
      final mockPlayerA = MockAudioPlayer();
      final mockPlayerB = MockAudioPlayer();
      final mockSessionA = FakeAdhanAudioSession();
      final mockSessionB = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final clientA = JustAudioPlayerClient(
        playerFactory: () => mockPlayerA,
        audioSession: mockSessionA,
        nativeAudioControl: fakeNative,
      );
      final clientB = JustAudioPlayerClient(
        playerFactory: () => mockPlayerB,
        audioSession: mockSessionB,
        nativeAudioControl: fakeNative,
      );
      addTearDown(() async {
        await clientA.dispose();
        await clientB.dispose();
      });

      await clientA.playUrl(
        QuranAudioSource.getSurahAudioUrl(1),
        requestToken: 'a1',
      );
      await clientA.stop();

      await clientB.playUrl(
        QuranAudioSource.getSurahAudioUrl(2),
        requestToken: 'b1',
      );
      await clientB.stop();

      expect(fakeNative.acquiredRequestIds.length, 2);
      final idA = fakeNative.acquiredRequestIds[0];
      final idB = fakeNative.acquiredRequestIds[1];
      expect(idA, isNot(idB));
      expect(idA.startsWith('lease_seq_'), isTrue);
      expect(idB.startsWith('lease_seq_'), isTrue);
    });

    test('9. Reset controller awaits SDK stop and native release before SQLite wipe', () async {
      final tempDir = await Directory.systemTemp.createTemp('zad_manual_reset_test_');
      final db = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: p.join(tempDir.path, 'reset_test.db'),
      );
      final repo = ProgressRepository(db);

      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();
      final fakeResetBoundary = FakeNativeAlarmResetBoundary();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
        isResetBarrierActive: () => repo.mutationBarrier.isResetInProgress,
        getResetGeneration: () => repo.mutationBarrier.currentGeneration,
      );

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          nativePrayerAudioControlProvider.overrideWithValue(fakeNative),
          adhanAudioPlayerClientProvider.overrideWithValue(client),
        ],
      );

      fakeResetBoundary.isAudioActiveCheck = () => mockPlayer.isPlaying;

      addTearDown(() async {
        container.dispose();
        await client.dispose();
        await repo.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });

      // 1. Seed real SQLite records (reading progress page 42)
      final rawDb = await db.database;
      await rawDb.update(
        'reading_progress',
        {
          'last_page': 42,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = 1',
      );
      final seededRows = await rawDb.query('reading_progress', where: 'id = 1');
      expect(seededRows.first['last_page'], 42);

      // 2. Start playing voice preview
      await container.read(adhanAudioControllerProvider.notifier).playVoice(AdhanVoice.adam);
      expect(mockPlayer.isPlaying, isTrue);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

      // 3. Apply release gate on FakeNativePrayerAudioControl
      final releaseEntered = Completer<void>();
      final releaseGate = Completer<void>();
      fakeNative.releaseEnteredCompleter = releaseEntered;
      fakeNative.releaseGateCompleter = releaseGate;

      // 4. Start reset asynchronously
      final resetFuture = container.read(preferencesControllerProvider.notifier).resetAllState(
        nativeBoundaryOverride: fakeResetBoundary,
      );

      // Await until audio stop enters native lease release and pauses on the gate
      try {
        await releaseEntered.future.timeout(const Duration(seconds: 3));

        // 5. Verify that during the release gate:
        // - The reset fence is active
        expect(repo.mutationBarrier.isResetInProgress, isTrue);
        // - Native alarm reset is NOT called
        expect(fakeResetBoundary.resetAllCallCount, 0);
        // - Raw DB seed remains intact
        final duringGateRows = await rawDb.query('reading_progress', where: 'id = 1');
        expect(duringGateRows.first['last_page'], 42);
      } finally {
        fakeNative.releaseGateCompleter = null;
        if (!releaseGate.isCompleted) {
          releaseGate.complete();
        }
      }
      await resetFuture.timeout(const Duration(seconds: 5));

      // 7. Verify audio stopped, lease inactive, native reset called, and DB reset to defaults (page 1)
      expect(mockPlayer.isPlaying, isFalse);
      expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
      expect(fakeResetBoundary.resetAllCallCount, 1);
      final afterResetRows = await rawDb.query('reading_progress', where: 'id = 1');
      expect(afterResetRows.first['last_page'], 1);
    });

    test('10. Late acquire after reset cancellation with release false retains orphan and retries via stop', () async {
      int sdkPlayerFactoryCount = 0;
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      bool resetActive = false;

      final client = JustAudioPlayerClient(
        playerFactory: () {
          sdkPlayerFactoryCount++;
          return mockPlayer;
        },
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
        isResetBarrierActive: () => resetActive,
      );

      try {
        // When acquireManualPlaybackLease is called, trigger reset cancellation
        // and make the subsequent lease release fail!
        fakeNative.onAcquire = (_) {
          resetActive = true;
          fakeNative.nextReleaseResult = false; // release will fail
        };

        final startResult = await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q_late',
        );
        expect(startResult, PlaybackStartupResult.cancelled);

        // Assert 0 SDK factory calls! Zero real AudioPlayer allocated on stale startup!
        expect(sdkPlayerFactoryCount, 0, reason: 'Zero SDK allocation on late acquire cancellation');
        // Orphan token stored in client
        expect(client.orphanLeaseToken, isNotNull);
        // Lease remains active on native side because release failed
        expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

        // Reset ends, but new playback is blocked by unreleased orphan lease
        resetActive = false;
        await expectLater(
          client.playUrl(QuranAudioSource.getSurahAudioUrl(2), requestToken: 'q_blocked'),
          throwsA(isA<StateError>()),
        );
        expect(sdkPlayerFactoryCount, 0, reason: 'Still zero SDK allocation while orphan release fails');

        // Now native release will succeed
        fakeNative.nextReleaseResult = true;

        // Retry via stop(): physical queue drains orphan lease and acknowledges release!
        await client.stop();

        expect(client.orphanLeaseToken, isNull);
        expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
        expect(fakeNative.releaseCallCount, greaterThanOrEqualTo(2));
      } finally {
        fakeNative.onAcquire = null;
        fakeNative.nextReleaseResult = true;
        await client.dispose().timeout(const Duration(seconds: 3));
      }
    });

    test('11. SDK dispose failure retains lease, blocks next start, and retries dispose without double stop', () async {
      final mockPlayer = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      final client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );

      try {
        await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q1',
        );
        expect(mockPlayer.isPlaying, isTrue);
        expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

        // Make player.stop() succeed, but player.dispose() throw
        mockPlayer.throwOnDispose = true;

        await expectLater(client.stop(), throwsA(anything));

        // Stop was confirmed on player, but dispose failed (before reaching internal stop)!
        expect(mockPlayer.stopCallCount, 1, reason: 'Stop count is 1 before dispose succeeds');
        expect(mockPlayer.disposeCallCount, 1);
        // Native lease is STILL held because cleanup failed and active op barrier remains
        expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);

        // Next start is blocked by unconfirmed cleanup barrier
        await expectLater(
          client.playUrl(QuranAudioSource.getSurahAudioUrl(2), requestToken: 'q2'),
          throwsA(anything),
        );
        // On this retry, stop() must NOT be called again (NO double stop)!
        expect(mockPlayer.stopCallCount, 1, reason: 'Stop is confirmed and must not be repeated by owner cleanup retry');
        expect(mockPlayer.disposeCallCount, 2, reason: 'Dispose is retried (attempt 2)');

        // Now SDK dispose succeeds
        mockPlayer.throwOnDispose = false;

        // Retry stop: only dispose() is called, stop() is skipped, lease is released!
        await client.stop();

        // After dispose succeeds, SDK AudioPlayer.dispose() internally calls stop, bringing count to 2
        expect(mockPlayer.stopCallCount, 2, reason: 'Stop count is 2 after dispose succeeds (SDK AudioPlayer.dispose() internally calls stop)');
        expect(mockPlayer.disposeCallCount, 3);
        expect(await fakeNative.isManualPlaybackLeaseActive(), isFalse);
      } finally {
        mockPlayer.throwOnDispose = false;
        await client.dispose().timeout(const Duration(seconds: 3));
      }
    });

    test('12. Gated handoff retires A before B starts', () async {
      final mockPlayerA = MockAudioPlayer();
      final mockPlayerB = MockAudioPlayer();
      final mockSession = FakeAdhanAudioSession();
      final fakeNative = FakeNativePrayerAudioControl();

      int playerIndex = 0;
      final client = JustAudioPlayerClient(
        playerFactory: () => playerIndex++ == 0 ? mockPlayerA : mockPlayerB,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
      );

      final releaseGateA = Completer<void>();
      final releaseEnteredA = Completer<void>();

      try {
        // Start playback A
        await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'owner_A',
        );
        expect(mockPlayerA.isPlaying, isTrue);
        final tokenA = fakeNative.activeLeaseToken;
        expect(tokenA, isNotNull);

        // Gate lease release of token A
        fakeNative.releaseEnteredCompleter = releaseEnteredA;
        fakeNative.releaseGateCompleter = releaseGateA;

        // Now start playback B which supersedes playback A
        final futureB = client.playUrl(
          QuranAudioSource.getSurahAudioUrl(2),
          requestToken: 'owner_B',
        );

        // Wait until playback A enters lease release and pauses at gate
        try {
          await releaseEnteredA.future.timeout(const Duration(seconds: 3));
          // Player A was physically stopped and disposed (SDK AudioPlayer.dispose() internally calls stop)
          expect(mockPlayerA.stopCallCount, 2, reason: 'SDK AudioPlayer.dispose() internally calls stop');
          expect(mockPlayerA.disposeCallCount, 1);
        } finally {
          fakeNative.releaseGateCompleter = null;
          if (!releaseGateA.isCompleted) {
            releaseGateA.complete();
          }
        }

        // Playback B completes startup and becomes the active owner
        await futureB.timeout(const Duration(seconds: 5));
        expect(mockPlayerB.isPlaying, isTrue);
        final tokenB = fakeNative.activeLeaseToken;
        expect(tokenB, isNotNull);
        expect(tokenB, isNot(tokenA));

        // Assert that release touched only old token A and did NOT clobber token B
        expect(fakeNative.releasedTokens, contains(tokenA));
        expect(fakeNative.releasedTokens, isNot(contains(tokenB)));
        expect(fakeNative.activeLeaseToken, tokenB);
        expect(await fakeNative.isManualPlaybackLeaseActive(), isTrue);
      } finally {
        fakeNative.releaseGateCompleter = null;
        if (!releaseGateA.isCompleted) {
          releaseGateA.complete();
        }
        await client.dispose().timeout(const Duration(seconds: 3));
      }
    });
  });
}
