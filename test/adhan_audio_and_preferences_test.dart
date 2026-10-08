import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/more/presentation/settings_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/sources_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/adhan_voice.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_session.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/just_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/adhan_audio_controller.dart';
import 'package:zad_alruh/src/features/prayers/presentation/prayers_screen.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/models/user_preferences.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';
import 'package:zad_alruh/src/features/shell/presentation/app_shell.dart';

bool _fontsLoaded = false;
Future<void> _ensureTestFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();

    final plex = FontLoader('IBM Plex Sans Arabic');
    for (final face in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      plex.addFont(
        rootBundle.load('assets/fonts/IBM-Plex-Sans-Arabic-$face.ttf'),
      );
    }
    await plex.load();

    final amiri = FontLoader('Amiri Quran')
      ..addFont(rootBundle.load('assets/fonts/Amiri-Quran-Regular.ttf'));
    await amiri.load();
    _fontsLoaded = true;
  });
}

/// Mock of [AudioPlayer] for isolating [JustAudioPlayerClient] at the genuine SDK/OS boundary.
class MockAudioPlayer extends Fake implements AudioPlayer {
  final _positionSubject = StreamController<Duration>.broadcast();
  final _durationSubject = StreamController<Duration?>.broadcast();
  final _playingSubject = StreamController<bool>.broadcast();
  final _playerStateSubject = StreamController<PlayerState>.broadcast();
  final _errorSubject = StreamController<PlayerException>.broadcast();
  final _playbackEventSubject = StreamController<PlaybackEvent>.broadcast();

  String? currentAsset;
  dynamic currentTag;
  bool isPlaying = false;
  bool isCompleted = false;
  bool isDisposed = false;
  int playCallCount = 0;
  int stopCallCount = 0;
  int setAssetCallCount = 0;
  int disposeCallCount = 0;

  Completer<void>? setAssetEnteredCompleter;
  Completer<void>? setAssetGateCompleter;
  Completer<void>? playEndCompleter;
  Completer<void>? stopEnteredCompleter;
  Completer<void>? stopGateCompleter;

  bool throwOnSetAsset = false;
  bool throwOnPlay = false;
  bool throwOnStop = false;

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
  SequenceState get sequenceState {
    return SequenceState(
      sequence: [
        AudioSource.asset(
          currentAsset ?? 'assets/audio/adhan/adam-converted.mp3',
          tag: currentTag,
        ),
      ],
      currentIndex: 0,
      shuffleIndices: const [0],
      shuffleModeEnabled: false,
      loopMode: LoopMode.off,
    );
  }

  @override
  Future<Duration?> setAsset(
    String assetPath, {
    String? package,
    bool preload = true,
    Duration? initialPosition,
    dynamic tag,
  }) async {
    setAssetCallCount++;
    currentAsset = assetPath;
    currentTag = tag;
    isCompleted = false;

    if (setAssetEnteredCompleter != null &&
        !setAssetEnteredCompleter!.isCompleted) {
      setAssetEnteredCompleter!.complete();
    }
    if (setAssetGateCompleter != null) {
      await setAssetGateCompleter!.future;
    }
    if (throwOnSetAsset) {
      throw Exception('Simulated decoder failure on setAsset');
    }
    return const Duration(seconds: 120);
  }

  @override
  Future<void> play() async {
    playCallCount++;
    if (throwOnPlay) {
      throw Exception('Simulated play error');
    }
    isPlaying = true;
    _playingSubject.add(true);
    _playerStateSubject.add(PlayerState(true, ProcessingState.ready));
    playEndCompleter = Completer<void>();
    await playEndCompleter!.future;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (stopEnteredCompleter != null && !stopEnteredCompleter!.isCompleted) {
      stopEnteredCompleter!.complete();
    }
    if (stopGateCompleter != null) {
      await stopGateCompleter!.future;
    }
    if (throwOnStop) {
      throw Exception('Simulated stop failure');
    }
    isPlaying = false;
    if (!_playingSubject.isClosed) {
      _playingSubject.add(false);
    }
    if (!_playerStateSubject.isClosed) {
      _playerStateSubject.add(PlayerState(false, ProcessingState.idle));
    }
    if (playEndCompleter != null && !playEndCompleter!.isCompleted) {
      playEndCompleter!.complete();
    }
  }

  void emitCompletion() {
    isCompleted = true;
    isPlaying = false;
    if (!_playerStateSubject.isClosed) {
      _playerStateSubject.add(PlayerState(false, ProcessingState.completed));
    }
    if (playEndCompleter != null && !playEndCompleter!.isCompleted) {
      playEndCompleter!.complete();
    }
  }

  void emitError(String message) {
    if (!_errorSubject.isClosed) {
      _errorSubject.add(PlayerException(1, message, 0));
    }
  }

  void emitPosition(Duration pos) {
    if (!_positionSubject.isClosed) {
      _positionSubject.add(pos);
    }
  }

  void emitDuration(Duration? dur) {
    if (!_durationSubject.isClosed) {
      _durationSubject.add(dur);
    }
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
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

/// Controllable [AudioSession] implementation for testing [DefaultAdhanAudioSession] at the SDK boundary.
class ControllableAudioSession extends Fake implements AudioSession {
  final _interruptionController =
      StreamController<AudioInterruptionEvent>.broadcast();
  final _noisyController = StreamController<void>.broadcast();

  final List<bool> setActiveCalls = [];
  int configureCallCount = 0;

  Completer<bool>? setActiveCompleter;
  bool nextSetActiveResult = true;

  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      _interruptionController.stream;

  @override
  Stream<void> get becomingNoisyEventStream => _noisyController.stream;

  @override
  Future<void> configure(AudioSessionConfiguration configuration) async {
    configureCallCount++;
  }

  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    setActiveCalls.add(active);
    if (setActiveCompleter != null) {
      return await setActiveCompleter!.future;
    }
    return nextSetActiveResult;
  }

  Future<void> closeStreams() async {
    await _interruptionController.close();
    await _noisyController.close();
  }
}

/// Fake OS audio session boundary for deterministic activation and interruption testing.
class FakeAdhanAudioSession implements AdhanAudioSession {
  final _interruptionController = StreamController<void>.broadcast();
  final _noisyController = StreamController<void>.broadcast();

  bool isActivated = false;
  bool isDeactivated = false;
  bool isDisposed = false;
  bool simulateActivationDenial = false;
  Completer<bool>? activationCompleter;
  int activateCallCount = 0;
  int deactivateCallCount = 0;

  @override
  Stream<void> get interruptionStream => _interruptionController.stream;

  @override
  Stream<void> get becomingNoisyStream => _noisyController.stream;

  @override
  Future<bool> activate() async {
    activateCallCount++;
    if (activationCompleter != null) {
      return await activationCompleter!.future;
    }
    if (simulateActivationDenial) {
      return false;
    }
    isActivated = true;
    return true;
  }

  @override
  Future<void> deactivate() async {
    deactivateCallCount++;
    isActivated = false;
    isDeactivated = true;
  }

  void emitInterruption() {
    _interruptionController.add(null);
  }

  void emitNoisy() {
    _noisyController.add(null);
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _interruptionController.close();
    await _noisyController.close();
  }
}

/// Fake client boundary for controller and widget tests.
class FakeAdhanAudioPlayerClient implements AdhanAudioPlayerClient {
  final _eventController = StreamController<AdhanPlaybackEvent>.broadcast();

  String? lastPlayedAsset;
  String? lastRequestToken;
  bool isPlaying = false;
  bool isDisposed = false;
  bool throwOnPlay = false;
  bool throwOnStop = false;
  int stopCallCount = 0;
  int playCallCount = 0;

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
  }) async {
    playCallCount++;
    final token = requestToken ?? 'fake_tok_$playCallCount';
    lastPlayedAsset = assetPath;
    lastRequestToken = token;
    if (throwOnPlay) {
      _eventController.add(AdhanPlaybackEvent(
        requestToken: token,
        status: AdhanPlaybackStatus.error,
        errorMessage: 'تعذر تشغيل التسجيل الصوتي',
      ));
      throw Exception('Simulated playback error');
    }
    isPlaying = true;
    _eventController.add(AdhanPlaybackEvent(
      requestToken: token,
      status: AdhanPlaybackStatus.playing,
      duration: const Duration(seconds: 120),
    ));
    return PlaybackStartupResult.started;
  }

  void emitPosition(Duration position, {String? token}) {
    _eventController.add(AdhanPlaybackEvent(
      requestToken: token ?? lastRequestToken ?? '',
      status: AdhanPlaybackStatus.playing,
      position: position,
      duration: const Duration(seconds: 120),
    ));
  }

  void emitCompletion({String? token}) {
    isPlaying = false;
    _eventController.add(AdhanPlaybackEvent(
      requestToken: token ?? lastRequestToken ?? '',
      status: AdhanPlaybackStatus.completed,
      position: Duration.zero,
      duration: const Duration(seconds: 120),
    ));
  }

  void emitError(String message, {String? token}) {
    _eventController.add(AdhanPlaybackEvent(
      requestToken: token ?? lastRequestToken ?? '',
      status: AdhanPlaybackStatus.error,
      errorMessage: message,
    ));
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (throwOnStop) {
      _eventController.add(AdhanPlaybackEvent(
        requestToken: lastRequestToken ?? '',
        status: AdhanPlaybackStatus.error,
        errorMessage: 'تعذر إيقاف التشغيل الصوتي',
      ));
      throw Exception('Simulated stop error');
    }
    isPlaying = false;
    _eventController.add(AdhanPlaybackEvent(
      requestToken: lastRequestToken ?? '',
      status: AdhanPlaybackStatus.stopped,
    ));
  }

  @override
  Future<void> dispose() async {
    isDisposed = true;
    await _eventController.close();
  }
}

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late QuranRepository quranRepo;
  late CityRepository cityRepo;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'stopActivePlayback') {
          return {'stopped': true};
        }
        if (methodCall.method == 'acquireManualPlaybackLease') {
          final dynamic args = methodCall.arguments;
          final String reqId = (args is Map && args['requestId'] != null)
              ? args['requestId'].toString()
              : 'mock_req';
          return {
            'acquired': true,
            'leaseToken': 'mock_lease_$reqId',
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
            'enabled': false,
            'generationToken': 2,
            'canScheduleExactAlarms': true,
            'notificationsAllowed': true,
            'isPlaybackStatusChannelBlocked': false,
            'isDndOrSilentActive': false,
            'isManualPlaybackLeaseActive': false,
            'isServiceRunning': false,
            'futureEventsCount': 0,
            'pendingCleanupCount': 0,
            'cityId': 360630,
            'cityNameAr': 'القاهرة',
            'timezone': 'Africa/Cairo',
            'coverageHorizonUtc': 0,
            'consumedLedgerCount': 0,
          };
        }
        if (methodCall.method == 'getAuthorizationToken') {
          return {'token': 2};
        }
        if (methodCall.method == 'disableAlarms') {
          return {'success': true, 'token': 2, 'partialFailure': false};
        }
        if (methodCall.method == 'resetAll') {
          return {
            'success': true,
            'token': 3,
            'partialFailure': false,
            'authorizationInvalidated': true,
          };
        }
        return null;
      },
    );

    final textBytes = await File(
      'assets/content/quran/quran-uthmani.txt',
    ).readAsBytes();
    final xmlBytes = await File(
      'assets/content/quran/quran-data.xml',
    ).readAsBytes();
    quranRepo = QuranRepository.fromBytes(
      textBytes: textBytes,
      xmlBytes: xmlBytes,
    );

    final cityBytes = await File(
      'assets/content/cities/cities15000.txt',
    ).readAsBytes();
    cityRepo = CityAssetAdapter.fromBytes(cityBytes);
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zad_audio_test_');
    dbPath = p.join(tempDir.path, 'zad_audio_test.db');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('JustAudioPlayerClient - Fresh Player per Source & Serial Physical Handoff', () {
    test(
      'allocates fresh player per operation; old player subscriptions are retired and physically stopped',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        // 1. Play Voice A
        await client.playAsset('assets/audio/adhan/adam-converted.mp3');
        expect(players.length, 1);
        final playerA = players[0];
        expect(playerA.playCallCount, 1);
        expect(playerA.isPlaying, isTrue);

        // 2. Play Voice B: triggers serial physical handoff
        await client.playAsset('assets/audio/adhan/atcovi-original.mp3');
        expect(players.length, 2);
        final playerB = players[1];

        // Player A must have been physically stopped and disposed
        expect(playerA.stopCallCount, greaterThanOrEqualTo(1));
        expect(playerA.disposeCallCount, greaterThanOrEqualTo(1));
        expect(playerA.isDisposed, isTrue);
        expect(playerA.isPlaying, isFalse);

        // Player B is now playing
        expect(playerB.playCallCount, 1);
        expect(playerB.isPlaying, isTrue);
      },
    );

    test(
      'same voice restart allocates a fresh player and retires the old player cleanly',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        // First click on Adam
        await client.playAsset('assets/audio/adhan/adam-converted.mp3');
        expect(players.length, 1);
        final firstPlayer = players[0];

        // Second click on Adam (same voice restart)
        await client.playAsset('assets/audio/adhan/adam-converted.mp3');
        expect(players.length, 2);
        final secondPlayer = players[1];

        expect(firstPlayer.stopCallCount, greaterThanOrEqualTo(1));
        expect(secondPlayer.playCallCount, 1);
        expect(secondPlayer.isPlaying, isTrue);
      },
    );

    test(
      'play is NEVER called before OS audio session activation; activation denial throws and cancels player',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        fakeSession.simulateActivationDenial = true; // OS denies activation

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        await expectLater(
          client.playAsset('assets/audio/adhan/adam-converted.mp3'),
          throwsA(isA<StateError>()),
        );

        expect(players.length, 1);
        final player = players[0];
        // CRITICAL: play() must NOT have been called because activation was denied!
        expect(player.playCallCount, 0,
            reason: 'play() must never be called when OS session activation is denied');
        expect(player.stopCallCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'activation timeout safely retires player so late activation cannot play',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        // activationCompleter never completes within the 50ms timeout window
        fakeSession.activationCompleter = Completer<bool>();

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
          activationTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(client.dispose);

        // Client times out waiting for OS session activation and throws StateError
        await expectLater(
          client.playAsset('assets/audio/adhan/adam-converted.mp3'),
          throwsA(isA<StateError>()),
        );

        expect(players.length, 1);
        final player = players[0];
        expect(player.playCallCount, 0,
            reason: 'Timed out activation must not invoke play()');

        // Late completion arrives AFTER timeout has retired player
        fakeSession.activationCompleter!.complete(true);
        await Future<void>.delayed(Duration.zero);

        // Player must still not have played
        expect(player.playCallCount, 0,
            reason: 'Late activation completion must not cause player to play');
        expect(player.stopCallCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'late load after stop() or new source cancels player before play() is called',
      () async {
        final playerA = MockAudioPlayer();
        final enteredCompleter = Completer<void>();
        final gateCompleter = Completer<void>();
        playerA.setAssetEnteredCompleter = enteredCompleter;
        playerA.setAssetGateCompleter = gateCompleter;

        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          if (players.isEmpty) {
            players.add(playerA);
            return playerA;
          }
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        // Start loading asset A (blocks in setAsset)
        final playFuture = client.playAsset('assets/audio/adhan/adam-converted.mp3');

        // Wait until player A has actually entered setAsset
        await enteredCompleter.future;

        // Caller initiates stop while setAsset is in flight (capture future before unlocking gate)
        final stopFuture = client.stop();

        // Now release setAsset load gate
        gateCompleter.complete();

        // Await both play and stop futures
        await playFuture;
        await stopFuture;

        // Player A must NEVER have called play()
        expect(playerA.playCallCount, 0,
            reason: 'Player retired during setAsset must never call play()');
      },
    );

    test(
      'hardware interruption begin cancels preview immediately and does NOT resume on end',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        await client.playAsset('assets/audio/adhan/adam-converted.mp3');
        expect(players.length, 1);
        final player = players[0];
        expect(player.isPlaying, isTrue);

        // Fire hardware interruption begin (phone call, alarm, ducking)
        fakeSession.emitInterruption();
        await Future<void>.delayed(Duration.zero);

        // Player must be stopped immediately
        expect(player.isPlaying, isFalse);
        expect(player.stopCallCount, greaterThanOrEqualTo(1));

        // Interruption ends: must NOT resume!
        await Future<void>.delayed(Duration.zero);
        expect(player.isPlaying, isFalse);
        expect(player.playCallCount, 1, reason: 'Interruption end must not auto-resume playback');
      },
    );

    test(
      'truthful stop failure: if prior audible stop fails, new audible play is forbidden',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );

        try {
          // Start playing voice A
          await client.playAsset('assets/audio/adhan/adam-converted.mp3');
          final playerA = players[0];

          // Simulate stop failure on player A
          playerA.throwOnStop = true;

          // Attempting to play voice B must fail because stopping player A failed!
          await expectLater(
            client.playAsset('assets/audio/adhan/atcovi-original.mp3'),
            throwsA(anything),
          );

          // Player B must NOT have been started!
          expect(players.length, 1,
              reason: 'New player must not be started if old player failed to stop physically');
        } finally {
          for (final p in players) {
            p.throwOnStop = false;
            if (p.stopGateCompleter != null && !p.stopGateCompleter!.isCompleted) {
              p.stopGateCompleter!.complete();
            }
          }
          await client.dispose().timeout(const Duration(seconds: 3));
        }
      },
    );

    test(
      'delayed physical stop A, new B then C before A stop finishes => C cannot play/activate before A stop success',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        // 1. Play Voice A
        await client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_A');
        expect(players.length, 1);
        final playerA = players[0];
        expect(playerA.isPlaying, isTrue);

        // Gate Player A's stop call
        final stopEntered = Completer<void>();
        final stopGate = Completer<void>();
        playerA.stopEnteredCompleter = stopEntered;
        playerA.stopGateCompleter = stopGate;

        // 2. Play B, then immediately play C before A's stop finishes
        final futB = client.playAsset('assets/audio/adhan/atcovi-original.mp3', requestToken: 'tok_B');
        await stopEntered.future;

        final futC = client.playAsset('assets/audio/adhan/malmo-fajr-extracted.mp3', requestToken: 'tok_C');

        // Give event loop turns
        await Future<void>.delayed(Duration.zero);

        // At this point, A is still blocked in stop. Neither B nor C could have played!
        expect(players.length, 1, reason: 'No new player could be created before Player A stop completes');
        expect(fakeSession.activateCallCount, 1, reason: 'Session cannot be reactivated before Player A stops');

        // Now release Player A stop
        stopGate.complete();

        final resB = await futB;
        final resC = await futC;

        // B was superseded by C while waiting for A to stop
        expect(resB, PlaybackStartupResult.cancelled);
        expect(resC, PlaybackStartupResult.started);

        // Player C is now created and playing
        expect(players.length, 2); // playerA and playerC (playerB was skipped before instantiation)
        expect(players[1].isPlaying, isTrue);
        expect(players[1].playCallCount, 1);
      },
    );

    test(
      'old deactivate deferred while B requested cannot disable B',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        await client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_A');
        expect(fakeSession.isActivated, isTrue);

        // Switch to B
        await client.playAsset('assets/audio/adhan/atcovi-original.mp3', requestToken: 'tok_B');
        expect(players.length, 2);
        final playerB = players[1];
        expect(playerB.isPlaying, isTrue);

        // CRITICAL: B's session must remain active; old A deactivation must not have disabled B!
        expect(fakeSession.isActivated, isTrue);
      },
    );

    test(
      'interruption/noisy during entered load leaves controller idle with no physical play',
      () async {
        final fakeSession = FakeAdhanAudioSession();
        final mockPlayer = MockAudioPlayer();
        final loadEntered = Completer<void>();
        final loadGate = Completer<void>();
        mockPlayer.setAssetEnteredCompleter = loadEntered;
        mockPlayer.setAssetGateCompleter = loadGate;

        final client = JustAudioPlayerClient(
          playerFactory: () => mockPlayer,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        final controller = AdhanAudioController(client);
        addTearDown(controller.dispose);

        final playFuture = controller.playVoice(AdhanVoice.adam);
        await loadEntered.future;

        // Interrupt while in entered load
        fakeSession.emitInterruption();
        await Future<void>.delayed(Duration.zero);

        loadGate.complete();
        await playFuture;

        expect(controller.state.status, AdhanAudioStatus.idle);
        expect(mockPlayer.playCallCount, 0, reason: 'Physical play must never be called when interrupted during load');
      },
    );

    test(
      'interruption/noisy during session activation leaves controller idle with no physical play',
      () async {
        final fakeSession = FakeAdhanAudioSession();
        fakeSession.activationCompleter = Completer<bool>();

        final mockPlayer = MockAudioPlayer();
        final client = JustAudioPlayerClient(
          playerFactory: () => mockPlayer,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        final controller = AdhanAudioController(client);
        addTearDown(controller.dispose);

        final playFuture = controller.playVoice(AdhanVoice.adam);
        await Future<void>.delayed(Duration.zero);

        // Interrupt during activation
        fakeSession.emitInterruption();
        await Future<void>.delayed(Duration.zero);

        // Complete activation late
        fakeSession.activationCompleter!.complete(true);
        await playFuture;

        expect(controller.state.status, AdhanAudioStatus.idle);
        expect(mockPlayer.playCallCount, 0, reason: 'Physical play must never be called when interrupted during activation');
      },
    );

    test(
      'SDK old event queued before handoff cannot mutate subsequent voice B state',
      () async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        final controller = AdhanAudioController(fakeClient);
        addTearDown(controller.dispose);

        // Play Voice A
        await controller.playVoice(AdhanVoice.adam);
        expect(controller.state.isPlaying, isTrue);
        final tokenA = fakeClient.lastRequestToken!;

        // Controller starts Voice B (currently loading)
        final bPlayFut = controller.playVoice(AdhanVoice.atcovi);

        // While B is loading, old completion and error with token A arrive
        fakeClient.emitCompletion(token: tokenA);
        fakeClient.emitError('Old decoder error', token: tokenA);
        fakeClient.emitPosition(const Duration(seconds: 50), token: tokenA);

        await bPlayFut;

        // Controller must be playing B, NOT completed or error from A!
        expect(controller.state.activeVoiceId, 'atcovi');
        expect(controller.state.isPlaying, isTrue);
        expect(controller.state.errorMessage, isNull);
      },
    );

    test(
      'same voice repeat generates unique tokens so old events do not mutate new playback',
      () async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        final controller = AdhanAudioController(fakeClient);
        addTearDown(controller.dispose);

        // 1. Play Adam first time
        await controller.playVoice(AdhanVoice.adam);
        final token1 = fakeClient.lastRequestToken!;

        // 2. Play Adam second time
        await controller.playVoice(AdhanVoice.adam);
        final token2 = fakeClient.lastRequestToken!;

        // Token must be distinct even for identical voice
        expect(token1, isNot(equals(token2)));

        // Event for token1 arrives late
        fakeClient.emitCompletion(token: token1);
        await Future<void>.delayed(Duration.zero);

        // Current status is playing token2, NOT completed from token1!
        expect(controller.state.isPlaying, isTrue);
      },
    );

    test(
      'late activation after timeout/stop does not invoke play or deactivate new session lease',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        fakeSession.activationCompleter = Completer<bool>();

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
          activationTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(client.dispose);

        // Player A times out waiting for activation
        await expectLater(
          client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_A'),
          throwsA(isA<StateError>()),
        );
        expect(players.length, 1);
        final playerA = players[0];
        expect(playerA.playCallCount, 0);

        // Now Player B plays and activates session
        fakeSession.activationCompleter = null;
        await client.playAsset('assets/audio/adhan/atcovi-original.mp3', requestToken: 'tok_B');
        expect(players.length, 2);
        final playerB = players[1];
        expect(playerB.isPlaying, isTrue);
        expect(fakeSession.isActivated, isTrue);

        await Future<void>.delayed(Duration.zero);

        // Player A still hasn't played and Player B session was NOT deactivated!
        expect(playerA.playCallCount, 0);
        expect(fakeSession.isActivated, isTrue);
        expect(playerB.isPlaying, isTrue);
      },
    );

    test(
      'position listener preserves actual lifecycle status pre-activation, post-completion, and on error',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final actCompleter = Completer<bool>();
        fakeSession.activationCompleter = actCompleter;

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
        );
        addTearDown(client.dispose);

        final events = <AdhanPlaybackEvent>[];
        final sub = client.playbackEventStream.listen(events.add);
        addTearDown(sub.cancel);

        final playFuture = client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_pos');

        await Future<void>.delayed(Duration.zero);
        final player = players[0];

        // 1. Position update emitted while still loading
        player.emitPosition(const Duration(seconds: 1));
        await Future<void>.delayed(Duration.zero);

        final loadPosEvent = events.lastWhere((e) => e.position == const Duration(seconds: 1));
        expect(loadPosEvent.status, AdhanPlaybackStatus.loading);

        // Complete activation and start playing
        actCompleter.complete(true);
        await playFuture;

        expect(events.last.status, AdhanPlaybackStatus.playing);

        // 2. Complete playback
        player.emitCompletion();
        await Future<void>.delayed(Duration.zero);
        expect(events.last.status, AdhanPlaybackStatus.completed);

        // Late position emitted after completion must NOT become playing
        player.emitPosition(const Duration(seconds: 2));
        await Future<void>.delayed(Duration.zero);
        expect(events.last.status, AdhanPlaybackStatus.completed);

        // 3. Error emitted
        player.emitError('Low level error');
        await Future<void>.delayed(Duration.zero);
        expect(events.last.status, AdhanPlaybackStatus.error);
        expect(events.last.errorMessage, 'خطأ أثناء تشغيل التسجيل الصوتي');

        // Late position emitted after error must NOT become playing
        player.emitPosition(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);
        expect(events.last.status, AdhanPlaybackStatus.error);
      },
    );

    test(
      'delayed stop success does not overwrite newly started Voice B with idle',
      () async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        final controller = AdhanAudioController(fakeClient);
        addTearDown(controller.dispose);

        // 1. Play Voice A
        await controller.playVoice(AdhanVoice.adam);
        expect(controller.state.isPlaying, isTrue);

        // 2. Start stop() (asynchronous)
        final stopFuture = controller.stop();

        // 3. While stop is in-flight, user taps Voice B
        final playBFuture = controller.playVoice(AdhanVoice.atcovi);

        await stopFuture;
        await playBFuture;

        // Controller state must remain with Voice B, NOT overwritten to idle
        expect(controller.state.activeVoiceId, 'atcovi');
        expect(controller.state.status, isNot(AdhanAudioStatus.idle));
      },
    );

    test(
      'delayed stop failure does not overwrite newly started Voice B with error but rethrows for reset',
      () async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        fakeClient.throwOnStop = true;
        addTearDown(fakeClient.dispose);

        final controller = AdhanAudioController(fakeClient);
        addTearDown(controller.dispose);

        // 1. Play Voice A
        await controller.playVoice(AdhanVoice.adam);

        // 2. Start stop() which will fail
        final stopFuture = controller.stop();

        // 3. While stop is in-flight, user taps Voice B
        final playBFuture = controller.playVoice(AdhanVoice.atcovi);

        // The stopFuture must rethrow the stop failure
        await expectLater(stopFuture, throwsA(anything));
        await playBFuture;

        // Voice B must NOT have been overwritten with stop's error state
        expect(controller.state.activeVoiceId, 'atcovi');
        expect(controller.state.status, isNot(AdhanAudioStatus.error));
      },
    );

    test(
      'timed-out activation completing late with true cleans up unowned focus when idle',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        fakeSession.activationCompleter = Completer<bool>();

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
          activationTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(client.dispose);

        // Activation times out
        await expectLater(
          client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_timeout'),
          throwsA(isA<StateError>()),
        );

        // System is idle (no active playback)
        fakeSession.activationCompleter!.complete(true);

        // Allow queue to drain and process late cleanup
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Unowned focus was cleaned up via deactivate
        expect(fakeSession.deactivateCallCount, greaterThanOrEqualTo(1));
      },
    );

    test(
      'timed-out activation completing late with true preserves newer active lease for Voice B',
      () async {
        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final fakeSession = FakeAdhanAudioSession();
        final actACompleter = Completer<bool>();
        fakeSession.activationCompleter = actACompleter;

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: fakeSession,
          activationTimeout: const Duration(milliseconds: 50),
        );
        addTearDown(client.dispose);

        // Player A times out
        await expectLater(
          client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_A'),
          throwsA(isA<StateError>()),
        );

        // Player B starts and immediately activates
        fakeSession.activationCompleter = null;
        await client.playAsset('assets/audio/adhan/atcovi-original.mp3', requestToken: 'tok_B');

        final deactivationsBeforeLateA = fakeSession.deactivateCallCount;

        // Player A's abandoned activation completes late with true
        actACompleter.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        // Player B is still playing, and Player B's active session lease was NOT deactivated
        expect(players[1].isPlaying, isTrue);
        expect(fakeSession.isActivated, isTrue);
        expect(fakeSession.deactivateCallCount, equals(deactivationsBeforeLateA));
      },
    );
  });

  group('DefaultAdhanAudioSession - Memoized Initialization & In-flight Dispose', () {
    test('concurrent getters memoize single ensureSession and create exactly one subscription pair', () async {
      int sessionCallCount = 0;
      final session = DefaultAdhanAudioSession(
        sessionProvider: () async {
          sessionCallCount++;
          return AudioSession.instance;
        },
      );
      addTearDown(session.dispose);

      // Access both streams concurrently
      final s1 = session.interruptionStream;
      final s2 = session.becomingNoisyStream;

      expect(s1, isNotNull);
      expect(s2, isNotNull);

      await Future<void>.delayed(Duration.zero);
      expect(sessionCallCount, lessThanOrEqualTo(1));
    });

    test('dispose while sessionProvider is in-flight cleanly aborts without leaking or throwing', () async {
      final providerCompleter = Completer<AudioSession>();
      final session = DefaultAdhanAudioSession(
        sessionProvider: () => providerCompleter.future,
      );

      final stream = session.interruptionStream;
      expect(stream, isNotNull);

      final disposeFuture = session.dispose();
      providerCompleter.complete(AudioSession.instance);
      await disposeFuture;
    });

    test(
      'timeout -> dispose -> late true triggers underlying OS setActive(false) and zero player.play',
      () async {
        DefaultAdhanAudioSession.resetStaticLeaseForTesting();

        final players = <MockAudioPlayer>[];
        MockAudioPlayer factory() {
          final p = MockAudioPlayer();
          players.add(p);
          return p;
        }

        final controllableAudioSession = ControllableAudioSession();
        addTearDown(controllableAudioSession.closeStreams);

        final session = DefaultAdhanAudioSession(
          sessionProvider: () async => controllableAudioSession,
        );

        final client = JustAudioPlayerClient(
          playerFactory: factory,
          audioSession: session,
          activationTimeout: const Duration(milliseconds: 30),
        );

        // Underlying OS setActive(true) hangs until manually completed
        controllableAudioSession.setActiveCompleter = Completer<bool>();

        // 1. Play asset times out on audio session activation
        await expectLater(
          client.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_timeout'),
          throwsA(isA<StateError>()),
        );

        // Player must never have played
        expect(players.length, 1);
        expect(players.first.playCallCount, 0);
        expect(controllableAudioSession.setActiveCalls, [true]);

        // 2. Client is disposed before OS activation completes
        await client.dispose();
        expect(players.first.playCallCount, 0);

        // 3. Underlying OS late-grants audio focus (true)
        controllableAudioSession.setActiveCompleter!.complete(true);

        // Allow late completion and cleanup to process
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Deterministic assertions:
        // Zero physical play calls
        expect(players.first.playCallCount, 0);
        // Abandoned activation must have triggered underlying OS setActive(false) cleanup
        expect(controllableAudioSession.setActiveCalls, [true, false]);
      },
    );

    test(
      'multiple DefaultAdhanAudioSession instances sharing OS session: older disposed instance late completion preserves newer owner lease',
      () async {
        DefaultAdhanAudioSession.resetStaticLeaseForTesting();

        final players1 = <MockAudioPlayer>[];
        MockAudioPlayer factory1() {
          final p = MockAudioPlayer();
          players1.add(p);
          return p;
        }

        final players2 = <MockAudioPlayer>[];
        MockAudioPlayer factory2() {
          final p = MockAudioPlayer();
          players2.add(p);
          return p;
        }

        final sharedOsSession = ControllableAudioSession();
        addTearDown(sharedOsSession.closeStreams);

        // Instance 1: times out and is disposed while OS activation is in-flight
        final session1 = DefaultAdhanAudioSession(
          sessionProvider: () async => sharedOsSession,
        );
        final client1 = JustAudioPlayerClient(
          playerFactory: factory1,
          audioSession: session1,
          activationTimeout: const Duration(milliseconds: 30),
        );

        final session1Completer = Completer<bool>();
        sharedOsSession.setActiveCompleter = session1Completer;

        await expectLater(
          client1.playAsset('assets/audio/adhan/adam-converted.mp3', requestToken: 'tok_inst1'),
          throwsA(isA<StateError>()),
        );
        await client1.dispose();

        expect(sharedOsSession.setActiveCalls, [true]);

        // Instance 2: new session activates immediately and acquires active lease
        sharedOsSession.setActiveCompleter = null;
        final session2 = DefaultAdhanAudioSession(
          sessionProvider: () async => sharedOsSession,
        );
        final client2 = JustAudioPlayerClient(
          playerFactory: factory2,
          audioSession: session2,
        );
        addTearDown(client2.dispose);

        await client2.playAsset('assets/audio/adhan/atcovi-original.mp3', requestToken: 'tok_inst2');
        expect(players2.first.isPlaying, isTrue);
        expect(sharedOsSession.setActiveCalls, [true, true]);

        // Now Instance 1's abandoned activation completes late with true
        session1Completer.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // Instance 2's active lease must NOT have been deactivated by Instance 1
        expect(players2.first.isPlaying, isTrue);
        expect(
          sharedOsSession.setActiveCalls,
          [true, true],
          reason: 'Older disposed instance must not call setActive(false) while newer instance owns lease',
        );

        // When Instance 2 eventually disposes, it cleanly deactivates the OS session
        await client2.dispose();
        expect(sharedOsSession.setActiveCalls, [true, true, false]);
      },
    );
  });

  group('PreferencesController.resetAllState and Persistence Safety', () {
    test(
      'resetAllState() fails and preserves database records when audio stop fails',
      () async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        fakeClient.throwOnStop = true;
        addTearDown(fakeClient.dispose);

        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        await repo.createBookmark(
          name: 'علامة ورد الفجر',
          pageNumber: 50,
        );
        await repo.savePreferences(
          const UserPreferences(
            selectedCity: 'الرياض',
            selectedTimezone: 'Asia/Riyadh',
          ),
        );

        final container = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
            adhanAudioPlayerClientProvider.overrideWithValue(fakeClient),
          ],
        );
        addTearDown(container.dispose);

        await container.read(preferencesControllerProvider.future);
        final controller = container.read(preferencesControllerProvider.notifier);

        await expectLater(
          controller.resetAllState(),
          throwsA(anything),
        );

        final bookmarks = await repo.getBookmarks();
        expect(bookmarks.length, 1,
            reason: 'User bookmarks must be preserved when audio stop fails');
        expect(bookmarks.first.name, 'علامة ورد الفجر');

        final prefs = await repo.getPreferences();
        expect(prefs.selectedCity, 'الرياض',
            reason: 'User preferences must be preserved when audio stop fails');
      },
    );

    test(
      'resetAllState() succeeds and resets database records when audio stop succeeds',
      () async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        await repo.createBookmark(
          name: 'علامة للحذف',
          pageNumber: 50,
        );

        final container = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
            adhanAudioPlayerClientProvider.overrideWithValue(fakeClient),
          ],
        );
        addTearDown(container.dispose);

        await container.read(preferencesControllerProvider.future);
        final controller = container.read(preferencesControllerProvider.notifier);

        await controller.resetAllState();

        final bookmarks = await repo.getBookmarks();
        expect(bookmarks, isEmpty, reason: 'Bookmarks should be cleared after successful reset');

        final prefs = await repo.getPreferences();
        expect(prefs.generalAdhanVoice, 'adam');
        expect(prefs.fajrAdhanVoice, 'malmo_fajr');
      },
    );
  });

  group('Canonical Manifest pending_registries Agreement', () {
    test(
      'canonical manifest pending_registries.adhan_audio agrees with AdhanVoice definitions',
      () async {
        final manifestFile = File('assets/content/manifest.json');
        expect(manifestFile.existsSync(), isTrue);

        final manifestJson =
            jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        final pending =
            manifestJson['pending_registries'] as Map<String, dynamic>;
        final adhanAudio = pending['adhan_audio'] as Map<String, dynamic>;
        final manifestVoices =
            (adhanAudio['voices'] as List).cast<Map<String, dynamic>>();

        expect(manifestVoices.length, 3);
        expect(AdhanVoice.allVoices.length, 3);

        for (final mVoice in manifestVoices) {
          final voiceId = mVoice['id'] as String;
          final domainVoice = AdhanVoice.findById(voiceId);
          expect(domainVoice, isNotNull,
              reason: 'Domain must contain voice $voiceId');

          expect(domainVoice!.isFajr, mVoice['is_fajr']);
          expect(domainVoice.nameAr, mVoice['name_ar']);
          expect(domainVoice.title, mVoice['title']);
          expect(domainVoice.performerOrSource, mVoice['performer_or_source']);
          expect(domainVoice.license, mVoice['license']);
          expect(domainVoice.licenseUrl, mVoice['license_url']);
          expect(domainVoice.sourceUrl, mVoice['source_url']);

          final audioFile = mVoice['audio_file'] as Map<String, dynamic>;
          expect(domainVoice.audioAssetPath, audioFile['path']);
          expect(domainVoice.durationSeconds, audioFile['duration_seconds']);

          final alertClip = mVoice['alert_clip'] as Map<String, dynamic>;
          expect(domainVoice.alertClipPath, alertClip['path']);
        }
      },
    );
  });

  group('Schema Version Upgrade & Migration (All 9 Tables Preserved)', () {
    test(
      'upgrades schema v1 to v4, preserves all original tables and rows intact, adds voice columns with defaults',
      () async {
        final rawDb = await databaseFactory.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              final batch = db.batch();
              batch.execute('''
                CREATE TABLE reading_progress (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  last_page INTEGER NOT NULL DEFAULT 1 CHECK (last_page >= 1 AND last_page <= 604),
                  selected_surah INTEGER,
                  selected_verse INTEGER,
                  updated_at TEXT NOT NULL
                );
              ''');
              batch.execute('''
                INSERT INTO reading_progress (id, last_page, updated_at)
                VALUES (1, 42, '2026-09-01T00:00:00');
              ''');

              batch.execute('''
                CREATE TABLE bookmarks (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  name TEXT NOT NULL,
                  page_number INTEGER NOT NULL CHECK (page_number >= 1 AND page_number <= 604),
                  surah_number INTEGER,
                  verse_number INTEGER,
                  created_at TEXT NOT NULL
                );
              ''');
              batch.execute('''
                INSERT INTO bookmarks (name, page_number, created_at)
                VALUES ('علامة ورد الفجر', 42, '2026-09-01T00:00:00');
              ''');

              batch.execute('''
                CREATE TABLE favorites (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  content_kind TEXT NOT NULL,
                  stable_id TEXT NOT NULL,
                  title TEXT NOT NULL,
                  subtitle TEXT,
                  created_at TEXT NOT NULL,
                  UNIQUE (content_kind, stable_id)
                );
              ''');
              batch.execute('''
                INSERT INTO favorites (content_kind, stable_id, title, subtitle, created_at)
                VALUES ('dua', 'dua_morning_01', 'أذكار الصباح', 'حصن المسلم', '2026-09-01T00:00:00');
              ''');

              batch.execute('''
                CREATE TABLE dhikr_sessions (
                  session_id TEXT PRIMARY KEY,
                  dhikr_id TEXT NOT NULL,
                  category TEXT NOT NULL,
                  target_count INTEGER NOT NULL CHECK (target_count > 0),
                  current_count INTEGER NOT NULL DEFAULT 0 CHECK (current_count >= 0 AND current_count <= target_count),
                  is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
                  date_bucket TEXT NOT NULL,
                  created_at TEXT NOT NULL,
                  updated_at TEXT NOT NULL
                );
              ''');
              batch.execute('''
                INSERT INTO dhikr_sessions (session_id, dhikr_id, category, target_count, current_count, is_completed, date_bucket, created_at, updated_at)
                VALUES ('sess_subhanallah_01', 'subhan_allah', 'morning', 33, 15, 0, '2026-09-01', '2026-09-01T00:00:00', '2026-09-01T00:00:00');
              ''');

              batch.execute('''
                CREATE TABLE daily_progress (
                  date_bucket TEXT PRIMARY KEY,
                  quran_completed INTEGER NOT NULL DEFAULT 0,
                  morning_dhikr_completed INTEGER NOT NULL DEFAULT 0,
                  evening_dhikr_completed INTEGER NOT NULL DEFAULT 0,
                  post_prayer_dhikr_completed INTEGER NOT NULL DEFAULT 0,
                  daily_dua_completed INTEGER NOT NULL DEFAULT 0,
                  quran_goal_pages INTEGER NOT NULL DEFAULT 2,
                  quran_pages_read INTEGER NOT NULL DEFAULT 0,
                  updated_at TEXT NOT NULL
                );
              ''');
              batch.execute('''
                INSERT INTO daily_progress (date_bucket, quran_completed, morning_dhikr_completed, updated_at)
                VALUES ('2026-09-01', 1, 1, '2026-09-01T00:00:00');
              ''');

              batch.execute('''
                CREATE TABLE user_preferences (
                  id INTEGER PRIMARY KEY CHECK (id = 1),
                  dark_mode TEXT NOT NULL DEFAULT 'system',
                  text_scale REAL NOT NULL DEFAULT 1.0,
                  selected_city TEXT NOT NULL DEFAULT 'القاهرة',
                  selected_timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
                  quran_default_goal INTEGER NOT NULL DEFAULT 2,
                  notifications_enabled INTEGER NOT NULL DEFAULT 0,
                  active_dhikr_session_id TEXT,
                  updated_at TEXT NOT NULL
                );
              ''');
              batch.execute('''
                INSERT INTO user_preferences (id, dark_mode, text_scale, selected_city, selected_timezone, quran_default_goal, notifications_enabled, active_dhikr_session_id, updated_at)
                VALUES (1, 'dark', 1.2, 'مكة المكرمة', 'Asia/Riyadh', 4, 1, 'sess_subhanallah_01', '2026-09-01T00:00:00');
              ''');
              await batch.commit(noResult: true);
            },
          ),
        );
        await rawDb.close();

        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final openedDb = await appDb.database;
        final version = await openedDb.getVersion();
        expect(version, 4, reason: 'Database schema version must be upgraded to 4');

        final tables = await openedDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        final tableNames = tables.map((t) => t['name'] as String).toSet();
        expect(tableNames, containsAll({
          'reading_progress',
          'bookmarks',
          'favorites',
          'dhikr_sessions',
          'daily_progress',
          'user_preferences',
          'hisn_daily_item_progress',
          'daily_quran_pages',
          'daily_source_confirmations',
        }));

        final prefs = await repo.getPreferences();
        expect(prefs.darkMode, 'dark');
        expect(prefs.textScale, 1.2);
        expect(prefs.selectedCity, 'مكة المكرمة');
        expect(prefs.selectedTimezone, 'Asia/Riyadh');
        expect(prefs.quranDefaultGoal, 4);
        expect(prefs.notificationsEnabled, isTrue);
        expect(prefs.activeDhikrSessionId, 'sess_subhanallah_01');
        expect(prefs.generalAdhanVoice, 'adam');
        expect(prefs.fajrAdhanVoice, 'malmo_fajr');

        final reading = await repo.getReadingProgress();
        expect(reading.lastPage, 42);

        final bookmarks = await repo.getBookmarks();
        expect(bookmarks.length, 1);
        expect(bookmarks.first.name, 'علامة ورد الفجر');
        expect(bookmarks.first.pageNumber, 42);

        final favs = await repo.getFavorites();
        expect(favs.length, 1);
        expect(favs.first.stableId, 'dua_morning_01');

        final session = await repo.getDhikrSession('sess_subhanallah_01');
        expect(session, isNotNull);
        expect(session!.currentCount, 15);

        final rawDailyRows = await openedDb.query(
          'daily_progress',
          where: 'date_bucket = ?',
          whereArgs: ['2026-09-01'],
        );
        expect(rawDailyRows.length, 1);
        expect(rawDailyRows.first['quran_completed'], 1);
        expect(rawDailyRows.first['morning_dhikr_completed'], 1);

        final daily = await repo.getDailyProgress('2026-09-01');
        expect(daily.quranCompleted, isFalse);
        expect(daily.morningDhikrCompleted, isFalse);
      },
    );
  });

  group('Preferences Concurrent Updates & Data Loss Prevention', () {
    test(
      'concurrent intent setters serialize and preserve all modified fields without full-row clobbering',
      () async {
        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final container = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
          ],
        );
        addTearDown(container.dispose);

        await container.read(preferencesControllerProvider.future);
        final controller = container.read(preferencesControllerProvider.notifier);

        await Future.wait([
          controller.setDarkMode('dark'),
          controller.setTextScale(1.4),
          controller.setCity('دبي', 'Asia/Dubai'),
          controller.setQuranGoal(8),
          controller.setGeneralAdhanVoice('atcovi'),
          controller.setFajrAdhanVoice('adam'),
        ]);

        final inMemory = container.read(preferencesControllerProvider).valueOrNull;
        expect(inMemory?.darkMode, 'dark');
        expect(inMemory?.textScale, 1.4);
        expect(inMemory?.selectedCity, 'دبي');
        expect(inMemory?.selectedTimezone, 'Asia/Dubai');
        expect(inMemory?.quranDefaultGoal, 8);
        expect(inMemory?.generalAdhanVoice, 'atcovi');
        expect(inMemory?.fajrAdhanVoice, 'adam');

        final persisted = await repo.getPreferences();
        expect(persisted.darkMode, 'dark');
        expect(persisted.textScale, 1.4);
        expect(persisted.selectedCity, 'دبي');
        expect(persisted.selectedTimezone, 'Asia/Dubai');
        expect(persisted.quranDefaultGoal, 8);
        expect(persisted.generalAdhanVoice, 'atcovi');
        expect(persisted.fajrAdhanVoice, 'adam');
      },
    );
  });

  group('Timezone Stability in DateBucketService', () {
    test(
      'retains last known selected timezone during preferences reload without projecting Cairo',
      () async {
        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        await repo.savePreferences(
          const UserPreferences(
            selectedCity: 'الرياض',
            selectedTimezone: 'Asia/Riyadh',
          ),
        );

        DateTime fixedClock() => DateTime.utc(2026, 9, 28, 12, 0);

        final container = ProviderContainer(
          overrides: [
            clockProvider.overrideWithValue(fixedClock),
            progressRepositoryProvider.overrideWithValue(repo),
            quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
          ],
        );
        addTearDown(container.dispose);

        await container.read(preferencesControllerProvider.future);
        final initialBucket = container.read(activeDateBucketProvider);
        expect(initialBucket, startsWith('Asia/Riyadh|'));

        container.invalidate(preferencesControllerProvider);

        final bucketDuringLoading = container.read(activeDateBucketProvider);
        expect(
          bucketDuringLoading,
          startsWith('Asia/Riyadh|'),
          reason: 'Date bucket must stabilize on last known timezone and not fall back to Cairo during loading',
        );
      },
    );
  });

  group('Voice Validation, Equality, & Corrupted Recovery', () {
    test('AdhanAudioState equality correctly checks other.activeVoiceId', () {
      const state1 = AdhanAudioState(
        activeVoiceId: 'adam',
        status: AdhanAudioStatus.playing,
      );
      const state2 = AdhanAudioState(
        activeVoiceId: 'atcovi',
        status: AdhanAudioStatus.playing,
      );
      const state3 = AdhanAudioState(
        activeVoiceId: 'adam',
        status: AdhanAudioStatus.playing,
      );

      expect(state1 == state2, isFalse, reason: 'States with different voices must not be equal');
      expect(state1 == state3, isTrue, reason: 'States with identical fields must be equal');
      expect(state1.hashCode == state3.hashCode, isTrue);
    });

    test('UserPreferences equality correctly checks voiceRecoveryNotice', () {
      const prefs1 = UserPreferences(
        generalAdhanVoice: 'adam',
        voiceRecoveryNotice: false,
      );
      const prefs2 = UserPreferences(
        generalAdhanVoice: 'adam',
        voiceRecoveryNotice: true,
      );
      expect(prefs1 == prefs2, isFalse);
      expect(prefs1.hashCode == prefs2.hashCode, isFalse);
    });

    test('rejects unauthorized voice IDs in setters', () async {
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(
        appDb,
        versePageValidator: quranRepo.isValidVerseOnPage,
      );
      addTearDown(() => repo.close());

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      final controller = container.read(preferencesControllerProvider.notifier);

      expect(
        () => controller.setGeneralAdhanVoice('malmo_fajr'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => controller.setGeneralAdhanVoice('nonexistent_voice'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => controller.setFajrAdhanVoice('nonexistent_voice'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'recovers safely to defaults when raw database values are corrupted and flags recovery notice',
      () async {
        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final db = await appDb.database;
        await db.execute('''
          UPDATE user_preferences
          SET general_adhan_voice = 'corrupted_general',
              fajr_adhan_voice = 'corrupted_fajr'
          WHERE id = 1;
        ''');

        final prefs = await repo.getPreferences();
        expect(prefs.generalAdhanVoice, 'adam');
        expect(prefs.fajrAdhanVoice, 'malmo_fajr');
        expect(
          prefs.voiceRecoveryNotice,
          isTrue,
          reason: 'Corrupted database voice IDs must trigger honest recovery notice',
        );
      },
    );

    test(
      'unrelated preference setter retains corrupted voice and recovery notice until explicit repair',
      () async {
        final appDb = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final repo = ProgressRepository(
          appDb,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        addTearDown(() => repo.close());

        final db = await appDb.database;
        await db.execute('''
          UPDATE user_preferences
          SET general_adhan_voice = 'corrupted_general',
              fajr_adhan_voice = 'corrupted_fajr'
          WHERE id = 1;
        ''');

        final container = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
          ],
        );
        addTearDown(container.dispose);

        await container.read(preferencesControllerProvider.future);
        final controller = container.read(preferencesControllerProvider.notifier);

        var prefs = container.read(preferencesControllerProvider).valueOrNull;
        expect(prefs?.voiceRecoveryNotice, isTrue);

        await controller.setDarkMode('dark');

        prefs = container.read(preferencesControllerProvider).valueOrNull;
        expect(prefs?.darkMode, 'dark');
        expect(prefs?.voiceRecoveryNotice, isTrue,
            reason: 'Unrelated setter must not clear voice recovery notice');

        final rawRows = await db.query('user_preferences', where: 'id = 1');
        expect(rawRows.first['general_adhan_voice'], 'corrupted_general',
            reason: 'Unrelated setter must not overwrite corrupted voice column in SQLite');

        await controller.setGeneralAdhanVoice('atcovi');
        await controller.setFajrAdhanVoice('adam');

        prefs = container.read(preferencesControllerProvider).valueOrNull;
        expect(prefs?.generalAdhanVoice, 'atcovi');
        expect(prefs?.fajrAdhanVoice, 'adam');
        expect(prefs?.voiceRecoveryNotice, isFalse,
            reason: 'Explicit repair clears recovery notice');
      },
    );
  });

  group('Adhan Audio Controller Lifecycle & Stop Failures', () {
    test('plays voice and handles natural completion truthfully', () async {
      final fakeClient = FakeAdhanAudioPlayerClient();
      addTearDown(fakeClient.dispose);

      final controller = AdhanAudioController(fakeClient);
      addTearDown(controller.dispose);

      expect(controller.state.status, AdhanAudioStatus.idle);

      await controller.playVoice(AdhanVoice.adam);
      expect(controller.state.status, AdhanAudioStatus.playing);
      expect(controller.state.activeVoiceId, 'adam');

      fakeClient.emitCompletion();
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.status, AdhanAudioStatus.completed);
      expect(controller.state.position, Duration.zero);
      expect(controller.state.isPlaying, isFalse);
    });

    test('handles stop failure conservatively without falsely claiming idle', () async {
      final fakeClient = FakeAdhanAudioPlayerClient();
      addTearDown(fakeClient.dispose);

      final controller = AdhanAudioController(fakeClient);
      addTearDown(controller.dispose);

      await controller.playVoice(AdhanVoice.adam);
      expect(controller.state.status, AdhanAudioStatus.playing);

      fakeClient.throwOnStop = true;
      try {
        await controller.stop();
      } catch (_) {}

      expect(controller.state.status, AdhanAudioStatus.error);
      expect(controller.state.errorMessage, 'تعذر إيقاف التشغيل الصوتي. يرجى إعادة المحاولة.');
    });

    test('handles playback error with stable localized Arabic error message', () async {
      final fakeClient = FakeAdhanAudioPlayerClient();
      fakeClient.throwOnPlay = true;
      addTearDown(fakeClient.dispose);

      final controller = AdhanAudioController(fakeClient);
      addTearDown(controller.dispose);

      await controller.playVoice(AdhanVoice.adam);
      expect(controller.state.status, AdhanAudioStatus.error);
      expect(controller.state.errorMessage, 'تعذر تشغيل التسجيل الصوتي. يرجى إعادة المحاولة.');
    });
  });

  group('SettingsScreen, PrayersScreen, and AppShell UI Audio Integration', () {
    testWidgets(
      'SettingsScreen displays voice pickers, preview tiles, and recovery notice banner',
      (tester) async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        late Directory testDir;
        late AppDatabase testDb;
        late ProgressRepository testRepo;
        late ProviderContainer container;

        await tester.runAsync(() async {
          testDir = await Directory.systemTemp.createTemp('zad_settings_ui_');
          testDb = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: p.join(testDir.path, 'settings.db'),
          );
          testRepo = ProgressRepository(
            testDb,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );

          // Seed corrupted general voice to verify honest recovery notice
          final db = await testDb.database;
          await db.execute('''
            UPDATE user_preferences
            SET general_adhan_voice = 'invalid_voice'
            WHERE id = 1;
          ''');

          container = ProviderContainer(
            overrides: [
              progressRepositoryProvider.overrideWithValue(testRepo),
              quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
              cityRepositoryProvider.overrideWith((ref) async => cityRepo),
              adhanAudioPlayerClientProvider.overrideWithValue(fakeClient),
            ],
          );

          // Hydrate city and preferences controller before mounting widget
          await container.read(cityRepositoryProvider.future);
          await container.read(preferencesControllerProvider.future);
        });

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() async {
            await testRepo.close();
            if (await testDir.exists()) await testDir.delete(recursive: true);
          });
        });

        try {
          await _ensureTestFonts(tester);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: SettingsScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Scroll bounded actual ListView until heading is built and visible BEFORE assertions
          final headingFinder = find.text('أصوات الأذان وتجربة الاستماع');
          for (int i = 0; i < 30 && headingFinder.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -150));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(headingFinder, findsOneWidget);

          // Scroll progressively through recovery notice and voice pickers
          final recoveryNotice = find.text(
            'تمت استعادة أصوات الأذان الافتراضية لعدم صلاحية الاختيار المحفوظ سابقاً.',
          );
          for (int i = 0; i < 15 && recoveryNotice.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -100));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(recoveryNotice, findsOneWidget);

          final generalVoiceFinder = find.text('صوت أذان الصلوات العامة');
          for (int i = 0; i < 15 && generalVoiceFinder.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -100));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(generalVoiceFinder, findsOneWidget);

          final fajrVoiceFinder = find.text('صوت أذان الفجر');
          for (int i = 0; i < 15 && fajrVoiceFinder.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -100));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(fajrVoiceFinder, findsOneWidget);

          // Genuinely scroll to the first preview button and assert hitTestable
          final previewBtn = find.byWidgetPredicate(
            (w) => w is IconButton && (w.tooltip == 'استماع للتسجيل' || w.tooltip == 'تشغيل المعاينة'),
          ).first;
          for (int i = 0; i < 20 && previewBtn.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -100));
            await tester.pumpAndSettle();
          }
          expect(previewBtn.hitTestable(), findsOneWidget);

          await tester.tap(previewBtn);
          await tester.pumpAndSettle();

          expect(fakeClient.playCallCount, 1);
          expect(find.text('إيقاف الاستماع'), findsAtLeastNWidgets(1));

          // Genuinely scroll if needed to stop button and assert hitTestable
          final stopBtn = find.text('إيقاف الاستماع').first;
          for (int i = 0; i < 20 && stopBtn.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(ListView), const Offset(0, -100));
            await tester.pumpAndSettle();
          }
          expect(stopBtn.hitTestable(), findsWidgets);

          await tester.tap(stopBtn);
          await tester.pumpAndSettle();
          expect(fakeClient.stopCallCount, greaterThanOrEqualTo(1));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() async {
            await testRepo.close();
            if (await testDir.exists()) await testDir.delete(recursive: true);
          });
        }
      },
    );

    testWidgets(
      'PrayersScreen displays neutral available-recordings label and preview buttons',
      (tester) async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        late Directory testDir;
        late AppDatabase testDb;
        late ProgressRepository testRepo;
        late ProviderContainer container;

        await tester.runAsync(() async {
          testDir = await Directory.systemTemp.createTemp('zad_prayers_ui_');
          testDb = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: p.join(testDir.path, 'prayers.db'),
          );
          testRepo = ProgressRepository(
            testDb,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );

          container = ProviderContainer(
            overrides: [
              progressRepositoryProvider.overrideWithValue(testRepo),
              quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
              cityRepositoryProvider.overrideWith((ref) async => cityRepo),
              adhanAudioPlayerClientProvider.overrideWithValue(fakeClient),
            ],
          );

          // Hydrate city and preferences controller before mounting widget
          await container.read(cityRepositoryProvider.future);
          await container.read(preferencesControllerProvider.future);
        });

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() async {
            await testRepo.close();
            if (await testDir.exists()) await testDir.delete(recursive: true);
          });
        });

        try {
          await _ensureTestFonts(tester);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: PrayersScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Genuinely scroll to the neutral available-recordings section until preview button is hitTestable
          final labelFinder = find.text('تسجيلات الأذان المتوفرة');
          final previewBtn = find.text('معاينة أذان الصلوات العامة');
          for (int i = 0; i < 25 && previewBtn.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -150));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(labelFinder, findsOneWidget);
          expect(previewBtn.hitTestable(), findsOneWidget);
          expect(find.text('معاينة أذان الفجر'), findsOneWidget);

          // Tap preview button
          await tester.tap(previewBtn);
          await tester.pumpAndSettle();
          expect(fakeClient.playCallCount, 1);

          // Tap stop button
          final stopBtn = find.text('إيقاف');
          for (int i = 0; i < 25 && stopBtn.hitTestable().evaluate().isEmpty; i++) {
            await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -150));
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(stopBtn.hitTestable(), findsOneWidget);
          await tester.tap(stopBtn);
          await tester.pumpAndSettle();
          expect(fakeClient.stopCallCount, greaterThanOrEqualTo(1));
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() async {
            await testRepo.close();
            if (await testDir.exists()) await testDir.delete(recursive: true);
          });
        }
      },
    );

    testWidgets(
      'AppShell stops audio on tab switch and on lifecycle backgrounding',
      (tester) async {
        final fakeClient = FakeAdhanAudioPlayerClient();
        addTearDown(fakeClient.dispose);

        late Directory testDir;
        late AppDatabase testDb;
        late ProgressRepository testRepo;
        late ProviderContainer container;

        await tester.runAsync(() async {
          testDir = await Directory.systemTemp.createTemp('zad_appshell_ui_');
          testDb = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: p.join(testDir.path, 'appshell.db'),
          );
          testRepo = ProgressRepository(
            testDb,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );

          container = ProviderContainer(
            overrides: [
              progressRepositoryProvider.overrideWithValue(testRepo),
              quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
              cityRepositoryProvider.overrideWith((ref) async => cityRepo),
              adhanAudioPlayerClientProvider.overrideWithValue(fakeClient),
            ],
          );

          await testRepo.saveReadingProgress(const ReadingProgress(lastPage: 1));
          await container.read(cityRepositoryProvider.future);
          await container.read(readingProgressControllerProvider.future);
          await container.read(preferencesControllerProvider.future);
        });

        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() async {
            await testRepo.close();
            if (await testDir.exists()) await testDir.delete(recursive: true);
          });
        });

        try {
          await _ensureTestFonts(tester);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: AppShell(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await container.read(adhanAudioControllerProvider.notifier).playVoice(AdhanVoice.adam);
          expect(container.read(adhanAudioControllerProvider).isPlaying, isTrue);

          final quranTab = find.text('القرآن');
          expect(quranTab.hitTestable(), findsOneWidget);
          await tester.tap(quranTab);
          await tester.pumpAndSettle();

          expect(
            container.read(adhanAudioControllerProvider).isPlaying,
            isFalse,
            reason: 'Audio must stop when switching tabs in AppShell',
          );
          expect(fakeClient.stopCallCount, greaterThanOrEqualTo(1));

          await container.read(adhanAudioControllerProvider.notifier).playVoice(AdhanVoice.adam);
          expect(container.read(adhanAudioControllerProvider).isPlaying, isTrue);

          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await tester.pump();

          expect(
            container.read(adhanAudioControllerProvider).isPlaying,
            isFalse,
            reason: 'Audio must stop when app is backgrounded/paused',
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() async {
            await testRepo.close();
            if (await testDir.exists()) await testDir.delete(recursive: true);
          });
        }
      },
    );

    Future<void> scrollSourcesListViewUntil({
      required WidgetTester tester,
      required Finder target,
      int maxDrags = 140,
    }) async {
      final listViewFinder = find.byType(ListView);
      expect(listViewFinder, findsOneWidget, reason: 'SourcesScreen ListView must exist');
      final listRect = tester.getRect(listViewFinder);
      // Start drag at outer-list margin: left + 4 (inside ListView bounds, outside child Card 16 padding)
      final dragPoint = Offset(listRect.left + 4.0, listRect.center.dy);
      final scrollableFinder = find.descendant(
        of: listViewFinder,
        matching: find.byType(Scrollable),
      ).first;

      for (int i = 0; i < maxDrags; i++) {
        if (target.hitTestable().evaluate().isNotEmpty) {
          return;
        }

        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        final position = scrollableState.position;
        final pixelsBefore = position.pixels;
        final maxScroll = position.maxScrollExtent;

        await tester.dragFrom(dragPoint, const Offset(0, -150));
        await tester.pump(const Duration(milliseconds: 50));

        final pixelsAfter = position.pixels;
        if (pixelsBefore < maxScroll) {
          expect(
            pixelsAfter,
            greaterThan(pixelsBefore),
            reason: 'Outer ListView must actually move on drag $i (before=$pixelsBefore, after=$pixelsAfter, max=$maxScroll)',
          );
        } else {
          break;
        }
      }

      if (target.hitTestable().evaluate().isEmpty) {
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        final position = scrollableState.position;
        final sampleTexts = find.byType(Text).evaluate()
            .map((e) => (e.widget as Text).data ?? '')
            .where((t) => t.trim().isNotEmpty)
            .take(8)
            .toList();
        fail('Target not hitTestable after $maxDrags drags. Scroll position: ${position.pixels}/${position.maxScrollExtent}. Visible sample texts: $sampleTexts');
      }
    }

    testWidgets(
      'SourcesScreen displays Card 8 with verified Adhan audio provenance',
      (tester) async {
        await _ensureTestFonts(tester);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const Directionality(
                textDirection: TextDirection.rtl,
                child: SourcesScreen(),
              ),
            ),
          ),
        );

        // Bounded pump + runAsync real I/O until FutureBuilder licenses snapshot completes
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        bool licensesReady = false;
        String? loadError;

        while (DateTime.now().isBefore(deadline)) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();

          final waiting = find.text('جاري قراءة نصوص التراخيص الأصلية من حزمة التطبيق...');
          final error = find.text('تعذر قراءة نصوص التراخيص الأصلية من ملفات الحزمة.');

          if (error.evaluate().isNotEmpty) {
            loadError = 'SourcesScreen displayed license error card (asset read failure)';
            break;
          }
          if (waiting.evaluate().isEmpty) {
            licensesReady = true;
            break;
          }
        }

        if (loadError != null) {
          fail(loadError);
        }
        if (!licensesReady) {
          fail('SourcesScreen license asset I/O timed out after 5s; snapshot still waiting');
        }

        await tester.pumpAndSettle();

        // Card 2 at top of screen
        expect(find.text('تسجيلات الأذان والتنبيهات المدمجة'), findsOneWidget);
        expect(find.text('مدمجة ومحققة المصدر'), findsOneWidget);

        // Genuinely scroll to Card 8 near bottom of list
        final card8Finder = find.text('نسب المصادر وتراخيص تسجيلات الأذان (Adhan Audio Sources)');
        await scrollSourcesListViewUntil(
          tester: tester,
          target: card8Finder,
          maxDrags: 140,
        );
        expect(card8Finder.hitTestable(), findsOneWidget);

        // Progressively scroll to verify disclosures inside Card 8
        final voice1Finder = find.textContaining('المؤلف والرافع: Adam-synagda');
        await scrollSourcesListViewUntil(
          tester: tester,
          target: voice1Finder,
          maxDrags: 20,
        );
        expect(voice1Finder.hitTestable(), findsOneWidget);

        final voice2Finder = find.textContaining('المؤلف والرافع المنسوب: Atcovi');
        await scrollSourcesListViewUntil(
          tester: tester,
          target: voice2Finder,
          maxDrags: 20,
        );
        expect(voice2Finder.hitTestable(), findsOneWidget);

        final voice3Finder = find.textContaining('المؤلف المنسوب: المركز الإسلامي في مالمو');
        await scrollSourcesListViewUntil(
          tester: tester,
          target: voice3Finder,
          maxDrags: 20,
        );
        expect(voice3Finder.hitTestable(), findsOneWidget);
      },
    );
  });
}
