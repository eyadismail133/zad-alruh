import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/home/presentation/home_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/favorites_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/sources_screen.dart';
import 'package:zad_alruh/src/features/progress/data/models/reading_progress.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/kfqc_mushaf_catalog.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';
import 'package:zad_alruh/src/features/quran/presentation/controllers/quran_navigation_controller.dart';
import 'package:zad_alruh/src/features/quran/presentation/quran_reader_screen.dart';
import 'package:zad_alruh/src/features/quran/presentation/quran_screen.dart';
import 'package:zad_alruh/src/features/quran/presentation/utils/quran_ui_utils.dart';

const bool kCapturePreviews = bool.fromEnvironment(
  'CAPTURE_PREVIEWS',
  defaultValue: false,
);

bool _fontsLoaded = false;
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

Future<void> _maybeCapture(GlobalKey key, String name) async {
  if (!kCapturePreviews) return;
  final ctx = key.currentContext;
  if (ctx != null) {
    await precacheImage(const AssetImage('assets/branding/logo.png'), ctx);
  }
  final boundary = ctx?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return;
  final outDir = Directory('.local/previews');
  if (!await outDir.exists()) await outDir.create(recursive: true);
  final pixels = await boundary.toImage(pixelRatio: 1);
  try {
    final byteData = await pixels.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      await File(
        p.join(outDir.path, '$name.png'),
      ).writeAsBytes(byteData.buffer.asUint8List());
    }
  } finally {
    pixels.dispose();
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(condition(), isTrue, reason: reason);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> drainQueue(
  WidgetTester tester,
  ReadingProgressController controller, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  bool drained = false;
  final drainFuture = controller.drainPendingWrites().then(
    (_) => drained = true,
  );
  final deadline = DateTime.now().add(timeout);
  while (!drained && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    drained,
    isTrue,
    reason: 'Reading progress controller queue must drain before deadline',
  );
  await drainFuture;
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

Future<void> selectPageVerse(WidgetTester tester, int surah, int ayah) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(QuranReaderScreen)),
  );
  final verse = container
      .read(quranRepositoryProvider)
      .requireValue
      .getVerse(surah, ayah);
  await tester.tap(find.byTooltip('اختيار آية من الصفحة'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('page_verse_surah')));
  await tester.pumpAndSettle();
  final name = container
      .read(quranRepositoryProvider)
      .requireValue
      .getSurah(verse.surahNumber)
      .name;
  await tester.tap(find.text('سورة $name').last);
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(ValueKey('page_verse_ayah_${verse.surahNumber}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.text('الآية ${QuranUiUtils.toArabicDigits(verse.verseNumber)}').last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('اختيار'));
  await tester.pumpAndSettle();
}

class TransientCachingAssetBundle extends CachingAssetBundle {
  bool shouldFail = true;
  final Set<String> loadedKeys = {};

  @override
  Future<ByteData> load(String key) async {
    if (shouldFail) throw FlutterError('Simulated asset failure');
    final data = await rootBundle.load(key);
    loadedKeys.add(key);
    return data;
  }
}

class _FailingWebpAssetBundle extends CachingAssetBundle {
  final Set<String> failedKeys = {};

  @override
  Future<ByteData> load(String key) async {
    if (key.endsWith('.webp')) {
      failedKeys.add(key);
      throw FlutterError('Simulated image asset failure for $key');
    }
    return rootBundle.load(key);
  }
}

class _TestUrlLauncherPlatform extends UrlLauncherPlatform {
  String? lastUrl;
  LaunchOptions? lastOptions;
  Object? errorToThrow;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    lastUrl = url;
    lastOptions = options;
    if (errorToThrow != null) throw errorToThrow!;
    return false;
  }
}

class _GatedProgressRepository extends ProgressRepository {
  _GatedProgressRepository(super.database, {super.versePageValidator});

  Completer<void>? gate;
  bool shouldFail = false;

  @override
  Future<ReadingProgress> getReadingProgress() async {
    if (gate != null) await gate!.future;
    if (shouldFail) throw StateError('Simulated bootstrap failure');
    return super.getReadingProgress();
  }
}

class _TestContext {
  final Directory tempDir;
  final AppDatabase db;
  final ProgressRepository repo;
  final ProviderContainer container;
  bool _disposed = false;

  _TestContext(this.tempDir, this.db, this.repo, this.container);

  static Future<_TestContext> create({
    required QuranRepository quranRepo,
    ProgressRepository Function(AppDatabase db)? repoBuilder,
  }) async {
    final tempDir = await Directory.systemTemp.createTemp('q_ui_');
    final db = AppDatabase(
      databaseFactory: databaseFactoryFfiNoIsolate,
      databasePath: p.join(tempDir.path, 'q.db'),
    );
    final repo = repoBuilder != null
        ? repoBuilder(db)
        : ProgressRepository(
            db,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );
    final container = ProviderContainer(
      overrides: [
        quranRepositoryProvider.overrideWith((ref) => Future.value(quranRepo)),
        progressRepositoryProvider.overrideWithValue(repo),
        cityRepositoryProvider.overrideWith((ref) async => cityRepo),
      ],
    );
    return _TestContext(tempDir, db, repo, container);
  }

  Future<void> prehydrate([int page = 1]) async {
    await repo.saveReadingProgress(ReadingProgress(lastPage: page));
    await container.read(readingProgressControllerProvider.future);
    await container.read(bookmarksControllerProvider.future);
    await container.read(favoritesControllerProvider.future);
    await container.read(preferencesControllerProvider.future);
    final readiness = container.read(dateReadinessProvider);
    if (readiness.activeBucket != null) {
      await container.read(
        dailyQuranPagesControllerProvider(readiness.activeBucket!).future,
      );
      await container.read(
        dailyProgressControllerProvider(readiness.activeBucket!).future,
      );
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    if (_disposed) return;
    _disposed = true;
    try {
      await drainQueue(
        tester,
        container.read(readingProgressControllerProvider.notifier),
      );
    } catch (_) {}
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
    await tester.runAsync(() async {
      await repo.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });
  }
}

late CityRepository cityRepo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  ensureTimeZonesInitialized();

  late QuranRepository quranRepo;

  setUpAll(() async {
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

  group('Quran UI - Core Navigation, Search & Reader Workflows', () {
    testWidgets(
      'KFQC page 121 picker excludes neighboring Tanzil boundary verses',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        await tester.runAsync(() => ctx.prehydrate(121));
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 121),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('اختيار آية من الصفحة'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('page_verse_ayah_5')));
        await tester.pumpAndSettle();
        expect(find.text('الآية ٧٨'), findsWidgets);
        expect(find.text('الآية ٨٣'), findsOneWidget);
        expect(find.text('الآية ٧٧'), findsNothing);
        expect(find.text('الآية ٨٤'), findsNothing);
      },
    );

    testWidgets(
      'bookmark from image picker preserves both surah and ayah on multi-surah page',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        await tester.runAsync(() => ctx.prehydrate(604));
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 604),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await selectPageVerse(tester, 114, 6);
        await tester.tap(find.text('إضافة علامة مرجعية مخصصة'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(quranRepo.getVerse(114, 6).text),
          findsNothing,
        );
        await tester.tap(find.text('حفظ العلامة'));
        await pumpUntil(
          tester,
          () =>
              ctx.container
                  .read(bookmarksControllerProvider)
                  .valueOrNull
                  ?.isNotEmpty ==
              true,
        );
        final bookmark = (await tester.runAsync(
          () => ctx.repo.getBookmarks(),
        ))!.single;
        expect(bookmark.pageNumber, 604);
        expect(bookmark.surahNumber, 114);
        expect(bookmark.verseNumber, 6);
      },
    );
    testWidgets(
      'confirmed page resumes the next image in the same index session without marking it read',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        await tester.runAsync(() => ctx.prehydrate(2));
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(container: ctx.container, child: const QuranScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('متابعة ←'));
        await pumpUntil(
          tester,
          () =>
              find.byKey(const Key('quran_page_confirm')).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byKey(const Key('quran_page_confirm')));
        await tester.tap(find.byKey(const Key('quran_page_confirm')));
        await pumpUntil(
          tester,
          () =>
              ctx.container
                  .read(readingProgressControllerProvider)
                  .valueOrNull
                  ?.resumePage ==
              3,
        );
        expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);
        await tester.tap(find.byTooltip('العودة إلى الفهرس'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('متابعة ←'));
        await tester.pumpAndSettle();
        expect(find.text('صفحة ٣ / ٦٠٤'), findsOneWidget);
        final bucket = ctx.container.read(dateReadinessProvider).activeBucket!;
        expect(
          await tester.runAsync(() => ctx.repo.getConfirmedQuranPages(bucket)),
          {2},
        );
        expect(find.byKey(const Key('quran_page_confirm')), findsOneWidget);
      },
    );

    testWidgets(
      'page picker verse favorite reopens its canonical image without showing stored text',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        await tester.runAsync(() => ctx.prehydrate(604));
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 604),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await selectPageVerse(tester, 112, 2);
        await tester.tap(find.text('إضافة الآية إلى المفضلة'));
        await pumpUntil(
          tester,
          () =>
              ctx.container
                  .read(favoritesControllerProvider)
                  .valueOrNull
                  ?.any((f) => f.stableId == '112:2') ==
              true,
        );
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const FavoritesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('المفضلة'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(quranRepo.getVerse(112, 2).text),
          findsNothing,
        );
        await tester.tap(find.text('سورة 112 · الآية 2'));
        await pumpUntil(
          tester,
          () => find.text('صفحة ٦٠٤ / ٦٠٤').evaluate().isNotEmpty,
        );
        expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
      },
    );

    testWidgets(
      'image page semantics identifies its multi-surah source without Quran text',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        final semantics = tester.ensureSemantics();
        await tester.runAsync(() => ctx.prehydrate(604));
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 604),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.bySemanticsLabel(
            RegExp('صفحة مصورة رقم ٦٠٤.*الإخلاص.*الفلق.*الناس'),
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            quranRepo.getVerse(114, 6).text,
            findRichText: true,
          ),
          findsNothing,
        );
        semantics.dispose();
      },
    );
    testWidgets(
      'image reader selects exact stop on a multi-surah page without text mode',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        await tester.runAsync(() => ctx.prehydrate(604));
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: const QuranReaderScreen(initialPage: 604),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('نص القرآن'), findsNothing);
        await tester.tap(find.byTooltip('اختيار آية من الصفحة'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('page_verse_surah')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('سورة الناس').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('page_verse_ayah_114')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('الآية ٦').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('اختيار'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining(quranRepo.getVerse(114, 6).text),
          findsNothing,
        );
        await tester.tap(find.text('تحديد كموضع توقف عند هذه الآية'));
        await tester.pumpAndSettle();
        await drainQueue(
          tester,
          ctx.container.read(readingProgressControllerProvider.notifier),
        );
        final saved = await tester.runAsync(
          () => ctx.repo.getReadingProgress(),
        );
        expect(saved!.lastPage, 604);
        expect(saved.selectedSurah, 114);
        expect(saved.selectedVerse, 6);
      },
    );
    testWidgets(
      'renders 114 Surahs and 30 Juz tabs, and autosaves chapter navigation immediately',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));

        try {
          // Seed page 5 to verify initial navigation changes lastPage to 2
          await tester.runAsync(() => ctx.prehydrate(5));

          final captureKey = GlobalKey();
          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: RepaintBoundary(
                  key: captureKey,
                  child: const QuranScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('القرآن الكريم'), findsOneWidget);
          expect(find.text('آخر موضع قراءة'), findsOneWidget);
          expect(find.text('متابعة ←'), findsOneWidget);
          expect(find.text('الفاتحة'), findsOneWidget);
          expect(find.text('البقرة'), findsOneWidget);

          // Switch to Juzs tab
          final juzTab = find.text('الأجزاء (٣٠)');
          await tester.ensureVisible(juzTab);
          await tester.tap(juzTab);
          await tester.pumpAndSettle();
          expect(find.text('الجزء ١'), findsOneWidget);
          expect(find.text('الجزء ٢'), findsWidgets);

          // Switch back to Surahs tab and tap Al-Baqarah (starts at page 2)
          final surahsTab = find.text('السور (١١٤)');
          await tester.ensureVisible(surahsTab);
          await tester.tap(surahsTab);
          await tester.pumpAndSettle();

          final chapter = find.text('البقرة');
          await tester.ensureVisible(chapter);
          await tester.tap(chapter);
          await tester.pumpAndSettle();

          expect(find.text('المصحف المصوّر'), findsOneWidget);
          expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);

          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );
          final saved = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(saved.lastPage, 2);

          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();
          expect(find.text('القرآن الكريم'), findsOneWidget);
          expect(find.textContaining('صفحة ٢'), findsWidgets);
          await tester.runAsync(
            () => _maybeCapture(captureKey, 'quran-index-view'),
          );
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'searches offline metadata without text snippets and opens mapped image page',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          final captureKey = GlobalKey();
          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: RepaintBoundary(
                  key: captureKey,
                  child: const QuranScreen(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Search for verbatim term
          await tester.enterText(find.byType(TextField), 'نستعين');
          await tester.pumpAndSettle();

          expect(find.textContaining('نتائج البحث'), findsOneWidget);
          expect(
            find.textContaining('إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ'),
            findsNothing,
          );

          await tester.runAsync(
            () => _maybeCapture(captureKey, 'quran-search-view'),
          );

          // Tapping search result opens mapped page (Page 1)
          await tester.tap(find.text('سورة الفاتحة · الآية ٥'));
          await tester.pumpAndSettle();

          expect(find.text('المصحف المصوّر'), findsOneWidget);
          expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);

          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );
          final progress = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(progress.lastPage, 1);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'digit-normalized page jump rejects out-of-range, accepts Arabic-Indic and ASCII, and displays authentic Surah from repo',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Open jump dialog
          await tester.tap(find.byIcon(Icons.pin_outlined));
          await tester.pumpAndSettle();

          final jumpTextField = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );

          // 1. Invalid out-of-range input (999)
          await tester.enterText(jumpTextField, '999');
          await tester.tap(find.text('انتقال'));
          await tester.pumpAndSettle();
          expect(
            find.text('يرجى إدخال رقم صفحة صحيح بين ١ و ٦٠٤'),
            findsOneWidget,
          );

          // 2. Arabic-Indic digits '١٨٧' (187)
          await tester.enterText(jumpTextField, '١٨٧');
          await tester.tap(find.text('انتقال'));
          await tester.pumpAndSettle();

          expect(find.text('المصحف المصوّر'), findsOneWidget);
          expect(find.text('صفحة ١٨٧ / ٦٠٤'), findsOneWidget);

          final surah9 = quranRepo.getSurah(9);
          expect(find.textContaining(surah9.name), findsWidgets);

          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );
          final progress187 = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(progress187.lastPage, 187);

          // 3. ASCII digits jump '604'
          await tester.tap(find.byIcon(Icons.pin_outlined));
          await tester.pumpAndSettle();
          final jumpTextField2 = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(jumpTextField2, '604');
          await tester.tap(find.text('انتقال'));
          await tester.pumpAndSettle();

          expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
          final surah114 = quranRepo.getSurah(114);
          expect(find.textContaining(surah114.name), findsWidgets);

          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );
          final progress604 = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(progress604.lastPage, 604);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'page-scoped image verse selection sets exact stop verse in UI, persists across reopen, and clears on page turn',
      (tester) async {
        await _ensureTestFonts(tester);
        final tempDir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('q_exact_'),
        ))!;
        final dbPath = p.join(tempDir.path, 'exact.db');

        final db1 = AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: dbPath,
        );
        final repo1 = ProgressRepository(
          db1,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        final container1 = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo1),
          ],
        );

        AppDatabase? db2;
        ProgressRepository? repo2;
        ProviderContainer? container2;

        try {
          // Session 1: Open Reader at page 2 (Al-Baqarah 2:1..5)
          await tester.runAsync(() async {
            await repo1.saveReadingProgress(const ReadingProgress(lastPage: 2));
            await container1.read(readingProgressControllerProvider.future);
          });

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: container1,
                child: const QuranReaderScreen(initialPage: 2),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await selectPageVerse(tester, 2, 2);
          await tester.pumpAndSettle();

          // BottomSheet options appear
          final setStopOption = find.text('تحديد كموضع توقف عند هذه الآية');
          expect(setStopOption, findsOneWidget);
          await tester.tap(setStopOption);
          await tester.pumpAndSettle();

          // Await public reading queue completion
          await drainQueue(
            tester,
            container1.read(readingProgressControllerProvider.notifier),
          );

          // Verify real SQLite was updated to Surah 2, Verse 2
          final savedProgress = (await tester.runAsync(
            () => repo1.getReadingProgress(),
          ))!;
          expect(savedProgress.lastPage, 2);
          expect(savedProgress.selectedSurah, 2);
          expect(savedProgress.selectedVerse, 2);

          // Reader displays the exact stop badge
          expect(find.textContaining('الآية ٢'), findsWidgets);

          // Close Session 1
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container1.dispose();
          await tester.runAsync(() => repo1.close());

          // Session 2: Reopen with same SQLite file
          db2 = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: dbPath,
          );
          repo2 = ProgressRepository(
            db2,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );
          container2 = ProviderContainer(
            overrides: [
              quranRepositoryProvider.overrideWith(
                (ref) => Future.value(quranRepo),
              ),
              progressRepositoryProvider.overrideWithValue(repo2),
            ],
          );

          await tester.runAsync(
            () => container2!.read(readingProgressControllerProvider.future),
          );

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(container: container2!, child: const QuranScreen()),
            ),
          );
          await tester.pumpAndSettle();

          // Resume banner reflects restored page 2 with exact verse 2
          expect(find.textContaining('صفحة ٢'), findsWidgets);
          expect(find.textContaining('الآية ٢'), findsWidgets);

          // Open reader via resume button
          await tester.tap(find.text('متابعة ←'));
          await drainQueue(
            tester,
            container2.read(readingProgressControllerProvider.notifier),
          );
          await tester.pumpAndSettle();

          expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);

          expect(find.textContaining('الآية ٢'), findsWidgets);

          // Turn to page 3 via 'التالي' - clears stop verse
          await tester.tap(find.text('التالي'));
          await drainQueue(
            tester,
            container2.read(readingProgressControllerProvider.notifier),
          );
          await tester.pumpAndSettle();

          expect(find.text('صفحة ٣ / ٦٠٤'), findsOneWidget);

          final readingP3 = (await tester.runAsync(
            () => repo2!.getReadingProgress(),
          ))!;
          expect(readingP3.lastPage, 3);
          expect(readingP3.selectedSurah, isNull);
          expect(readingP3.selectedVerse, isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container1.dispose();
          container2?.dispose();
          await tester.runAsync(() async {
            try {
              await repo1.close();
            } catch (_) {}
            try {
              await repo2?.close();
            } catch (_) {}
            if (await tempDir.exists()) await tempDir.delete(recursive: true);
          });
        }
      },
    );

    testWidgets(
      'reader autosave failure surfaces Arabic SnackBar retry and recovers when SQLite write is restored',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(2));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranReaderScreen(initialPage: 2),
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Drain initial page autosave before putting database into read-only mode
          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );

          // 1. Put SQLite into read-only mode to induce write failure
          final rawDb = await ctx.db.database;
          await tester.runAsync(() => rawDb.execute('PRAGMA query_only = ON;'));

          // 2. Navigate to Page 3 (write fails)
          await tester.tap(find.text('التالي'));
          await pumpUntil(
            tester,
            () => find
                .text('تعذر حفظ موضع القراءة الحالي.')
                .evaluate()
                .isNotEmpty,
            reason: 'Arabic error SnackBar must appear after write failure',
          );

          // UI surfaces honest Arabic SnackBar without raw SQL or technical details
          expect(find.text('تعذر حفظ موضع القراءة الحالي.'), findsOneWidget);
          final retryButton = find.descendant(
            of: find.byType(SnackBar),
            matching: find.text('إعادة المحاولة'),
          );
          expect(retryButton, findsOneWidget);
          expect(find.textContaining('query_only'), findsNothing);
          expect(find.textContaining('DatabaseException'), findsNothing);

          // Database still has prior page (page 2)
          final progressBefore = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(progressBefore.lastPage, 2);

          // 3. Restore database writes
          await tester.runAsync(
            () => rawDb.execute('PRAGMA query_only = OFF;'),
          );

          // 4. Tap SnackBar retry action
          await tester.tap(retryButton);
          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );
          await tester.pumpAndSettle();

          // Database is now safely updated to intended destination (page 3)
          final progressAfter = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(progressAfter.lastPage, 3);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'creates named bookmark, displays in Bookmarks and Favorites, deletes, and opens mapped page',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(10));

          // Mount reader at page 10
          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranReaderScreen(initialPage: 10),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Open add bookmark dialog
          await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
          await tester.pumpAndSettle();

          expect(find.text('إضافة علامة مرجعية'), findsOneWidget);
          final nameField = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(nameField, 'ورد الصباح صفحة ١٠');
          await tester.tap(find.text('حفظ العلامة'));
          await pumpUntil(
            tester,
            () => find.byType(AlertDialog).evaluate().isEmpty,
          );

          final bookmarks = (await tester.runAsync(
            () => ctx.repo.getBookmarks(),
          ))!;
          expect(bookmarks.length, 1);
          expect(bookmarks.first.name, 'ورد الصباح صفحة ١٠');
          expect(bookmarks.first.pageNumber, 10);

          // Mount FavoritesScreen using same container
          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const FavoritesScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('ورد الصباح صفحة ١٠'), findsOneWidget);

          // Tap bookmark opens reader at page 10
          await tester.tap(find.text('ورد الصباح صفحة ١٠'));
          await tester.pumpAndSettle();

          expect(find.text('المصحف المصوّر'), findsOneWidget);
          expect(find.text('صفحة ١٠ / ٦٠٤'), findsOneWidget);

          // Return to favorites and delete
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.delete_outline));
          await tester.pumpAndSettle();

          final remaining = (await tester.runAsync(
            () => ctx.repo.getBookmarks(),
          ))!;
          expect(remaining.isEmpty, isTrue);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets('Home continue-reading button opens restored page in reader', (
      tester,
    ) async {
      await _ensureTestFonts(tester);
      final ctx = (await tester.runAsync(
        () => _TestContext.create(quranRepo: quranRepo),
      ))!;
      addTearDown(() => ctx.dispose(tester));
      try {
        await tester.runAsync(() => ctx.prehydrate(50));

        int? navigatedTab;
        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              child: HomeScreen(onNavigateTab: (tab) => navigatedTab = tab),
            ),
          ),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (find.text('آخر صفحة مسجلة: صفحة 50 من ٦٠٤').evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        await tester.pump();

        expect(find.text('آخر صفحة مسجلة: صفحة 50 من ٦٠٤'), findsOneWidget);

        await tester.tap(find.text('كمّل وِردك  ←'));
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        expect(navigatedTab, 1);
        final navState = ctx.container.read(quranNavigationProvider);
        expect(navState.isReaderOpen, isTrue);
        expect(navState.currentPage, 50);
      } finally {
        await ctx.dispose(tester);
      }
    });

    testWidgets(
      'Mushaf image mode defaults to bundled KFQC sheet, shows attribution dialog without text mode',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranReaderScreen(initialPage: 1),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // 1. Defaults to Mushaf image mode with InteractiveViewer
          expect(find.byType(InteractiveViewer), findsOneWidget);
          expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);
          expect(find.text('مصحف المدينة (حفص)'), findsOneWidget);

          // 2. Tapping narration badge opens KFQC attribution dialog
          await tester.tap(find.text('مصحف المدينة (حفص)'));
          await tester.pumpAndSettle();
          expect(find.text('مصحف المدينة النبوية'), findsOneWidget);
          expect(
            find.textContaining('الدليل الفني لمجمع الملك فهد'),
            findsOneWidget,
          );
          expect(find.textContaining('quran-ws/quran-svg'), findsOneWidget);
          await tester.tap(find.text('إغلاق'));
          await tester.pumpAndSettle();

          expect(find.text('نص القرآن'), findsNothing);
          expect(find.byType(InteractiveViewer), findsOneWidget);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'Sources screen renders complete notices, handles asset load failure with retry, and external URL fallback with copy',
      (tester) async {
        await _ensureTestFonts(tester);
        String? copiedClipboardText;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedClipboardText = (call.arguments as Map)['text'] as String;
              return null;
            }
            if (call.method == 'Clipboard.getData') {
              return {'text': copiedClipboardText};
            }
            if (call.method == 'Clipboard.hasStrings') {
              return {'value': copiedClipboardText?.isNotEmpty ?? false};
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final previousPlatform = UrlLauncherPlatform.instance;
        final testPlatform = _TestUrlLauncherPlatform();
        UrlLauncherPlatform.instance = testPlatform;
        addTearDown(() {
          UrlLauncherPlatform.instance = previousPlatform;
        });

        final failingBundle = TransientCachingAssetBundle();
        final container = ProviderContainer();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
        });

        try {
          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: container,
                child: SourcesScreen(bundle: failingBundle),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Scroll to error card before assert/retry (offscreen in lazy ListView)
          final errorText = find.text(
            'تعذر قراءة نصوص التراخيص الأصلية من ملفات الحزمة.',
          );
          await tester.scrollUntilVisible(
            errorText,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();

          // Verify failure view and retry button
          expect(errorText, findsOneWidget);
          final retryBtn = find.text('إعادة المحاولة');
          expect(retryBtn, findsOneWidget);

          // Recover bundle and retry
          failingBundle.shouldFail = false;
          await tester.tap(retryBtn);

          // Await all three actual assets loaded via real I/O
          await pumpUntil(
            tester,
            () =>
                failingBundle.loadedKeys.contains(
                  'assets/content/quran/quran-uthmani.txt',
                ) &&
                failingBundle.loadedKeys.contains(
                  'assets/fonts/IBM-Plex-LICENSE.txt',
                ) &&
                failingBundle.loadedKeys.contains('assets/fonts/Amiri-OFL.txt'),
            reason:
                'All three license assets must load successfully via real I/O',
          );
          await tester.pumpAndSettle();

          // Reset scroll position to top before forward scroll to lazy Tanzil card
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0.0);
          await tester.pumpAndSettle();

          // Scroll to Tanzil card then condition driver await actual verbatim copyright notice
          final tanzilHeader = find.text(
            'نسب المصدر ورخصة نص تنزيل (Tanzil License)',
          );
          await tester.scrollUntilVisible(
            tanzilHeader,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await pumpUntil(
            tester,
            () => find
                .textContaining(
                  '# PLEASE DO NOT REMOVE OR CHANGE THIS COPYRIGHT BLOCK',
                )
                .evaluate()
                .isNotEmpty,
            reason: 'Verbatim Tanzil copyright notice must load via real I/O',
          );

          expect(
            find.textContaining('مشروع تنزيل (Tanzil Project)'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              '# PLEASE DO NOT REMOVE OR CHANGE THIS COPYRIGHT BLOCK',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('Tanzil Quran Text (Uthmani, Version 1.1)'),
            findsOneWidget,
          );

          // Scroll to and verify KFQC Mushaf artwork card
          final kfqcHeader = find.text(
            'نسب المصدر ورخصة صفحات مصحف المدينة النبوية (KFQC)',
          );
          await tester.scrollUntilVisible(
            kfqcHeader,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(kfqcHeader, findsOneWidget);
          expect(find.textContaining('quran-ws/quran-svg'), findsWidgets);

          // Scroll to Font card
          final fontHeader = find.text('تراخيص الخطوط وبيانات المصحف الوصفية');
          await tester.scrollUntilVisible(
            fontHeader,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();

          expect(find.textContaining('IBM Plex Sans Arabic'), findsOneWidget);
          expect(find.textContaining('Amiri Quran'), findsOneWidget);
          expect(
            find.textContaining('SIL Open Font License, Version 1.1'),
            findsWidgets,
          );

          // Scroll BACK to Tanzil visit button before ensureVisible/tap (lazy ListView recycled it)
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
          final launchButton = find.text('زيارة موقع تنزيل');
          await tester.scrollUntilVisible(
            launchButton,
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();

          // 1. External URL launch fallback (canLaunch true, launchUrl false)
          await tester.ensureVisible(launchButton);
          await tester.tap(launchButton);
          await tester.pumpAndSettle();

          expect(testPlatform.lastUrl, 'https://tanzil.net');
          expect(
            testPlatform.lastOptions?.mode,
            PreferredLaunchMode.externalApplication,
          );
          expect(
            find.textContaining('تعذر فتح رابط مشروع تنزيل في المتصفح الخارجي'),
            findsOneWidget,
          );

          // Tap copy link action and verify clipboard contents
          final copyButton = find.text('نسخ الرابط');
          expect(copyButton, findsOneWidget);
          await tester.tap(copyButton);
          await tester.pumpAndSettle();

          expect(
            find.textContaining('تم نسخ رابط مشروع تنزيل بنجاح'),
            findsOneWidget,
          );
          final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
          expect(clipboard?.text, 'https://tanzil.net');

          // 2. PlatformException handling
          testPlatform.lastUrl = null;
          testPlatform.errorToThrow = PlatformException(
            code: 'ACTIVITY_NOT_FOUND',
            message: 'No activity',
          );
          await tester.ensureVisible(launchButton);
          await tester.tap(launchButton);
          await tester.pumpAndSettle();

          expect(
            find.textContaining('تعذر فتح رابط مشروع تنزيل في المتصفح الخارجي'),
            findsOneWidget,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
        }
      },
    );

    testWidgets(
      'renders index, search, reader, bookmark, and jump at 360x640 with 1.8 font scale without overflow',
      (tester) async {
        await _ensureTestFonts(tester);
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.8)),
                  child: child!,
                ),
                child: const QuranScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('القرآن الكريم'), findsOneWidget);

          // Verify all 3 scrollable tabs are visible and tappable at 1.8 font scale
          final juzTab = find.text('الأجزاء (٣٠)');
          await tester.ensureVisible(juzTab);
          await tester.tap(juzTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('الجزء ١'), findsOneWidget);

          final bookmarksTab = find.text('العلامات المحفوظة');
          await tester.ensureVisible(bookmarksTab);
          await tester.tap(bookmarksTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            find.text('لا توجد علامات مرجعية محفوظة حالياً'),
            findsOneWidget,
          );

          final surahsTab = find.text('السور (١١٤)');
          await tester.ensureVisible(surahsTab);
          await tester.tap(surahsTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('الفاتحة'), findsOneWidget);
          expect(find.text('البقرة'), findsOneWidget);

          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();

          // Search at 1.8
          final searchField = find.byType(TextField);
          await tester.enterText(searchField, 'نستعين');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('نتائج البحث'), findsOneWidget);

          await tester.enterText(searchField, '');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // Open reader
          final surahTile = find.text('البقرة');
          await tester.ensureVisible(surahTile);
          await tester.tap(surahTile);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('المصحف المصوّر'), findsOneWidget);

          // Bookmark dialog at 1.8
          await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('إضافة علامة مرجعية'), findsOneWidget);

          final bookmarkNameField = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          );
          await tester.enterText(bookmarkNameField, 'علامة 1.8');
          await tester.tap(find.text('حفظ العلامة'));
          await pumpUntil(
            tester,
            () => find.byType(AlertDialog).evaluate().isEmpty,
          );
          expect(tester.takeException(), isNull);

          // Page jump dialog at 1.8
          await tester.tap(find.byIcon(Icons.pin_outlined));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('الانتقال إلى صفحة'), findsOneWidget);

          await tester.tap(find.text('إلغاء'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'preserves latest navigation order under blocked SQLite writer even if reader is popped',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        final enteredCompleter = Completer<void>();
        final releaseCompleter = Completer<void>();
        Future<void>? txnFuture;

        addTearDown(() async {
          if (!releaseCompleter.isCompleted) {
            releaseCompleter.complete();
          }
          if (txnFuture != null) {
            try {
              await tester.runAsync(() => txnFuture!);
            } catch (_) {}
          }
          try {
            await drainQueue(
              tester,
              ctx.container.read(readingProgressControllerProvider.notifier),
            );
          } catch (_) {}
          await ctx.dispose(tester);
        });

        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Open reader at page 1
          ctx.container.read(quranNavigationProvider.notifier).openReader(1);
          await tester.pumpAndSettle();
          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );

          // Block the SQLite writer thread
          await tester.runAsync(() async {
            final rawDb = await ctx.db.database;
            txnFuture = rawDb.transaction((txn) async {
              enteredCompleter.complete();
              await releaseCompleter.future;
            });
          });
          await pumpUntil(tester, () => enteredCompleter.isCompleted);

          // Rapidly navigate: Page 2 -> 3 -> 4
          await tester.tap(find.text('التالي'));
          await tester.pump();
          await tester.tap(find.text('التالي'));
          await tester.pump();
          await tester.tap(find.text('التالي'));
          await tester.pump();

          expect(find.text('صفحة ٤ / ٦٠٤'), findsOneWidget);

          // Pop reader back to index while write is still blocked
          ctx.container.read(quranNavigationProvider.notifier).closeReader();
          await tester.pump();

          // Release SQLite writer lock and drain queue
          if (!releaseCompleter.isCompleted) {
            releaseCompleter.complete();
          }
          if (txnFuture != null) {
            await tester.runAsync(() => txnFuture!);
          }
          await drainQueue(
            tester,
            ctx.container.read(readingProgressControllerProvider.notifier),
          );
          await tester.pumpAndSettle();

          // Latest navigated page (page 4) was persisted
          final finalProgress = (await tester.runAsync(
            () => ctx.repo.getReadingProgress(),
          ))!;
          expect(finalProgress.lastPage, 4);
        } finally {
          if (!releaseCompleter.isCompleted) {
            releaseCompleter.complete();
          }
          if (txnFuture != null) {
            try {
              await tester.runAsync(() => txnFuture!);
            } catch (_) {}
          }
          try {
            await drainQueue(
              tester,
              ctx.container.read(readingProgressControllerProvider.notifier),
            );
          } catch (_) {}
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'Sol P1: QuranScreen resume banner loading, error retry, and safe resume of actual page 155',
      (tester) async {
        await _ensureTestFonts(tester);
        _GatedProgressRepository? gatedRepo;
        final ctx = (await tester.runAsync(
          () => _TestContext.create(
            quranRepo: quranRepo,
            repoBuilder: (db) {
              gatedRepo = _GatedProgressRepository(
                db,
                versePageValidator: quranRepo.isValidVerseOnPage,
              );
              return gatedRepo!;
            },
          ),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          // Seed actual saved page 155 into SQLite
          await tester.runAsync(
            () => gatedRepo!.saveReadingProgress(
              const ReadingProgress(lastPage: 155),
            ),
          );

          // Gate the bootstrap read
          gatedRepo!.gate = Completer<void>();

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranScreen(),
              ),
            ),
          );
          await tester.pump();

          // 1. Loading state: banner indicates loading, Resume button is NOT enabled/rendered
          expect(find.text('جاري استرجاع موضع القراءة...'), findsOneWidget);
          expect(find.text('متابعة ←'), findsNothing);

          // Intentional chapter list remains usable while reading progress is loading
          expect(find.text('الفاتحة'), findsOneWidget);
          expect(find.text('البقرة'), findsOneWidget);

          // 2. Trigger error state
          gatedRepo!.shouldFail = true;
          gatedRepo!.gate!.complete();
          await tester.pumpAndSettle();

          expect(find.text('تعذر تحميل آخر موضع قراءة.'), findsOneWidget);
          expect(find.text('إعادة المحاولة'), findsOneWidget);
          expect(find.text('متابعة ←'), findsNothing);

          // 3. Recover and tap retry
          gatedRepo!.shouldFail = false;
          gatedRepo!.gate = null;
          await tester.tap(find.text('إعادة المحاولة'));
          await pumpUntil(
            tester,
            () => find.text('متابعة ←').evaluate().isNotEmpty,
          );

          // 4. Actual saved page 155 is displayed and safely resumed
          expect(find.textContaining('صفحة ١٥٥'), findsWidgets);
          expect(find.text('متابعة ←'), findsOneWidget);

          await tester.tap(find.text('متابعة ←'));
          await tester.pumpAndSettle();

          expect(find.text('المصحف المصوّر'), findsOneWidget);
          expect(find.text('صفحة ١٥٥ / ٦٠٤'), findsOneWidget);

          // Position was safely preserved as 155 and not corrupted to 1
          final progress = (await tester.runAsync(
            () => gatedRepo!.getReadingProgress(),
          ))!;
          expect(progress.lastPage, 155);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'horizontal drag/swipe in default Mushaf image mode advances exact KFQC page image and header',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranReaderScreen(initialPage: 1),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // Initially on Page 1 in default Mushaf image mode
          expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);
          expect(find.text('سورة الفاتحة'), findsWidgets);
          expect(find.byType(InteractiveViewer), findsOneWidget);

          final pageViewFinder = find.byType(PageView);
          expect(pageViewFinder, findsOneWidget);

          // Fling forward (left to right in RTL)
          await tester.fling(pageViewFinder, const Offset(400, 0), 1000);
          await tester.pumpAndSettle();

          // Advanced to Page 2
          expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);
          expect(find.text('سورة البقرة'), findsWidgets);
          expect(find.byType(InteractiveViewer), findsOneWidget);

          // Fling backward (right to left in RTL)
          await tester.fling(pageViewFinder, const Offset(-400, 0), 1000);
          await tester.pumpAndSettle();

          // Returned to Page 1
          expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);
          expect(find.text('سورة الفاتحة'), findsWidgets);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'Mushaf image mode InteractiveViewer configures zoom constraints and resets zoom',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranReaderScreen(initialPage: 1),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(InteractiveViewer), findsOneWidget);
          final viewer = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer).first,
          );
          expect(viewer.minScale, 1.0);
          expect(viewer.maxScale, 4.0);

          // At scale 1.0, pan is disabled so horizontal swipe is preserved for PageView
          expect(viewer.panEnabled, isFalse);

          // Zoom-out reset button is not shown at default scale
          expect(find.byIcon(Icons.zoom_out_map), findsNothing);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'delayed Quran load reconciles legacy 5:77 stop and bookmark in real SQLite and surfaces recoverable error on failure',
      (tester) async {
        await tester.runAsync(() async {
          final tempDir = await Directory.systemTemp.createTemp('q_delayed_');
          final db = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: p.join(tempDir.path, 'delayed.db'),
          );
          final rawDb = await db.database;

          // Seed legacy records directly into SQLite: page 121 with selected verse 5:77
          await rawDb.insert('reading_progress', {
            'id': 1,
            'last_page': 121,
            'selected_surah': 5,
            'selected_verse': 77,
            'updated_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await rawDb.insert('bookmarks', {
            'id': 1,
            'name': 'Legacy Stop 5:77',
            'page_number': 121,
            'surah_number': 5,
            'verse_number': 77,
            'created_at': DateTime.now().toIso8601String(),
          });

          final repo = ProgressRepository(
            db,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );

          final quranCompleter = Completer<QuranRepository>();
          final container = ProviderContainer(
            overrides: [
              quranRepositoryProvider.overrideWith(
                (ref) => quranCompleter.future,
              ),
              progressRepositoryProvider.overrideWithValue(repo),
              cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            ],
          );

          try {
            final progressFuture = container.read(
              readingProgressControllerProvider.future,
            );
            final bookmarksFuture = container.read(
              bookmarksControllerProvider.future,
            );

            bool progressCompleted = false;
            bool bookmarksCompleted = false;
            unawaited(
              progressFuture
                  .then((_) => progressCompleted = true)
                  .catchError((_) => false),
            );
            unawaited(
              bookmarksFuture
                  .then((_) => bookmarksCompleted = true)
                  .catchError((_) => false),
            );

            await Future<void>.delayed(const Duration(milliseconds: 20));
            expect(progressCompleted, isFalse);
            expect(bookmarksCompleted, isFalse);

            quranCompleter.complete(quranRepo);

            final progress = await progressFuture;
            final bookmarks = await bookmarksFuture;

            expect(progress.lastPage, 120);
            expect(progress.selectedSurah, 5);
            expect(progress.selectedVerse, 77);

            expect(bookmarks.length, 1);
            expect(bookmarks.first.pageNumber, 120);
            expect(bookmarks.first.surahNumber, 5);
            expect(bookmarks.first.verseNumber, 77);

            final dbProgress = await rawDb.query(
              'reading_progress',
              where: 'id = 1',
            );
            expect(dbProgress.first['last_page'], 120);
            expect(dbProgress.first['selected_surah'], 5);
            expect(dbProgress.first['selected_verse'], 77);

            final dbBookmarks = await rawDb.query('bookmarks', where: 'id = 1');
            expect(dbBookmarks.first['page_number'], 120);
            expect(dbBookmarks.first['surah_number'], 5);
            expect(dbBookmarks.first['verse_number'], 77);
          } finally {
            container.dispose();
            await repo.close();
            if (await tempDir.exists()) await tempDir.delete(recursive: true);
          }

          final errTempDir = await Directory.systemTemp.createTemp('q_err_');
          final errDb = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: p.join(errTempDir.path, 'err.db'),
          );
          final rawErrDb = await errDb.database;
          await rawErrDb.insert('reading_progress', {
            'id': 1,
            'last_page': 121,
            'selected_surah': 5,
            'selected_verse': 77,
            'updated_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          final errRepo = ProgressRepository(
            errDb,
            versePageValidator: quranRepo.isValidVerseOnPage,
          );

          final errorContainer = ProviderContainer(
            overrides: [
              quranRepositoryProvider.overrideWith(
                (ref) async => throw StateError('Simulated Quran load failure'),
              ),
              progressRepositoryProvider.overrideWithValue(errRepo),
              cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            ],
          );

          try {
            await expectLater(
              errorContainer.read(readingProgressControllerProvider.future),
              throwsA(isA<StateError>()),
            );
            await expectLater(
              errorContainer.read(bookmarksControllerProvider.future),
              throwsA(isA<StateError>()),
            );
          } finally {
            errorContainer.dispose();
            await errRepo.close();
            if (await errTempDir.exists()) {
              await errTempDir.delete(recursive: true);
            }
          }
        });
      },
    );

    testWidgets(
      'Mushaf image reader bounds memory residency by evicting disposed sheets from imageCache after navigation',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();

          await tester.runAsync(
            () => tester.pumpWidget(
              createTestApp(
                container: ctx.container,
                child: const QuranReaderScreen(initialPage: 1),
              ),
            ),
          );
          await tester.pumpAndSettle();

          final nextButton = find.widgetWithText(ElevatedButton, 'التالي');
          expect(nextButton, findsOneWidget);

          // Turn pages 1 -> 2 -> 3 -> 4 -> 5
          for (int p = 1; p < 5; p++) {
            await tester.tap(nextButton);
            await tester.pumpAndSettle();
          }

          expect(find.text('صفحة ٥ / ٦٠٤'), findsOneWidget);

          final readerElement = tester.element(find.byType(QuranReaderScreen));
          final imageConfig = createLocalImageConfiguration(readerElement);
          final imageCache = PaintingBinding.instance.imageCache;

          // Resolve exact cache keys using the reader's ambient configuration and bundle
          final key1 = await AssetImage(
            KfqcMushafCatalog.assetPathForPage(1),
          ).obtainKey(imageConfig);
          final key2 = await AssetImage(
            KfqcMushafCatalog.assetPathForPage(2),
          ).obtainKey(imageConfig);
          final key5 = await AssetImage(
            KfqcMushafCatalog.assetPathForPage(5),
          ).obtainKey(imageConfig);

          // Disposed earlier sheets (pages 1 and 2) must be absent/untracked from imageCache without test mutating the cache
          expect(
            imageCache.containsKey(key1),
            isFalse,
            reason:
                'Disposed page 1 sheet must have been evicted from imageCache upon navigation',
          );
          expect(
            imageCache.statusForKey(key1).tracked,
            isFalse,
            reason:
                'Page 1 must be completely untracked (neither pending, live, nor keepAlive)',
          );
          expect(
            imageCache.containsKey(key2),
            isFalse,
            reason:
                'Disposed page 2 sheet must have been evicted from imageCache upon navigation',
          );
          expect(
            imageCache.statusForKey(key2).tracked,
            isFalse,
            reason: 'Page 2 must be completely untracked',
          );

          // Currently active page sheet (page 5) must be present in imageCache
          expect(
            imageCache.containsKey(key5),
            isTrue,
            reason:
                'Current visible sheet (page 5) must be present in imageCache',
          );
          final status5 = imageCache.statusForKey(key5);
          expect(
            status5.live || status5.keepAlive,
            isTrue,
            reason: 'Current visible sheet must be live or kept alive in cache',
          );

          // Overall cache metrics must remain strictly bounded rather than leaking all turned pages
          expect(
            imageCache.currentSize,
            lessThanOrEqualTo(3),
            reason: 'Image cache keepAlive size must remain bounded',
          );
          expect(
            imageCache.liveImageCount,
            lessThanOrEqualTo(2),
            reason:
                'Live images must remain bounded to current active viewport sheet',
          );
        } finally {
          await ctx.dispose(tester);
        }
      },
    );

    testWidgets(
      'Mushaf image reader error card shows page number, retry, and Arabic guidance without exposing internal asset path',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        try {
          await tester.runAsync(() => ctx.prehydrate(1));

          final failingBundle = _FailingWebpAssetBundle();

          await tester.runAsync(
            () => tester.pumpWidget(
              DefaultAssetBundle(
                bundle: failingBundle,
                child: createTestApp(
                  container: ctx.container,
                  child: const QuranReaderScreen(initialPage: 1),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('تعذر تحميل صورة الصفحة ١'), findsOneWidget);
          expect(
            find.text('يرجى إعادة المحاولة لتحميل صورة الصفحة.'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ElevatedButton, 'إعادة المحاولة'),
            findsOneWidget,
          );
          expect(find.textContaining('assets/content/quran'), findsNothing);
          expect(find.textContaining('المسار:'), findsNothing);
        } finally {
          await ctx.dispose(tester);
        }
      },
    );
  });
}
