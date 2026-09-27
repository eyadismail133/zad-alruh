import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  final DatabaseFactory? _factory;
  final String? _customPath;
  Database? _db;
  bool _isClosed = false;

  AppDatabase({
    DatabaseFactory? databaseFactory,
    String? databasePath,
  })  : _factory = databaseFactory,
        _customPath = databasePath;

  static const int schemaVersion = 1;
  static const String databaseName = 'zad_alruh.db';

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
          // Schema migrations when version increases
        },
      ),
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
    batch.execute('CREATE INDEX idx_dhikr_sessions_date ON dhikr_sessions (date_bucket);');
    batch.execute('CREATE INDEX idx_dhikr_sessions_dhikr ON dhikr_sessions (dhikr_id);');

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
      VALUES (1, 'system', 1.0, 'القاهرة', 'Africa/Cairo', 2, 0, NULL, '${DateTime.now().toIso8601String()}');
    ''');

    await batch.commit(noResult: true);
  }

  Future<void> close() async {
    _isClosed = true;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
