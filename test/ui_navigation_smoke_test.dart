import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zad_alruh/main.dart';
import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/widgets/retryable_error_view.dart';
import 'package:zad_alruh/src/features/more/presentation/duas_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/favorites_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/hadith_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/more_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/settings_screen.dart';
import 'package:zad_alruh/src/features/more/presentation/sources_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';

void main() {
  sqfliteFfiInit();
  ensureTimeZonesInitialized();
  final databaseFactory = databaseFactoryFfiNoIsolate;

  late Uint8List cityBytes;
  late CityRepository cityRepo;

  setUpAll(() async {
    for (final entry in <String, List<String>>{
      'IBM Plex Sans Arabic': [
        'assets/fonts/IBM-Plex-Sans-Arabic-Regular.ttf',
        'assets/fonts/IBM-Plex-Sans-Arabic-Medium.ttf',
        'assets/fonts/IBM-Plex-Sans-Arabic-SemiBold.ttf',
        'assets/fonts/IBM-Plex-Sans-Arabic-Bold.ttf',
      ],
      'Amiri Quran': ['assets/fonts/Amiri-Quran-Regular.ttf'],
      'MaterialIcons': [
        '${Platform.environment['FLUTTER_ROOT'] ?? 'D:/tools/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final font in entry.value) {
        final bytes = await File(font).readAsBytes();
        expect(bytes, isNotEmpty);
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    }

    final file = File('assets/content/cities/cities15000.txt');
    expect(file.existsSync(), isTrue, reason: 'cities15000.txt must exist');
    cityBytes = file.readAsBytesSync();
    cityRepo = CityAssetAdapter.fromBytes(cityBytes);
  });

  Widget createTestApp(ProgressRepository repository) {
    return ProviderScope(
      overrides: [
        progressRepositoryProvider.overrideWithValue(repository),
        cityRepositoryProvider.overrideWith((ref) async => cityRepo),
      ],
      child: const ZadAlruhApp(),
    );
  }

  Future<void> pumpBounded(WidgetTester tester, [int frames = 8]) async {
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpTestApp(WidgetTester tester, ProgressRepository repo) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(createTestApp(repo));
      try {
        final element = tester.element(find.byType(ZadAlruhApp));
        final container = ProviderScope.containerOf(element);
        await container.read(preferencesControllerProvider.future);
        await container.read(cityRepositoryProvider.future);
      } catch (_) {
        // Corrupted database fixtures or initialization failures reject the future
      }
    });
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (find.byType(ZadAlruhApp).evaluate().isNotEmpty &&
        find.text('الرئيسية').evaluate().isEmpty &&
        find.byType(RetryableErrorView).evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pump();
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await pumpBounded(tester);
  }

  Future<void> popRoute(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton).last);
    for (int i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('UI Navigation & Responsive Smoke Tests', () {
    testWidgets(
      'boots in Arabic RTL, navigates across 5 main tabs, and opens sub-routes',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: inMemoryDatabasePath,
        );
        final repo = ProgressRepository(db);

        await pumpTestApp(tester, repo);

        // Verify Directionality is RTL
        final directionality = tester.widget<Directionality>(
          find.byType(Directionality).first,
        );
        expect(directionality.textDirection, TextDirection.rtl);

        // Verify Initial Screen is Home (الرئيسية)
        expect(find.text('الرئيسية'), findsWidgets);
        expect(find.text('وِردك اليومي'), findsOneWidget);

        // Tab 1: Quran (القرآن)
        await tapAndSettle(tester, find.byIcon(Icons.menu_book_outlined));
        expect(find.text('القرآن الكريم'), findsOneWidget);
        expect(find.text('السور (١١٤)'), findsOneWidget);

        // Tab 2: Prayers (الصلاة)
        await tapAndSettle(
          tester,
          find.byIcon(Icons.access_time_filled_outlined),
        );
        expect(find.text('مواقيت الصلاة'), findsOneWidget);
        expect(find.textContaining('الصلاة القادمة'), findsWidgets);
        expect(find.text('الفجر'), findsOneWidget);

        // Tab 3: Dhikr (الأذكار)
        await tapAndSettle(tester, find.byIcon(Icons.auto_awesome_outlined));
        expect(find.text('التسبيح والذكر'), findsOneWidget);
        expect(find.textContaining('ابدأ جلسة ذكر جديدة'), findsOneWidget);

        // Tab 4: More (المزيد)
        await tapAndSettle(tester, find.byIcon(Icons.more_horiz_outlined));
        expect(find.text('المزيد'), findsWidgets);
        expect(find.text('الإعدادات'), findsOneWidget);
        expect(find.text('الأدعية'), findsOneWidget);
        expect(find.text('الأحاديث النبوية'), findsOneWidget);
        expect(find.text('المفضلة والعلامات'), findsOneWidget);
        expect(find.text('المصادر والخصوصية'), findsOneWidget);

        // Navigate to Settings
        await tapAndSettle(tester, find.text('الإعدادات'));
        expect(find.text('إعدادات التطبيق'), findsOneWidget);
        final settingsScroll = find
            .descendant(
              of: find.byType(SettingsScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byType(SwitchListTile),
          200,
          scrollable: settingsScroll,
        );
        final switchListTile = tester.widget<SwitchListTile>(
          find.byType(SwitchListTile),
        );
        expect(switchListTile.onChanged, isNotNull);
        await tester.scrollUntilVisible(
          find.text('إعادة ضبط كافة البيانات المحلية'),
          200,
          scrollable: settingsScroll,
        );
        expect(find.text('إعادة ضبط كافة البيانات المحلية'), findsOneWidget);

        // Pop Settings back to More tab
        await popRoute(tester);

        // Navigate to Duas
        final moreScrollable = find.descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(
          find.text('الأدعية'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('الأدعية'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('الأدعية'));
        expect(find.byType(DuasScreen), findsOneWidget);
        expect(find.text('الأدعية والأذكار (حصن المسلم)'), findsOneWidget);

        // Pop Duas
        await popRoute(tester);

        // Navigate to Hadith
        await tester.scrollUntilVisible(
          find.text('الأحاديث النبوية'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('الأحاديث النبوية'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('الأحاديث النبوية'));
        expect(find.byType(HadithScreen), findsOneWidget);
        expect(find.text('الأحاديث النبوية الشريفة'), findsOneWidget);

        // Pop Hadith
        await popRoute(tester);

        // Navigate to Sources & Privacy
        await tester.scrollUntilVisible(
          find.text('المصادر والخصوصية'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('المصادر والخصوصية'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('المصادر والخصوصية'));
        expect(find.text('المصادر والخصوصية والتراخيص'), findsOneWidget);
        expect(find.textContaining('بدون إعلانات وبدون تتبع'), findsOneWidget);

        // Pop Sources & Privacy
        await popRoute(tester);

        // Unmount ProviderScope to cancel timers before closing database
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.close();
      },
    );

    testWidgets(
      'AppShell bottomNavigationBar vertically shrink wraps and body is visible and hit-testable in small viewport (Finding 2)',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: inMemoryDatabasePath,
        );
        final repo = ProgressRepository(db);

        // Set small real viewport (360 x 640)
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpTestApp(tester, repo);

        // Body content is visible and hit-testable
        final continueReadingBtn = find.text('كمّل وِردك  ←');
        expect(continueReadingBtn, findsOneWidget);
        await tapAndSettle(tester, continueReadingBtn);

        // Tapping hero button opens reader at current page
        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);

        // Return to Quran index via AppBar back button
        await tapAndSettle(tester, find.byTooltip('العودة إلى الفهرس'));
        expect(find.text('القرآن الكريم'), findsOneWidget);

        // Nav bar items are visible and hit-testable
        final homeNav = find.text('الرئيسية');
        expect(homeNav, findsOneWidget);
        await tapAndSettle(tester, homeNav);

        // Returned to Home tab
        expect(find.text('وِردك اليومي'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.close();
      },
    );

    testWidgets(
      'Home exposes five working daily task routes without auto-confirming a reading',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: inMemoryDatabasePath,
        );
        final repo = ProgressRepository(db);

        await pumpTestApp(tester, repo);

        for (final task in [
          'home_task_quran',
          'home_task_morning_dhikr',
          'home_task_evening_dhikr',
          'home_task_post_prayer',
          'home_task_daily_dua',
        ]) {
          final taskFinder = find.byKey(Key(task));
          await tester.ensureVisible(taskFinder);
          expect(tester.widget<InkWell>(taskFinder).onTap, isNotNull);
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ZadAlruhApp)),
        );
        final bucket = container.read(activeDateBucketProvider);
        await tester.ensureVisible(find.byKey(const Key('home_task_quran')));
        await tapAndSettle(tester, find.byKey(const Key('home_task_quran')));
        expect(find.text('مصحف المدينة المنورة'), findsOneWidget);
        final daily = (await tester.runAsync(
          () => repo.getDailyProgress(bucket),
        ))!;
        expect(daily.quranPagesRead, 0);
        expect(
          daily.completedTasksCount,
          0,
          reason: 'Opening a task is not a reading confirmation',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.close();
      },
    );

    testWidgets(
      'respects system accessibility scaling combined with user preference and renders at 360x640 with system 1.8 scale without overflow (Finding 7)',
      (tester) async {
        // Make hit test warnings fatal to catch any missed tap
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: inMemoryDatabasePath,
        );
        final repo = ProgressRepository(db);

        // Set small real viewport (360 x 640) and platform text scale to 1.8
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpTestApp(tester, repo);

        // Assert effective descendant scale combines system scale (>= 1.8)
        final homeText = tester.element(find.text('وِردك اليومي'));
        final descendantScaler = MediaQuery.textScalerOf(homeText);
        expect(descendantScaler.scale(1.0), greaterThanOrEqualTo(1.8));

        // No overflow exceptions on Home
        expect(tester.takeException(), isNull);

        // Quran Tab at 1.8+ scale
        await tapAndSettle(tester, find.byIcon(Icons.menu_book_outlined));
        expect(tester.takeException(), isNull);

        // Prayers Tab at 1.8+ scale
        await tapAndSettle(
          tester,
          find.byIcon(Icons.access_time_filled_outlined),
        );
        expect(tester.takeException(), isNull);

        // Dhikr Counter at 1.8+ scale
        await tapAndSettle(tester, find.byIcon(Icons.auto_awesome_outlined));
        expect(tester.takeException(), isNull);

        // More Tab at 1.8+ scale
        await tapAndSettle(tester, find.byIcon(Icons.more_horiz_outlined));
        expect(tester.takeException(), isNull);
        expect(find.byType(MoreScreen), findsOneWidget);

        final moreScrollable = find.descendant(
          of: find.byType(MoreScreen),
          matching: find.byType(Scrollable),
        );

        // Settings screen at 1.8+ scale
        await tester.scrollUntilVisible(
          find.text('الإعدادات'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('الإعدادات'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('الإعدادات'));
        expect(tester.takeException(), isNull);
        expect(find.byType(SettingsScreen), findsOneWidget);
        await popRoute(tester);
        expect(find.byType(MoreScreen), findsOneWidget);

        // Sub-route: Favorites & Bookmarks
        await tester.scrollUntilVisible(
          find.text('المفضلة والعلامات'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('المفضلة والعلامات'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('المفضلة والعلامات'));
        expect(tester.takeException(), isNull);
        expect(find.byType(FavoritesScreen), findsOneWidget);
        await popRoute(tester);
        expect(find.byType(MoreScreen), findsOneWidget);

        // Sub-route: Duas
        await tester.scrollUntilVisible(
          find.text('الأدعية'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('الأدعية'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('الأدعية'));
        expect(tester.takeException(), isNull);
        expect(find.byType(DuasScreen), findsOneWidget);
        await popRoute(tester);
        expect(find.byType(MoreScreen), findsOneWidget);

        // Sub-route: Hadith
        await tester.scrollUntilVisible(
          find.text('الأحاديث النبوية'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('الأحاديث النبوية'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('الأحاديث النبوية'));
        expect(tester.takeException(), isNull);
        expect(find.byType(HadithScreen), findsOneWidget);
        await popRoute(tester);
        expect(find.byType(MoreScreen), findsOneWidget);

        // Sub-route: Sources & Privacy
        await tester.scrollUntilVisible(
          find.text('المصادر والخصوصية'),
          100,
          scrollable: moreScrollable,
        );
        await tester.ensureVisible(find.text('المصادر والخصوصية'));
        await pumpBounded(tester);
        await tapAndSettle(tester, find.text('المصادر والخصوصية'));
        expect(tester.takeException(), isNull);
        expect(find.byType(SourcesScreen), findsOneWidget);
        await popRoute(tester);
        expect(find.byType(MoreScreen), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.close();
      },
    );

    testWidgets(
      'initial genuine corrupt SQLite failure leaves app rendered with Arabic retry control and recovers when database fixture is restored',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'corrupt_db_ui_test_',
        );
        final dbFile = File('${tempDir.path}/corrupt_test.db');
        dbFile.writeAsStringSync('corrupted non-sqlite database payload');

        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbFile.path,
        );
        final repo = ProgressRepository(db);

        // Register strict LIFO teardowns (execution: unmount -> repo.close() -> tempDir.deleteSync)
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        addTearDown(() => repo.close());
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });

        // 1. Boot app with corrupt database fixture
        await pumpTestApp(tester, repo);

        // 2. App must NOT throw unhandled frame/async exceptions and remains rendered with Arabic retry control
        expect(tester.takeException(), isNull);
        expect(find.byType(RetryableErrorView), findsOneWidget);
        expect(
          find.textContaining(
            'تعذر قراءة قاعدة البيانات المحلية أو إعدادات التطبيق',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('26'),
          findsWidgets,
        ); // Genuine SQLite error code 26 (SQLITE_NOTADB)
        expect(find.text('إعادة المحاولة'), findsOneWidget);

        // Verify that user database was NOT auto-wiped or deleted
        expect(dbFile.existsSync(), isTrue);
        expect(
          dbFile.readAsStringSync(),
          'corrupted non-sqlite database payload',
        );

        // 3. Replace corrupt file with clean state (simulate user restoration)
        if (dbFile.existsSync()) {
          dbFile.deleteSync();
        }

        // 4. Tap the actual Arabic Retry button inside runAsync and pump rebuild
        await tester.runAsync(() async {
          await tester.tap(find.text('إعادة المحاولة'));
          await tester.pump();
          try {
            final element = tester.element(find.byType(ZadAlruhApp));
            final container = ProviderScope.containerOf(element);
            await container.read(preferencesControllerProvider.future);
            await container.read(cityRepositoryProvider.future);
          } catch (_) {}
        });
        await pumpBounded(tester);

        // 5. After retry with restored fixture, app recovers cleanly and renders main shell without errors
        expect(tester.takeException(), isNull);
        expect(find.byType(RetryableErrorView), findsNothing);
        expect(find.text('الرئيسية'), findsWidgets);
        expect(find.text('وِردك اليومي'), findsOneWidget);

        // 6. Dispose mounted scope before closing DB to cancel timers
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.close();
      },
    );

    testWidgets(
      'UI mutation failure under read-only SQLite surfaces Arabic retryable SnackBar, preserves dialog input, and recovers on retry',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: inMemoryDatabasePath,
        );
        final repo = ProgressRepository(db);
        addTearDown(() => repo.close());

        await pumpTestApp(tester, repo);

        // 1. Make DB read-only
        final rawDb = await db.database;

        // Confirm an actual reader page; the database rejects the real write.
        await tapAndSettle(tester, find.text('كمّل وِردك  ←'));
        final container = ProviderScope.containerOf(
          tester.element(find.byType(ZadAlruhApp)),
        );
        final bucket = container.read(activeDateBucketProvider);
        await tester.runAsync(() async {
          await container.read(
            dailyQuranPagesControllerProvider(bucket).future,
          );
          await container
              .read(readingProgressControllerProvider.notifier)
              .drainPendingWrites();
          await rawDb.execute('PRAGMA query_only = ON;');
        });
        await pumpBounded(tester);
        final confirmPage = find.byKey(const Key('quran_page_confirm'));
        await tester.ensureVisible(confirmPage);
        final hitDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (confirmPage.hitTestable().evaluate().isEmpty &&
            DateTime.now().isBefore(hitDeadline)) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(
          confirmPage.hitTestable(),
          findsOneWidget,
          reason:
              'Actual page confirmation must be reachable: ${tester.getRect(confirmPage)}',
        );
        await tapAndSettle(tester, confirmPage);
        expect(tester.takeException(), isNull);
        expect(find.textContaining('تعذر حفظ تأكيد الصفحة'), findsOneWidget);
        final snackBarRetryAction = find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('إعادة المحاولة'),
        );
        expect(snackBarRetryAction, findsOneWidget);
        expect(await rawDb.query('daily_quran_pages'), isEmpty);
        await rawDb.execute('PRAGMA query_only = OFF;');
        await tapAndSettle(tester, snackBarRetryAction);
        expect(tester.takeException(), isNull);
        final confirmedRows = await rawDb.query('daily_quran_pages');
        expect(confirmedRows, hasLength(1));
        expect(confirmedRows.single['page_number'], 1);
        await tapAndSettle(tester, find.byTooltip('العودة إلى الفهرس'));

        // 2. Test Dialog input preservation under read-only SQLite
        await rawDb.execute('PRAGMA query_only = ON;');

        // Reader back action already returned to the active Quran index.
        expect(find.text('القرآن الكريم'), findsOneWidget);

        // Open Add Bookmark dialog
        await tapAndSettle(tester, find.byIcon(Icons.bookmark_add_outlined));
        expect(find.text('إضافة علامة مرجعية'), findsOneWidget);

        // Enter custom bookmark name
        final bookmarkDialogFinder = find.byType(AlertDialog);
        final bookmarkTextFieldFinder = find.descendant(
          of: bookmarkDialogFinder,
          matching: find.byType(TextField),
        );
        await tester.enterText(
          bookmarkTextFieldFinder,
          'علامة الصباح المستمرة',
        );
        await pumpBounded(tester);

        // Tap save button while DB is read-only
        final saveBookmarkButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('حفظ العلامة'),
        );
        await tester.tap(saveBookmarkButton);
        await pumpBounded(tester);

        // Verify no unhandled exception, dialog remains open, and user input is preserved
        expect(tester.takeException(), isNull);
        expect(find.text('إضافة علامة مرجعية'), findsOneWidget);
        expect(find.text('علامة الصباح المستمرة'), findsOneWidget);
        expect(find.textContaining('تعذر حفظ العلامة'), findsOneWidget);

        // Restore DB to read-write mode
        await rawDb.execute('PRAGMA query_only = OFF;');

        // Tap save button again with the retained input
        await tapAndSettle(tester, saveBookmarkButton);

        // Dialog closed without errors
        expect(tester.takeException(), isNull);
        expect(find.text('إضافة علامة مرجعية'), findsNothing);

        // Wait for bookmark persistence to settle in real SQLite
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (DateTime.now().isBefore(deadline)) {
            final bookmarks = await repo.getBookmarks();
            if (bookmarks.any((b) => b.name == 'علامة الصباح المستمرة')) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });

        // Switch to bookmarks tab in QuranScreen to view saved bookmark
        await tapAndSettle(tester, find.text('العلامات المحفوظة'));
        expect(find.text('علامة الصباح المستمرة'), findsOneWidget);

        final bookmarks = (await tester.runAsync(() => repo.getBookmarks()))!;
        expect(bookmarks.any((b) => b.name == 'علامة الصباح المستمرة'), isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await repo.close();
      },
    );
  });
}
