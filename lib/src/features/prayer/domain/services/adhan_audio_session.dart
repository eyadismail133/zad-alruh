import 'dart:async';
import 'package:audio_session/audio_session.dart';

/// Abstract OS audio session boundary for adhan audio playback.
///
/// Decouples OS audio session configuration, activation, and hardware interruption
/// handling from the playback adapter, enabling deterministic unit testing.
abstract class AdhanAudioSession {
  /// Stream emitting when an OS audio interruption begins (e.g. phone call, alarm, ducking).
  Stream<void> get interruptionStream;

  /// Stream emitting when audio output becomes noisy (e.g. headphones unplugged).
  Stream<void> get becomingNoisyStream;

  /// Configures and activates the OS audio session.
  /// Returns `true` if OS granted audio activation, `false` if denied.
  Future<bool> activate();

  /// Deactivates the OS audio session.
  Future<void> deactivate();

  /// Disposes session subscriptions and streams.
  Future<void> dispose();
}

/// Production implementation of [AdhanAudioSession] backed by [AudioSession].
class DefaultAdhanAudioSession implements AdhanAudioSession {
  final Future<AudioSession> Function() _sessionProvider;
  AudioSession? _cachedSession;
  Future<AudioSession?>? _initFuture;

  // Global lease epoch and owner tracking across DefaultAdhanAudioSession instances sharing OS audio focus
  static int _globalLeaseEpoch = 0;
  static int _activeLeaseOwner = 0;
  int _instanceLease = 0;

  /// Visible for testing: resets static lease state between test cases.
  static void resetStaticLeaseForTesting() {
    _globalLeaseEpoch = 0;
    _activeLeaseOwner = 0;
  }

  final StreamController<void> _interruptionController =
      StreamController<void>.broadcast();
  final StreamController<void> _noisyController =
      StreamController<void>.broadcast();

  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;
  bool _isDisposed = false;

  DefaultAdhanAudioSession({Future<AudioSession> Function()? sessionProvider})
      : _sessionProvider = sessionProvider ?? (() => AudioSession.instance);

  Future<AudioSession?> _ensureSession() {
    if (_cachedSession != null) return Future.value(_cachedSession);
    if (_isDisposed) return Future.value(null);

    if (_initFuture != null) return _initFuture!;

    _initFuture = () async {
      try {
        final session = await _sessionProvider();
        if (_isDisposed) {
          return null;
        }
        _cachedSession = session;

        // Memoized: exactly one subscription pair created
        _interruptionSub = session.interruptionEventStream.listen((event) {
          if (event.begin && !_isDisposed && !_interruptionController.isClosed) {
            _interruptionController.add(null);
          }
        });

        _noisySub = session.becomingNoisyEventStream.listen((_) {
          if (!_isDisposed && !_noisyController.isClosed) {
            _noisyController.add(null);
          }
        });

        return session;
      } catch (_) {
        _initFuture = null;
        return null;
      }
    }();

    return _initFuture!;
  }

  @override
  Stream<void> get interruptionStream {
    unawaited(_ensureSession());
    return _interruptionController.stream;
  }

  @override
  Stream<void> get becomingNoisyStream {
    unawaited(_ensureSession());
    return _noisyController.stream;
  }

  @override
  Future<bool> activate() async {
    if (_isDisposed) return false;
    final int lease = ++_globalLeaseEpoch;
    _instanceLease = lease;

    final session = await _ensureSession();
    if (session == null || _isDisposed || lease != _globalLeaseEpoch) {
      return false;
    }

    try {
      await session.configure(const AudioSessionConfiguration.music());
    } catch (_) {
      return false;
    }

    if (_isDisposed || lease != _globalLeaseEpoch) {
      return false;
    }

    bool granted = false;
    try {
      granted = await session.setActive(true);
    } catch (_) {
      return false;
    }

    // Guard in-flight activation completion if disposed or superseded while awaiting setActive:
    if (_isDisposed || lease != _globalLeaseEpoch) {
      if (granted) {
        // Abandoned activation: OS granted focus late, but this session was disposed or superseded.
        // Clean up unowned focus immediately if no newer lease has claimed ownership:
        if (_activeLeaseOwner == 0 || _activeLeaseOwner == lease) {
          _activeLeaseOwner = 0;
          try {
            await session.setActive(false);
          } catch (_) {}
        }
      }
      return false;
    }

    if (granted) {
      _activeLeaseOwner = lease;
      return true;
    }
    return false;
  }

  @override
  Future<void> deactivate() async {
    final session = _cachedSession;
    if (session != null) {
      // Allow deactivation even after dispose if this instance owns the lease or system is unowned,
      // but protect any newer owner lease!
      if (_activeLeaseOwner == 0 || _activeLeaseOwner == _instanceLease) {
        _activeLeaseOwner = 0;
        try {
          await session.setActive(false);
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _initFuture = null;
    await _interruptionSub?.cancel();
    _interruptionSub = null;
    await _noisySub?.cancel();
    _noisySub = null;
    if (!_interruptionController.isClosed) {
      await _interruptionController.close();
    }
    if (!_noisyController.isClosed) {
      await _noisyController.close();
    }

    // Clean up active lease if this instance was the active owner
    final session = _cachedSession;
    if (session != null && _activeLeaseOwner == _instanceLease && _instanceLease != 0) {
      _activeLeaseOwner = 0;
      try {
        await session.setActive(false);
      } catch (_) {}
    }
  }
}
