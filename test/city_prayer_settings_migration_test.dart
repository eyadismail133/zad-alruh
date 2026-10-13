import 'dart:async';
import 'dart:io';

import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:zad_alruh/src/core/database/app_database.dart';
import 'package:zad_alruh/src/core/theme/app_theme.dart';
import 'package:zad_alruh/src/features/more/presentation/widgets/prayer_calculation_settings_section.dart';
import 'package:zad_alruh/src/features/prayer/data/sources/city_asset_adapter.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_settings.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/selected_city.dart';
import 'package:zad_alruh/src/features/prayer/domain/repositories/city_repository.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_calculator.dart';
import 'package:zad_alruh/src/features/prayers/presentation/controllers/prayers_controller.dart';
import 'package:zad_alruh/src/features/prayers/presentation/widgets/city_search_picker_dialog.dart';
import 'package:zad_alruh/src/features/progress/data/models/user_preferences.dart';
import 'package:zad_alruh/src/features/progress/data/progress_repository.dart';
import 'package:zad_alruh/src/features/progress/presentation/controllers/progress_controller.dart';

/// Test double gating ONLY response delivery of the first completed SQLite write.
class GatedProgressRepository extends ProgressRepository {
  Completer<void>? responseGateEntered;
  Completer<void>? responseGateCompleter;

  GatedProgressRepository(super.database);

  @override
  Future<UserPreferences> updatePreferencesFields({
    String? darkMode,
    double? textScale,
    Object? selectedCityId = kPreferenceSentinel,
    bool clearSelectedCityId = false,
    String? selectedCity,
    String? selectedTimezone,
    Object? calculationMethodOverride = kPreferenceSentinel,
    bool clearCalculationMethodOverride = false,
    Madhab? asrMadhab,
    HighLatitudeRule? highLatitudeRule,
    PolarDayResolution? polarResolution,
    UmmAlQuraRamadanPolicy? ramadanPolicy,
    int? hijriDayAdjustment,
    int? fajrOffset,
    int? sunriseOffset,
    int? dhuhrOffset,
    int? asrOffset,
    int? maghribOffset,
    int? ishaOffset,
    int? quranDefaultGoal,
    bool? notificationsEnabled,
    String? generalAdhanVoice,
    String? fajrAdhanVoice,
    Object? activeDhikrSessionId = kPreferenceSentinel,
    bool clearActiveDhikrSession = false,
  }) async {
    // Call super FIRST - genuine SQLite write completes under real mutation barrier!
    final result = await super.updatePreferencesFields(
      darkMode: darkMode,
      textScale: textScale,
      selectedCityId: selectedCityId,
      clearSelectedCityId: clearSelectedCityId,
      selectedCity: selectedCity,
      selectedTimezone: selectedTimezone,
      calculationMethodOverride: calculationMethodOverride,
      clearCalculationMethodOverride: clearCalculationMethodOverride,
      asrMadhab: asrMadhab,
      highLatitudeRule: highLatitudeRule,
      polarResolution: polarResolution,
      ramadanPolicy: ramadanPolicy,
      hijriDayAdjustment: hijriDayAdjustment,
      fajrOffset: fajrOffset,
      sunriseOffset: sunriseOffset,
      dhuhrOffset: dhuhrOffset,
      asrOffset: asrOffset,
      maghribOffset: maghribOffset,
      ishaOffset: ishaOffset,
      quranDefaultGoal: quranDefaultGoal,
      notificationsEnabled: notificationsEnabled,
      generalAdhanVoice: generalAdhanVoice,
      fajrAdhanVoice: fajrAdhanVoice,
      activeDhikrSessionId: activeDhikrSessionId,
      clearActiveDhikrSession: clearActiveDhikrSession,
    );

    // Gate ONLY response delivery of the completed write
    if (responseGateEntered != null && !responseGateEntered!.isCompleted) {
      responseGateEntered!.complete();
    }
    if (responseGateCompleter != null) {
      await responseGateCompleter!.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  PrayerCalculator.ensureTimeZonesInitialized();
  final databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late CityRepository cityRepo;

  setUpAll(() async {
    // Mock Android OS boundary MethodChannel with method-specific replies
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm'),
      (MethodCall call) async {
        switch (call.method) {
          case 'resetAll':
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': 1,
              'messageAr': 'تمت إعادة ضبط مواعيد الأذان بنجاح',
            };
          case 'disableAlarms':
            return <String, dynamic>{
              'success': true,
              'authorizationInvalidated': true,
              'token': 1,
              'messageAr': 'تم تعطيل مواعيد الأذان وإلغاء التنبيهات بنجاح',
            };
          case 'stopActivePlayback':
            return <String, dynamic>{'stopped': true};
          case 'getState':
            return <String, dynamic>{
              'enabled': false,
              'generationToken': 1,
              'canScheduleExactAlarms': true,
              'notificationsAllowed': true,
              'isPlaybackStatusChannelBlocked': false,
              'isDndOrSilentActive': false,
              'isServiceRunning': false,
              'isManualPlaybackLeaseActive': false,
              'futureEventsCount': 0,
              'pendingCleanupCount': 0,
              'cityId': 360630,
              'cityNameAr': 'القاهرة',
              'timezone': 'Africa/Cairo',
              'coverageHorizonUtc': 1800000000,
              'consumedLedgerCount': 0,
            };
          default:
            return null;
        }
      },
    );

    // Load offline verified cities dataset
    final cityFile = File('assets/content/cities/cities15000.txt');
    expect(await cityFile.exists(), isTrue, reason: 'Cities dataset file must exist');
    final bytes = await cityFile.readAsBytes();
    cityRepo = CityAssetAdapter.fromBytes(bytes);

    final naskhBytes = await File('assets/fonts/NotoNaskhArabic-Variable.ttf').readAsBytes();
    final naskhLoader = FontLoader('Noto Naskh Arabic')..addFont(Future.value(ByteData.sublistView(naskhBytes)));
    await naskhLoader.load();

  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm'),
      null,
    );
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('city_prayer_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  String createDbPath(String name) => p.join(tempDir.path, name);

  Widget buildTestApp({
    required ProviderContainer container,
    required Widget child,
    double textScale = 1.0,
  }) {
    return UncontrolledProviderScope(
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
        builder: (context, currentChild) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: currentChild!,
        ),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: child,
        ),
      ),
    );
  }

  // ===========================================================================
  // 1. SQLite Schema Creation, v1/v2/v3 -> v4 Migration & 9-Table Parity
  // ===========================================================================
  group('Database Schema Creation & Migration Parity (All 9 Tables)', () {
    const expectedTables = [
      'reading_progress',
      'bookmarks',
      'favorites',
      'dhikr_sessions',
      'daily_progress',
      'user_preferences',
      'hisn_daily_item_progress',
      'daily_quran_pages',
      'daily_source_confirmations',
    ];

    test('fresh v4 database creates all 9 tables with schemaVersion 5 and Cairo defaults', () async {
      final dbPath = createDbPath('fresh_v4.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final rawDb = await appDb.database;

      final version = await rawDb.getVersion();
      expect(version, AppDatabase.schemaVersion);

      final tableRows = await rawDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
      );
      final actualTables = tableRows.map((r) => r['name'] as String).toSet();
      for (final table in expectedTables) {
        expect(actualTables.contains(table), isTrue, reason: 'Table $table must exist in fresh v4');
      }

      final prefsRows = await rawDb.query('user_preferences', where: 'id = 1');
      expect(prefsRows.length, 1);
      final row = prefsRows.first;
      expect(row['selected_city_id'], 360630);
      expect(row['selected_city'], 'القاهرة');
      expect(row['selected_timezone'], 'Africa/Cairo');
      expect(row['calculation_method'], isNull);
      expect(row['asr_madhab'], 'shafi');
      expect(row['high_latitude_rule'], 'middle_of_the_night');
      expect(row['polar_resolution'], 'unresolved');
      expect(row['ramadan_policy'], 'eveningOfRamadan');
      expect(row['hijri_day_adjustment'], 0);
      expect(row['fajr_offset'], 0);
      expect(row['sunrise_offset'], 0);
      expect(row['dhuhr_offset'], 0);
      expect(row['asr_offset'], 0);
      expect(row['maghrib_offset'], 0);
      expect(row['isha_offset'], 0);
      expect(row['general_adhan_voice'], 'adam');
      expect(row['fajr_adhan_voice'], 'malmo_fajr');

      await appDb.close();
    });

    test('migrates from v1 to v4: adds voice columns, v3 tables, v4 columns, maps Makkah to 104515', () async {
      final dbPath = createDbPath('v1_to_v4.db');

      final rawV1 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE reading_progress (id INTEGER PRIMARY KEY CHECK (id = 1), last_page INTEGER DEFAULT 1, updated_at TEXT);
            ''');
            await db.execute('''
              CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, page_number INTEGER, created_at TEXT);
            ''');
            await db.execute('''
              CREATE TABLE favorites (id INTEGER PRIMARY KEY AUTOINCREMENT, content_kind TEXT, stable_id TEXT, title TEXT, created_at TEXT, UNIQUE(content_kind, stable_id));
            ''');
            await db.execute('''
              CREATE TABLE dhikr_sessions (session_id TEXT PRIMARY KEY, dhikr_id TEXT, category TEXT, target_count INTEGER, date_bucket TEXT, created_at TEXT, updated_at TEXT);
            ''');
            await db.execute('''
              CREATE TABLE daily_progress (date_bucket TEXT PRIMARY KEY, updated_at TEXT);
            ''');
            await db.execute('''
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
            await db.execute('''
              INSERT INTO user_preferences (
                id, dark_mode, text_scale, selected_city, selected_timezone,
                quran_default_goal, notifications_enabled, active_dhikr_session_id, updated_at
              ) VALUES (
                1, 'dark', 1.25, 'مكة المكرمة', 'Asia/Riyadh', 4, 1, 'session_v1', '2026-09-01T00:00:00Z'
              );
            ''');
          },
        ),
      );
      await rawV1.close();

      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final rawDb = await appDb.database;

      expect(await rawDb.getVersion(), AppDatabase.schemaVersion);

      final tableRows = await rawDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
      );
      final actualTables = tableRows.map((r) => r['name'] as String).toSet();
      for (final table in expectedTables) {
        expect(actualTables.contains(table), isTrue);
      }

      final row = (await rawDb.query('user_preferences', where: 'id = 1')).first;
      expect(row['selected_city_id'], 104515);
      expect(row['selected_city'], 'مكة المكرمة');
      expect(row['selected_timezone'], 'Asia/Riyadh');
      expect(row['dark_mode'], 'dark');
      expect(row['general_adhan_voice'], 'adam');
      expect(row['fajr_adhan_voice'], 'malmo_fajr');
      expect(row['calculation_method'], isNull);
      expect(row['asr_madhab'], 'shafi');

      await appDb.close();
    });

    test('migrates from v2 to v4: adds v3 tables, v4 columns, maps Dubai to 292223', () async {
      final dbPath = createDbPath('v2_to_v4.db');

      final rawV2 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE reading_progress (id INTEGER PRIMARY KEY CHECK (id = 1), last_page INTEGER DEFAULT 1, updated_at TEXT);');
            await db.execute('CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, page_number INTEGER, created_at TEXT);');
            await db.execute('CREATE TABLE favorites (id INTEGER PRIMARY KEY AUTOINCREMENT, content_kind TEXT, stable_id TEXT, title TEXT, created_at TEXT, UNIQUE(content_kind, stable_id));');
            await db.execute('CREATE TABLE dhikr_sessions (session_id TEXT PRIMARY KEY, dhikr_id TEXT, category TEXT, target_count INTEGER, date_bucket TEXT, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE daily_progress (date_bucket TEXT PRIMARY KEY, updated_at TEXT);');
            await db.execute('''
              CREATE TABLE user_preferences (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                dark_mode TEXT NOT NULL DEFAULT 'system',
                text_scale REAL NOT NULL DEFAULT 1.0,
                selected_city TEXT NOT NULL DEFAULT 'القاهرة',
                selected_timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
                quran_default_goal INTEGER NOT NULL DEFAULT 2,
                notifications_enabled INTEGER NOT NULL DEFAULT 0,
                active_dhikr_session_id TEXT,
                general_adhan_voice TEXT NOT NULL DEFAULT 'atcovi',
                fajr_adhan_voice TEXT NOT NULL DEFAULT 'malmo_fajr',
                updated_at TEXT NOT NULL
              );
            ''');
            await db.execute('''
              INSERT INTO user_preferences (
                id, selected_city, selected_timezone, general_adhan_voice, fajr_adhan_voice, updated_at
              ) VALUES (
                1, 'دبي', 'Asia/Dubai', 'atcovi', 'malmo_fajr', '2026-09-01T00:00:00Z'
              );
            ''');
          },
        ),
      );
      await rawV2.close();

      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final rawDb = await appDb.database;

      expect(await rawDb.getVersion(), AppDatabase.schemaVersion);
      final row = (await rawDb.query('user_preferences', where: 'id = 1')).first;
      expect(row['selected_city_id'], 292223);
      expect(row['general_adhan_voice'], 'atcovi');

      await appDb.close();
    });

    test('migrates from v3 to v4: maps Jerusalem to 281184, keeps all 9 tables and records intact', () async {
      final dbPath = createDbPath('v3_to_v4.db');

      final rawV3 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE reading_progress (id INTEGER PRIMARY KEY CHECK (id = 1), last_page INTEGER DEFAULT 1, updated_at TEXT);');
            await db.execute('CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, page_number INTEGER, created_at TEXT);');
            await db.execute('CREATE TABLE favorites (id INTEGER PRIMARY KEY AUTOINCREMENT, content_kind TEXT, stable_id TEXT, title TEXT, created_at TEXT, UNIQUE(content_kind, stable_id));');
            await db.execute('CREATE TABLE dhikr_sessions (session_id TEXT PRIMARY KEY, dhikr_id TEXT, category TEXT, target_count INTEGER, date_bucket TEXT, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE daily_progress (date_bucket TEXT PRIMARY KEY, updated_at TEXT);');
            await db.execute('''
              CREATE TABLE user_preferences (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                dark_mode TEXT NOT NULL DEFAULT 'system',
                text_scale REAL NOT NULL DEFAULT 1.0,
                selected_city TEXT NOT NULL DEFAULT 'القاهرة',
                selected_timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
                quran_default_goal INTEGER NOT NULL DEFAULT 2,
                notifications_enabled INTEGER NOT NULL DEFAULT 0,
                active_dhikr_session_id TEXT,
                general_adhan_voice TEXT NOT NULL DEFAULT 'adam',
                fajr_adhan_voice TEXT NOT NULL DEFAULT 'malmo_fajr',
                updated_at TEXT NOT NULL
              );
            ''');
            await db.execute('CREATE TABLE hisn_daily_item_progress (date_bucket TEXT NOT NULL, period TEXT NOT NULL, item_id INTEGER NOT NULL, is_completed INTEGER DEFAULT 0, updated_at TEXT, PRIMARY KEY (date_bucket, period, item_id));');
            await db.execute('CREATE TABLE daily_quran_pages (date_bucket TEXT NOT NULL, page_number INTEGER NOT NULL, confirmed_at TEXT, PRIMARY KEY (date_bucket, page_number));');
            await db.execute('CREATE TABLE daily_source_confirmations (date_bucket TEXT NOT NULL, task_key TEXT NOT NULL, hisn_item_id INTEGER, is_completed INTEGER DEFAULT 0, updated_at TEXT, PRIMARY KEY (date_bucket, task_key));');

            await db.execute('''
              INSERT INTO user_preferences (
                id, selected_city, selected_timezone, updated_at
              ) VALUES (
                1, 'القدس الشريف', 'Asia/Jerusalem', '2026-09-01T00:00:00Z'
              );
            ''');
            await db.execute('''
              INSERT INTO hisn_daily_item_progress (date_bucket, period, item_id, is_completed, updated_at)
              VALUES ('Asia/Jerusalem|2026-10-01', 'morning', 1, 1, '2026-10-01T06:00:00Z');
            ''');
          },
        ),
      );
      await rawV3.close();

      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final rawDb = await appDb.database;

      expect(await rawDb.getVersion(), AppDatabase.schemaVersion);
      final row = (await rawDb.query('user_preferences', where: 'id = 1')).first;
      expect(row['selected_city_id'], 281184);

      final hisnRows = await rawDb.query('hisn_daily_item_progress');
      expect(hisnRows.length, 1);
      expect(hisnRows.first['item_id'], 1);

      await appDb.close();
    });

    test('unrecognized legacy selection leaves selected_city_id null (never overwritten with Cairo)', () async {
      final dbPath = createDbPath('unrecognized_v3_to_v4.db');

      final rawV3 = await databaseFactory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: 3,
          onCreate: (db, version) async {
            await db.execute('CREATE TABLE reading_progress (id INTEGER PRIMARY KEY CHECK (id = 1), last_page INTEGER DEFAULT 1, updated_at TEXT);');
            await db.execute('CREATE TABLE bookmarks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, page_number INTEGER, created_at TEXT);');
            await db.execute('CREATE TABLE favorites (id INTEGER PRIMARY KEY AUTOINCREMENT, content_kind TEXT, stable_id TEXT, title TEXT, created_at TEXT, UNIQUE(content_kind, stable_id));');
            await db.execute('CREATE TABLE dhikr_sessions (session_id TEXT PRIMARY KEY, dhikr_id TEXT, category TEXT, target_count INTEGER, date_bucket TEXT, created_at TEXT, updated_at TEXT);');
            await db.execute('CREATE TABLE daily_progress (date_bucket TEXT PRIMARY KEY, updated_at TEXT);');
            await db.execute('''
              CREATE TABLE user_preferences (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                dark_mode TEXT NOT NULL DEFAULT 'system',
                text_scale REAL NOT NULL DEFAULT 1.0,
                selected_city TEXT NOT NULL DEFAULT 'القاهرة',
                selected_timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
                quran_default_goal INTEGER NOT NULL DEFAULT 2,
                notifications_enabled INTEGER NOT NULL DEFAULT 0,
                active_dhikr_session_id TEXT,
                general_adhan_voice TEXT NOT NULL DEFAULT 'adam',
                fajr_adhan_voice TEXT NOT NULL DEFAULT 'malmo_fajr',
                updated_at TEXT NOT NULL
              );
            ''');
            await db.execute('CREATE TABLE hisn_daily_item_progress (date_bucket TEXT NOT NULL, period TEXT NOT NULL, item_id INTEGER NOT NULL, is_completed INTEGER DEFAULT 0, updated_at TEXT, PRIMARY KEY (date_bucket, period, item_id));');
            await db.execute('CREATE TABLE daily_quran_pages (date_bucket TEXT NOT NULL, page_number INTEGER NOT NULL, confirmed_at TEXT, PRIMARY KEY (date_bucket, page_number));');
            await db.execute('CREATE TABLE daily_source_confirmations (date_bucket TEXT NOT NULL, task_key TEXT NOT NULL, hisn_item_id INTEGER, is_completed INTEGER DEFAULT 0, updated_at TEXT, PRIMARY KEY (date_bucket, task_key));');

            await db.execute('''
              INSERT INTO user_preferences (
                id, selected_city, selected_timezone, updated_at
              ) VALUES (
                1, 'مدينة_مجهولة', 'Mars/Base_Alpha', '2026-09-01T00:00:00Z'
              );
            ''');
          },
        ),
      );
      await rawV3.close();

      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final rawDb = await appDb.database;

      final row = (await rawDb.query('user_preferences', where: 'id = 1')).first;
      expect(row['selected_city_id'], isNull, reason: 'Unrecognized legacy pair must remain null/unresolved');
      expect(row['selected_city'], 'مدينة_مجهولة');
      expect(row['selected_timezone'], 'Mars/Base_Alpha');

      await appDb.close();
    });
  });

  // ===========================================================================
  // 2. ProgressRepository & UserPreferences Field-Intent Bounds & Clear Semantics
  // ===========================================================================
  group('ProgressRepository - Prayer Settings Field-Intents & Validation', () {
    test('enforces strict boundary validation on prayer calculation fields', () async {
      final dbPath = createDbPath('bounds_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      await expectLater(
        repo.updatePreferencesFields(hijriDayAdjustment: -3),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repo.updatePreferencesFields(hijriDayAdjustment: 3),
        throwsA(isA<ArgumentError>()),
      );

      await expectLater(
        repo.updatePreferencesFields(fajrOffset: -121),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repo.updatePreferencesFields(ishaOffset: 121),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('atomic city and calculation settings update, persist, and clear nullable method', () async {
      final dbPath = createDbPath('settings_persist_test.db');
      final appDb1 = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo1 = ProgressRepository(appDb1);

      // 1. Atomically set city to Riyadh (108410)
      final updatedPrefs1 = await repo1.updatePreferencesFields(
        selectedCityId: 108410,
        selectedCity: 'الرياض',
        selectedTimezone: 'Asia/Riyadh',
      );
      expect(updatedPrefs1.selectedCityId, 108410);
      expect(updatedPrefs1.selectedCity, 'الرياض');
      expect(updatedPrefs1.selectedTimezone, 'Asia/Riyadh');

      // 2. Set calculation override and minute offsets
      final updatedPrefs2 = await repo1.updatePreferencesFields(
        calculationMethodOverride: CalculationMethod.muslim_world_league,
        asrMadhab: Madhab.hanafi,
        highLatitudeRule: HighLatitudeRule.twilight_angle,
        polarResolution: PolarDayResolution.nearestLatitude,
        ramadanPolicy: UmmAlQuraRamadanPolicy.disabled,
        hijriDayAdjustment: 1,
        fajrOffset: -5,
        sunriseOffset: 2,
        dhuhrOffset: 4,
        asrOffset: -2,
        maghribOffset: 3,
        ishaOffset: -3,
      );
      expect(updatedPrefs2.calculationMethodOverride, CalculationMethod.muslim_world_league);
      expect(updatedPrefs2.asrMadhab, Madhab.hanafi);
      expect(updatedPrefs2.highLatitudeRule, HighLatitudeRule.twilight_angle);
      expect(updatedPrefs2.polarResolution, PolarDayResolution.nearestLatitude);
      expect(updatedPrefs2.ramadanPolicy, UmmAlQuraRamadanPolicy.disabled);
      expect(updatedPrefs2.hijriDayAdjustment, 1);
      expect(updatedPrefs2.fajrOffset, -5);
      expect(updatedPrefs2.sunriseOffset, 2);
      expect(updatedPrefs2.dhuhrOffset, 4);
      expect(updatedPrefs2.asrOffset, -2);
      expect(updatedPrefs2.maghribOffset, 3);
      expect(updatedPrefs2.ishaOffset, -3);

      await repo1.close();

      // 3. Reopen database and verify persistence
      final appDb2 = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo2 = ProgressRepository(appDb2);

      final reopenedPrefs = await repo2.getPreferences();
      expect(reopenedPrefs.selectedCityId, 108410);
      expect(reopenedPrefs.calculationMethodOverride, CalculationMethod.muslim_world_league);
      expect(reopenedPrefs.asrMadhab, Madhab.hanafi);
      expect(reopenedPrefs.fajrOffset, -5);

      // 4. Clear nullable calculation method override back to city default
      final clearedPrefs = await repo2.updatePreferencesFields(
        clearCalculationMethodOverride: true,
      );
      expect(clearedPrefs.calculationMethodOverride, isNull);
      expect(clearedPrefs.selectedCityId, 108410);
      expect(clearedPrefs.asrMadhab, Madhab.hanafi);

      await repo2.close();
    });

    test('resetLocalState resets city to Cairo 360630 and clears calculation overrides', () async {
      final dbPath = createDbPath('reset_state_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      await repo.updatePreferencesFields(
        selectedCityId: 292223,
        selectedCity: 'دبي',
        selectedTimezone: 'Asia/Dubai',
        calculationMethodOverride: CalculationMethod.karachi,
        fajrOffset: 15,
      );

      await repo.resetLocalState();

      final resetPrefs = await repo.getPreferences();
      expect(resetPrefs.selectedCityId, 360630);
      expect(resetPrefs.selectedCity, 'القاهرة');
      expect(resetPrefs.selectedTimezone, 'Africa/Cairo');
      expect(resetPrefs.calculationMethodOverride, isNull);
      expect(resetPrefs.fajrOffset, 0);
      expect(resetPrefs.asrMadhab, Madhab.shafi);
    });
  });

  // ===========================================================================
  // 3. PreferencesController Genuine Accepted Queued Setter & Lifecycle Guards
  // ===========================================================================
  group('PreferencesController Lifecycle & Reset Generation Token Guards', () {
    test('queued setter accepted before reset is rejected after await, preserving fresh reset defaults', () async {
      final dbPath = createDbPath('lifecycle_queued_reset_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final gatedRepo = GatedProgressRepository(appDb);
      addTearDown(gatedRepo.close);

      // Container 1 (Old controller)
      final container1 = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(gatedRepo),
        ],
      );

      await container1.read(preferencesControllerProvider.future);
      final controller1 = container1.read(preferencesControllerProvider.notifier);

      // Arm response gate
      gatedRepo.responseGateEntered = Completer<void>();
      gatedRepo.responseGateCompleter = Completer<void>();

      // 1. Enqueue FIRST real controller setter
      final firstSetterFuture = controller1.setDarkMode('dark');

      // 2. Wait until first write has completed in SQLite and reaches response gate
      await gatedRepo.responseGateEntered!.future;

      // 3. While first response is held in repo, enqueue SECOND real controller setter
      final secondSetterFuture = controller1.setDarkMode('light');
      final secondSetterExpectation = expectLater(
        secondSetterFuture,
        throwsA(isA<StateError>()),
      );

      // 4. Dispose old container / controller
      container1.dispose();

      // 5. Container 2 (New controller)
      final container2 = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(gatedRepo),
        ],
      );
      addTearDown(container2.dispose);

      await container2.read(preferencesControllerProvider.future);
      final controller2 = container2.read(preferencesControllerProvider.notifier);

      try {
        // 6. New controller resets SQLite (generation advances to 1, DB wiped to defaults)
        await controller2.resetAllState();

        // 7. Release response delivery of first write
        gatedRepo.responseGateCompleter!.complete();

        // Await firstSetterFuture (which completed persistence before reset)
        await firstSetterFuture.timeout(const Duration(seconds: 3));

        // SECOND queued old intent MUST reject with StateError and NEVER write to fresh DB
        await secondSetterExpectation.timeout(const Duration(seconds: 3));

        // Assert persisted SQLite state remains reset defaults ('system', not overwritten by second queued intent)
        final persistedPrefs = await gatedRepo.getPreferences();
        expect(persistedPrefs.darkMode, 'system');
        expect(persistedPrefs.selectedCityId, 360630);

        // Later fresh setter on new controller survives and works properly
        await controller2.setDarkMode('dark');
        final afterFreshSetter = await gatedRepo.getPreferences();
        expect(afterFreshSetter.darkMode, 'dark');
      } finally {
        if (gatedRepo.responseGateCompleter != null &&
            !gatedRepo.responseGateCompleter!.isCompleted) {
          gatedRepo.responseGateCompleter!.complete();
        }
      }
    });

    test('calling setter on disposed controller immediately throws StateError without touching SQLite', () async {
      final dbPath = createDbPath('disposed_rejection_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await container.read(preferencesControllerProvider.future);
      final controller = container.read(preferencesControllerProvider.notifier);

      container.dispose();

      await expectLater(
        controller.setDarkMode('dark'),
        throwsA(isA<StateError>()),
      );

      final persisted = await repo.getPreferences();
      expect(persisted.darkMode, 'system');
    });
  });

  // ===========================================================================
  // 4. EffectivePrayerSettings Injection, Corrupted Raw Preservation & Repair
  // ===========================================================================
  group('EffectivePrayerSettings Corrupted Raw Recovery & Timezone Incoherence', () {
    test('derives default Cairo with Egyptian calculation method when override is null', () async {
      final dbPath = createDbPath('effective_cairo_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      await container.read(cityRepositoryProvider.future);

      final effective = container.read(effectivePrayerSettingsProvider).requireValue;
      expect(effective.city.id, 360630);
      expect(effective.city.name, 'Cairo');
      expect(effective.city.arabicName, 'القاهرة');
      expect(effective.city.timezone, 'Africa/Cairo');
      expect(effective.settings.calculationMethod, CalculationMethod.egyptian);

      final selectedCity = container.read(selectedPrayerCityProvider).requireValue;
      expect(selectedCity.id, 360630);
    });

    test('raw malformed calculation method produces AsyncError, unrelated updates preserve raw, explicit repair recovers snapshot', () async {
      final dbPath = createDbPath('corrupt_raw_method_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      // Inject malformed raw calculation method directly into SQLite
      final rawDb = await appDb.database;
      await rawDb.execute(
        "UPDATE user_preferences SET calculation_method = 'bogus_calc_method' WHERE id = 1;",
      );

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      await container.read(cityRepositoryProvider.future);

      // effectivePrayerSettingsProvider must reject with actionable Arabic error
      final effectiveBefore = container.read(effectivePrayerSettingsProvider);
      expect(effectiveBefore.hasError, isTrue);
      expect(effectiveBefore.error, isA<PrayerSettingsCorruptedException>());

      // Unrelated update (e.g. dark mode) must NOT rewrite or sanitize raw corrupted method
      final controller = container.read(preferencesControllerProvider.notifier);
      await controller.setDarkMode('dark');

      final rawRows = await rawDb.query('user_preferences', where: 'id = 1');
      expect(rawRows.first['calculation_method'], 'bogus_calc_method');
      expect(rawRows.first['dark_mode'], 'dark');

      // Still in error state after unrelated update
      final effectiveAfterUnrelated = container.read(effectivePrayerSettingsProvider);
      expect(effectiveAfterUnrelated.hasError, isTrue);
      expect(effectiveAfterUnrelated.error, isA<PrayerSettingsCorruptedException>());

      // Explicit repair of calculation method fixes only explicit field and recovers snapshot
      await controller.setCalculationMethodOverride(CalculationMethod.muslim_world_league);

      final rawRowsAfterRepair = await rawDb.query('user_preferences', where: 'id = 1');
      expect(rawRowsAfterRepair.first['calculation_method'], CalculationMethod.muslim_world_league.name);

      final effectiveAfterRepair = container.read(effectivePrayerSettingsProvider);
      expect(effectiveAfterRepair.hasValue, isTrue);
      expect(
        effectiveAfterRepair.requireValue.settings.calculationMethod,
        CalculationMethod.muslim_world_league,
      );
    });

    test('incoherent canonical city ID and timezone produces AsyncError, atomic city selection restores coherency', () async {
      final dbPath = createDbPath('incoherent_city_tz_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      // Inject incoherent timezone: Cairo canonical ID (360630) with timezone Mars/Base_Alpha
      final rawDb = await appDb.database;
      await rawDb.execute(
        "UPDATE user_preferences SET selected_city_id = 360630, selected_timezone = 'Mars/Base_Alpha' WHERE id = 1;",
      );

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      await container.read(cityRepositoryProvider.future);

      // Snapshot must reject incoherent canonical ID and timezone
      final effectiveBefore = container.read(effectivePrayerSettingsProvider);
      expect(effectiveBefore.hasError, isTrue);
      expect(effectiveBefore.error, isA<IncoherentCityTimezoneException>());

      // Unrelated update (textScale) preserves incoherent timezone in SQLite
      final controller = container.read(preferencesControllerProvider.notifier);
      await controller.setTextScale(1.4);

      final rawRows = await rawDb.query('user_preferences', where: 'id = 1');
      expect(rawRows.first['selected_timezone'], 'Mars/Base_Alpha');
      expect(rawRows.first['text_scale'], 1.4);

      final effectiveAfterUnrelated = container.read(effectivePrayerSettingsProvider);
      expect(effectiveAfterUnrelated.hasError, isTrue);
      expect(effectiveAfterUnrelated.error, isA<IncoherentCityTimezoneException>());

      // Atomic city selection restores coherency and recovers snapshot
      final SelectedCity cairo = cityRepo.getCityById(360630)!;
      await controller.setSelectedCity(cairo);

      final rawRowsAfterRepair = await rawDb.query('user_preferences', where: 'id = 1');
      expect(rawRowsAfterRepair.first['selected_timezone'], 'Africa/Cairo');

      final effectiveAfterRepair = container.read(effectivePrayerSettingsProvider);
      expect(effectiveAfterRepair.hasValue, isTrue);
      expect(effectiveAfterRepair.requireValue.city.id, 360630);
      expect(effectiveAfterRepair.requireValue.city.timezone, 'Africa/Cairo');
    });

    test('manual calculation override survives city change; clearing restores new city default', () async {
      final dbPath = createDbPath('override_retention_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      await container.read(cityRepositoryProvider.future);

      // 1. User sets calculation method override to Egyptian (different from Saudi default)
      await container
          .read(preferencesControllerProvider.notifier)
          .setCalculationMethodOverride(CalculationMethod.egyptian);

      var effective = container.read(effectivePrayerSettingsProvider).requireValue;
      expect(effective.settings.calculationMethod, CalculationMethod.egyptian);

      // 2. User changes city to Riyadh (108410, default is Muslim World League)
      final SelectedCity riyadhCity = cityRepo.getCityById(108410)!;
      await container
          .read(preferencesControllerProvider.notifier)
          .setSelectedCity(riyadhCity);

      effective = container.read(effectivePrayerSettingsProvider).requireValue;
      expect(effective.city.id, 108410);
      expect(effective.settings.calculationMethod, CalculationMethod.egyptian);

      // 3. User explicitly resets calculation method to city default
      await container
          .read(preferencesControllerProvider.notifier)
          .clearCalculationMethodOverride();

      effective = container.read(effectivePrayerSettingsProvider).requireValue;
      expect(effective.city.id, 108410);
      expect(effective.settings.calculationMethod, CalculationMethod.muslim_world_league);
    });

    test('unknown stored city ID produces actionable CityNotFoundException (never Cairo fallback)', () async {
      final dbPath = createDbPath('corrupt_city_id_test.db');
      final appDb = AppDatabase(
        databaseFactory: databaseFactory,
        databasePath: dbPath,
      );
      final repo = ProgressRepository(appDb);
      addTearDown(repo.close);

      await repo.updatePreferencesFields(selectedCityId: 999999999);

      final container = ProviderContainer(
        overrides: [
          progressRepositoryProvider.overrideWithValue(repo),
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesControllerProvider.future);
      await container.read(cityRepositoryProvider.future);

      final effectiveAsync = container.read(effectivePrayerSettingsProvider);
      expect(effectiveAsync.hasError, isTrue);
      expect(effectiveAsync.error, isA<CityNotFoundException>());

      final cityAsync = container.read(selectedPrayerCityProvider);
      expect(cityAsync.hasError, isTrue);
      expect(cityAsync.error, isA<CityNotFoundException>());
    });

    test('fingerprint covers all calculation inputs and value equality matches', () async {
      final SelectedCity cairo = cityRepo.getCityById(360630)!;
      final settingsA = PrayerSettings(
        calculationMethod: CalculationMethod.egyptian,
        asrMadhab: Madhab.shafi,
        fajrOffsetMinutes: 0,
      );
      final settingsB = PrayerSettings(
        calculationMethod: CalculationMethod.egyptian,
        asrMadhab: Madhab.shafi,
        fajrOffsetMinutes: 5,
      );

      final snapshotA1 = EffectivePrayerSettings(city: cairo, settings: settingsA);
      final snapshotA2 = EffectivePrayerSettings(city: cairo, settings: settingsA);
      final snapshotB = EffectivePrayerSettings(city: cairo, settings: settingsB);

      expect(snapshotA1, equals(snapshotA2));
      expect(snapshotA1.hashCode, equals(snapshotA2.hashCode));
      expect(snapshotA1.fingerprint, equals(snapshotA2.fingerprint));

      expect(snapshotA1, isNot(equals(snapshotB)));
      expect(snapshotA1.fingerprint, isNot(equals(snapshotB.fingerprint)));
      expect(snapshotA1.fingerprint.contains('360630|Africa/Cairo'), isTrue);
    });
  });

  // ===========================================================================
  // 5. Widget Layout, Gestures & Real Dialog Harness (320x480 & textScale 2.0)
  // ===========================================================================
  group('CitySearchPickerDialog & PrayerCalculationSettingsSection UI Tests', () {
    testWidgets('CitySearchPickerDialog real dialog harness selects Makkah and returns canonical ID/timezone', (tester) async {
      final container = ProviderContainer(
        overrides: [
          cityRepositoryProvider.overrideWith((ref) async => cityRepo),
        ],
      );
      addTearDown(container.dispose);

      SelectedCity? returnedCity;

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  returnedCity = await CitySearchPickerDialog.show(
                    context,
                    currentCityId: 360630,
                  );
                },
                child: const Text('فتح نافذة اختيار المدينة'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('فتح نافذة اختيار المدينة'));
      await tester.pumpAndSettle();

      expect(find.text('اختر المدينة (قاعدة بيانات المدن العالمية)'), findsOneWidget);

      // Search with Arabic query
      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'مكة');
      await tester.pumpAndSettle();

      // Tap on Makkah result using actual ListTile display name
      final makkahCity = cityRepo.getCityById(104515)!;
      final makkahDisplayName = makkahCity.arabicName != null
          ? '${makkahCity.arabicName} (${makkahCity.name})'
          : makkahCity.name;
      final makkahTile = find.widgetWithText(ListTile, makkahDisplayName);
      expect(makkahTile, findsWidgets);
      await tester.tap(makkahTile.first);
      await tester.pumpAndSettle();

      // Dialog is dismissed and returned canonical selection
      expect(find.text('اختر المدينة (قاعدة بيانات المدن العالمية)'), findsNothing);
      expect(returnedCity, isNotNull);
      expect(returnedCity!.id, 104515);
      expect(returnedCity!.timezone, 'Asia/Riyadh');
    });

    testWidgets('PrayerCalculationSettingsSection interactive gestures at 320x480 textScale 2.0 persist settings and survive reopen', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      late AppDatabase appDb;
      late ProgressRepository repo;
      late ProviderContainer container;
      bool containerDisposed = false;
      bool repoClosed = false;

      // Real SQLite setup inside tester.runAsync using databaseFactoryFfiNoIsolate
      await tester.runAsync(() async {
        final dbPath = createDbPath('widget_gestures_test.db');
        appDb = AppDatabase(
          databaseFactory: databaseFactoryFfiNoIsolate,
          databasePath: dbPath,
        );
        repo = ProgressRepository(appDb);
        container = ProviderContainer(
          overrides: [
            progressRepositoryProvider.overrideWithValue(repo),
            cityRepositoryProvider.overrideWith((ref) async => cityRepo),
          ],
        );
        await container.read(preferencesControllerProvider.future);
        await container.read(cityRepositoryProvider.future);
      });

      // Bounded real-drag helper on SingleChildScrollView checking hitTestable()
      Future<void> dragUntilHitTestable(
        Finder target, {
        required Offset dragDelta,
        int maxDrags = 30,
      }) async {
        final scrollView = find.byType(SingleChildScrollView);
        for (int i = 0; i < maxDrags; i++) {
          if (target.hitTestable().evaluate().isNotEmpty) {
            break;
          }
          await tester.drag(scrollView, dragDelta);
          await tester.pumpAndSettle();
        }
        expect(
          target.hitTestable(),
          findsAtLeastNWidgets(1),
          reason: 'Target must be hit-testable after bounded drags',
        );
      }

      // Helper to dispatch a gesture outside runAsync and await preference publication via bounded interleaved IO loop
      Future<void> tapAndAwaitPreference(
        Finder target, {
        required bool Function(UserPreferences prefs) condition,
        int maxCycles = 100,
      }) async {
        // 1. Gesture executed in fakeAsync zone
        await tester.tap(target);
        // 2. Finish route pop animation, transitions and pending microtasks
        await tester.pumpAndSettle();

        // 3. Interleaved real-IO yield and fakeAsync pump loop
        for (int i = 0; i < maxCycles; i++) {
          final current = container.read(preferencesControllerProvider);
          if (current.hasError) {
            Error.throwWithStackTrace(current.error!, current.stackTrace ?? StackTrace.current);
          }
          if (current.hasValue && condition(current.requireValue)) {
            return;
          }
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump(const Duration(milliseconds: 20));
        }

        // 4. If cycles exhausted without matching condition, assert with actual last state
        final last = container.read(preferencesControllerProvider);
        if (last.hasError) {
          Error.throwWithStackTrace(last.error!, last.stackTrace ?? StackTrace.current);
        }
        expect(
          last.valueOrNull,
          predicate<UserPreferences?>((p) => p != null && condition(p)),
          reason: 'Preferences update timed out after $maxCycles cycles. Last preferences: ${last.valueOrNull}',
        );
      }

      try {
        await tester.pumpWidget(
          buildTestApp(
            container: container,
            textScale: 2.0,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Consumer(
                  builder: (context, ref, _) {
                    final prefsAsync = ref.watch(preferencesControllerProvider);
                    if (!prefsAsync.hasValue) return const SizedBox.shrink();
                    return PrayerCalculationSettingsSection(
                      prefs: prefsAsync.requireValue,
                      isDark: false,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull, reason: 'Zero RenderFlex overflow permitted at 320x480 / textScale 2.0');

        // Gesture 1: Drag to Madhab dropdown, open it, and select Hanafi
        final madhabDropdown = find.byKey(const ValueKey('asr_madhab_shafi'));
        await dragUntilHitTestable(madhabDropdown, dragDelta: const Offset(0, -120));

        await tester.tap(madhabDropdown.hitTestable().first);
        await tester.pumpAndSettle();

        final hanafiOption = find.text('الحنفي (ظل المثلين)').hitTestable();
        expect(hanafiOption, findsOneWidget);

        await tapAndAwaitPreference(
          hanafiOption,
          condition: (p) => p.asrMadhab == Madhab.hanafi,
        );

        // Verify Madhab persistence in SQLite (assertions extracted outside runAsync)
        UserPreferences? prefsAfterMadhab;
        await tester.runAsync(() async {
          prefsAfterMadhab = await repo.getPreferences();
        });
        expect(prefsAfterMadhab!.asrMadhab, Madhab.hanafi);

        // Gesture 2: Drag to Offsets section and increment Fajr offset
        final fajrRowFinder = find.ancestor(
          of: find.text('الفجر'),
          matching: find.byType(Row),
        ).first;
        final fajrAddBtn = find.descendant(
          of: fajrRowFinder,
          matching: find.byIcon(Icons.add),
        );
        await dragUntilHitTestable(fajrAddBtn, dragDelta: const Offset(0, -120));

        await tapAndAwaitPreference(
          fajrAddBtn.hitTestable().first,
          condition: (p) => p.fajrOffset == 1,
        );

        // Verify offset persistence in SQLite (assertions extracted outside runAsync)
        UserPreferences? prefsAfterOffset;
        await tester.runAsync(() async {
          prefsAfterOffset = await repo.getPreferences();
        });
        expect(prefsAfterOffset!.fajrOffset, 1);

        // Gesture 3: Drag back to City Card, tap 'تغيير', search Riyadh and select it
        final changeCityBtn = find.text('تغيير');
        await dragUntilHitTestable(changeCityBtn, dragDelta: const Offset(0, 120));

        await tester.tap(changeCityBtn.hitTestable().first);
        await tester.pumpAndSettle();

        final searchField = find.byType(TextField);
        expect(searchField, findsOneWidget);
        await tester.enterText(searchField, 'الرياض');
        await tester.pumpAndSettle();

        final riyadhCity = cityRepo.getCityById(108410)!;
        final riyadhDisplayName = riyadhCity.arabicName != null
            ? '${riyadhCity.arabicName} (${riyadhCity.name})'
            : riyadhCity.name;
        final riyadhTile = find.widgetWithText(ListTile, riyadhDisplayName).hitTestable();
        expect(riyadhTile, findsOneWidget);

        await tapAndAwaitPreference(
          riyadhTile,
          condition: (p) => p.selectedCityId == 108410,
        );

        // Verify city persistence and snapshot coherence
        UserPreferences? prefsAfterCity;
        await tester.runAsync(() async {
          prefsAfterCity = await repo.getPreferences();
        });
        expect(prefsAfterCity!.selectedCityId, 108410);
        expect(prefsAfterCity!.selectedTimezone, 'Asia/Riyadh');

        final snapshot = container.read(effectivePrayerSettingsProvider).requireValue;
        expect(snapshot.city.id, 108410);
        expect(snapshot.city.timezone, 'Asia/Riyadh');
        expect(snapshot.settings.asrMadhab, Madhab.hanafi);
        expect(snapshot.settings.fajrOffsetMinutes, 1);

        // Unmount and dispose container before closing repo and reopening DB
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        containerDisposed = true;

        await tester.runAsync(() async {
          await repo.mutationBarrier.drainActiveOperations(
            timeout: const Duration(seconds: 3),
          );
          await repo.close();
          repoClosed = true;
        });

        // Verify changes survive database reopen using databaseFactoryFfiNoIsolate
        UserPreferences? reopenedPrefs;
        await tester.runAsync(() async {
          AppDatabase? appDb2;
          ProgressRepository? repo2;
          try {
            appDb2 = AppDatabase(
              databaseFactory: databaseFactoryFfiNoIsolate,
              databasePath: createDbPath('widget_gestures_test.db'),
            );
            repo2 = ProgressRepository(appDb2);
            reopenedPrefs = await repo2.getPreferences();
          } finally {
            if (repo2 != null) await repo2.close();
            if (appDb2 != null) await appDb2.close();
          }
        });
        expect(reopenedPrefs!.selectedCityId, 108410);
        expect(reopenedPrefs!.selectedTimezone, 'Asia/Riyadh');
        expect(reopenedPrefs!.asrMadhab, Madhab.hanafi);
        expect(reopenedPrefs!.fajrOffset, 1);
      } finally {
        // Guaranteed idempotent unmount and disposal inside tester.runAsync with finite deadline
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (!containerDisposed) {
          container.dispose();
        }
        await tester.runAsync(() async {
          if (!repoClosed) {
            Object? drainError;
            StackTrace? drainStack;
            try {
              await repo.mutationBarrier.drainActiveOperations(
                timeout: const Duration(seconds: 3),
              );
            } catch (err, stack) {
              drainError = err;
              drainStack = stack;
            } finally {
              await repo.close();
            }
            if (drainError != null) {
              Error.throwWithStackTrace(drainError, drainStack ?? StackTrace.current);
            }
          }
        });
      }
    });
  });
}
