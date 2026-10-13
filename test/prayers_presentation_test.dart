import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/core/widgets/retryable_error_view.dart';
import 'package:zad_alruh/src/features/home/presentation/home_screen.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_event.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/prayers_controller.dart';
import 'package:zad_alruh/src/features/prayers/presentation/prayers_screen.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';

/// Helper awaiting real [PrayerState] emission matching an optional [condition].
Future<PrayerState> awaitPrayerState(
  ProviderContainer container, {
  bool Function(PrayerState)? condition,
  Duration timeout = const Duration(seconds: 5),
}) async {
  await container.read(cityRepositoryProvider.future);
  await container.read(preferencesControllerProvider.future);

  final completer = Completer<PrayerState>();
  final sub = container.listen<AsyncValue<PrayerState>>(
    prayerTimesControllerProvider,
    (previous, next) {
      if (next is AsyncData<PrayerState>) {
        if (condition == null || condition(next.value)) {
          if (!completer.isCompleted) {
            completer.complete(next.value);
          }
        }
      } else if (next is AsyncError) {
        if (!completer.isCompleted) {
          completer.completeError(next.error!, next.stackTrace);
        }
      }
    },
    fireImmediately: true,
  );

  try {
    return await completer.future.timeout(timeout);
  } finally {
    sub.close();
  }
}

/// Helper driving widget test with bounded async run loop until [condition] is met.
Future<void> ready(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(
    condition(),
    isTrue,
    reason: 'Observable actual UI/SQLite completion must arrive',
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

void main() {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;

  late Uint8List cityBytes;
  late CityRepository cityRepo;
  late Directory tempDir;
  late String dbPath;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tzdata.initializeTimeZones();
    for (final entry in <String, List<String>>{
      'Noto Naskh Arabic': ['assets/fonts/NotoNaskhArabic-Variable.ttf'],
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('zad_prayer_test_');
    dbPath = p.join(tempDir.path, 'prayer_test.db');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Prayers Presentation Provider - Real Calculations & State', () {
    test(
      'Cairo fixed clock: calculates real times, next prayer Dhuhr, and Egyptian method',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);
        addTearDown(() => progressRepo.close());

        // Cairo time: 2026-09-28 10:00:00 (07:00:00 UTC)
        final fixedUtc = DateTime.utc(2026, 9, 28, 7, 0);

        final container = ProviderContainer(
          overrides: [
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            progressRepositoryProvider.overrideWithValue(progressRepo),
            clockProvider.overrideWithValue(() => fixedUtc),
          ],
        );
        addTearDown(container.dispose);

        // Wait for preferences and prayer times to resolve
        final prayerState = await awaitPrayerState(container);

        expect(prayerState.isUnsupported, isFalse);
        expect(prayerState.city?.name, 'Cairo');
        expect(prayerState.city?.timezone, 'Africa/Cairo');
        expect(
          prayerState.calculationMethodArabicName,
          'الهيئة المصرية العامة للمساحة',
        );

        final day = prayerState.prayerDay;
        expect(day, isNotNull);
        expect(day!.isUnresolved, isFalse);
        expect(day.orderedEvents.length, 6);

        // At 10:00 AM Cairo time, next prayer is Dhuhr (~11:47 AM or ~12:47 PM depending on DST)
        final next = prayerState.nextPrayer;
        expect(next, isNotNull);
        expect(next!.type, PrayerType.dhuhr);
        expect(prayerState.timeToNextPrayer!.isNegative, isFalse);
        expect(prayerState.countdownString, isNot('--:--'));
      },
    );

    test(
      'London fixed clock & city switch: recalculates to MWL and Europe/London',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);
        addTearDown(() => progressRepo.close());

        // London time: 2026-09-28 10:00:00 BST (09:00:00 UTC)
        final fixedUtc = DateTime.utc(2026, 9, 28, 9, 0);

        final container = ProviderContainer(
          overrides: [
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            progressRepositoryProvider.overrideWithValue(progressRepo),
            clockProvider.overrideWithValue(() => fixedUtc),
          ],
        );
        addTearDown(container.dispose);

        await awaitPrayerState(container);

        // Switch city to London
        await container
            .read(preferencesControllerProvider.notifier)
            .setCity('لندن', 'Europe/London');

        final prayerState = await awaitPrayerState(
          container,
          condition: (s) => s.city?.name == 'London',
        );
        expect(prayerState.isUnsupported, isFalse);
        expect(prayerState.city?.name, 'London');
        expect(prayerState.city?.timezone, 'Europe/London');
        expect(
          prayerState.calculationMethodArabicName,
          'رابطة العالم الإسلامي',
        );

        final day = prayerState.prayerDay;
        expect(day, isNotNull);
        expect(day!.isUnresolved, isFalse);
        expect(prayerState.civilDate, DateTime.utc(2026, 9, 28));
      },
    );

    test('next prayer after Isha advances to tomorrow Fajr', () async {
      final db = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final progressRepo = ProgressRepository(db);
      addTearDown(() => progressRepo.close());

      // Nighttime in Cairo: 2026-09-28 23:00:00 (20:00:00 UTC, well after Isha)
      final fixedUtc = DateTime.utc(2026, 9, 28, 20, 0);

      final container = ProviderContainer(
        overrides: [
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          progressRepositoryProvider.overrideWithValue(progressRepo),
          clockProvider.overrideWithValue(() => fixedUtc),
        ],
      );
      addTearDown(container.dispose);

      final prayerState = await awaitPrayerState(container);

      final next = prayerState.nextPrayer;
      expect(next, isNotNull);
      expect(next!.type, PrayerType.fajr);

      // Next Fajr must be on tomorrow's local calendar day (September 29)
      final nextLocal = next.toCityTime(prayerState.city!.timezone);
      expect(nextLocal.year, 2026);
      expect(nextLocal.month, 9);
      expect(nextLocal.day, 29);
    });

    test(
      'unknown legacy city produces actionable error and preserves saved preferences',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);
        addTearDown(progressRepo.close);
        await progressRepo.updatePreferencesFields(
          clearSelectedCityId: true,
          selectedCity: 'باريس',
          selectedTimezone: 'Europe/Paris',
        );
        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            progressRepositoryProvider.overrideWithValue(progressRepo),
            clockProvider.overrideWithValue(
              () => DateTime.utc(2026, 9, 28, 12),
            ),
          ],
        );
        addTearDown(container.dispose);
        await container.read(preferencesControllerProvider.future);
        await container.read(cityRepositoryProvider.future);
        final state = container.read(prayerTimesControllerProvider);
        expect(state.hasError, isTrue);
        expect(state.error, isA<UnresolvedCityException>());
        final prefs = await progressRepo.getPreferences();
        expect(prefs.selectedCityId, isNull);
        expect(prefs.selectedCity, 'باريس');
        expect(prefs.selectedTimezone, 'Europe/Paris');
      },
    );

    test(
      'timer disposal cancels internal timer and leaves no stale updates',
      () async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);
        addTearDown(() => progressRepo.close());

        final fixedUtc = DateTime.utc(2026, 9, 28, 12, 0);

        final container = ProviderContainer(
          overrides: [
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
            progressRepositoryProvider.overrideWithValue(progressRepo),
            clockProvider.overrideWithValue(() => fixedUtc),
          ],
        );

        await awaitPrayerState(container);

        final notifier = container.read(prayerTimesControllerProvider.notifier);
        expect(notifier.activeTimer, isNotNull);

        // Dispose container
        container.dispose();
        expect(notifier.activeTimer, isNull);
      },
    );
  });

  Future<ProviderContainer> prepareWidgetContainer(
    WidgetTester tester,
    AppDatabase db,
    ProgressRepository repo,
    DateTime clock, {
    bool failCityLoading = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        progressRepositoryProvider.overrideWithValue(repo),
        cityRepositoryProvider.overrideWith((ref) async {
          if (failCityLoading) {
            throw Exception(
              'Database locked at /internal/app_db/storage.sqlite',
            );
          }
          return cityRepo;
        }),
        clockProvider.overrideWithValue(() => clock),
      ],
    );
    await tester.runAsync(() async {
      await container.read(preferencesControllerProvider.future);
      if (failCityLoading) {
        await expectLater(
          container.read(cityRepositoryProvider.future),
          throwsException,
        );
      } else {
        await container.read(cityRepositoryProvider.future);
      }
      await container.read(readingProgressControllerProvider.future);
      final bucket = container.read(activeDateBucketProvider);
      await container.read(dailyProgressControllerProvider(bucket).future);
    });
    return container;
  }

  group('Prayers & Home UI - Widget & Scalability Tests', () {
    testWidgets(
      'PrayersScreen renders 6 prayer rows, method, and hero countdown',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);

        final fixedUtc = DateTime.utc(2026, 9, 28, 7, 0);

        final container = await prepareWidgetContainer(
          tester,
          db,
          progressRepo,
          fixedUtc,
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                locale: const Locale('ar'),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: PrayersScreen(),
                ),
              ),
            ),
          );

          await ready(tester, () => find.text('الفجر').evaluate().isNotEmpty);

          // Check city and method
          expect(find.textContaining('القاهرة'), findsWidgets);
          expect(
            find.text(
              'طريقة الحساب: الهيئة المصرية العامة للمساحة (افتراضي المدينة)',
            ),
            findsOneWidget,
          );

          // Check prayer rows
          expect(find.text('الفجر'), findsOneWidget);
          expect(find.text('الشروق'), findsOneWidget);
          expect(find.text('الظهر'), findsOneWidget);
          expect(find.text('العصر'), findsOneWidget);
          expect(find.text('المغرب'), findsOneWidget);
          expect(find.text('العشاء'), findsOneWidget);

          // Check hero card
          expect(find.textContaining('الصلاة القادمة'), findsWidgets);
          expect(
            find.textContaining('التنبيهات التلقائية غير مفعّلة حالياً'),
            findsOneWidget,
          );
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() => progressRepo.close());
        }
      },
    );

    testWidgets(
      'HomeScreen next prayer card renders real times and navigates to tab 2',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);

        final fixedUtc = DateTime.utc(2026, 9, 28, 7, 0);
        int? navigatedTab;

        final container = await prepareWidgetContainer(
          tester,
          db,
          progressRepo,
          fixedUtc,
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                locale: const Locale('ar'),
                home: Directionality(
                  textDirection: TextDirection.rtl,
                  child: HomeScreen(onNavigateTab: (tab) => navigatedTab = tab),
                ),
              ),
            ),
          );

          await ready(
            tester,
            () => find.text('الصلاة القادمة').evaluate().isNotEmpty,
          );

          // Verify real next prayer card is shown instead of placeholder
          expect(find.text('الصلاة القادمة'), findsOneWidget);
          expect(find.textContaining('الظهر'), findsWidgets);
          expect(find.text('عرض الكل'), findsOneWidget);

          // Tap next prayer card to navigate to Prayers tab
          await tester.ensureVisible(find.text('عرض الكل'));
          await tester.pump();
          await tester.tap(find.text('عرض الكل'));
          await tester.pump();
          expect(navigatedTab, 2);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() => progressRepo.close());
        }
      },
    );

    testWidgets(
      '360x640 with text scale 1.8 renders without layout overflow on PrayersScreen',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);

        final fixedUtc = DateTime.utc(2026, 9, 28, 7, 0);

        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = await prepareWidgetContainer(
          tester,
          db,
          progressRepo,
          fixedUtc,
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                locale: const Locale('ar'),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: MediaQuery(
                    data: MediaQueryData(
                      size: Size(360, 640),
                      textScaler: TextScaler.linear(1.8),
                    ),
                    child: PrayersScreen(),
                  ),
                ),
              ),
            ),
          );

          await ready(tester, () => find.text('الفجر').evaluate().isNotEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() => progressRepo.close());
        }
      },
    );

    testWidgets(
      'after Isha, hero shows tomorrow Fajr while daily schedule has no row marked next on PrayersScreen',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);

        // 20:00 UTC = 23:00 Cairo local time (after Isha ~21:45 local in DST UTC+3)
        final fixedUtc = DateTime.utc(2026, 9, 28, 20, 0);

        final container = await prepareWidgetContainer(
          tester,
          db,
          progressRepo,
          fixedUtc,
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                locale: const Locale('ar'),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: PrayersScreen(),
                ),
              ),
            ),
          );

          await ready(tester, () => find.text('الفجر').evaluate().isNotEmpty);

          // Hero card must display tomorrow Fajr countdown and time
          expect(find.textContaining('الصلاة القادمة · الفجر'), findsOneWidget);
          expect(find.textContaining('متبقي على أذان الفجر'), findsOneWidget);

          // In daily schedule card, no prayer row should be marked with the next prayer badge
          expect(find.text('الصلاة القادمة'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() => progressRepo.close());
        }
      },
    );

    testWidgets(
      'after Isha, HomeScreen next prayer card displays tomorrow Fajr and summary row has no row marked next',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);

        // 20:00 UTC = 23:00 Cairo local time (after Isha ~21:45 local in DST UTC+3)
        final fixedUtc = DateTime.utc(2026, 9, 28, 20, 0);

        final container = await prepareWidgetContainer(
          tester,
          db,
          progressRepo,
          fixedUtc,
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                locale: const Locale('ar'),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: HomeScreen(),
                ),
              ),
            ),
          );

          await ready(
            tester,
            () => find.text('الصلاة القادمة').evaluate().isNotEmpty,
          );

          // Next prayer callout shows Fajr (tomorrow's prayer)
          expect(find.textContaining('الفجر · بعد'), findsOneWidget);

          // Summary row items should all have normal font weight on prayer names (none marked isNext)
          final fajrSummary = tester
              .widgetList<Text>(find.text('الفجر'))
              .firstWhere((t) => t.style?.fontSize == 10);
          expect(fajrSummary.style?.fontWeight, FontWeight.normal);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() => progressRepo.close());
        }
      },
    );

    testWidgets(
      'PrayersScreen error state renders actionable Arabic recovery message without internal details',
      (tester) async {
        final db = AppDatabase(
          databaseFactory: databaseFactory,
          databasePath: dbPath,
        );
        final progressRepo = ProgressRepository(db);

        final fixedUtc = DateTime.utc(2026, 9, 28, 7, 0);

        final container = await prepareWidgetContainer(
          tester,
          db,
          progressRepo,
          fixedUtc,
          failCityLoading: true,
        );
        try {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: AppTheme.lightTheme,
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                locale: const Locale('ar'),
                home: const Directionality(
                  textDirection: TextDirection.rtl,
                  child: PrayersScreen(),
                ),
              ),
            ),
          );

          await ready(
            tester,
            () => find.byType(RetryableErrorView).evaluate().isNotEmpty,
          );

          expect(find.byType(RetryableErrorView), findsOneWidget);
          expect(
            find.text(
              'تعذر تحميل مواقيت الصلاة. يرجى التحقق من إعدادات المدينة أو إعادة المحاولة.',
            ),
            findsOneWidget,
          );
          expect(find.text('إعادة المحاولة'), findsOneWidget);

          // Must not expose internal raw exception text or filesystem paths
          expect(find.textContaining('Database locked'), findsNothing);
          expect(find.textContaining('/internal/app_db'), findsNothing);
          expect(find.textContaining('Exception'), findsNothing);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          container.dispose();
          await tester.runAsync(() => progressRepo.close());
        }
      },
    );
  });
}
