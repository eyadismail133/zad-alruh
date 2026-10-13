import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  final DatabaseFactory? _factory;
  final String? _customPath;
  Database? _db;
  bool _isClosed = false;

  AppDatabase({DatabaseFactory? databaseFactory, String? databasePath})
    : _factory = databaseFactory,
      _customPath = databasePath;

  static const int schemaVersion = 6;
  static const String databaseName = 'zad_alruh.db';
  static const String _sourceConfirmationTableSchema = '''
    CREATE TABLE IF NOT EXISTS daily_source_confirmations (
      date_bucket TEXT NOT NULL CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0),
      task_key TEXT NOT NULL CHECK (task_key IN ('daily_dua', 'post_prayer')),
      hisn_item_id INTEGER CHECK (hisn_item_id IS NULL OR (hisn_item_id BETWEEN 1 AND 267) OR (hisn_item_id BETWEEN 1000001 AND 1069999)),
      is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
      updated_at TEXT NOT NULL,
      PRIMARY KEY (date_bucket, task_key)
    );
  ''';

  DatabaseFactory get _effectiveFactory => _factory ?? databaseFactory;

  Future<Database> get database async {
    if (_isClosed) {
      throw StateError('Database has been closed and cannot be used');
    }
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final String path;
    if (_customPath != null) {
      path = _customPath;
    } else {
      final dbFolder = await _effectiveFactory.getDatabasesPath();
      path = p.join(dbFolder, databaseName);
    }

    return await _effectiveFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE user_preferences ADD COLUMN general_adhan_voice TEXT NOT NULL DEFAULT 'adam'",
            );
            await db.execute(
              "ALTER TABLE user_preferences ADD COLUMN fajr_adhan_voice TEXT NOT NULL DEFAULT 'malmo_fajr'",
            );
          }
          if (oldVersion < 3) {
            await _createV3Tables(db);
          }
          if (oldVersion < 4) {
            await _upgradeToV4(db);
          }
          if (oldVersion < 5) {
            await db.execute(
              'ALTER TABLE reading_progress ADD COLUMN resume_page INTEGER CHECK (resume_page >= 1 AND resume_page <= 604)',
            );
          }
          if (oldVersion < 6) await _upgradeToV6(db);
        },
      ),
    );
  }

  Future<void> _upgradeToV6(DatabaseExecutor db) async {
    // SQLite cannot widen a CHECK in place; the upgrade transaction retains
    // every old row, including selections no longer eligible for new prayers.
    await db.execute(
      'ALTER TABLE daily_source_confirmations RENAME TO legacy_source_confirmations',
    );
    await db.execute(_sourceConfirmationTableSchema);
    await db.execute(
      'INSERT INTO daily_source_confirmations SELECT * FROM legacy_source_confirmations',
    );
    await db.execute('DROP TABLE legacy_source_confirmations');
    await db.execute(
      'CREATE INDEX idx_daily_source_confirmations_bucket ON daily_source_confirmations (date_bucket)',
    );
  }

  Future<void> _createTables(Database db) async {
    final batch = db.batch();

    // 1. Reading Progress
    batch.execute('''
      CREATE TABLE reading_progress (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_page INTEGER NOT NULL DEFAULT 1 CHECK (last_page >= 1 AND last_page <= 604),
        selected_surah INTEGER,
        selected_verse INTEGER,
        resume_page INTEGER CHECK (resume_page >= 1 AND resume_page <= 604),
        updated_at TEXT NOT NULL
      );
    ''');
    batch.execute('''
      INSERT INTO reading_progress (id, last_page, updated_at)
      VALUES (1, 1, '${DateTime.now().toIso8601String()}');
    ''');

    // 2. Bookmarks
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

    // 3. Favorites
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

    // 4. Dhikr Sessions
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
    batch.execute(
      'CREATE INDEX idx_dhikr_sessions_date ON dhikr_sessions (date_bucket);',
    );
    batch.execute(
      'CREATE INDEX idx_dhikr_sessions_dhikr ON dhikr_sessions (dhikr_id);',
    );

    // 5. Daily Progress
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

    // 6. User Preferences
    batch.execute('''
      CREATE TABLE user_preferences (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        dark_mode TEXT NOT NULL DEFAULT 'system',
        text_scale REAL NOT NULL DEFAULT 1.0,
        selected_city_id INTEGER DEFAULT 360630,
        selected_city TEXT NOT NULL DEFAULT 'القاهرة',
        selected_timezone TEXT NOT NULL DEFAULT 'Africa/Cairo',
        calculation_method TEXT DEFAULT NULL,
        asr_madhab TEXT NOT NULL DEFAULT 'shafi',
        high_latitude_rule TEXT NOT NULL DEFAULT 'middle_of_the_night',
        polar_resolution TEXT NOT NULL DEFAULT 'unresolved',
        ramadan_policy TEXT NOT NULL DEFAULT 'eveningOfRamadan',
        hijri_day_adjustment INTEGER NOT NULL DEFAULT 0,
        fajr_offset INTEGER NOT NULL DEFAULT 0,
        sunrise_offset INTEGER NOT NULL DEFAULT 0,
        dhuhr_offset INTEGER NOT NULL DEFAULT 0,
        asr_offset INTEGER NOT NULL DEFAULT 0,
        maghrib_offset INTEGER NOT NULL DEFAULT 0,
        isha_offset INTEGER NOT NULL DEFAULT 0,
        quran_default_goal INTEGER NOT NULL DEFAULT 2,
        notifications_enabled INTEGER NOT NULL DEFAULT 0,
        active_dhikr_session_id TEXT,
        general_adhan_voice TEXT NOT NULL DEFAULT 'adam',
        fajr_adhan_voice TEXT NOT NULL DEFAULT 'malmo_fajr',
        updated_at TEXT NOT NULL
      );
    ''');
    batch.execute('''
      INSERT INTO user_preferences (
        id, dark_mode, text_scale, selected_city_id, selected_city, selected_timezone,
        calculation_method, asr_madhab, high_latitude_rule, polar_resolution,
        ramadan_policy, hijri_day_adjustment, fajr_offset, sunrise_offset,
        dhuhr_offset, asr_offset, maghrib_offset, isha_offset,
        quran_default_goal, notifications_enabled, active_dhikr_session_id,
        general_adhan_voice, fajr_adhan_voice, updated_at
      )
      VALUES (
        1, 'system', 1.0, 360630, 'القاهرة', 'Africa/Cairo',
        NULL, 'shafi', 'middle_of_the_night', 'unresolved',
        'eveningOfRamadan', 0, 0, 0,
        0, 0, 0, 0,
        2, 0, NULL,
        'adam', 'malmo_fajr', '${DateTime.now().toIso8601String()}'
      );
    ''');

    // 7. Hisn Daily Item Progress (Morning 22 / Evening 20 / Shared 100)
    batch.execute('''
      CREATE TABLE hisn_daily_item_progress (
        date_bucket TEXT NOT NULL CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0),
        period TEXT NOT NULL CHECK (period IN ('morning', 'evening', 'shared_100')),
        item_id INTEGER NOT NULL CHECK (item_id >= 1 AND item_id <= 267),
        is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
        updated_at TEXT NOT NULL,
        PRIMARY KEY (date_bucket, period, item_id)
      );
    ''');
    batch.execute(
      'CREATE INDEX idx_hisn_daily_bucket_period ON hisn_daily_item_progress (date_bucket, period);',
    );

    // 8. Daily Confirmed Quran Pages (1..604)
    batch.execute('''
      CREATE TABLE daily_quran_pages (
        date_bucket TEXT NOT NULL CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0),
        page_number INTEGER NOT NULL CHECK (page_number >= 1 AND page_number <= 604),
        confirmed_at TEXT NOT NULL,
        PRIMARY KEY (date_bucket, page_number)
      );
    ''');
    batch.execute(
      'CREATE INDEX idx_daily_quran_pages_bucket ON daily_quran_pages (date_bucket);',
    );

    // 9. Daily Source-Linked Confirmations (Daily Dua & Post-Prayer)
    batch.execute(_sourceConfirmationTableSchema);
    batch.execute(
      'CREATE INDEX idx_daily_source_confirmations_bucket ON daily_source_confirmations (date_bucket);',
    );

    await batch.commit(noResult: true);
  }

  Future<void> _createV3Tables(DatabaseExecutor db) async {
    final batch = db.batch();

    batch.execute('''
      CREATE TABLE IF NOT EXISTS hisn_daily_item_progress (
        date_bucket TEXT NOT NULL CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0),
        period TEXT NOT NULL CHECK (period IN ('morning', 'evening', 'shared_100')),
        item_id INTEGER NOT NULL CHECK (item_id >= 1 AND item_id <= 267),
        is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),
        updated_at TEXT NOT NULL,
        PRIMARY KEY (date_bucket, period, item_id)
      );
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_hisn_daily_bucket_period ON hisn_daily_item_progress (date_bucket, period);',
    );

    batch.execute('''
      CREATE TABLE IF NOT EXISTS daily_quran_pages (
        date_bucket TEXT NOT NULL CHECK (length(date_bucket) > 0 AND instr(date_bucket, '|') > 0),
        page_number INTEGER NOT NULL CHECK (page_number >= 1 AND page_number <= 604),
        confirmed_at TEXT NOT NULL,
        PRIMARY KEY (date_bucket, page_number)
      );
    ''');
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_quran_pages_bucket ON daily_quran_pages (date_bucket);',
    );

    batch.execute(_sourceConfirmationTableSchema);
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_daily_source_confirmations_bucket ON daily_source_confirmations (date_bucket);',
    );

    await batch.commit(noResult: true);
  }

  Future<void> _upgradeToV4(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN selected_city_id INTEGER',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN calculation_method TEXT',
    );
    await db.execute(
      "ALTER TABLE user_preferences ADD COLUMN asr_madhab TEXT NOT NULL DEFAULT 'shafi'",
    );
    await db.execute(
      "ALTER TABLE user_preferences ADD COLUMN high_latitude_rule TEXT NOT NULL DEFAULT 'middle_of_the_night'",
    );
    await db.execute(
      "ALTER TABLE user_preferences ADD COLUMN polar_resolution TEXT NOT NULL DEFAULT 'unresolved'",
    );
    await db.execute(
      "ALTER TABLE user_preferences ADD COLUMN ramadan_policy TEXT NOT NULL DEFAULT 'eveningOfRamadan'",
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN hijri_day_adjustment INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN fajr_offset INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN sunrise_offset INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN dhuhr_offset INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN asr_offset INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN maghrib_offset INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute(
      'ALTER TABLE user_preferences ADD COLUMN isha_offset INTEGER NOT NULL DEFAULT 0',
    );

    // Canonical migration of existing exact legacy 8 city+timezone pairs
    final rows = await db.query(
      'user_preferences',
      columns: ['id', 'selected_city', 'selected_timezone'],
      where: 'id = 1',
    );
    if (rows.isNotEmpty) {
      final cityName = rows.first['selected_city'] as String?;
      final timezone = rows.first['selected_timezone'] as String?;
      final key = '$cityName|$timezone';
      const legacyMap = <String, int>{
        'القاهرة|Africa/Cairo': 360630,
        'مكة المكرمة|Asia/Riyadh': 104515,
        'المدينة المنورة|Asia/Riyadh': 109223,
        'الرياض|Asia/Riyadh': 108410,
        'دبي|Asia/Dubai': 292223,
        'القدس الشريف|Asia/Jerusalem': 281184,
        'إسطنبول|Europe/Istanbul': 745044,
        'لندن|Europe/London': 2643743,
      };
      final canonicalId = legacyMap[key];
      if (canonicalId != null) {
        await db.update('user_preferences', {
          'selected_city_id': canonicalId,
        }, where: 'id = 1');
      }
      // If unrecognized, canonicalId is null and selected_city_id remains null (unresolved)!
    }
  }

  Future<void> close() async {
    _isClosed = true;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
