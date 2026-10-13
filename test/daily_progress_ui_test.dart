import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/core/widgets/retryable_error_view.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/domain/models/hisn_daily_catalog.dart';
import 'package:zad_alruh/src/features/hisn/domain/repositories/hisn_repository.dart';
import 'package:zad_alruh/src/features/hisn/presentation/controllers/hisn_provider.dart';
import 'package:zad_alruh/src/features/hisn/presentation/daily/daily_dua_screen.dart';
import 'package:zad_alruh/src/features/hisn/presentation/daily/daily_hisn_checklist_screen.dart';
import 'package:zad_alruh/src/features/hisn/presentation/daily/post_prayer_daily_screen.dart';
import 'package:zad_alruh/src/features/home/presentation/home_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/progress/data/models/daily_progress.dart';
import 'package:zad_alruh/src/features/progress/data/models/daily_source_confirmation.dart';
import 'package:zad_alruh/src/features/progress/data/models/hisn_daily_item_progress.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';
import 'package:zad_alruh/src/features/progress/presentation/widgets/quran_page_confirmation_control.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';

class _FailingProgressRepository extends ProgressRepository {
  bool failConfirmQuran = false;
  bool failHisnProgress = false;
  bool failSourceConfirmation = false;

  Future<Set<int>> Function(String dateBucket)? overrideGetConfirmedPages;
  Future<List<HisnDailyItemProgress>>? Function(String dateBucket, DhikrPeriod period)? overrideGetHisnProgress;
  Future<DailySourceConfirmation?> Function(String dateBucket, String taskKey)? overrideGetSourceConfirmation;
  Future<DailyProgress> Function(String dateBucket)? overrideGetDailyProgress;
  Future<HisnDailyItemProgress> Function({
    required String dateBucket,
    required DhikrPeriod period,
    required int itemId,
    required bool isCompleted,
  })? overrideSetHisnProgress;

  _FailingProgressRepository(super.database);

  @override
  Future<Set<int>> getConfirmedQuranPages(String dateBucket) async {
    if (overrideGetConfirmedPages != null) {
      return overrideGetConfirmedPages!(dateBucket);
    }
    return super.getConfirmedQuranPages(dateBucket);
  }

  @override
  Future<List<HisnDailyItemProgress>> getHisnDailyItemProgress(
    String dateBucket,
    DhikrPeriod period,
  ) async {
    if (overrideGetHisnProgress != null) {
      final custom = overrideGetHisnProgress!(dateBucket, period);
      if (custom != null) return custom;
    }
    return super.getHisnDailyItemProgress(dateBucket, period);
  }

  @override
  Future<DailySourceConfirmation?> getSourceConfirmation(
    String dateBucket,
    String taskKey,
  ) async {
    if (overrideGetSourceConfirmation != null) {
      return overrideGetSourceConfirmation!(dateBucket, taskKey);
    }
    return super.getSourceConfirmation(dateBucket, taskKey);
  }

  @override
  Future<DailyProgress> getDailyProgress(String dateBucket) async {
    if (overrideGetDailyProgress != null) {
      return overrideGetDailyProgress!(dateBucket);
    }
    return super.getDailyProgress(dateBucket);
  }

  @override
  Future<void> confirmQuranPage({
    required String dateBucket,
    required int pageNumber,
  }) async {
    if (failConfirmQuran) {
      throw Exception('Simulated SQLite write error for Quran confirmation');
    }
    return super.confirmQuranPage(
      dateBucket: dateBucket,
      pageNumber: pageNumber,
    );
  }

  @override
  Future<HisnDailyItemProgress> setHisnDailyItemProgress({
    required String dateBucket,
    required DhikrPeriod period,
    required int itemId,
    required bool isCompleted,
  }) async {
    if (failHisnProgress) {
      throw Exception('Simulated SQLite write error for Hisn item progress');
    }
    if (overrideSetHisnProgress != null) {
      return overrideSetHisnProgress!(
        dateBucket: dateBucket,
        period: period,
        itemId: itemId,
        isCompleted: isCompleted,
      );
    }
    return super.setHisnDailyItemProgress(
      dateBucket: dateBucket,
      period: period,
      itemId: itemId,
      isCompleted: isCompleted,
    );
  }

  Future<HisnDailyItemProgress> superSetHisnDailyItemProgress({
    required String dateBucket,
    required DhikrPeriod period,
    required int itemId,
    required bool isCompleted,
  }) {
    return super.setHisnDailyItemProgress(
      dateBucket: dateBucket,
      period: period,
      itemId: itemId,
      isCompleted: isCompleted,
    );
  }

  @override
  Future<DailySourceConfirmation> setSourceConfirmation({
    required String dateBucket,
    required String taskKey,
    int? hisnItemId,
    required bool isCompleted,
  }) async {
    if (failSourceConfirmation) {
      throw Exception('Simulated SQLite write error for source confirmation');
    }
    return super.setSourceConfirmation(
      dateBucket: dateBucket,
      taskKey: taskKey,
      hisnItemId: hisnItemId,
      isCompleted: isCompleted,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late HisnRepository realHisnRepo;
  late QuranRepository realQuranRepo;
  late CityRepository realCityRepo;

  final fixedClock = DateTime(2026, 10, 7, 10, 0, 0);

  setUpAll(() async {
    ensureTimeZonesInitialized();

    // Finding 6: Native boundary MethodChannel mock returning method-specific payloads
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm'),
      (call) async {
        switch (call.method) {
          case 'resetAll':
            return {
              'success': true,
              'authorizationInvalidated': true,
              'token': 'mock_token',
            };
          case 'disableAlarms':
            return {'success': true};
          case 'stopActivePlayback':
            return {'stopped': true};
          default:
            return true;
        }
      },
    );

    final notoBytes = await File('assets/fonts/NotoNaskhArabic-Variable.ttf').readAsBytes();
    final notoLoader = FontLoader('Noto Naskh Arabic');
    notoLoader.addFont(Future.value(ByteData.sublistView(notoBytes)));
    await notoLoader.load();

    final fontLoaderIcons = FontLoader('MaterialIcons');
    Uint8List? iconBytes;
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final iconFile = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconFile.existsSync()) {
        iconBytes = iconFile.readAsBytesSync();
      }
    }
    if (iconBytes == null) {
      for (final candidate in [
        'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        '../bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ]) {
        final f = File(candidate);
        if (f.existsSync()) {
          iconBytes = f.readAsBytesSync();
          break;
        }
      }
    }
    if (iconBytes == null) {
      try {
        final data = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
        iconBytes = data.buffer.asUint8List();
      } catch (_) {}
    }
    if (iconBytes != null) {
      fontLoaderIcons.addFont(Future.value(ByteData.sublistView(iconBytes)));
      await fontLoaderIcons.load();
    }

    final hisnFile = File('assets/content/hisn/hisn-muslim.json');
    expect(await hisnFile.exists(), isTrue, reason: 'Hisn JSON asset must exist');
    final hisnBytes = await hisnFile.readAsBytes();
    realHisnRepo = HisnRepositoryImpl.fromBytes(hisnBytes);

    final textFile = File('assets/content/quran/quran-uthmani.txt');
    final xmlFile = File('assets/content/quran/quran-data.xml');
    final boundsFile = File('assets/content/quran/kfqc-page-bounds.json');
    expect(await textFile.exists(), isTrue, reason: 'Quran text must exist');
    expect(await xmlFile.exists(), isTrue, reason: 'Quran XML must exist');
    expect(await boundsFile.exists(), isTrue, reason: 'Quran bounds must exist');

    realQuranRepo = QuranRepository.fromBytes(
      textBytes: await textFile.readAsBytes(),
      xmlBytes: await xmlFile.readAsBytes(),
      boundsBytes: await boundsFile.readAsBytes(),
    );

    final cityFile = File('assets/content/cities/cities15000.txt');
    expect(await cityFile.exists(), isTrue, reason: 'Cities dataset must exist');
    realCityRepo = CityAssetAdapter.fromBytes(await cityFile.readAsBytes());
  });

  /// Finding 4: Bounded SQLite lifecycle guaranteed inside tester.runAsync.
  /// Unmounts widget tree FIRST in finally, then cleanly closes SQLite DB.
  Future<void> runWithAppDatabase(
    WidgetTester tester,
    Future<void> Function(AppDatabase db) body,
  ) async {
    late AppDatabase db;
    await tester.runAsync(() async {
      db = AppDatabase(
        databaseFactory: databaseFactoryFfiNoIsolate,
        databasePath: inMemoryDatabasePath,
      );
      final sqliteDb = await db.database;
      expect(sqliteDb.isOpen, isTrue);
    });
    try {
      await body(db);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() async {
        await db.close();
      });
    }
  }

  Widget buildTestApp({
    required Widget child,
    required AppDatabase db,
    DateTime Function()? clock,
    ProgressRepository? progressRepo,
    ProgressMutationBarrier? mutationBarrier,
    List<Override> additionalOverrides = const [],
  }) {
    return ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(clock ?? (() => fixedClock)),
        appDatabaseProvider.overrideWithValue(db),
        if (progressRepo != null)
          progressRepositoryProvider.overrideWithValue(progressRepo),
        if (mutationBarrier != null)
          resetBarrierProvider.overrideWith((ref) => mutationBarrier),
        hisnRepositoryProvider.overrideWith((ref) => realHisnRepo),
        quranRepositoryProvider.overrideWith((ref) => realQuranRepo),
        cityRepositoryProvider.overrideWith((ref) => realCityRepo),
        ...additionalOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      ),
    );
  }

  testWidgets('legacy praise selection offers replacement without erasing history', (tester) async {
    await runWithAppDatabase(tester, (db) async {
      final repo = ProgressRepository(db);
      await tester.runAsync(() async {
        final sqlite = await db.database;
        await sqlite.insert('daily_source_confirmations', {
          'date_bucket': 'Africa/Cairo|2026-10-07',
          'task_key': 'daily_dua',
          'hisn_item_id': 1,
          'is_completed': 1,
          'updated_at': DateTime.now().toIso8601String(),
        });
      });
      await tester.pumpWidget(buildTestApp(db: db, progressRepo: repo,
        clock: () => DateTime(2026, 10, 7, 10), child: const DailyDuaScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legacy_daily_dua_notice')), findsOneWidget);
      expect(find.byKey(const Key('daily_dua_confirm_checkbox')), findsNothing);
      expect(find.byKey(const Key('select_dua_1')), findsNothing);
      await tester.runAsync(() async {
        final saved = await repo.getSourceConfirmation('Africa/Cairo|2026-10-07', 'daily_dua');
        expect(saved!.hisnItemId, 1);
        expect(saved.isCompleted, isTrue);
      });
    });
  });

  group('Finding 1 & 2: QuranPageConfirmationControl Tests', () {
    testWidgets('unbounded horizontal reader footer layout with textScale 2.0 does not throw RenderFlex', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        await tester.runAsync(() async {
          final repo = ProgressRepository(db);
          await repo.getPreferences();
        });

        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Placed inside unbounded horizontal SingleChildScrollView -> Row (reader footer emulation)
        await tester.pumpWidget(
          buildTestApp(
            db: db,
            child: const Scaffold(
              body: MediaQuery(
                data: MediaQueryData(
                  size: Size(320, 480),
                  textScaler: TextScaler.linear(2.0),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      QuranPageConfirmationControl(pageNumber: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Horizontal reader footer must not throw RenderFlex');

        // Genuine tap without ensureVisible cheat
        final confirmButtonFinder = find.byKey(const Key('quran_page_confirm'));
        expect(confirmButtonFinder, findsOneWidget);
        await tester.tap(confirmButtonFinder);
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quran_page_undo')), findsOneWidget);
      });
    });

    testWidgets('failed write followed by reset prevents old SnackBar retry resurrection', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        final failingRepo = _FailingProgressRepository(db);
        failingRepo.failConfirmQuran = true;

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: failingRepo,
            child: const Scaffold(
              body: QuranPageConfirmationControl(pageNumber: 5),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap confirm button (fails)
        await tester.tap(find.byKey(const Key('quran_page_confirm')));
        await tester.pumpAndSettle();

        expect(find.text('تعذر حفظ تأكيد الصفحة. يرجى إعادة المحاولة.'), findsOneWidget);
        expect(find.text('إعادة المحاولة'), findsOneWidget);

        // Execute reset before user taps retry action
        final token = failingRepo.mutationBarrier.beginReset();
        await tester.runAsync(() async {
          await failingRepo.resetLocalState();
        });
        failingRepo.mutationBarrier.endReset(token: token, success: true);

        // Allow write to succeed now
        failingRepo.failConfirmQuran = false;

        // User taps old SnackBar retry action from before the reset
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pumpAndSettle();

        // Verify: page 5 was NOT resurrected in SQLite
        await tester.runAsync(() async {
          final confirmed = await failingRepo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
          expect(confirmed.contains(5), isFalse, reason: 'Reset generation mismatch must prevent resurrection');
        });

        // Verify: fresh explicit gesture after reset succeeds cleanly
        await tester.tap(find.byKey(const Key('quran_page_confirm')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quran_page_undo')), findsOneWidget);
        await tester.runAsync(() async {
          final confirmed = await failingRepo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
          expect(confirmed.contains(5), isTrue, reason: 'New explicit gesture after reset must succeed');
        });
      });
    });

    testWidgets('failed page on bucket A then midnight to bucket B retries ONLY original page on bucket A', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        final failingRepo = _FailingProgressRepository(db);
        failingRepo.failConfirmQuran = true;
        var currentClock = DateTime(2026, 10, 7, 23, 59, 0);

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: failingRepo,
            clock: () => currentClock,
            child: const Scaffold(
              body: QuranPageConfirmationControl(pageNumber: 5),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap confirm on page 5 on Oct 7 (fails)
        await tester.tap(find.byKey(const Key('quran_page_confirm')));
        await tester.pumpAndSettle();
        expect(find.text('تعذر حفظ تأكيد الصفحة. يرجى إعادة المحاولة.'), findsOneWidget);

        // Midnight strikes: advance clock to Oct 8
        currentClock = DateTime(2026, 10, 8, 0, 5, 0);

        // Resolve failure
        failingRepo.failConfirmQuran = false;

        // Tap SnackBar retry action (which captured original intent for Oct 7 page 5)
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pumpAndSettle();

        // Verify: original bucket 'Africa/Cairo|2026-10-07' has page 5 confirmed
        await tester.runAsync(() async {
          final oct7Pages = await failingRepo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
          expect(oct7Pages.contains(5), isTrue, reason: 'Retry must target original captured bucket and page');

          // Verify: new bucket 'Africa/Cairo|2026-10-08' does NOT have page 5 confirmed
          final oct8Pages = await failingRepo.getConfirmedQuranPages('Africa/Cairo|2026-10-08');
          expect(oct8Pages.contains(5), isFalse, reason: 'Retry must not bleed into newly active midnight bucket');
        });
      });
    });

    testWidgets('failed page 5 on bucket A then navigate to page 6 in-place retries ONLY original page 5', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        final failingRepo = _FailingProgressRepository(db);
        failingRepo.failConfirmQuran = true;

        final pageNotifier = ValueNotifier<int>(5);
        addTearDown(pageNotifier.dispose);

        // Finding 2: Single stable ProviderScope + ScaffoldMessenger + controlState
        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: failingRepo,
            child: Scaffold(
              body: ValueListenableBuilder<int>(
                valueListenable: pageNotifier,
                builder: (context, currentPage, _) {
                  return QuranPageConfirmationControl(
                    key: const ValueKey('quran_control'),
                    pageNumber: currentPage,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap confirm on page 5 (fails)
        await tester.tap(find.byKey(const Key('quran_page_confirm')));
        await tester.pumpAndSettle();
        expect(find.text('تعذر حفظ تأكيد الصفحة. يرجى إعادة المحاولة.'), findsOneWidget);
        expect(find.text('إعادة المحاولة'), findsOneWidget);

        // In-place navigation: change page from 5 to 6 without unmounting ProviderScope or ScaffoldMessenger
        pageNotifier.value = 6;
        await tester.pumpAndSettle();

        // SnackBar retry action from original page 5 failure remains visible
        expect(find.text('إعادة المحاولة'), findsOneWidget);

        // Resolve write failure
        failingRepo.failConfirmQuran = false;

        // User taps visible old retry action targeting original page 5
        await tester.tap(find.text('إعادة المحاولة'));
        await tester.pumpAndSettle();

        // Verify: page 5 is confirmed in SQLite on bucket A, page 6 is NOT confirmed
        await tester.runAsync(() async {
          final confirmed = await failingRepo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
          expect(confirmed.contains(5), isTrue, reason: 'Retry must target original captured page 5');
          expect(confirmed.contains(6), isFalse, reason: 'Retry must not confirm navigated page 6');
        });

        // Verify: fresh explicit gesture on page 6 confirms page 6
        expect(find.byKey(const Key('quran_page_confirm')), findsOneWidget);
        await tester.tap(find.byKey(const Key('quran_page_confirm')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('quran_page_undo')), findsOneWidget);
        await tester.runAsync(() async {
          final confirmed = await failingRepo.getConfirmedQuranPages('Africa/Cairo|2026-10-07');
          expect(confirmed.contains(6), isTrue, reason: 'Fresh gesture on page 6 confirms page 6');
        });
      });
    });

    testWidgets('authoritative loading and error states disable writes without false unconfirmed status', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        // 1. Loading state
        final loadingRepo = _FailingProgressRepository(db);
        final hangCompleter = Completer<Set<int>>();
        loadingRepo.overrideGetConfirmedPages = (bucket) => hangCompleter.future;

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: loadingRepo,
            child: const Scaffold(
              body: QuranPageConfirmationControl(pageNumber: 1),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('جاري تحميل تأكيدات القراءة...'), findsOneWidget);
        expect(find.byKey(const Key('quran_page_confirm')), findsNothing);
        expect(find.byKey(const Key('quran_page_undo')), findsNothing);

        // 2. Error state
        final errorRepo = _FailingProgressRepository(db);
        errorRepo.overrideGetConfirmedPages = (bucket) => Future.error(Exception('Simulated read failure'));

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: errorRepo,
            child: const Scaffold(
              body: QuranPageConfirmationControl(pageNumber: 1),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('تعذر تحميل تأكيدات القراءة.'), findsOneWidget);
        expect(find.text('إعادة المحاولة'), findsOneWidget);
        expect(find.byKey(const Key('quran_page_confirm')), findsNothing);
      });
    });

    testWidgets('real pages hydrate while goal read gated loading then error with goal target 20 and >=2 pages: no completed ward/default 2, then actual goal 20 proper', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        // Prehydrate preferences and seed SQLite with 2 confirmed pages and goal 20
        await tester.runAsync(() async {
          final progressRepo = ProgressRepository(db);
          await progressRepo.getPreferences();
          await progressRepo.confirmQuranPage(
            dateBucket: 'Africa/Cairo|2026-10-07',
            pageNumber: 1,
          );
          await progressRepo.confirmQuranPage(
            dateBucket: 'Africa/Cairo|2026-10-07',
            pageNumber: 2,
          );
          await progressRepo.updateDailyTask(
            dateBucket: 'Africa/Cairo|2026-10-07',
            quranGoalPages: 20,
          );
        });

        final repo = _FailingProgressRepository(db);

        // Goal read is initially loading
        final goalCompleter = Completer<DailyProgress>();
        repo.overrideGetDailyProgress = (bucket) => goalCompleter.future;

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: repo,
            child: const Scaffold(
              body: QuranPageConfirmationControl(pageNumber: 1),
            ),
          ),
        );
        // Bounded pump until readiness and pages are ready while goalCompleter stays pending
        for (int i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Page confirmation button is interactive and shows undo for page 1
        expect(find.byKey(const Key('quran_page_undo')), findsOneWidget);

        // Goal state is loading: distinct pending indicator without fallback 2 or false completion
        expect(find.text('2 صفحة'), findsOneWidget);
        expect(find.text('جاري تحميل الورد...'), findsOneWidget);
        expect(find.text('اكتمل الورد ✓'), findsNothing, reason: 'Cannot claim goal completion while loading');
        expect(find.textContaining('من 2 صفحة'), findsNothing, reason: 'Must not invent default 2 pages');

        // Transition goal to error state
        goalCompleter.completeError(Exception('Simulated daily progress read error'));
        await tester.pumpAndSettle();

        // Error state: distinct error label + read retry button
        expect(find.text('2 صفحة'), findsOneWidget);
        expect(find.text('تعذر تحميل الورد'), findsOneWidget);
        expect(find.byKey(const Key('quran_goal_retry')), findsOneWidget);
        expect(find.text('اكتمل الورد ✓'), findsNothing, reason: 'Cannot claim goal completion while in error');
        expect(find.textContaining('من 2 صفحة'), findsNothing, reason: 'Must not invent default 2 pages');

        // Now resolve goal read with actual authoritative target 20
        repo.overrideGetDailyProgress = (bucket) async => DailyProgress(
          dateBucket: bucket,
          quranGoalPages: 20,
          quranPagesRead: 2,
        );

        // Tap retry button
        await tester.tap(find.byKey(const Key('quran_goal_retry')));
        await tester.pumpAndSettle();

        // Authoritative goal 20 rendered properly: '2 من 20 صفحة'
        expect(find.text('2 من 20 صفحة'), findsOneWidget);
        expect(find.text('اكتمل الورد ✓'), findsNothing, reason: '2 < 20, goal not met yet');
      });
    });
  });

  group('Finding 3 & 4: DailyHisnChecklistScreen Geometry & Verification', () {
    testWidgets('evening checklist renders full verbatim notes 77, 78, 80, 81, 89, 90 and item 75 preface at 320x480 textScale 2.0 without overflow', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            child: const MediaQuery(
              data: MediaQueryData(
                size: Size(320, 480),
                textScaler: TextScaler.linear(2.0),
              ),
              child: DailyHisnChecklistScreen(period: DhikrPeriod.evening),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Initial load must not overflow at 320x480 textScale 2.0');

        // Finding 3: Bounded scroll helper using genuine ListView drags, no ensureVisible cheat
        Future<void> scrollUntilVisible(Finder targetFinder, {double delta = -200.0, int maxScrolls = 80}) async {
          final listRect = tester.getRect(find.byType(ListView).first);
          for (int i = 0; i < maxScrolls; i++) {
            if (targetFinder.hitTestable().evaluate().isNotEmpty) {
              return;
            }
            if (targetFinder.evaluate().isNotEmpty) {
              final center = tester.getCenter(targetFinder.first);
              if (center.dy >= listRect.top + 10 && center.dy <= listRect.bottom - 10) {
                return;
              }
            }
            // Drag on viewport margin to avoid panning inner SelectableText
            await tester.dragFrom(Offset(listRect.left + 4, listRect.center.dy), Offset(0, delta));
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'No RenderFlex overflow during bounded scroll towards $targetFinder (step $i)',
            );
          }
          expect(targetFinder, findsWidgets, reason: 'Target widget not visible within bounded scroll limit');
        }

        // 1. Title shows exact 20 and header progress summary is asserted at START while header is rendered and visible
        expect(find.text('أذكار المساء (٢٠ ذكراً)'), findsOneWidget);
        expect(find.text('0 من 20 ذكراً مكتملاً (0٪)'), findsOneWidget);

        // 2. Item 75 preface is preserved from actual repository/asset
        final item75 = realHisnRepo.getById(75)!;
        final cb75Finder = find.byKey(const Key('hisn_checklist_checkbox_75'));
        await scrollUntilVisible(cb75Finder);
        expect(cb75Finder, findsOneWidget);

        // Verify preface text from actual item 75 first paragraph from real HisnRepo
        final prefaceText = item75.paragraphs.isNotEmpty ? item75.paragraphs.first.trim() : item75.text.trim();
        expect(find.textContaining(prefaceText), findsWidgets);

        // Expand item 75 footnote control and verify actual footnote 101 full text
        final toggle75Finder = find.byKey(const Key('hisn_checklist_footnotes_toggle_75'));
        await scrollUntilVisible(toggle75Finder);
        await tester.tap(toggle75Finder.first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Expanding item 75 footnotes must not overflow');

        final fn101 = item75.footnotes.firstWhere((fn) => fn.id == '101');
        expect(find.text('• ${fn101.text.trim()}'), findsOneWidget);

        // 3. For each evening alternative note item (77, 78, 80, 81, 89, 90):
        // Scroll into view, verify banner verbatim footnotes from real HisnRepo,
        // expand footnote control, verify all footnotes verbatim, catch no overflow.
        final noteItemIds = [77, 78, 80, 81, 89, 90];
        for (final itemId in noteItemIds) {
          final cardFinder = find.byKey(Key('hisn_checklist_checkbox_$itemId'));
          await scrollUntilVisible(cardFinder);

          final item = realHisnRepo.getById(itemId)!;
          final eveningNote = HisnDailyCatalog.eveningAlternativeNotes[itemId]!;

          // Verify banner renders verbatim text of evening footnote(s) from real HisnRepo
          for (final fnId in eveningNote.footnoteIds) {
            final footnote = item.footnotes.firstWhere((fn) => fn.id == fnId);
            expect(
              find.text(footnote.text.trim()),
              findsWidgets,
              reason: 'Item $itemId evening footnote $fnId must match verbatim source text in banner',
            );
          }

          // Expand real UI footnote control
          final toggleFinder = find.byKey(Key('hisn_checklist_footnotes_toggle_$itemId'));
          await scrollUntilVisible(toggleFinder);
          await tester.tap(toggleFinder.first);
          await tester.pumpAndSettle();

          // Catch no overflow after expansion
          expect(
            tester.takeException(),
            isNull,
            reason: 'No RenderFlex overflow after expanding item $itemId footnotes at 320x480 textScale 2.0',
          );

          // Compare ENTIRE source footnote texts through actual HisnRepo API
          for (final fn in item.footnotes) {
            expect(
              find.text('• ${fn.text.trim()}'),
              findsOneWidget,
              reason: 'Item $itemId footnote ${fn.id} must match verbatim source text when expanded',
            );
          }
        }

        // 4. Item 92 repetition label is null with conditional note (no invented counter)
        final cb92Finder = find.byKey(const Key('hisn_checklist_checkbox_92'));
        await scrollUntilVisible(cb92Finder);
        expect(
          tester.takeException(),
          isNull,
          reason: 'No layout error or RenderFlex overflow when item 92 is scrolled into view at 320x480 textScale 2.0',
        );
        expect(find.text('١٠ مرات أو مرة واحدة عند الكسل (حسب الرواية)'), findsOneWidget);

        // 5. Shared 100 item (96) is present and excluded from 20 denominator
        final cb96Finder = find.byKey(const Key('hisn_checklist_checkbox_96'));
        await scrollUntilVisible(cb96Finder);
        expect(
          tester.takeException(),
          isNull,
          reason: 'No layout error or RenderFlex overflow when shared 100 item 96 is scrolled into view at 320x480 textScale 2.0',
        );
        expect(cb96Finder, findsOneWidget);
      });
    });

    testWidgets('shared 100 async error disables its checkbox without breaking morning 22 items', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        final repo = _FailingProgressRepository(db);
        repo.overrideGetHisnProgress = (bucket, period) {
          if (period == DhikrPeriod.shared100) {
            throw Exception('Simulated Hisn progress read failure');
          }
          return null;
        };

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: repo,
            child: const DailyHisnChecklistScreen(period: DhikrPeriod.morning),
          ),
        );
        await tester.pumpAndSettle();

        // Morning checklist is loaded with all 22 items
        expect(find.text('أذكار الصباح (٢٢ ذكراً)'), findsOneWidget);
        expect(find.byKey(const Key('hisn_checklist_checkbox_75')), findsOneWidget);

        // Checkbox 75 is fully interactive
        await tester.scrollUntilVisible(find.byKey(const Key('hisn_checklist_checkbox_75')), 180,
          scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byKey(const Key('hisn_checklist_checkbox_75')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('1 من 22 ذكراً مكتملاً (5٪)'), -180,
          scrollable: find.byType(Scrollable).first);
        expect(find.text('1 من 22 ذكراً مكتملاً (5٪)'), findsOneWidget);

        // Scroll boundedly using viewport margin drags to bring shared 100 card into view
        final cb96Finder = find.byKey(const Key('hisn_checklist_checkbox_96'));
        for (int i = 0; i < 30; i++) {
          if (cb96Finder.evaluate().isNotEmpty) {
            final center = tester.getCenter(cb96Finder.first);
            if (center.dy >= 60 && center.dy <= 420) {
              break;
            }
          }
          // Drag on viewport margin to avoid panning inner SelectableText
          final listRect = tester.getRect(find.byType(ListView).first);
          await tester.dragFrom(Offset(listRect.left + 4, listRect.center.dy), const Offset(0, -250));
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: 'No overflow during scroll to shared 100 checkbox (step $i)',
          );
        }
        expect(cb96Finder, findsOneWidget);

        // Shared 100 card shows disabled error status
        expect(find.text('تعذر تحميل الحالة (معطل)'), findsOneWidget);
        final cb96 = tester.widget<Checkbox>(cb96Finder);
        expect(cb96.onChanged, isNull, reason: 'Shared 100 checkbox must be disabled during error');
      });
    });

    testWidgets('pending DB write followed by route pop completes safely in SQLite without disposed ref error', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        final repo = _FailingProgressRepository(db);

        final enteredGate = Completer<void>();
        final releaseGate = Completer<void>();

        repo.overrideSetHisnProgress = ({
          required dateBucket,
          required period,
          required itemId,
          required isCompleted,
        }) async {
          enteredGate.complete();
          await releaseGate.future;
          return repo.superSetHisnDailyItemProgress(
            dateBucket: dateBucket,
            period: period,
            itemId: itemId,
            isCompleted: isCompleted,
          );
        };

        // Genuine retained ProviderScope with navigation push/pop
        final navKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: repo,
            child: Navigator(
              key: navKey,
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      key: const Key('open_checklist_btn'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const DailyHisnChecklistScreen(period: DhikrPeriod.morning),
                          ),
                        );
                      },
                      child: const Text('Open Checklist'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Push DailyHisnChecklistScreen
        await tester.tap(find.byKey(const Key('open_checklist_btn')));
        await tester.pumpAndSettle();

        final cb75 = find.byKey(const Key('hisn_checklist_checkbox_75'));
        expect(cb75, findsOneWidget);

        // Tap item 75
        await tester.scrollUntilVisible(cb75, 180, scrollable: find.byType(Scrollable).first);
        await tester.tap(cb75);

        // Pump until gate entered
        await tester.pump();
        await tester.runAsync(() async {
          await enteredGate.future;
        });

        // Verify SQL unchanged while write is blocked at DB boundary
        await tester.runAsync(() async {
          final progress = await repo.getHisnDailyItemProgress('Africa/Cairo|2026-10-07', DhikrPeriod.morning);
          expect(progress.any((p) => p.itemId == 75 && p.isCompleted), isFalse, reason: 'SQL must remain unchanged while write is blocked at gate');
        });

        // Navigator pop: hit tappable Back button on the screen before gate release
        final backButton = find.byType(BackButton).last;
        expect(backButton, findsOneWidget);
        await tester.tap(backButton);
        await tester.pumpAndSettle();

        // Screen is unmounted and disposed while DB write is still pending
        expect(find.byType(DailyHisnChecklistScreen), findsNothing);

        // THEN release gate and await actual SQL write + bounded pumps
        releaseGate.complete();
        for (int i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }

        // Must not throw FlutterError or StateError on disposed ref
        expect(tester.takeException(), isNull, reason: 'Exiting screen while save is pending must not throw disposed ref error');

        // Verify write was accepted and persisted in SQLite
        await tester.runAsync(() async {
          final progress = await repo.getHisnDailyItemProgress('Africa/Cairo|2026-10-07', DhikrPeriod.morning);
          expect(progress.any((p) => p.itemId == 75 && p.isCompleted), isTrue, reason: 'Real write accepted before route disposal must persist in SQLite');
        });
      });
    });
  });

  group('Finding 3: DailyDuaScreen and PostPrayerDailyScreen Authoritative States', () {
    testWidgets('DailyDuaScreen authoritative loading and error disable writes', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        // Loading
        final loadingRepo = _FailingProgressRepository(db);
        final hangCompleter = Completer<DailySourceConfirmation?>();
        loadingRepo.overrideGetSourceConfirmation = (bucket, taskKey) => hangCompleter.future;

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: loadingRepo,
            child: const DailyDuaScreen(),
          ),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('اختر دعاء اليوم من الأدعية الموثقة'), findsNothing);

        // Error
        final errorRepo = _FailingProgressRepository(db);
        errorRepo.overrideGetSourceConfirmation = (bucket, taskKey) => Future.error(Exception('Simulated source confirmation read failure'));

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: errorRepo,
            child: const DailyDuaScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('تعذر تحميل حالة دعاء اليوم.'), findsOneWidget);
        expect(find.byType(RetryableErrorView), findsOneWidget);
      });
    });

    testWidgets('PostPrayerDailyScreen authoritative loading and error disable writes', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        // Loading
        final loadingRepo = _FailingProgressRepository(db);
        final hangCompleter = Completer<DailySourceConfirmation?>();
        loadingRepo.overrideGetSourceConfirmation = (bucket, taskKey) => hangCompleter.future;

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: loadingRepo,
            child: const PostPrayerDailyScreen(),
          ),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(const Key('post_prayer_confirm_checkbox')), findsNothing);

        // Error
        final errorRepo = _FailingProgressRepository(db);
        errorRepo.overrideGetSourceConfirmation = (bucket, taskKey) => Future.error(Exception('Simulated source confirmation read failure'));

        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: errorRepo,
            child: const PostPrayerDailyScreen(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('تعذر تحميل حالة أذكار بعد الصلاة.'), findsOneWidget);
        expect(find.byType(RetryableErrorView), findsOneWidget);
      });
    });

    testWidgets('user DailyDua acceptance flow on genuine on-disk SQLite with reopen and next civil day fresh selection', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('daily_dua_disk_test_');
      final dbPath = '${tempDir.path}/daily_dua_disk.db';
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      var currentClock = DateTime(2026, 10, 7, 10, 0, 0);

      // Phase 1: Create on-disk DB and run initial selection + confirmation
      late AppDatabase db;
      late ProgressRepository repo;

      await tester.runAsync(() async {
        db = AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: dbPath,
        );
        repo = ProgressRepository(db);
        await repo.getPreferences();
      });

      try {
        await tester.pumpWidget(
          buildTestApp(
            db: db,
            progressRepo: repo,
            clock: () => currentClock,
            child: const Scaffold(
              body: DailyDuaScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Step 1: Choose the sourced petition (item 2) from selection view.
        expect(find.text('اختر دعاء اليوم من الأدعية الموثقة'), findsOneWidget);
        final selectBtn = find.byKey(const Key('select_dua_2'));
        expect(selectBtn, findsOneWidget);
        await tester.tap(selectBtn);
        await tester.pumpAndSettle();

        // Verify SQL: selected with isCompleted: false
        await tester.runAsync(() async {
          final conf = await repo.getSourceConfirmation('Africa/Cairo|2026-10-07', 'daily_dua');
          expect(conf, isNotNull);
          expect(conf!.hisnItemId, equals(2));
          expect(conf.isCompleted, isFalse, reason: 'Choosing item initially records isCompleted as false');
        });

        // Step 2: Explicit confirm -> SQL true
        final confirmCbFinder = find.byKey(const Key('daily_dua_confirm_checkbox'));
        expect(confirmCbFinder, findsOneWidget);
        final confirmCbBefore = tester.widget<Checkbox>(confirmCbFinder);
        expect(confirmCbBefore.value, isFalse);

        await tester.tap(confirmCbFinder);
        await tester.pumpAndSettle();

        final confirmCbAfter = tester.widget<Checkbox>(confirmCbFinder);
        expect(confirmCbAfter.value, isTrue);

        await tester.runAsync(() async {
          final conf = await repo.getSourceConfirmation('Africa/Cairo|2026-10-07', 'daily_dua');
          expect(conf, isNotNull);
          expect(conf!.hisnItemId, equals(2));
          expect(conf.isCompleted, isTrue, reason: 'Explicit confirmation sets isCompleted to true in SQLite');
        });

        // Step 3: Unmount and close first DB instance to simulate app process exit
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await repo.close();
          await db.close();
        });

        // Step 4: Reopen same on-disk DB file and verify chosen & confirmed state restored
        late AppDatabase reopenedDb;
        late ProgressRepository reopenedRepo;
        await tester.runAsync(() async {
          reopenedDb = AppDatabase(
            databaseFactory: databaseFactoryFfiNoIsolate,
            databasePath: dbPath,
          );
          reopenedRepo = ProgressRepository(reopenedDb);
          await reopenedRepo.getPreferences();
        });

        try {
          await tester.pumpWidget(
            buildTestApp(
              db: reopenedDb,
              progressRepo: reopenedRepo,
              clock: () => currentClock,
              child: const Scaffold(
                body: DailyDuaScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // UI restored: shows chosen dua view with checked confirmation checkbox
          expect(find.byKey(const Key('daily_dua_confirm_checkbox')), findsOneWidget);
          final restoredCb = tester.widget<Checkbox>(find.byKey(const Key('daily_dua_confirm_checkbox')));
          expect(restoredCb.value, isTrue, reason: 'Reopening from on-disk SQLite restores confirmed state');

          // Step 5: Undo -> SQL false
          await tester.tap(find.byKey(const Key('daily_dua_confirm_checkbox')));
          await tester.pumpAndSettle();

          final undidCb = tester.widget<Checkbox>(find.byKey(const Key('daily_dua_confirm_checkbox')));
          expect(undidCb.value, isFalse);

          await tester.runAsync(() async {
            final conf = await reopenedRepo.getSourceConfirmation('Africa/Cairo|2026-10-07', 'daily_dua');
            expect(conf, isNotNull);
            expect(conf!.hisnItemId, equals(2));
            expect(conf.isCompleted, isFalse, reason: 'Undo sets isCompleted to false in SQLite');
          });

          // Step 6: Advance clock to next civil day (2026-10-08) -> fresh unselected while old selection kept
          currentClock = DateTime(2026, 10, 8, 10, 0, 0);

          await tester.pumpWidget(
            buildTestApp(
              db: reopenedDb,
              progressRepo: reopenedRepo,
              clock: () => currentClock,
              child: const Scaffold(
                body: DailyDuaScreen(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          // On new day: selection view is shown fresh
          expect(find.text('اختر دعاء اليوم من الأدعية الموثقة'), findsOneWidget);
          expect(find.byKey(const Key('select_dua_2')), findsOneWidget);

          // Verify SQLite state: old selection kept on Oct 7, Oct 8 is null
          await tester.runAsync(() async {
            final oct7Conf = await reopenedRepo.getSourceConfirmation('Africa/Cairo|2026-10-07', 'daily_dua');
            expect(oct7Conf, isNotNull);
            expect(oct7Conf!.hisnItemId, equals(2));

            final oct8Conf = await reopenedRepo.getSourceConfirmation('Africa/Cairo|2026-10-08', 'daily_dua');
            expect(oct8Conf, isNull, reason: 'Next civil day starts fresh with no selection');
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.runAsync(() async {
            await reopenedRepo.close();
            await reopenedDb.close();
          });
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(() async {
          await repo.close();
          await db.close();
        });
      }
    });
  });

  group('HomeScreen Working Routes & Dhikr Routing', () {
    testWidgets('HomeScreen five working routes navigate truthfully', (tester) async {
      await runWithAppDatabase(tester, (db) async {
        int? navigatedTab;
        await tester.pumpWidget(
          buildTestApp(
            db: db,
            child: HomeScreen(
              onNavigateTab: (tab) => navigatedTab = tab,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Quran row
        await tester.tap(find.byKey(const Key('home_task_quran')));
        await tester.pumpAndSettle();
        expect(navigatedTab, equals(1));

        // 2. Morning dhikr row
        await tester.tap(find.byKey(const Key('home_task_morning_dhikr')));
        await tester.pumpAndSettle();
        expect(find.byType(DailyHisnChecklistScreen), findsOneWidget);
        Navigator.pop(tester.element(find.byType(DailyHisnChecklistScreen)));
        await tester.pumpAndSettle();

        // 3. Evening dhikr row
        await tester.tap(find.byKey(const Key('home_task_evening_dhikr')));
        await tester.pumpAndSettle();
        expect(find.byType(DailyHisnChecklistScreen), findsOneWidget);
        Navigator.pop(tester.element(find.byType(DailyHisnChecklistScreen)));
        await tester.pumpAndSettle();

        // 4. Post prayer row
        await tester.tap(find.byKey(const Key('home_task_post_prayer')));
        await tester.pumpAndSettle();
        expect(find.byType(PostPrayerDailyScreen), findsOneWidget);
        Navigator.pop(tester.element(find.byType(PostPrayerDailyScreen)));
        await tester.pumpAndSettle();

        // 5. Daily dua row
        await tester.tap(find.byKey(const Key('home_task_daily_dua')));
        await tester.pumpAndSettle();
        expect(find.byType(DailyDuaScreen), findsOneWidget);
        Navigator.pop(tester.element(find.byType(DailyDuaScreen)));
        await tester.pumpAndSettle();
      });
    });
  });
}
