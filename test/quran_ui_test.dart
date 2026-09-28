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

Future<void> tapVerseSpan(WidgetTester tester, String verseText) async {
  final richTextFinder = find.byType(RichText);
  RenderParagraph? targetParagraph;
  for (final element in richTextFinder.evaluate()) {
    final renderObj = element.renderObject as RenderParagraph?;
    if (renderObj != null &&
        renderObj.text
            .toPlainText(includeSemanticsLabels: false)
            .contains(verseText)) {
      targetParagraph = renderObj;
      break;
    }
  }
  expect(
    targetParagraph,
    isNotNull,
    reason: 'Must find RichText paragraph containing verse text "$verseText"',
  );
  final text = targetParagraph!.text.toPlainText(
    includeSemanticsLabels: false,
  );
  final startIndex = text.indexOf(verseText);
  final endIndex = startIndex + verseText.length;
  final boxes = targetParagraph.getBoxesForSelection(
    TextSelection(baseOffset: startIndex, extentOffset: endIndex),
  );
  expect(
    boxes.isNotEmpty,
    isTrue,
    reason: 'Must find glyph bounding box for verse span "$verseText"',
  );
  final globalCenter = targetParagraph.localToGlobal(boxes.first.toRect().center);
  await tester.tapAt(globalCenter);
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
      'renders 114 Surahs and 30 Juz tabs, and autosaves chapter navigation immediately',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));

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

        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
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
      },
    );

    testWidgets(
      'searches offline with unmodified verbatim text and opens mapped page',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
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
          findsOneWidget,
        );

        await tester.runAsync(
          () => _maybeCapture(captureKey, 'quran-search-view'),
        );

        // Tapping search result opens mapped page (Page 1)
        await tester.tap(
          find.textContaining('إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ'),
        );
        await tester.pumpAndSettle();

        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
        expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);

        await drainQueue(
          tester,
          ctx.container.read(readingProgressControllerProvider.notifier),
        );
        final progress = (await tester.runAsync(
          () => ctx.repo.getReadingProgress(),
        ))!;
        expect(progress.lastPage, 1);
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
        await tester.runAsync(() => ctx.prehydrate(1));

        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(container: ctx.container, child: const QuranScreen()),
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

        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
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
      },
    );

    testWidgets(
      'actual displayed Tanzil verse tap sets exact stop verse in UI, persists across reopen, and clears on page turn',
      (tester) async {
        await _ensureTestFonts(tester);
        final tempDir = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('q_exact_'),
        ))!;
        final dbPath = p.join(tempDir.path, 'exact.db');

        // Session 1: Open Reader at page 2 (Al-Baqarah 2:1..5)
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

        // 1. Tap actual displayed Tanzil verse (verse 2:2)
        final verse2Finder = find.textContaining(
          quranRepo.getVerse(2, 2).text,
          findRichText: true,
        );
        await tester.ensureVisible(verse2Finder);
        await tester.pumpAndSettle();
        expect(verse2Finder, findsOneWidget);
        await tapVerseSpan(tester, quranRepo.getVerse(2, 2).text);
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
        expect(find.text('موضع التوقف الحالي 🔖'), findsOneWidget);

        // Close Session 1
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container1.dispose();
        await tester.runAsync(() => repo1.close());

        // Session 2: Reopen with same SQLite file
        final db2 = AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: dbPath,
        );
        final repo2 = ProgressRepository(
          db2,
          versePageValidator: quranRepo.isValidVerseOnPage,
        );
        final container2 = ProviderContainer(
          overrides: [
            quranRepositoryProvider.overrideWith(
              (ref) => Future.value(quranRepo),
            ),
            progressRepositoryProvider.overrideWithValue(repo2),
          ],
        );

        await tester.runAsync(
          () => container2.read(readingProgressControllerProvider.future),
        );

        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(container: container2, child: const QuranScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Resume banner reflects restored page 2 with exact verse 2
        expect(find.textContaining('صفحة ٢'), findsWidgets);
        expect(find.textContaining('الآية ٢'), findsWidgets);

        // Open reader via resume button
        await tester.tap(find.text('متابعة ←'));
        await tester.pumpAndSettle();

        expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);
        expect(find.text('موضع التوقف الحالي 🔖'), findsOneWidget);

        // Turn to page 3 via 'التالي' - clears stop verse
        await tester.tap(find.text('التالي'));
        await tester.pumpAndSettle();

        expect(find.text('صفحة ٣ / ٦٠٤'), findsOneWidget);

        await drainQueue(
          tester,
          container2.read(readingProgressControllerProvider.notifier),
        );
        final readingP3 = (await tester.runAsync(
          () => repo2.getReadingProgress(),
        ))!;
        expect(readingP3.lastPage, 3);
        expect(readingP3.selectedSurah, isNull);
        expect(readingP3.selectedVerse, isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container2.dispose();
        await tester.runAsync(() async {
          await repo2.close();
          if (await tempDir.exists()) await tempDir.delete(recursive: true);
        });
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
          () =>
              find.text('تعذر حفظ موضع القراءة الحالي.').evaluate().isNotEmpty,
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
        await tester.runAsync(() => rawDb.execute('PRAGMA query_only = OFF;'));

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

        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
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

      // Explicitly cleanup ctx before Home test returns to cancel active provider timers
      await ctx.dispose(tester);
    });

    testWidgets(
      'Mushaf image mode displays honest absence state and toggles to verified text mode',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
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

        // Switch to Mushaf image mode
        await tester.tap(find.text('المصحف'));
        await tester.pumpAndSettle();

        expect(find.text('صفحات المصحف المصورة قيد التدقيق'), findsOneWidget);
        expect(
          find.textContaining(
            'صفحات المصحف المصورة (٦٠٤ صفحات من مصحف المدينة المنورة) قيد المراجعة',
          ),
          findsOneWidget,
        );

        // Switch back to text mode
        final returnButton = find.text('الانتقال إلى وضع النص القرآني الموثق');
        await tester.ensureVisible(returnButton);
        await tester.pumpAndSettle();
        await tester.tap(returnButton);
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            quranRepo.getVerse(1, 1).text,
            findRichText: true,
          ),
          findsWidgets,
        );
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
        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);

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

        await tester.runAsync(() => ctx.prehydrate(1));

        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(container: ctx.container, child: const QuranScreen()),
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
            createTestApp(container: ctx.container, child: const QuranScreen()),
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

        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
        expect(find.text('صفحة ١٥٥ / ٦٠٤'), findsOneWidget);

        // Position was safely preserved as 155 and not corrupted to 1
        final progress = (await tester.runAsync(
          () => gatedRepo!.getReadingProgress(),
        ))!;
        expect(progress.lastPage, 155);
      },
    );

    testWidgets(
      'compact continuous Mushaf sheet renders all verses assigned to page 1, 2, and 604 with surah headers',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
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

        // Page 1: Al-Fatiha all 7 verses rendered on the sheet
        final page1Verses = quranRepo.getVersesForPage(1);
        expect(page1Verses.length, 7);
        for (final verse in page1Verses) {
          expect(
            find.textContaining(verse.text, findRichText: true),
            findsOneWidget,
            reason: 'Verse 1:${verse.verseNumber} must be rendered on page 1',
          );
          expect(
            find.textContaining('۝${QuranUiUtils.toArabicDigits(verse.verseNumber)}'),
            findsOneWidget,
            reason: 'Marker 1:${verse.verseNumber} must be rendered on page 1',
          );
        }
        expect(find.text('۞ سُورَةُ الفاتحة ۞'), findsOneWidget);
        expect(find.text('سورة الفاتحة'), findsWidgets);

        // Turn to Page 2: Al-Baqarah 2:1..5
        await tester.tap(find.text('التالي'));
        await tester.pumpAndSettle();

        final page2Verses = quranRepo.getVersesForPage(2);
        expect(page2Verses.length, 5);
        for (final verse in page2Verses) {
          expect(
            find.textContaining(verse.text, findRichText: true),
            findsOneWidget,
            reason: 'Verse 2:${verse.verseNumber} must be rendered on page 2',
          );
          expect(
            find.textContaining('۝${QuranUiUtils.toArabicDigits(verse.verseNumber)}'),
            findsOneWidget,
            reason: 'Marker 2:${verse.verseNumber} must be rendered on page 2',
          );
        }
        expect(find.text('۞ سُورَةُ البقرة ۞'), findsOneWidget);

        // Jump to Page 604: All 15 verses across 3 surahs
        await tester.tap(find.byIcon(Icons.pin_outlined));
        await tester.pumpAndSettle();
        final jumpField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(jumpField, '604');
        await tester.tap(find.text('انتقال'));
        await tester.pumpAndSettle();

        final page604Verses = quranRepo.getVersesForPage(604);
        expect(page604Verses.length, 15);
        for (final verse in page604Verses) {
          expect(
            find.textContaining(verse.text, findRichText: true),
            findsOneWidget,
            reason:
                'Verse ${verse.surahNumber}:${verse.verseNumber} must be rendered on page 604',
          );
          expect(
            find.textContaining('۝${QuranUiUtils.toArabicDigits(verse.verseNumber)}'),
            findsWidgets,
            reason:
                'Marker ${verse.surahNumber}:${verse.verseNumber} must be rendered on page 604',
          );
        }
        expect(find.text('۞ سُورَةُ الإخلاص ۞'), findsOneWidget);
        expect(find.text('۞ سُورَةُ الفلق ۞'), findsOneWidget);
        expect(find.text('۞ سُورَةُ الناس ۞'), findsOneWidget);
        expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
      },
    );

    testWidgets(
      'preserves exact page boundaries: 1->2 advances to Baqarah start, and 603->604 advances to final page with disabled next button',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
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

        // On Page 1, 'السابق' is disabled
        final prevButtonFinder = find.widgetWithText(OutlinedButton, 'السابق');
        final prevButton = tester.widget<OutlinedButton>(prevButtonFinder);
        expect(prevButton.onPressed, isNull);

        // Tap 'التالي' moves to Page 2
        await tester.tap(find.text('التالي'));
        await tester.pumpAndSettle();
        expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);
        expect(
          find.textContaining(
            quranRepo.getVerse(2, 1).text,
            findRichText: true,
          ),
          findsOneWidget,
        );
        // Fatiha verses are no longer present
        expect(
          find.textContaining(
            quranRepo.getVerse(1, 7).text,
            findRichText: true,
          ),
          findsNothing,
        );

        // Jump to Page 603
        await tester.tap(find.byIcon(Icons.pin_outlined));
        await tester.pumpAndSettle();
        final jumpField = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(jumpField, '603');
        await tester.tap(find.text('انتقال'));
        await tester.pumpAndSettle();

        expect(find.text('صفحة ٦٠٣ / ٦٠٤'), findsOneWidget);
        // Page 603 contains Surahs 109, 110, 111
        expect(find.text('۞ سُورَةُ الكافرون ۞'), findsOneWidget);

        // Tap 'التالي' moves to Page 604
        await tester.tap(find.text('التالي'));
        await tester.pumpAndSettle();

        expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
        // On Page 604, 'التالي' is disabled
        final nextButtonFinder = find.widgetWithText(ElevatedButton, 'التالي');
        final nextButton = tester.widget<ElevatedButton>(nextButtonFinder);
        expect(nextButton.onPressed, isNull);
      },
    );

    testWidgets(
      'compact sheet verse tap opens bottom sheet, sets exact stop verse and displays stop badge',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
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

        // Tap verse 1:2: "ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ"
        final verse2 = quranRepo.getVerse(1, 2);
        final verse2Finder = find.textContaining(
          verse2.text,
          findRichText: true,
        );
        expect(verse2Finder, findsOneWidget);
        await tapVerseSpan(tester, verse2.text);
        await tester.pumpAndSettle();

        // Options bottomsheet appears
        expect(find.text('تحديد كموضع توقف عند هذه الآية'), findsOneWidget);
        await tester.tap(find.text('تحديد كموضع توقف عند هذه الآية'));
        await drainQueue(
          tester,
          ctx.container.read(readingProgressControllerProvider.notifier),
        );
        await tester.pumpAndSettle();

        // Stop badge appears on compact sheet
        expect(find.text('موضع التوقف الحالي 🔖'), findsOneWidget);

        final saved = (await tester.runAsync(
          () => ctx.repo.getReadingProgress(),
        ))!;
        expect(saved.lastPage, 1);
        expect(saved.selectedSurah, 1);
        expect(saved.selectedVerse, 2);
      },
    );

    testWidgets(
      'compact continuous sheet renders at 320x480 small screen with 2.0 text scale without overflow',
      (tester) async {
        await _ensureTestFonts(tester);
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
        await tester.runAsync(() => ctx.prehydrate(604));

        await tester.runAsync(
          () => tester.pumpWidget(
            createTestApp(
              container: ctx.container,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2.0),
                ),
                child: child!,
              ),
              child: const QuranReaderScreen(initialPage: 604),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
        expect(find.text('صفحة ٦٠٤ / ٦٠٤'), findsOneWidget);
        expect(find.text('۞ سُورَةُ الناس ۞'), findsOneWidget);

        // Turn to Page 603 at 2.0 font scale on 320x480
        await tester.tap(find.text('السابق'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('صفحة ٦٠٣ / ٦٠٤'), findsOneWidget);
      },
    );

    testWidgets(
      'flowing rich-text paragraph geometry: adjacent short verses share line in wide viewport and verse span tap works',
      (tester) async {
        await _ensureTestFonts(tester);
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

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

        // On Page 604, Surah Al-Ikhlas (112) verses 1 and 2 are short:
        // 112:1: "قُلْ هُوَ ٱللَّهُ أَحَدٌ ۝١ "
        // 112:2: "ٱللَّهُ ٱلصَّمَدُ ۝٢ "
        final v1 = quranRepo.getVerse(112, 1);
        final v2 = quranRepo.getVerse(112, 2);

        final richTextFinder = find.byType(RichText);
        RenderParagraph? ikhlasParagraph;
        for (final element in richTextFinder.evaluate()) {
          final renderObj = element.renderObject as RenderParagraph?;
          if (renderObj != null &&
              renderObj.text.toPlainText().contains(v1.text) &&
              renderObj.text.toPlainText().contains(v2.text)) {
            ikhlasParagraph = renderObj;
            break;
          }
        }
        expect(
          ikhlasParagraph,
          isNotNull,
          reason: 'Flowing paragraph for Surah 112 must exist',
        );

        final fullText = ikhlasParagraph!.text.toPlainText(
          includeSemanticsLabels: false,
        );
        final start1 = fullText.indexOf(v1.text);
        final boxes1 = ikhlasParagraph.getBoxesForSelection(
          TextSelection(
            baseOffset: start1,
            extentOffset: start1 + v1.text.length,
          ),
        );
        final start2 = fullText.indexOf(v2.text);
        final boxes2 = ikhlasParagraph.getBoxesForSelection(
          TextSelection(
            baseOffset: start2,
            extentOffset: start2 + v2.text.length,
          ),
        );

        expect(boxes1.isNotEmpty, isTrue);
        expect(boxes2.isNotEmpty, isTrue);

        // PROOF OF CONTINUOUS FLOW: In an 800px viewport, adjacent short verses 112:1 and 112:2
        // share the same line (same vertical top coordinate within font tolerance),
        // rather than being stacked on separate lines as isolated block containers.
        expect(
          (boxes1.first.top - boxes2.first.top).abs(),
          lessThanOrEqualTo(2.0),
          reason:
              'Adjacent short verses in flowing paragraph must share the same line in a wide viewport',
        );

        // Prove working tap on specific verse span (112:2)
        await tapVerseSpan(tester, v2.text);
        await tester.pumpAndSettle();

        expect(find.text('تحديد كموضع توقف عند هذه الآية'), findsOneWidget);
        await tester.tap(find.text('تحديد كموضع توقف عند هذه الآية'));
        await drainQueue(
          tester,
          ctx.container.read(readingProgressControllerProvider.notifier),
        );
        await tester.pumpAndSettle();

        final saved = (await tester.runAsync(
          () => ctx.repo.getReadingProgress(),
        ))!;
        expect(saved.lastPage, 604);
        expect(saved.selectedSurah, 112);
        expect(saved.selectedVerse, 2);
      },
    );

    testWidgets(
      'accessibility: screen reader semantics provides exactly one node per verse with content, chapter, number, and tap action',
      (tester) async {
        await _ensureTestFonts(tester);
        final semanticsHandle = tester.ensureSemantics();
        try {
          final ctx = (await tester.runAsync(
            () => _TestContext.create(quranRepo: quranRepo),
          ))!;
          addTearDown(() => ctx.dispose(tester));
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

          final surah1 = quranRepo.getSurah(1);
          final page1Verses = quranRepo.getVersesForPage(1);

          for (final verse in page1Verses) {
            // 1. Assert exactly ONE semantics node per verse matching the verse content and ayah number
            final verseFinder = find.semantics.byPredicate(
              (node) =>
                  node.label.startsWith(verse.text) &&
                  node.label.contains('الآية ${verse.verseNumber}'),
            );
            expect(
              verseFinder,
              findsOneWidget,
              reason:
                  'Must have exactly one semantics node for Verse 1:${verse.verseNumber}',
            );

            // 2. Assert content + chapter + number are present in the node
            final SemanticsNode node = verseFinder.evaluate().single;
            final SemanticsData data = node.getSemanticsData();
            expect(data.label, contains(verse.text));
            expect(data.label, contains(surah1.name));
            expect(data.label, contains('${verse.verseNumber}'));

            // 3. Assert tap action is available on the semantics node
            expect(
              data.hasAction(SemanticsAction.tap),
              isTrue,
              reason:
                  'Verse 1:${verse.verseNumber} semantics node must have a tap action',
            );
          }

          // 4. REGRESSION PROOF: Assert no duplicate or separate marker node exists in semantics
          final markerSemanticsFinder = find.semantics.byPredicate(
            (node) => node.label.contains('۝'),
          );
          expect(
            markerSemanticsFinder,
            findsNothing,
            reason:
                'Visual ayah markers must be excluded from semantics to prevent duplicate focus stops',
          );

          // 5. Verify the visual marker is still physically tappable on screen
          final markerWidgetFinder = find.textContaining(' ۝١ ');
          expect(markerWidgetFinder, findsOneWidget);
          await tester.tap(markerWidgetFinder);
          await tester.pumpAndSettle();
          expect(find.text('تحديد كموضع توقف عند هذه الآية'), findsOneWidget);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'horizontal drag/swipe on reader advances page number and official Medina verse boundaries',
      (tester) async {
        await _ensureTestFonts(tester);
        final ctx = (await tester.runAsync(
          () => _TestContext.create(quranRepo: quranRepo),
        ))!;
        addTearDown(() => ctx.dispose(tester));
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

        // Initially on Page 1 (Al-Fatiha 1:1..7)
        expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);
        expect(find.text('۞ سُورَةُ الفاتحة ۞'), findsOneWidget);
        final p1v1 = quranRepo.getVerse(1, 1);
        expect(find.textContaining(p1v1.text), findsOneWidget);

        // Perform horizontal swipe/drag across PageView.
        // In an RTL PageView, dragging from left-to-right (positive X delta) advances forward
        // to the next Medina page (Page 2), and right-to-left (negative X delta) navigates backward.
        final pageViewFinder = find.byType(PageView);
        expect(pageViewFinder, findsOneWidget);

        // Fling forward to advance to Page 2
        await tester.fling(pageViewFinder, const Offset(400, 0), 1000);
        await tester.pumpAndSettle();

        // Assert reader has advanced to official Page 2 (Al-Baqarah 2:1..5)
        expect(find.text('صفحة ٢ / ٦٠٤'), findsOneWidget);
        expect(find.text('۞ سُورَةُ البقرة ۞'), findsOneWidget);
        final p2v1 = quranRepo.getVerse(2, 1);
        expect(find.textContaining(p2v1.text), findsOneWidget);

        // And verify verses from Page 1 (e.g. Al-Fatiha 1:7) are no longer on current page
        final p1v7 = quranRepo.getVerse(1, 7);
        expect(find.textContaining(p1v7.text), findsNothing);

        // Swipe backward to return to Page 1
        await tester.fling(pageViewFinder, const Offset(-400, 0), 1000);
        await tester.pumpAndSettle();

        expect(find.text('صفحة ١ / ٦٠٤'), findsOneWidget);
        expect(find.text('۞ سُورَةُ الفاتحة ۞'), findsOneWidget);
        expect(find.textContaining(p1v1.text), findsOneWidget);
        expect(find.textContaining(p2v1.text), findsNothing);
      },
    );
  });
}
