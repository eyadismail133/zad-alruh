import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/more/presentation/sources_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/adhan_voice.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/adhan_audio_session.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/just_audio_player_client.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/native_prayer_audio_control.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_calculator.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/adhan_audio_controller.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/progress/presentation/widgets/quran_page_confirmation_control.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/kfqc_mushaf_catalog.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';
import 'package:zad_alruh/src/features/quran/domain/models/quran_audio_source.dart';
import 'package:zad_alruh/src/features/quran/presentation/quran_reader_screen.dart';
import 'package:zad_alruh/src/features/quran/presentation/quran_screen.dart';
import 'package:zad_alruh/src/features/shell/presentation/app_shell.dart';

// =============================================================================
// Test Doubles & Mocks
// =============================================================================

/// Controllable mock of [AudioPlayer] for isolating [JustAudioPlayerClient] at the genuine SDK boundary.
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
  Completer<void>? playEndCompleter;
  Completer<void>? stopEnteredCompleter;
  Completer<void>? stopGateCompleter;

  bool throwOnSetUrl = false;
  bool throwOnSetAsset = false;
  bool throwOnPlay = false;
  bool throwOnStop = false;
  bool throwOnPause = false;

  Duration? positionToReport;
  Duration? durationToReport = const Duration(minutes: 5);

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
  Duration get position => positionToReport ?? Duration.zero;

  @override
  ProcessingState get processingState => isCompleted
      ? ProcessingState.completed
      : (isPlaying ? ProcessingState.ready : ProcessingState.idle);

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool? preload,
    dynamic tag,
  }) async {
    setUrlCallCount++;
    currentUrl = url;
    isCompleted = false;

    if (setUrlEnteredCompleter != null &&
        !setUrlEnteredCompleter!.isCompleted) {
      setUrlEnteredCompleter!.complete();
    }
    if (setUrlGateCompleter != null) {
      await setUrlGateCompleter!.future;
    }
    if (throwOnSetUrl) {
      throw Exception('Simulated remote connection failure on setUrl');
    }
    return durationToReport;
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
    isCompleted = false;
    if (throwOnSetAsset) {
      throw Exception('Simulated asset failure');
    }
    return const Duration(seconds: 120);
  }

  @override
  Future<void> play() async {
    playCallCount++;
    if (playEnteredCompleter != null && !playEnteredCompleter!.isCompleted) {
      playEnteredCompleter!.complete();
    }
    if (playGateCompleter != null) {
      await playGateCompleter!.future;
    }
    if (throwOnPlay) {
      throw Exception('Simulated play error');
    }
    isPlaying = true;
    _playingSubject.add(true);
    _playerStateSubject.add(PlayerState(true, ProcessingState.ready));
    if (durationToReport != null) {
      _durationSubject.add(durationToReport);
    }
    playEndCompleter = Completer<void>();
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    if (throwOnPause) {
      throw Exception('Simulated pause error');
    }
    isPlaying = false;
    _playingSubject.add(false);
    _playerStateSubject.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCallCount++;
    positionToReport = position;
    if (position != null) {
      _positionSubject.add(position);
    }
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

  void emitBuffering() {
    if (!_playerStateSubject.isClosed) {
      _playerStateSubject.add(
        PlayerState(isPlaying, ProcessingState.buffering),
      );
    }
  }

  void emitError(String message) {
    if (!_errorSubject.isClosed) {
      _errorSubject.add(PlayerException(1, message, 0));
    }
  }

  void emitPosition(Duration pos) {
    positionToReport = pos;
    if (!_positionSubject.isClosed) {
      _positionSubject.add(pos);
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

/// Controllable [AdhanAudioSession] double for session tests.
class TestControllableSession implements AdhanAudioSession {
  final List<bool> activationCalls = [];
  bool nextActivateResult = true;
  Completer<bool>? activateCompleter;

  @override
  Stream<void> get interruptionStream => const Stream.empty();

  @override
  Stream<void> get becomingNoisyStream => const Stream.empty();

  @override
  Future<bool> activate() async {
    activationCalls.add(true);
    if (activateCompleter != null) {
      return await activateCompleter!.future;
    }
    return nextActivateResult;
  }

  @override
  Future<void> deactivate() async {
    activationCalls.add(false);
  }

  @override
  Future<void> dispose() async {}
}

/// Controllable [NativePrayerAudioControl] double for testing OS stop confirmation and fail-closed branches.
class FakeNativePrayerAudioControl implements NativePrayerAudioControl {
  bool nextResult = true;
  int stopCallCount = 0;
  Completer<bool>? stopCompleter;

  int acquireLeaseCallCount = 0;
  int releaseLeaseCallCount = 0;
  int isLeaseActiveCallCount = 0;
  ManualPlaybackLeaseResult nextLeaseResult = const ManualPlaybackLeaseResult(
    acquired: true,
    leaseToken: 'fake_manual_lease_token',
  );
  bool nextReleaseResult = true;
  bool nextIsLeaseActiveResult = false;
  String? lastAcquiredRequestId;
  String? lastReleasedToken;

  @override
  Future<bool> stopActivePlayback() async {
    stopCallCount++;
    if (stopCompleter != null) {
      return await stopCompleter!.future;
    }
    return nextResult;
  }

  @override
  Future<ManualPlaybackLeaseResult> acquireManualPlaybackLease({
    required String requestId,
  }) async {
    acquireLeaseCallCount++;
    stopCallCount++;
    lastAcquiredRequestId = requestId;
    if (stopCompleter != null) {
      final canProceed = await stopCompleter!.future;
      if (!canProceed) {
        return const ManualPlaybackLeaseResult(
          acquired: false,
          errorCode: 'NATIVE_SERVICE_STOP_FAILED',
          errorMessageAr: 'تعذر إيقاف التنبيه الصوتي النشط في النظام',
        );
      }
    }
    if (!nextResult) {
      return const ManualPlaybackLeaseResult(
        acquired: false,
        errorCode: 'NATIVE_SERVICE_STOP_FAILED',
        errorMessageAr: 'تعذر إيقاف التنبيه الصوتي النشط في النظام',
      );
    }
    return nextLeaseResult;
  }

  @override
  Future<bool> releaseManualPlaybackLease({required String leaseToken}) async {
    releaseLeaseCallCount++;
    lastReleasedToken = leaseToken;
    return nextReleaseResult;
  }

  @override
  Future<bool> isManualPlaybackLeaseActive() async {
    isLeaseActiveCallCount++;
    return nextIsLeaseActiveResult;
  }
}

/// In-memory controllable implementation of [OnlineAudioPlayerClient] and [AdhanAudioPlayerClient].
class FakeOnlineAudioPlayerClient
    implements AdhanAudioPlayerClient, OnlineAudioPlayerClient {
  final _eventController = StreamController<AdhanPlaybackEvent>.broadcast();
  String? lastPlayedAsset;
  String? lastPlayedUrl;
  String? lastRequestToken;
  int playAssetCount = 0;
  int playUrlCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int seekCount = 0;
  int stopCount = 0;
  bool isPlaying = false;
  bool isPaused = false;

  Completer<void>? pauseGateCompleter;
  Completer<void>? resumeGateCompleter;
  bool nextPauseResult = true;
  bool nextResumeResult = true;

  @override
  Stream<AdhanPlaybackEvent> get playbackEventStream => _eventController.stream;

  @override
  Stream<Duration> get positionStream =>
      _eventController.stream.map((e) => e.position);

  @override
  Stream<Duration?> get durationStream =>
      _eventController.stream.map((e) => e.duration);

  @override
  Stream<bool> get playingStream => _eventController.stream.map(
    (e) => e.status == AdhanPlaybackStatus.playing,
  );

  @override
  Stream<bool> get completedStream => _eventController.stream
      .where((e) => e.status == AdhanPlaybackStatus.completed)
      .map((_) => true);

  @override
  Stream<String> get errorStream => _eventController.stream
      .where(
        (e) => e.status == AdhanPlaybackStatus.error && e.errorMessage != null,
      )
      .map((e) => e.errorMessage!);

  @override
  Future<PlaybackStartupResult> playAsset(
    String assetPath, {
    String? requestToken,
  }) async {
    playAssetCount++;
    final token = requestToken ?? 'tok_${++playAssetCount}';
    lastPlayedAsset = assetPath;
    lastRequestToken = token;
    isPlaying = true;
    isPaused = false;
    _eventController.add(
      AdhanPlaybackEvent(
        requestToken: token,
        status: AdhanPlaybackStatus.playing,
        position: Duration.zero,
        duration: const Duration(seconds: 120),
      ),
    );
    return PlaybackStartupResult.started;
  }

  @override
  Future<PlaybackStartupResult> playUrl(
    String url, {
    String? requestToken,
  }) async {
    playUrlCount++;
    final token = requestToken ?? 'url_${++playUrlCount}';
    lastPlayedUrl = url;
    lastRequestToken = token;
    isPlaying = true;
    isPaused = false;
    _eventController.add(
      AdhanPlaybackEvent(
        requestToken: token,
        status: AdhanPlaybackStatus.playing,
        position: Duration.zero,
        duration: const Duration(minutes: 5),
      ),
    );
    return PlaybackStartupResult.started;
  }

  @override
  Future<bool> pause({String? requestToken}) async {
    pauseCount++;
    if (pauseGateCompleter != null) {
      await pauseGateCompleter!.future;
    }
    if (!nextPauseResult) return false;
    isPlaying = false;
    isPaused = true;
    final token = requestToken ?? lastRequestToken;
    if (token != null) {
      _eventController.add(
        AdhanPlaybackEvent(
          requestToken: token,
          status: AdhanPlaybackStatus.paused,
          position: const Duration(seconds: 10),
          duration: const Duration(minutes: 5),
        ),
      );
    }
    return true;
  }

  @override
  Future<bool> resume({String? requestToken}) async {
    resumeCount++;
    if (resumeGateCompleter != null) {
      await resumeGateCompleter!.future;
    }
    if (!nextResumeResult) return false;
    isPlaying = true;
    isPaused = false;
    final token = requestToken ?? lastRequestToken;
    if (token != null) {
      _eventController.add(
        AdhanPlaybackEvent(
          requestToken: token,
          status: AdhanPlaybackStatus.playing,
          position: const Duration(seconds: 10),
          duration: const Duration(minutes: 5),
        ),
      );
    }
    return true;
  }

  @override
  Future<void> seek(Duration position, {String? requestToken}) async {
    seekCount++;
    final token = requestToken ?? lastRequestToken;
    if (token != null) {
      _eventController.add(
        AdhanPlaybackEvent(
          requestToken: token,
          status: isPaused
              ? AdhanPlaybackStatus.paused
              : AdhanPlaybackStatus.playing,
          position: position,
          duration: const Duration(minutes: 5),
        ),
      );
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    isPlaying = false;
    isPaused = false;
    if (lastRequestToken != null) {
      _eventController.add(
        AdhanPlaybackEvent(
          requestToken: lastRequestToken!,
          status: AdhanPlaybackStatus.idle,
        ),
      );
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }

  void emitEvent(AdhanPlaybackEvent event) {
    _eventController.add(event);
  }
}

// =============================================================================
// Test Environment & Layout Inspection Helpers
// =============================================================================

bool _fontsLoaded = false;
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue);
  await tester.pumpAndSettle();
}

Future<void> _ensureTestFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();

    final naskh = FontLoader('Noto Naskh Arabic')
      ..addFont(rootBundle.load('assets/fonts/NotoNaskhArabic-Variable.ttf'));
    await naskh.load();
    _fontsLoaded = true;
  });
}

Future<void> _awaitDecodedPageImage(
  WidgetTester tester, {
  required int pageNumber,
}) async {
  final expectedAsset = KfqcMushafCatalog.assetPathForPage(pageNumber);
  final imageFinder = find.byWidgetPredicate((widget) {
    if (widget is Image && widget.image is AssetImage) {
      final asset = widget.image as AssetImage;
      return asset.assetName == expectedAsset;
    }
    return false;
  });

  final rawImageFinder = find.descendant(
    of: imageFinder,
    matching: find.byType(RawImage),
  );

  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (rawImageFinder.evaluate().isNotEmpty) {
      final render = tester.renderObject<RenderImage>(rawImageFinder.first);
      if (render.image != null) {
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<Rect> _getPaintedImageDestinationRect(
  WidgetTester tester, {
  required int pageNumber,
}) async {
  await _awaitDecodedPageImage(tester, pageNumber: pageNumber);

  final expectedAsset = KfqcMushafCatalog.assetPathForPage(pageNumber);
  final imageFinder = find.byWidgetPredicate((widget) {
    if (widget is Image && widget.image is AssetImage) {
      final asset = widget.image as AssetImage;
      return asset.assetName == expectedAsset;
    }
    return false;
  });

  expect(
    imageFinder,
    findsOneWidget,
    reason: 'Must find rendered Image for page $pageNumber ($expectedAsset)',
  );

  final rawImageFinder = find.descendant(
    of: imageFinder,
    matching: find.byType(RawImage),
  );
  expect(
    rawImageFinder,
    findsOneWidget,
    reason:
        'Must find decoded descendant RawImage for page $pageNumber ($expectedAsset)',
  );

  final renderImage = tester.renderObject<RenderImage>(rawImageFinder);
  final image = renderImage.image;
  expect(image, isNotNull, reason: 'RenderImage must have decoded ui.Image');

  final imageSize = Size(image!.width.toDouble(), image.height.toDouble());
  final fittedSizes = applyBoxFit(BoxFit.contain, imageSize, renderImage.size);
  final destinationRect = Alignment.center.inscribe(
    fittedSizes.destination,
    Offset.zero & renderImage.size,
  );
  final topLeft = renderImage.localToGlobal(destinationRect.topLeft);
  final bottomRight = renderImage.localToGlobal(destinationRect.bottomRight);
  return Rect.fromPoints(topLeft, bottomRight);
}

Rect _getWidgetGlobalRect(WidgetTester tester, Finder finder) {
  expect(
    finder,
    findsOneWidget,
    reason: 'Finder must match exactly one widget',
  );
  final renderBox = tester.renderObject<RenderBox>(finder);
  final topLeft = renderBox.localToGlobal(Offset.zero);
  return topLeft & renderBox.size;
}

Future<void> _scrollRowUntilHitTestable(
  WidgetTester tester, {
  required Finder target,
  required Finder scrollable,
  double step = 80.0,
  int maxDrags = 15,
}) async {
  expect(scrollable, findsOneWidget, reason: 'Scrollable row must exist');
  expect(target, findsWidgets, reason: 'Target widget must exist');

  int drags = 0;
  while (target.hitTestable().evaluate().isEmpty && drags < maxDrags) {
    drags++;
    final targetBox = tester.renderObject<RenderBox>(target.first);
    final targetCenter = targetBox.localToGlobal(
      targetBox.size.center(Offset.zero),
    );
    final scrollBox = tester.renderObject<RenderBox>(scrollable);
    final scrollBounds = scrollBox.localToGlobal(Offset.zero) & scrollBox.size;

    final dragDelta = targetCenter.dx < scrollBounds.left
        ? Offset(step, 0.0)
        : Offset(-step, 0.0);

    await tester.drag(scrollable, dragDelta);
    await tester.pumpAndSettle();
  }

  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'Target must be hitTestable after scroll',
  );
}

Future<void> _assertImageBoundedWithoutObstruction({
  required WidgetTester tester,
  required int pageNumber,
}) async {
  expect(
    tester.takeException(),
    isNull,
    reason: 'No Flutter exceptions or RenderFlex overflows permitted',
  );

  final imageRect = await _getPaintedImageDestinationRect(
    tester,
    pageNumber: pageNumber,
  );
  expect(
    imageRect.width,
    greaterThan(0.0),
    reason: 'Painted image width must be positive',
  );
  expect(
    imageRect.height,
    greaterThan(0.0),
    reason: 'Painted image height must be positive',
  );

  final viewportFinder = find.byKey(
    ValueKey('mushaf_image_viewport_$pageNumber'),
  );
  final badgeFinder = find.byKey(ValueKey('mushaf_metadata_badge_$pageNumber'));
  final footerFinder = find.byKey(
    const ValueKey('quran_reader_bottom_controls'),
  );
  final topControlsFinder = find.byKey(
    const ValueKey('quran_reader_top_controls'),
  );

  final viewportRect = _getWidgetGlobalRect(tester, viewportFinder);
  final badgeRect = _getWidgetGlobalRect(tester, badgeFinder);
  final footerRect = _getWidgetGlobalRect(tester, footerFinder);
  final topControlsRect = _getWidgetGlobalRect(tester, topControlsFinder);

  // Assert all 4 edges remain within viewport bounds
  expect(imageRect.left, greaterThanOrEqualTo(viewportRect.left - 0.05));
  expect(imageRect.right, lessThanOrEqualTo(viewportRect.right + 0.05));
  expect(imageRect.top, greaterThanOrEqualTo(viewportRect.top - 0.05));
  expect(imageRect.bottom, lessThanOrEqualTo(viewportRect.bottom + 0.05));

  // Zero pixel intersection with non-page UI widgets
  expect(
    badgeRect.overlaps(imageRect),
    isFalse,
    reason: 'Badge must not overlap image',
  );
  expect(
    footerRect.overlaps(imageRect),
    isFalse,
    reason: 'Footer must not overlap image',
  );
  expect(
    topControlsRect.overlaps(imageRect),
    isFalse,
    reason: 'Top controls must not overlap image',
  );

  final activeBarFinder = find.byKey(const ValueKey('quran_active_audio_bar'));
  if (activeBarFinder.evaluate().isNotEmpty) {
    final activeBarRect = _getWidgetGlobalRect(tester, activeBarFinder);
    expect(
      activeBarRect.overlaps(imageRect),
      isFalse,
      reason: 'Active audio bar must not overlap image',
    );
  }
}

Widget createTestApp({
  required ProviderContainer container,
  required Widget child,
  TransitionBuilder? builder,
}) => UncontrolledProviderScope(
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
    builder: builder,
    home: Directionality(textDirection: TextDirection.rtl, child: child),
  ),
);

class _TestContext {
  final Directory tempDir;
  final AppDatabase db;
  final ProgressRepository repo;
  final ProviderContainer container;
  final FakeOnlineAudioPlayerClient audioClient;
  bool _disposed = false;

  _TestContext(
    this.tempDir,
    this.db,
    this.repo,
    this.container,
    this.audioClient,
  );

  static Future<_TestContext> create({
    required QuranRepository quranRepo,
    required CityRepository cityRepo,
    FakeOnlineAudioPlayerClient? client,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('q_audio_test_');
    final db = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: p.join(tempDir.path, 'q_audio.db'),
    );
    final repo = ProgressRepository(
      db,
      versePageValidator: quranRepo.isValidVerseOnPage,
    );
    final audioClient = client ?? FakeOnlineAudioPlayerClient();
    final container = ProviderContainer(
      overrides: [
        quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
        progressRepositoryProvider.overrideWithValue(repo),
        cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        adhanAudioPlayerClientProvider.overrideWithValue(audioClient),
      ],
    );
    return _TestContext(tempDir, db, repo, container, audioClient);
  }

  Future<void> prehydrate([int page = 1]) async {
    await repo.saveReadingProgress(ReadingProgress(lastPage: page));
    await container.read(readingProgressControllerProvider.future);
    await container.read(bookmarksControllerProvider.future);
    await container.read(favoritesControllerProvider.future);
    await container.read(preferencesControllerProvider.future);
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      final controller = container.read(
        readingProgressControllerProvider.notifier,
      );
      bool drained = false;
      Object? drainError;
      final drainFuture = controller.drainPendingWrites().then<void>(
        (_) {
          drained = true;
        },
        onError: (Object error, StackTrace stack) {
          drainError = error;
        },
      );
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!drained &&
          drainError == null &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
      expect(
        drainError,
        isNull,
        reason: 'Pending writes drain encountered an error: $drainError',
      );
      expect(
        drained,
        isTrue,
        reason: 'Reading progress controller queue must drain before deadline',
      );
      if (drained) {
        await drainFuture;
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      await audioClient.dispose();
      await tester.runAsync(() async {
        await repo.close();
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
    }
  }
}

// =============================================================================
// Main Test Suite
// =============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  PrayerCalculator.ensureTimeZonesInitialized();

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
                  : 'mock_q_req';
              return {'acquired': true, 'leaseToken': 'mock_lease_$reqId'};
            }
            if (methodCall.method == 'releaseManualPlaybackLease') {
              return {'released': true, 'cleared': true};
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

  // ---------------------------------------------------------------------------
  // 1. QuranAudioSource Domain & Metadata Validation
  // ---------------------------------------------------------------------------
  group('QuranAudioSource Domain & URL Construction', () {
    test('exact verified metadata values', () {
      expect(QuranAudioSource.reciterId, 123);
      expect(QuranAudioSource.moshafId, 123);
      expect(QuranAudioSource.riwayahId, 1);
      expect(QuranAudioSource.surahTotal, 114);
      expect(QuranAudioSource.reciterName, 'مشاري العفاسي');
      expect(QuranAudioSource.riwayahName, 'حفص عن عاصم - مرتل');
      expect(
        QuranAudioSource.serverBaseUrl,
        'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/',
      );
      expect(
        QuranAudioSource.privacyPolicyUrl,
        'https://www.mp3quran.net/ar/privacy',
      );
      expect(QuranAudioSource.apiUrl, 'https://www.mp3quran.net/ar/api');
    });

    test('builds exact 3-digit padded URLs for specific landmark surahs', () {
      expect(
        QuranAudioSource.getSurahAudioUrl(1),
        'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/001.mp3',
      );
      expect(
        QuranAudioSource.getSurahAudioUrl(7),
        'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/007.mp3',
      );
      expect(
        QuranAudioSource.getSurahAudioUrl(10),
        'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/010.mp3',
      );
      expect(
        QuranAudioSource.getSurahAudioUrl(114),
        'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/114.mp3',
      );
    });

    test(
      'all 114 surahs generate strictly valid HTTPS 3-digit padded URLs',
      () {
        for (int i = 1; i <= 114; i++) {
          final url = QuranAudioSource.getSurahAudioUrl(i);
          expect(
            url.startsWith(
              'https://cdn.mp3quran.net/audio/mishary-alafasy/r1/',
            ),
            isTrue,
          );
          expect(url.endsWith('.mp3'), isTrue);
          final filename = url.split('/').last;
          final paddedNum = filename.replaceAll('.mp3', '');
          expect(paddedNum.length, 3);
          expect(int.parse(paddedNum), i);
        }
      },
    );

    test('out-of-bounds surah numbers strictly throw ArgumentError', () {
      expect(() => QuranAudioSource.getSurahAudioUrl(0), throwsArgumentError);
      expect(() => QuranAudioSource.getSurahAudioUrl(-1), throwsArgumentError);
      expect(() => QuranAudioSource.getSurahAudioUrl(115), throwsArgumentError);
      expect(() => QuranAudioSource.getSurahAudioUrl(999), throwsArgumentError);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. JustAudioPlayerClient Online Audio, Tokens & SDK Boundary (Sol Findings 1 & 2)
  // ---------------------------------------------------------------------------
  group('JustAudioPlayerClient Online Audio, Tokens & SDK Boundary', () {
    late MockAudioPlayer mockPlayer;
    late TestControllableSession mockSession;
    late FakeNativePrayerAudioControl fakeNative;
    late JustAudioPlayerClient client;

    setUp(() {
      mockPlayer = MockAudioPlayer();
      mockSession = TestControllableSession();
      fakeNative = FakeNativePrayerAudioControl();
      client = JustAudioPlayerClient(
        playerFactory: () => mockPlayer,
        audioSession: mockSession,
        nativeAudioControl: fakeNative,
        loadTimeout: const Duration(milliseconds: 300),
        remoteLoadTimeout: const Duration(milliseconds: 300),
        activationTimeout: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await client.dispose();
      await mockPlayer.dispose();
    });

    test(
      'playUrl loads remote URL, activates session, and exposes playing status',
      () async {
        final events = <AdhanPlaybackEvent>[];
        final sub = client.playbackEventStream.listen(events.add);

        final result = await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q_test_1',
        );

        expect(result, PlaybackStartupResult.started);
        expect(mockPlayer.setUrlCallCount, 1);
        expect(mockPlayer.currentUrl, QuranAudioSource.getSurahAudioUrl(1));
        expect(mockSession.activationCalls, [true]);
        expect(mockPlayer.playCallCount, 1);
        expect(mockPlayer.isPlaying, isTrue);

        expect(
          events.any(
            (e) =>
                e.status == AdhanPlaybackStatus.playing &&
                e.requestToken == 'q_test_1',
          ),
          isTrue,
        );

        await sub.cancel();
      },
    );

    test(
      'pause, resume, and seek forward to physical player with generation tokens',
      () async {
        await client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q_test_2',
        );

        final paused = await client.pause(requestToken: 'q_test_2');
        expect(paused, isTrue);
        expect(mockPlayer.pauseCallCount, 1);
        expect(mockPlayer.isPlaying, isFalse);

        final resumed = await client.resume(requestToken: 'q_test_2');
        expect(resumed, isTrue);
        expect(mockPlayer.playCallCount, 2);
        expect(mockPlayer.isPlaying, isTrue);

        await client.seek(
          const Duration(seconds: 45),
          requestToken: 'q_test_2',
        );
        expect(mockPlayer.seekCallCount, 1);
        expect(mockPlayer.positionToReport, const Duration(seconds: 45));
      },
    );

    test(
      'remote load timeout triggers Arabic error message and cleans up',
      () async {
        mockPlayer.setUrlGateCompleter = Completer<void>();
        final events = <AdhanPlaybackEvent>[];
        final sub = client.playbackEventStream.listen(events.add);

        final playFuture = client.playUrl(
          QuranAudioSource.getSurahAudioUrl(2),
          requestToken: 'q_hung',
        );

        await expectLater(playFuture, throwsA(anything));

        expect(
          events.any(
            (e) =>
                e.status == AdhanPlaybackStatus.error &&
                e.errorMessage != null &&
                e.errorMessage!.contains('الاتصال بالإنترنت'),
          ),
          isTrue,
        );

        mockPlayer.setUrlGateCompleter!.complete();
        await sub.cancel();
      },
    );

    test('remote load superseded by stop does not physically play', () async {
      mockPlayer.setUrlGateCompleter = Completer<void>();

      final playFuture = client.playUrl(
        QuranAudioSource.getSurahAudioUrl(1),
        requestToken: 'q_stale',
      );

      final stopFuture = client.stop();
      mockPlayer.setUrlGateCompleter!.complete();

      final result = await playFuture;
      await stopFuture;

      expect(result, PlaybackStartupResult.cancelled);
      expect(mockPlayer.playCallCount, 0);
      expect(mockPlayer.isPlaying, isFalse);
    });

    // Sol Finding 1 & 2: Late resume failure Q -> Q does NOT corrupt newer owner
    test(
      'Finding 1: late resume failure in Q1 does not emit error or mutate newer Q2 owner',
      () async {
        final player1 = MockAudioPlayer();
        final player2 = MockAudioPlayer();
        int factoryCall = 0;

        final multiClient = JustAudioPlayerClient(
          playerFactory: () {
            factoryCall++;
            return factoryCall == 1 ? player1 : player2;
          },
          audioSession: mockSession,
          nativeAudioControl: fakeNative,
        );
        addTearDown(multiClient.dispose);

        final events = <AdhanPlaybackEvent>[];
        final sub = multiClient.playbackEventStream.listen(events.add);

        // 1. Play Q1 and pause it
        await multiClient.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q1',
        );
        await multiClient.pause(requestToken: 'q1');
        expect(player1.isPlaying, isFalse);

        // 2. Gate resume on player1 so its play() future is entered and suspended
        player1.playEnteredCompleter = Completer<void>();
        player1.playGateCompleter = Completer<void>();
        player1.throwOnPlay = true; // when it executes, it will throw late!

        final resumeQ1Future = multiClient.resume(requestToken: 'q1');

        // Await actual resumed play entry before starting B
        await player1.playEnteredCompleter!.future;
        final resumeQ1Result = await resumeQ1Future;
        expect(resumeQ1Result, isTrue);

        // 3. Finish B startup
        final q2Result = await multiClient.playUrl(
          QuranAudioSource.getSurahAudioUrl(2),
          requestToken: 'q2',
        );
        expect(q2Result, PlaybackStartupResult.started);
        expect(player2.isPlaying, isTrue);

        // 4. Release A failure
        player1.playGateCompleter!.complete();

        // 5. Await event delivery
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // 6. Assert B playing with original B token/source and no erroneous error/stop
        expect(player2.isPlaying, isTrue);
        expect(player2.currentUrl, QuranAudioSource.getSurahAudioUrl(2));

        final q2Errors = events.where(
          (e) =>
              e.requestToken == 'q2' && e.status == AdhanPlaybackStatus.error,
        );
        expect(
          q2Errors,
          isEmpty,
          reason: 'Late failure of superseded Q1 must never emit error on Q2',
        );

        final q2Stops = events.where(
          (e) =>
              e.requestToken == 'q2' && e.status == AdhanPlaybackStatus.stopped,
        );
        expect(
          q2Stops,
          isEmpty,
          reason: 'Late failure of superseded Q1 must never emit stop on Q2',
        );

        await sub.cancel();
        await player1.dispose();
        await player2.dispose();
      },
    );

    // Sol Finding 1 & 2: Late resume failure Q -> Adhan does NOT corrupt newer Adhan owner
    test(
      'Finding 1: late resume failure in Q does not emit error or mutate newer Adhan owner',
      () async {
        final qPlayer = MockAudioPlayer();
        final adhanPlayer = MockAudioPlayer();
        int factoryCall = 0;

        final multiClient = JustAudioPlayerClient(
          playerFactory: () {
            factoryCall++;
            return factoryCall == 1 ? qPlayer : adhanPlayer;
          },
          audioSession: mockSession,
          nativeAudioControl: fakeNative,
        );
        addTearDown(multiClient.dispose);

        final events = <AdhanPlaybackEvent>[];
        final sub = multiClient.playbackEventStream.listen(events.add);

        await multiClient.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q_voice',
        );
        await multiClient.pause(requestToken: 'q_voice');
        expect(qPlayer.isPlaying, isFalse);

        qPlayer.playEnteredCompleter = Completer<void>();
        qPlayer.playGateCompleter = Completer<void>();
        qPlayer.throwOnPlay = true;

        final resumeFuture = multiClient.resume(requestToken: 'q_voice');

        // Await actual resumed play entry before starting Adhan
        await qPlayer.playEnteredCompleter!.future;
        final resumeResult = await resumeFuture;
        expect(resumeResult, isTrue);

        // Finish B startup
        final adhanResult = await multiClient.playAsset(
          'assets/audio/adhan/adam-converted.mp3',
          requestToken: 'adhan_voice',
        );
        expect(adhanResult, PlaybackStartupResult.started);
        expect(adhanPlayer.isPlaying, isTrue);

        // Release A failure
        qPlayer.playGateCompleter!.complete();

        // Await event delivery
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Assert B playing with original B token/source and no erroneous error/stop
        expect(adhanPlayer.isPlaying, isTrue);
        expect(
          adhanPlayer.currentAsset,
          'assets/audio/adhan/adam-converted.mp3',
        );

        final adhanErrors = events.where(
          (e) =>
              e.requestToken == 'adhan_voice' &&
              e.status == AdhanPlaybackStatus.error,
        );
        expect(
          adhanErrors,
          isEmpty,
          reason: 'Late failure of Q must never emit error on Adhan',
        );

        final adhanStops = events.where(
          (e) =>
              e.requestToken == 'adhan_voice' &&
              e.status == AdhanPlaybackStatus.stopped,
        );
        expect(
          adhanStops,
          isEmpty,
          reason: 'Late failure of Q must never emit stop on Adhan',
        );

        await sub.cancel();
        await qPlayer.dispose();
        await adhanPlayer.dispose();
      },
    );

    // Sol Finding 2: Delayed handoff queued transport with genuine gated SDK player factory
    test(
      'Finding 2: queued pause during handoff cannot pause newer owner B and does not deadlock',
      () async {
        final player1 = MockAudioPlayer();
        final player2 = MockAudioPlayer();
        int count = 0;

        final multiClient = JustAudioPlayerClient(
          playerFactory: () {
            count++;
            return count == 1 ? player1 : player2;
          },
          audioSession: mockSession,
          nativeAudioControl: fakeNative,
        );
        addTearDown(multiClient.dispose);

        // Start Q1
        await multiClient.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q1',
        );
        expect(player1.isPlaying, isTrue);

        // Gate player2's setUrl so handoff is delayed in queue
        player2.setUrlGateCompleter = Completer<void>();

        // Queue play Q2 (waits on gate)
        final playQ2Future = multiClient.playUrl(
          QuranAudioSource.getSurahAudioUrl(2),
          requestToken: 'q2',
        );

        // Queue a pause intended for Q1 (bound to 'q1')
        final queuedPauseFuture = multiClient.pause(requestToken: 'q1');

        // Complete the gate to avoid deadlock and allow queue execution to progress
        player2.setUrlGateCompleter!.complete();

        final pauseResult = await queuedPauseFuture;
        final q2Result = await playQ2Future;

        expect(
          pauseResult,
          isFalse,
          reason: 'Stale pause for Q1 during handoff must no-op',
        );
        expect(q2Result, PlaybackStartupResult.started);
        expect(
          player2.isPlaying,
          isTrue,
          reason: 'Newer owner Q2 must remain playing and not be paused',
        );

        await player1.dispose();
        await player2.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2b. NativePrayerAudioControl OS Boundary & Gated Native Stop
  // ---------------------------------------------------------------------------
  group('NativePrayerAudioControl OS Boundary', () {
    test('non-Android platform is legitimate no-op and returns true', () async {
      final control = MethodChannelNativePrayerAudioControl(isAndroid: false);
      final result = await control.stopActivePlayback();
      expect(result, isTrue);
    });

    test(
      'Android platform confirmed stop returns true when {stopped: true}',
      () async {
        const channel = MethodChannel('test.prayer_alarm.stopped_true');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'stopActivePlayback') {
                return {'stopped': true};
              }
              return null;
            });

        final control = MethodChannelNativePrayerAudioControl(
          channel: channel,
          isAndroid: true,
        );
        expect(await control.stopActivePlayback(), isTrue);
      },
    );

    test(
      'Android platform fail-closed on {stopped: false}, null, non-map, or exception',
      () async {
        const channel = MethodChannel('test.prayer_alarm.fail_closed');
        dynamic mockResult;
        bool shouldThrowMissingPlugin = false;
        bool shouldThrowPlatformException = false;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (shouldThrowMissingPlugin) throw MissingPluginException();
              if (shouldThrowPlatformException) {
                throw PlatformException(code: 'ERROR');
              }
              return mockResult;
            });

        final control = MethodChannelNativePrayerAudioControl(
          channel: channel,
          isAndroid: true,
        );

        // 1. {stopped: false}
        mockResult = {'stopped': false};
        expect(await control.stopActivePlayback(), isFalse);

        // 2. null
        mockResult = null;
        expect(await control.stopActivePlayback(), isFalse);

        // 3. Non-map string
        mockResult = 'unexpected_string';
        expect(await control.stopActivePlayback(), isFalse);

        // 4. MissingPluginException
        shouldThrowMissingPlugin = true;
        expect(await control.stopActivePlayback(), isFalse);
        shouldThrowMissingPlugin = false;

        // 5. PlatformException
        shouldThrowPlatformException = true;
        expect(await control.stopActivePlayback(), isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 2c. JustAudioPlayerClient - Gated Native Audio Stop & Fail-Closed Behavior
  // ---------------------------------------------------------------------------
  group(
    'JustAudioPlayerClient - Gated Native Audio Stop & Fail-Closed Behavior',
    () {
      test(
        'native stop returning false cancels playUrl, emits error, and prevents SDK play',
        () async {
          final mockPlayer = MockAudioPlayer();
          final mockSession = TestControllableSession();
          final fakeNative = FakeNativePrayerAudioControl()..nextResult = false;

          final client = JustAudioPlayerClient(
            playerFactory: () => mockPlayer,
            audioSession: mockSession,
            nativeAudioControl: fakeNative,
          );
          addTearDown(client.dispose);

          final events = <AdhanPlaybackEvent>[];
          final sub = client.playbackEventStream.listen(events.add);

          await expectLater(
            client.playUrl(
              QuranAudioSource.getSurahAudioUrl(1),
              requestToken: 'q_fail',
            ),
            throwsA(isA<StateError>()),
          );

          expect(fakeNative.stopCallCount, 1);
          expect(
            mockPlayer.playCallCount,
            0,
            reason: 'SDK play must NEVER be called when native stop fails',
          );
          expect(
            mockSession.activationCalls,
            isEmpty,
            reason: 'Session activation must not proceed',
          );
          expect(
            events.any(
              (e) =>
                  e.status == AdhanPlaybackStatus.error &&
                  e.errorMessage == 'تعذر إيقاف التنبيه الصوتي النشط في النظام',
            ),
            isTrue,
          );

          await sub.cancel();
          await mockPlayer.dispose();
        },
      );

      test(
        'native stop returning false cancels playAsset and prevents SDK play',
        () async {
          final mockPlayer = MockAudioPlayer();
          final mockSession = TestControllableSession();
          final fakeNative = FakeNativePrayerAudioControl()..nextResult = false;

          final client = JustAudioPlayerClient(
            playerFactory: () => mockPlayer,
            audioSession: mockSession,
            nativeAudioControl: fakeNative,
          );
          addTearDown(client.dispose);

          await expectLater(
            client.playAsset(
              'assets/audio/adhan/adam-converted.mp3',
              requestToken: 'ad_fail',
            ),
            throwsA(isA<StateError>()),
          );

          expect(fakeNative.stopCallCount, 1);
          expect(mockPlayer.playCallCount, 0);
          expect(mockSession.activationCalls, isEmpty);
          await mockPlayer.dispose();
        },
      );

      test(
        'native stop returning false prevents resume and emits error',
        () async {
          final mockPlayer = MockAudioPlayer();
          final mockSession = TestControllableSession();
          final fakeNative = FakeNativePrayerAudioControl()..nextResult = true;

          final client = JustAudioPlayerClient(
            playerFactory: () => mockPlayer,
            audioSession: mockSession,
            nativeAudioControl: fakeNative,
          );
          addTearDown(client.dispose);

          // Start and pause successfully
          await client.playUrl(
            QuranAudioSource.getSurahAudioUrl(1),
            requestToken: 'q_res',
          );
          await client.pause(requestToken: 'q_res');
          expect(mockPlayer.isPlaying, isFalse);

          // Now set native stop to fail on resume
          fakeNative.nextResult = false;
          final events = <AdhanPlaybackEvent>[];
          final sub = client.playbackEventStream.listen(events.add);

          final resumeResult = await client.resume(requestToken: 'q_res');
          expect(resumeResult, isFalse);
          expect(
            mockPlayer.playCallCount,
            1,
            reason:
                'playCallCount should remain 1 from initial play, not incremented on failed resume',
          );
          expect(
            events.any(
              (e) =>
                  e.status == AdhanPlaybackStatus.error &&
                  e.errorMessage == 'تعذر إيقاف التنبيه الصوتي النشط في النظام',
            ),
            isTrue,
          );

          await sub.cancel();
          await mockPlayer.dispose();
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // 2d. JustAudioPlayerClient - Reset Barrier & Generation Cancellation
  // ---------------------------------------------------------------------------
  group('JustAudioPlayerClient - Reset Barrier & Generation Cancellation', () {
    test(
      'active reset barrier at invocation rejects playUrl, playAsset, and resume immediately',
      () async {
        final mockPlayer = MockAudioPlayer();
        final mockSession = TestControllableSession();
        bool isResetActive = true;
        int generation = 1;

        final client = JustAudioPlayerClient(
          playerFactory: () => mockPlayer,
          audioSession: mockSession,
          nativeAudioControl: FakeNativePrayerAudioControl(),
          isResetBarrierActive: () => isResetActive,
          getResetGeneration: () => generation,
        );
        addTearDown(client.dispose);

        await expectLater(
          () => client.playUrl(QuranAudioSource.getSurahAudioUrl(1)),
          throwsA(isA<StateError>()),
        );
        expect(mockPlayer.playCallCount, 0);

        await expectLater(
          () => client.playAsset('assets/audio/adhan/adam-converted.mp3'),
          throwsA(isA<StateError>()),
        );
        expect(mockPlayer.playCallCount, 0);

        final resumed = await client.resume();
        expect(resumed, isFalse);
        await mockPlayer.dispose();
      },
    );

    test(
      'generation advance during pending load permanently cancels playUrl even after barrier ends',
      () async {
        final mockPlayer = MockAudioPlayer();
        final mockSession = TestControllableSession();
        bool isResetActive = false;
        int generation = 10;

        final client = JustAudioPlayerClient(
          playerFactory: () => mockPlayer,
          audioSession: mockSession,
          nativeAudioControl: FakeNativePrayerAudioControl(),
          isResetBarrierActive: () => isResetActive,
          getResetGeneration: () => generation,
        );
        addTearDown(client.dispose);

        // Gate setUrl
        mockPlayer.setUrlGateCompleter = Completer<void>();

        final playFuture = client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q_gen_cancel',
        );

        // Simulate reset occurring: barrier goes active, generation increments
        isResetActive = true;
        generation = 11;

        // Reset finishes: barrier drops, but generation remains advanced (11)
        isResetActive = false;

        // Release setUrl gate
        mockPlayer.setUrlGateCompleter!.complete();

        final result = await playFuture;
        expect(result, PlaybackStartupResult.cancelled);
        expect(
          mockPlayer.playCallCount,
          0,
          reason:
              'Must NOT physically play when generation changed, even after reset fence ended',
        );
        expect(mockSession.activationCalls, isEmpty);
        await mockPlayer.dispose();
      },
    );

    test(
      'generation advance during native stop permanently cancels playback',
      () async {
        final mockPlayer = MockAudioPlayer();
        final mockSession = TestControllableSession();
        final fakeNative = FakeNativePrayerAudioControl();
        bool isResetActive = false;
        int generation = 5;

        final client = JustAudioPlayerClient(
          playerFactory: () => mockPlayer,
          audioSession: mockSession,
          nativeAudioControl: fakeNative,
          isResetBarrierActive: () => isResetActive,
          getResetGeneration: () => generation,
        );
        addTearDown(client.dispose);

        fakeNative.stopCompleter = Completer<bool>();

        final playFuture = client.playUrl(
          QuranAudioSource.getSurahAudioUrl(1),
          requestToken: 'q_native_gen',
        );

        // While native stop is waiting, reset triggers
        generation = 6;

        // Native stop completes
        fakeNative.stopCompleter!.complete(true);

        final result = await playFuture;
        expect(result, PlaybackStartupResult.cancelled);
        expect(mockPlayer.playCallCount, 0);
        expect(mockSession.activationCalls, isEmpty);
        await mockPlayer.dispose();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 3. AdhanAudioController Shared Ownership & Stale Guards (Sol Finding 3)
  // ---------------------------------------------------------------------------
  group('AdhanAudioController Shared Ownership & Token Guards', () {
    late FakeOnlineAudioPlayerClient fakeClient;
    late AdhanAudioController controller;

    setUp(() {
      fakeClient = FakeOnlineAudioPlayerClient();
      controller = AdhanAudioController(fakeClient);
    });

    tearDown(() {
      controller.dispose();
    });

    test(
      'playing Quran clears active Adhan voice and sets surah state',
      () async {
        await controller.playVoice(AdhanVoice.adam);

        expect(controller.state.isPlaying, isTrue);
        expect(controller.state.activeVoiceId, AdhanVoice.adam.id);
        expect(controller.state.sourceType, AudioPlaybackSource.adhan);
        expect(controller.state.activeSurahNumber, isNull);

        await controller.playSurah(surahNumber: 1, surahName: 'الفاتحة');

        expect(controller.state.isPlaying, isTrue);
        expect(controller.state.activeSurahNumber, 1);
        expect(controller.state.activeSurahName, 'الفاتحة');
        expect(controller.state.sourceType, AudioPlaybackSource.quran);
        expect(controller.state.activeVoiceId, isNull);
        expect(fakeClient.lastPlayedUrl, QuranAudioSource.getSurahAudioUrl(1));
      },
    );

    test('playing Adhan voice clears active Quran surah', () async {
      await controller.playSurah(surahNumber: 112, surahName: 'الإخلاص');
      expect(controller.state.isPlaying, isTrue);
      expect(controller.state.activeSurahNumber, 112);
      expect(controller.state.sourceType, AudioPlaybackSource.quran);

      await controller.playVoice(AdhanVoice.atcovi);

      expect(controller.state.isPlaying, isTrue);
      expect(controller.state.activeVoiceId, AdhanVoice.atcovi.id);
      expect(controller.state.sourceType, AudioPlaybackSource.adhan);
      expect(controller.state.activeSurahNumber, isNull);
      expect(controller.state.activeSurahName, isNull);
    });

    test(
      'stop() clears both voice and surah and halts client playback',
      () async {
        await controller.playSurah(surahNumber: 18, surahName: 'الكهف');
        expect(controller.state.isSurahActive, isTrue);

        await controller.stop();

        expect(controller.state.status, AdhanAudioStatus.idle);
        expect(controller.state.activeSurahNumber, isNull);
        expect(controller.state.activeVoiceId, isNull);
        expect(controller.state.sourceType, AudioPlaybackSource.none);
        expect(fakeClient.stopCount, 1);
      },
    );

    test(
      'invalid surah number (0, 115) immediately transitions to error',
      () async {
        await controller.playSurah(surahNumber: 0, surahName: 'سورة غير صالحة');
        expect(controller.state.hasError, isTrue);
        expect(controller.state.errorMessage, contains('غير صالح'));
        expect(fakeClient.playUrlCount, 0);

        await controller.playSurah(
          surahNumber: 115,
          surahName: 'سورة غير صالحة',
        );
        expect(controller.state.hasError, isTrue);
        expect(controller.state.errorMessage, contains('غير صالح'));
        expect(fakeClient.playUrlCount, 0);
      },
    );

    test('stale events with outdated requestToken are discarded', () async {
      await controller.playSurah(surahNumber: 1, surahName: 'الفاتحة');

      fakeClient.emitEvent(
        const AdhanPlaybackEvent(
          requestToken: 'old_stale_token',
          status: AdhanPlaybackStatus.error,
          errorMessage: 'Stale error',
        ),
      );

      expect(controller.state.hasError, isFalse);
      expect(controller.state.isPlaying, isTrue);
      expect(controller.state.activeSurahNumber, 1);
    });

    // Sol Finding 3: Pending pause/resume invalidated by newer owner does not overwrite
    test(
      'Finding 3: pending pause invalidated by newer playSurah does not overwrite state to paused',
      () async {
        await controller.playSurah(surahNumber: 1, surahName: 'الفاتحة');
        expect(controller.state.isPlaying, isTrue);

        fakeClient.pauseGateCompleter = Completer<void>();

        final pauseFuture = controller.pause();

        // Before pause finishes, user starts Surah 2
        await controller.playSurah(surahNumber: 2, surahName: 'البقرة');

        // Complete pause on old token
        fakeClient.pauseGateCompleter!.complete();
        await pauseFuture;

        expect(controller.state.isPlaying, isTrue);
        expect(controller.state.activeSurahNumber, 2);
        expect(controller.state.status, AdhanAudioStatus.playing);
      },
    );

    test(
      'Finding 3: pending resume invalidated by stop does not overwrite state to playing',
      () async {
        await controller.playSurah(surahNumber: 1, surahName: 'الفاتحة');
        await controller.pause();
        expect(controller.state.isPaused, isTrue);

        fakeClient.resumeGateCompleter = Completer<void>();

        final resumeFuture = controller.resume();

        // Before resume finishes, user calls stop
        await controller.stop();
        expect(controller.state.status, AdhanAudioStatus.idle);

        fakeClient.resumeGateCompleter!.complete();
        await resumeFuture;

        expect(
          controller.state.status,
          AdhanAudioStatus.idle,
          reason: 'Stale resume must not overwrite stopped idle state',
        );
      },
    );

    test(
      'Finding 3: no optimistic playing when client resume returns false / cancelled',
      () async {
        await controller.playSurah(surahNumber: 1, surahName: 'الفاتحة');
        await controller.pause();
        expect(controller.state.isPaused, isTrue);

        fakeClient.nextResumeResult = false; // client cancelled / no-op

        await controller.resume();

        expect(
          controller.state.isPaused,
          isTrue,
          reason:
              'Must not optimistically set playing when client returns false',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 4. Quran Reader UI & Lifecycle Integration
  // ---------------------------------------------------------------------------
  group('Quran Reader UI & Lifecycle Integration', () {
    testWidgets('top controls contain audio headphones action button', (
      tester,
    ) async {
      await _ensureTestFonts(tester);
      final ctx = (await tester.runAsync(
        () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
      ))!;
      addTearDown(() => ctx.dispose(tester));
      try {
        await tester.runAsync(() => ctx.prehydrate(1));

        await tester.pumpWidget(
          createTestApp(
            container: ctx.container,
            child: const QuranReaderScreen(initialPage: 1),
          ),
        );
        await tester.pumpAndSettle();

        final audioBtn = find.byKey(
          const ValueKey('quran_audio_select_button'),
        );
        expect(audioBtn, findsOneWidget);

        expect(
          find.byKey(const ValueKey('quran_active_audio_bar')),
          findsNothing,
        );
      } finally {
        await ctx.dispose(tester);
      }
    });

    testWidgets(
      'tapping audio button opens modal with explicit Internet notice and multi-surah choice',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          // Page 604 contains 3 surahs: Al-Ikhlas (112), Al-Falaq (113), An-Nas (114)
          await tester.runAsync(() => ctx.prehydrate(604));

          await tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 604),
            ),
          );
          await tester.pumpAndSettle();

          final audioBtn = find.byKey(
            const ValueKey('quran_audio_select_button'),
          );
          await tester.tap(audioBtn);
          await tester.pumpAndSettle();

          expect(find.text('استماع للسورة كاملة'), findsOneWidget);
          expect(find.textContaining('مشاري العفاسي'), findsWidgets);
          expect(find.textContaining('حفص عن عاصم'), findsWidgets);
          expect(
            find.textContaining('اتصالاً نشطاً بالإنترنت'),
            findsOneWidget,
          );
          final btn112 = find.byKey(const ValueKey('play_page_surah_112'));
          final tile112 = find.ancestor(
            of: btn112,
            matching: find.byType(ListTile),
          );
          expect(
            find.descendant(
              of: tile112,
              matching: find.textContaining('الإخلاص'),
            ),
            findsOneWidget,
          );

          final btn113 = find.byKey(const ValueKey('play_page_surah_113'));
          final tile113 = find.ancestor(
            of: btn113,
            matching: find.byType(ListTile),
          );
          expect(
            find.descendant(
              of: tile113,
              matching: find.textContaining('الفلق'),
            ),
            findsOneWidget,
          );

          final btn114 = find.byKey(const ValueKey('play_page_surah_114'));
          final tile114 = find.ancestor(
            of: btn114,
            matching: find.byType(ListTile),
          );
          expect(
            find.descendant(
              of: tile114,
              matching: find.textContaining('الناس'),
            ),
            findsOneWidget,
          );

          // Bounded actual modal scroll until 114 button hitTestable before tap
          for (
            int i = 0;
            i < 15 && btn114.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(
              find.byType(Scrollable).last,
              const Offset(0, -150),
            );
            await tester.pumpAndSettle();
          }
          expect(btn114.hitTestable(), findsOneWidget);
          await tester.tap(btn114);
          await tester.pumpAndSettle();

          expect(find.text('استماع للسورة كاملة'), findsNothing);
          expect(
            find.byKey(const ValueKey('quran_active_audio_bar')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('quran_active_audio_bar')),
              matching: find.textContaining('الناس'),
            ),
            findsOneWidget,
          );
          expect(ctx.audioClient.playUrlCount, 1);
          expect(
            ctx.audioClient.lastPlayedUrl,
            QuranAudioSource.getSurahAudioUrl(114),
          );
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'active audio bar stop button halts playback and dismisses bar',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 1),
            ),
          );
          await tester.pumpAndSettle();

          await tester.runAsync(
            () => ctx.container
                .read(adhanAudioControllerProvider.notifier)
                .playSurah(surahNumber: 1, surahName: 'الفاتحة'),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('quran_active_audio_bar')),
            findsOneWidget,
          );

          final stopBtn = find.byKey(const ValueKey('quran_audio_stop_button'));
          expect(stopBtn, findsOneWidget);
          await tester.tap(stopBtn);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('quran_active_audio_bar')),
            findsNothing,
          );
          expect(ctx.audioClient.stopCount, 1);
          expect(
            ctx.container.read(adhanAudioControllerProvider).status,
            AdhanAudioStatus.idle,
          );
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets('exiting reader screen stops audio playback', (tester) async {
      await _ensureTestFonts(tester);
      final ctx = (await tester.runAsync(
        () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
      ))!;
      addTearDown(() => ctx.dispose(tester));
      try {
        await tester.runAsync(() => ctx.prehydrate(1));

        await tester.pumpWidget(
          createTestApp(
            container: ctx.container,
            child: Navigator(
              onGenerateRoute: (settings) {
                return MaterialPageRoute(
                  builder: (context) => const QuranReaderScreen(initialPage: 1),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.runAsync(
          () => ctx.container
              .read(adhanAudioControllerProvider.notifier)
              .playSurah(surahNumber: 1, surahName: 'الفاتحة'),
        );
        await tester.pumpAndSettle();
        expect(
          ctx.container.read(adhanAudioControllerProvider).isPlaying,
          isTrue,
        );

        final backBtn = find.byTooltip('العودة إلى الفهرس');
        expect(backBtn, findsOneWidget);
        await tester.tap(backBtn);
        await tester.pumpAndSettle();

        expect(
          ctx.container.read(adhanAudioControllerProvider).isPlaying,
          isFalse,
        );
      } finally {
        await ctx.dispose(tester);
      }
    });

    testWidgets(
      'footer contains QuranPageConfirmationControl in normal flow, page navigation does not auto-confirm, explicit tap confirms and undos',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(5));

          await tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 5),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Assert QuranPageConfirmationControl is rendered inside normal-flow bottom controls
          final confirmControlFinder = find.byType(
            QuranPageConfirmationControl,
          );
          expect(confirmControlFinder, findsOneWidget);

          final controlWidget = tester.widget<QuranPageConfirmationControl>(
            confirmControlFinder,
          );
          expect(controlWidget.pageNumber, 5);

          // Verify unconfirmed initially on page 5
          final confirmBtn = find.byKey(const Key('quran_page_confirm'));
          expect(confirmBtn, findsOneWidget);

          // 2. Change page: 5 -> 6
          final nextBtn = find.text('التالي');
          await tester.tap(nextBtn);
          await tester.pumpAndSettle();

          final updatedWidget = tester.widget<QuranPageConfirmationControl>(
            find.byType(QuranPageConfirmationControl),
          );
          expect(updatedWidget.pageNumber, 6);

          // Assert page navigation NEVER auto-confirms
          final todayBucket = ctx.container
              .read(dateReadinessProvider)
              .activeBucket!;
          final confirmedBefore = await ctx.repo.getConfirmedQuranPages(
            todayBucket,
          );
          expect(
            confirmedBefore,
            isEmpty,
            reason: 'Page navigation must NEVER auto-confirm',
          );

          // 3. Return to page 5
          final prevBtn = find.text('السابق');
          await tester.tap(prevBtn);
          await tester.pumpAndSettle();

          // 4. Explicit tap on confirm button
          await tester.tap(find.byKey(const Key('quran_page_confirm')));
          await _pumpUntil(
            tester,
            () =>
                find.byKey(const Key('quran_page_undo')).evaluate().isNotEmpty,
          );

          final confirmedAfter = await ctx.repo.getConfirmedQuranPages(
            todayBucket,
          );
          expect(confirmedAfter, contains(5));
          expect((await ctx.repo.getReadingProgress()).resumePage, 6);

          // 5. Undo confirmation
          final undoBtn = find.byKey(const Key('quran_page_undo'));
          expect(undoBtn, findsOneWidget);
          await tester.tap(undoBtn);
          await _pumpUntil(
            tester,
            () => find
                .byKey(const Key('quran_page_confirm'))
                .evaluate()
                .isNotEmpty,
          );

          final confirmedAfterUndo = await ctx.repo.getConfirmedQuranPages(
            todayBucket,
          );
          expect(confirmedAfterUndo, isEmpty);
          expect((await ctx.repo.getReadingProgress()).resumePage, 6);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 5. AppShell Navigation + Compact Layout Acceptance at 320x480 textScale 2 (Sol Finding 5)
  // ---------------------------------------------------------------------------
  group('Compact Layout Acceptance & AppShell Integration (Sol Finding 5)', () {
    testWidgets(
      'AppShell nav + insets 320x480 textScale 2 exercises genuine controls, page 604 and image bounding',
      (tester) async {
        await _ensureTestFonts(tester);

        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          // Prehydrate page 604
          await tester.runAsync(() => ctx.prehydrate(604));

          await tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: const Size(320, 480),
                  padding: const EdgeInsets.only(top: 24, bottom: 16),
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              child: const AppShell(),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Genuine navigation to Quran tab
          final quranTab = find.text('القرآن');
          expect(quranTab.hitTestable(), findsOneWidget);
          await tester.tap(quranTab);
          await tester.pumpAndSettle();

          // 2. Resume reading into Page 604 via resume button
          final resumeBtn = find.text('متابعة ←');
          expect(resumeBtn.hitTestable(), findsOneWidget);
          await tester.tap(resumeBtn);
          await tester.pumpAndSettle();

          // Precache page 604 image
          await tester.runAsync(() async {
            final element = tester.element(find.byType(QuranReaderScreen));
            await precacheImage(
              AssetImage(KfqcMushafCatalog.assetPathForPage(604)),
              element,
            );
          });
          await tester.pumpAndSettle();

          // Verify page 604 image destination rect before audio
          await _assertImageBoundedWithoutObstruction(
            tester: tester,
            pageNumber: 604,
          );

          // 3. Scroll top controls row if needed and tap headphones button
          final topScrollable = find.descendant(
            of: find.byKey(const ValueKey('quran_reader_top_controls')),
            matching: find.byType(SingleChildScrollView),
          );
          final audioBtn = find.byKey(
            const ValueKey('quran_audio_select_button'),
          );
          await _scrollRowUntilHitTestable(
            tester,
            target: audioBtn,
            scrollable: topScrollable,
          );
          await tester.tap(audioBtn);
          await tester.pumpAndSettle();

          // Assert multi-surah choices on page 604 and disclosures in dialog
          expect(find.text('استماع للسورة كاملة'), findsOneWidget);
          expect(find.textContaining('مشاري العفاسي'), findsWidgets);
          expect(find.textContaining('حفص عن عاصم'), findsWidgets);
          expect(
            find.textContaining('اتصالاً نشطاً بالإنترنت'),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('play_page_surah_112')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('play_page_surah_113')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('play_page_surah_114')),
            findsOneWidget,
          );

          // Select Surah 114 (An-Nas)
          final surah114Finder = find.byKey(
            const ValueKey('play_page_surah_114'),
          );
          for (
            int i = 0;
            i < 15 && surah114Finder.hitTestable().evaluate().isEmpty;
            i++
          ) {
            await tester.drag(
              find.byType(Scrollable).last,
              const Offset(0, -150),
            );
            await tester.pumpAndSettle();
          }
          expect(surah114Finder.hitTestable(), findsOneWidget);
          await tester.tap(surah114Finder);
          await tester.pumpAndSettle();

          // 4. Assert active audio bar is rendered and layout has no overflow
          expect(
            tester.takeException(),
            isNull,
            reason: 'RenderFlex overflow must not occur at 320x480 textScale 2',
          );
          expect(
            find.byKey(const ValueKey('quran_active_audio_bar')),
            findsOneWidget,
          );

          // 5. Test genuine pause and resume gestures inside active audio bar
          final pauseBtn = find.byKey(
            const ValueKey('quran_audio_pause_button'),
          );
          expect(pauseBtn.hitTestable(), findsOneWidget);
          await tester.tap(pauseBtn);
          await tester.pumpAndSettle();
          expect(
            ctx.container.read(adhanAudioControllerProvider).isPaused,
            isTrue,
          );

          final resumePlayBtn = find.byKey(
            const ValueKey('quran_audio_resume_button'),
          );
          expect(resumePlayBtn.hitTestable(), findsOneWidget);
          await tester.tap(resumePlayBtn);
          await tester.pumpAndSettle();
          expect(
            ctx.container.read(adhanAudioControllerProvider).isPlaying,
            isTrue,
          );

          // 6. Test bottom controls horizontal scroll if needed
          final bottomScrollable = find.descendant(
            of: find.byKey(const ValueKey('quran_reader_bottom_controls')),
            matching: find.byType(SingleChildScrollView),
          );
          final prevBtn = find.text('السابق');
          await _scrollRowUntilHitTestable(
            tester,
            target: prevBtn,
            scrollable: bottomScrollable,
          );
          expect(prevBtn.hitTestable(), findsOneWidget);

          // 7. Verify mushaf image retains positive viewport and all 4 edges bounded without obstruction
          await _assertImageBoundedWithoutObstruction(
            tester: tester,
            pageNumber: 604,
          );

          // 8. Tap stop button inside active audio bar to stop playback
          final stopBtn = find.byKey(const ValueKey('quran_audio_stop_button'));
          expect(stopBtn.hitTestable(), findsOneWidget);
          await tester.tap(stopBtn);
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('quran_active_audio_bar')),
            findsNothing,
          );
          expect(
            ctx.container.read(adhanAudioControllerProvider).status,
            AdhanAudioStatus.idle,
          );
        } finally {
          await ctx.dispose(tester);
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // 6. Quran Index & Sources Screen Attribution
  // ---------------------------------------------------------------------------
  group('Quran Index & Sources Screen Attribution', () {
    testWidgets(
      'surah list in QuranScreen contains audio play button and confirmation dialog',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.pumpWidget(
            createTestApp(container: ctx.container, child: const QuranScreen()),
          );
          await tester.pumpAndSettle();

          final surahAudioBtn = find.byKey(const ValueKey('listen_surah_1'));
          expect(surahAudioBtn, findsOneWidget);

          await tester.tap(surahAudioBtn);
          await tester.pumpAndSettle();

          expect(find.text('استماع للسورة كاملة'), findsWidgets);
          expect(find.textContaining('الفاتحة'), findsWidgets);
          expect(
            find.textContaining('اتصالاً نشطاً بالإنترنت'),
            findsOneWidget,
          );

          final playAction = find.byKey(const ValueKey('confirm_play_surah_1'));
          expect(playAction, findsOneWidget);
          await tester.tap(playAction);
          await tester.pumpAndSettle();

          expect(ctx.audioClient.playUrlCount, 1);
          expect(
            find.byKey(const ValueKey('quran_index_active_audio_bar')),
            findsOneWidget,
          );
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    Future<void> scrollSourcesListViewUntil({
      required WidgetTester tester,
      required Finder target,
      int maxDrags = 140,
    }) async {
      final listViewFinder = find.byType(ListView);
      expect(
        listViewFinder,
        findsOneWidget,
        reason: 'SourcesScreen ListView must exist',
      );
      final listRect = tester.getRect(listViewFinder);
      // Start drag at outer-list margin: left + 4 (inside ListView bounds, outside child Card 16 padding)
      final dragPoint = Offset(listRect.left + 4.0, listRect.center.dy);
      final scrollableFinder = find
          .descendant(of: listViewFinder, matching: find.byType(Scrollable))
          .first;

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
            reason:
                'Outer ListView must actually move on drag $i (before=$pixelsBefore, after=$pixelsAfter, max=$maxScroll)',
          );
        } else {
          break;
        }
      }

      if (target.hitTestable().evaluate().isEmpty) {
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        final position = scrollableState.position;
        final sampleTexts = find
            .byType(Text)
            .evaluate()
            .map((e) => (e.widget as Text).data ?? '')
            .where((t) => t.trim().isNotEmpty)
            .take(8)
            .toList();
        fail(
          'Target not hitTestable after $maxDrags drags. Scroll position: ${position.pixels}/${position.maxScrollExtent}. Visible sample texts: $sampleTexts',
        );
      }
    }

    testWidgets(
      'SourcesScreen displays MP3Quran attribution and IP logging disclaimer',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo, cityRepo: cityRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const SourcesScreen(),
            ),
          );

          // Bounded pump + runAsync real I/O until FutureBuilder licenses snapshot completes
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          bool licensesReady = false;
          String? loadError;

          while (DateTime.now().isBefore(deadline)) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump();

            final waiting = find.text(
              'جاري قراءة نصوص التراخيص الأصلية من حزمة التطبيق...',
            );
            final error = find.text(
              'تعذر قراءة نصوص التراخيص الأصلية من ملفات الحزمة.',
            );

            if (error.evaluate().isNotEmpty) {
              loadError =
                  'SourcesScreen displayed license error card (asset read failure)';
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
            fail(
              'SourcesScreen license asset I/O timed out after 5s; snapshot still waiting',
            );
          }

          await tester.pumpAndSettle();

          // Genuinely scroll to Card 9 near bottom of list
          final card9Finder = find.textContaining(
            'MP3Quran Recitation Sources',
          );
          await scrollSourcesListViewUntil(
            tester: tester,
            target: card9Finder,
            maxDrags: 140,
          );
          expect(card9Finder.hitTestable(), findsOneWidget);

          // Progressively scroll to verify disclosures inside Card 9
          final reciterFinder = find.textContaining('مشاري بن راشد العفاسي');
          await scrollSourcesListViewUntil(
            tester: tester,
            target: reciterFinder,
            maxDrags: 20,
          );
          expect(reciterFinder.hitTestable(), findsWidgets);

          final riwayahFinder = find.textContaining('حفص عن عاصم');
          await scrollSourcesListViewUntil(
            tester: tester,
            target: riwayahFinder,
            maxDrags: 20,
          );
          expect(riwayahFinder.hitTestable(), findsWidgets);

          // Heading before logging paragraph
          final headingFinder = find.text(
            'سياسة تسجيل الخوادم وخصوصية الاتصال:',
          );
          await scrollSourcesListViewUntil(
            tester: tester,
            target: headingFinder,
            maxDrags: 20,
          );
          expect(headingFinder.hitTestable(), findsOneWidget);

          // Logging policy paragraph with IP logging and unconfirmed CDN retention
          final loggingFinder = find.textContaining('خوادمه تسجل آلياً');
          await scrollSourcesListViewUntil(
            tester: tester,
            target: loggingFinder,
            maxDrags: 20,
          );
          expect(loggingFinder.hitTestable(), findsOneWidget);
          expect(find.textContaining('unconfirmed'), findsOneWidget);

          // Privacy and terms button
          final privacyFinder = find.text('سياسة الخصوصية وحقوق الاستخدام');
          await scrollSourcesListViewUntil(
            tester: tester,
            target: privacyFinder,
            maxDrags: 20,
          );
          expect(privacyFinder.hitTestable(), findsOneWidget);

          expect(
            find.textContaining('شبكة طريق الإسلام'),
            findsNothing,
            reason: 'Must not call MP3Quran شبكة طريق الإسلام',
          );
        } finally {
          await ctx.dispose(tester);
        }
      },
    );
  });
}
