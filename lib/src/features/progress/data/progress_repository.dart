import 'dart:async';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import 'models/bookmark.dart';
import 'models/daily_progress.dart';
import 'models/dhikr_session.dart';
import 'models/favorite.dart';
import 'models/reading_progress.dart';
import 'models/user_preferences.dart';

typedef QuranVersePageValidator =
    FutureOr<bool> Function({
      required int pageNumber,
      required int surahNumber,
      required int verseNumber,
    });

class ProgressRepository {
  final AppDatabase _database;
  QuranVersePageValidator? _versePageValidator;

  ProgressRepository(
    this._database, {
    QuranVersePageValidator? versePageValidator,
  }) : _versePageValidator = versePageValidator;

  void setVersePageValidator(QuranVersePageValidator? validator) {
    _versePageValidator = validator;
  }

  Future<bool> isValidVerseOnPage({
    required int pageNumber,
    required int surahNumber,
    required int verseNumber,
  }) async {
    if (_versePageValidator == null) return false;
    return _versePageValidator!(
      pageNumber: pageNumber,
      surahNumber: surahNumber,
      verseNumber: verseNumber,
    );
  }

  Future<Database> get _db => _database.database;

  // -------------------------------------------------------------
  // Reading Progress (1..604, optional verse)
  // -------------------------------------------------------------

  Future<ReadingProgress> getReadingProgress() async {
    final db = await _db;
    final results = await db.query(
      'reading_progress',
      where: 'id = 1',
      limit: 1,
    );
    if (results.isEmpty) {
      const initial = ReadingProgress();
      await db.insert(
        'reading_progress',
        initial.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return initial;
    }
    return ReadingProgress.fromMap(results.first);
  }

  Future<void> saveReadingProgress(ReadingProgress progress) async {
    if (progress.lastPage < 1 || progress.lastPage > 604) {
      throw ArgumentError.value(
        progress.lastPage,
        'lastPage',
        'Must be between 1 and 604',
      );
    }
    if (progress.selectedSurah != null || progress.selectedVerse != null) {
      if (progress.selectedSurah == null || progress.selectedVerse == null) {
        throw ArgumentError(
          'selectedSurah and selectedVerse must both be specified or both null',
        );
      }
      if (_versePageValidator == null) {
        throw StateError(
          'Verse validation unavailable; cannot persist unverified verse reference',
        );
      }
      final isValid = await _versePageValidator!(
        pageNumber: progress.lastPage,
        surahNumber: progress.selectedSurah!,
        verseNumber: progress.selectedVerse!,
      );
      if (!isValid) {
        throw ArgumentError(
          'Invalid verse ${progress.selectedSurah}:${progress.selectedVerse} for page ${progress.lastPage}',
        );
      }
    }
    final db = await _db;
    await db.insert(
      'reading_progress',
      progress.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // -------------------------------------------------------------
  // Bookmarks (Named CRUD, 1..604)
  // -------------------------------------------------------------

  Future<int> createBookmark({
    required String name,
    required int pageNumber,
    int? surahNumber,
    int? verseNumber,
  }) async {
    if (pageNumber < 1 || pageNumber > 604) {
      throw ArgumentError.value(
        pageNumber,
        'pageNumber',
        'Page must be between 1 and 604',
      );
    }
    if (surahNumber != null || verseNumber != null) {
      if (surahNumber == null || verseNumber == null) {
        throw ArgumentError(
          'surahNumber and verseNumber must both be specified or both null',
        );
      }
      if (_versePageValidator == null) {
        throw StateError(
          'Verse validation unavailable; cannot persist unverified verse reference',
        );
      }
      final isValid = await _versePageValidator!(
        pageNumber: pageNumber,
        surahNumber: surahNumber,
        verseNumber: verseNumber,
      );
      if (!isValid) {
        throw ArgumentError(
          'Invalid verse $surahNumber:$verseNumber for page $pageNumber',
        );
      }
    }
    final db = await _db;
    final bookmark = Bookmark(
      name: name,
      pageNumber: pageNumber,
      surahNumber: surahNumber,
      verseNumber: verseNumber,
      createdAt: DateTime.now(),
    );
    return await db.insert('bookmarks', bookmark.toMap());
  }

  Future<List<Bookmark>> getBookmarks() async {
    final db = await _db;
    final results = await db.query('bookmarks', orderBy: 'id DESC');
    return results.map((m) => Bookmark.fromMap(m)).toList();
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    if (bookmark.id == null) {
      throw ArgumentError('Bookmark id cannot be null on update');
    }
    if (bookmark.pageNumber < 1 || bookmark.pageNumber > 604) {
      throw ArgumentError.value(
        bookmark.pageNumber,
        'pageNumber',
        'Page must be between 1 and 604',
      );
    }
    if (bookmark.surahNumber != null || bookmark.verseNumber != null) {
      if (bookmark.surahNumber == null || bookmark.verseNumber == null) {
        throw ArgumentError(
          'surahNumber and verseNumber must both be specified or both null',
        );
      }
      if (_versePageValidator == null) {
        throw StateError(
          'Verse validation unavailable; cannot persist unverified verse reference',
        );
      }
      final isValid = await _versePageValidator!(
        pageNumber: bookmark.pageNumber,
        surahNumber: bookmark.surahNumber!,
        verseNumber: bookmark.verseNumber!,
      );
      if (!isValid) {
        throw ArgumentError(
          'Invalid verse ${bookmark.surahNumber}:${bookmark.verseNumber} for page ${bookmark.pageNumber}',
        );
      }
    }
    final db = await _db;
    await db.update(
      'bookmarks',
      bookmark.toMap(),
      where: 'id = ?',
      whereArgs: [bookmark.id],
    );
  }

  Future<void> deleteBookmark(int id) async {
    final db = await _db;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  // -------------------------------------------------------------
  // Favorites (Unique by content_kind & stable_id)
  // -------------------------------------------------------------

  Future<void> addFavorite(Favorite favorite) async {
    final db = await _db;
    await db.insert(
      'favorites',
      favorite.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(String contentKind, String stableId) async {
    final db = await _db;
    await db.delete(
      'favorites',
      where: 'content_kind = ? AND stable_id = ?',
      whereArgs: [contentKind, stableId],
    );
  }

  Future<bool> isFavorite(String contentKind, String stableId) async {
    final db = await _db;
    final results = await db.query(
      'favorites',
      where: 'content_kind = ? AND stable_id = ?',
      whereArgs: [contentKind, stableId],
      limit: 1,
    );
    return results.isNotEmpty;
  }

  Future<List<Favorite>> getFavorites() async {
    final db = await _db;
    final results = await db.query('favorites', orderBy: 'id DESC');
    return results.map((m) => Favorite.fromMap(m)).toList();
  }

  Future<List<Favorite>> getFavoritesByKind(String contentKind) async {
    final db = await _db;
    final results = await db.query(
      'favorites',
      where: 'content_kind = ?',
      whereArgs: [contentKind],
      orderBy: 'id DESC',
    );
    return results.map((m) => Favorite.fromMap(m)).toList();
  }

  // -------------------------------------------------------------
  // Dhikr Sessions (Capped atomic increments & resumable sessions)
  // -------------------------------------------------------------

  Future<DhikrSession> startDhikrSession({
    required String sessionId,
    required String dhikrId,
    required String category,
    required int targetCount,
    required String dateBucket,
    bool setActive = true,
  }) async {
    final db = await _db;
    return await db.transaction<DhikrSession>((txn) async {
      final existing = await txn.query(
        'dhikr_sessions',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw StateError(
          'Dhikr session $sessionId already exists and cannot be overwritten',
        );
      }

      final now = DateTime.now();
      final session = DhikrSession(
        sessionId: sessionId,
        dhikrId: dhikrId,
        category: category,
        targetCount: targetCount,
        currentCount: 0,
        isCompleted: false,
        dateBucket: dateBucket,
        createdAt: now,
        updatedAt: now,
      );
      await txn.insert(
        'dhikr_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      if (setActive) {
        await txn.update('user_preferences', {
          'active_dhikr_session_id': sessionId,
          'updated_at': now.toIso8601String(),
        }, where: 'id = 1');
      }

      return session;
    });
  }

  Future<void> setActiveDhikrSession(String? sessionId) async {
    final db = await _db;
    if (sessionId != null) {
      final existing = await db.query(
        'dhikr_sessions',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (existing.isEmpty) {
        throw StateError(
          'Cannot set active session: session $sessionId not found',
        );
      }
    }
    await db.update('user_preferences', {
      'active_dhikr_session_id': sessionId,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = 1');
  }

  Future<void> clearActiveDhikrSession() async {
    await setActiveDhikrSession(null);
  }

  Future<List<DhikrSession>> getUnfinishedDhikrSessions() async {
    final db = await _db;
    final rows = await db.query(
      'dhikr_sessions',
      where: 'is_completed = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map((r) => DhikrSession.fromMap(r)).toList();
  }

  Future<DhikrSession> incrementDhikrSession(
    String sessionId, {
    int step = 1,
  }) async {
    final db = await _db;
    return await db.transaction<DhikrSession>((txn) async {
      final rows = await txn.query(
        'dhikr_sessions',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('Dhikr session $sessionId not found');
      }

      final current = DhikrSession.fromMap(rows.first);
      if (current.currentCount >= current.targetCount) {
        return current;
      }

      final nextCount = min(current.targetCount, current.currentCount + step);
      final isCompleted = nextCount >= current.targetCount;
      final now = DateTime.now();

      await txn.update(
        'dhikr_sessions',
        {
          'current_count': nextCount,
          'is_completed': isCompleted ? 1 : 0,
          'updated_at': now.toIso8601String(),
        },
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

      return current.copyWith(
        currentCount: nextCount,
        isCompleted: isCompleted,
        updatedAt: now,
      );
    });
  }

  Future<DhikrSession?> getDhikrSession(String sessionId) async {
    final db = await _db;
    final rows = await db.query(
      'dhikr_sessions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DhikrSession.fromMap(rows.first);
  }

  Future<List<DhikrSession>> getDhikrSessionsForDhikr(String dhikrId) async {
    final db = await _db;
    final rows = await db.query(
      'dhikr_sessions',
      where: 'dhikr_id = ?',
      whereArgs: [dhikrId],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => DhikrSession.fromMap(r)).toList();
  }

  Future<List<DhikrSession>> getDhikrSessionsForDate(String dateBucket) async {
    final db = await _db;
    final bareDate = dateBucket.contains('|')
        ? dateBucket.split('|').last
        : dateBucket;
    final rows = await db.query(
      'dhikr_sessions',
      where: 'date_bucket = ? OR date_bucket = ?',
      whereArgs: [dateBucket, bareDate],
      orderBy: 'created_at DESC',
    );
    return rows.map((r) => DhikrSession.fromMap(r)).toList();
  }

  // -------------------------------------------------------------
  // Daily Five-Task Progress & Configurable Quran Goal
  // -------------------------------------------------------------

  Future<DailyProgress> getDailyProgress(String dateBucket) async {
    final db = await _db;
    final bareDate = dateBucket.contains('|')
        ? dateBucket.split('|').last
        : dateBucket;
    final rows = await db.query(
      'daily_progress',
      where: 'date_bucket = ? OR date_bucket = ?',
      whereArgs: [dateBucket, bareDate],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      final prefs = await getPreferences();
      return DailyProgress(
        dateBucket: dateBucket,
        quranGoalPages: prefs.quranDefaultGoal,
      );
    }
    return DailyProgress.fromMap(rows.first);
  }

  Future<DailyProgress> updateDailyTask({
    required String dateBucket,
    bool? quranCompleted,
    bool? morningDhikrCompleted,
    bool? eveningDhikrCompleted,
    bool? postPrayerDhikrCompleted,
    bool? dailyDuaCompleted,
    int? quranGoalPages,
    int? quranPagesRead,
  }) async {
    final db = await _db;
    return await db.transaction<DailyProgress>((txn) async {
      final bareDate = dateBucket.contains('|')
          ? dateBucket.split('|').last
          : dateBucket;
      final rows = await txn.query(
        'daily_progress',
        where: 'date_bucket = ? OR date_bucket = ?',
        whereArgs: [dateBucket, bareDate],
        orderBy: 'updated_at DESC',
        limit: 1,
      );

      final DailyProgress current;
      if (rows.isEmpty) {
        final prefsRows = await txn.query(
          'user_preferences',
          where: 'id = 1',
          limit: 1,
        );
        final defaultGoal = prefsRows.isNotEmpty
            ? ((prefsRows.first['quran_default_goal'] as num?)?.toInt() ?? 2)
            : 2;

        current = DailyProgress(
          dateBucket: dateBucket,
          quranGoalPages: quranGoalPages ?? defaultGoal,
        );
      } else {
        current = DailyProgress.fromMap(rows.first);
      }

      final updated = current.copyWith(
        dateBucket: dateBucket,
        quranCompleted: quranCompleted ?? current.quranCompleted,
        morningDhikrCompleted:
            morningDhikrCompleted ?? current.morningDhikrCompleted,
        eveningDhikrCompleted:
            eveningDhikrCompleted ?? current.eveningDhikrCompleted,
        postPrayerDhikrCompleted:
            postPrayerDhikrCompleted ?? current.postPrayerDhikrCompleted,
        dailyDuaCompleted: dailyDuaCompleted ?? current.dailyDuaCompleted,
        quranGoalPages: quranGoalPages ?? current.quranGoalPages,
        quranPagesRead: quranPagesRead ?? current.quranPagesRead,
        updatedAt: DateTime.now(),
      );

      // If migrating from legacy bare date to qualified date bucket, remove legacy key
      if (rows.isNotEmpty && rows.first['date_bucket'] != dateBucket) {
        await txn.delete(
          'daily_progress',
          where: 'date_bucket = ?',
          whereArgs: [rows.first['date_bucket']],
        );
      }

      await txn.insert(
        'daily_progress',
        updated.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return updated;
    });
  }

  // -------------------------------------------------------------
  // User Preferences
  // -------------------------------------------------------------

  Future<UserPreferences> getPreferences() async {
    final db = await _db;
    final rows = await db.query('user_preferences', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      const initial = UserPreferences();
      await db.insert(
        'user_preferences',
        initial.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return initial;
    }
    return UserPreferences.fromMap(rows.first);
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    final db = await _db;
    await db.insert(
      'user_preferences',
      preferences.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // -------------------------------------------------------------
  // Reset Local State
  // -------------------------------------------------------------

  Future<void> resetLocalState() async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('reading_progress');
      await txn.delete('bookmarks');
      await txn.delete('favorites');
      await txn.delete('dhikr_sessions');
      await txn.delete('daily_progress');
      await txn.delete('user_preferences');

      final now = DateTime.now().toIso8601String();
      await txn.insert('reading_progress', {
        'id': 1,
        'last_page': 1,
        'selected_surah': null,
        'selected_verse': null,
        'updated_at': now,
      });

      await txn.insert('user_preferences', {
        'id': 1,
        'dark_mode': 'system',
        'text_scale': 1.0,
        'selected_city': 'القاهرة',
        'selected_timezone': 'Africa/Cairo',
        'quran_default_goal': 2,
        'notifications_enabled': 0,
        'active_dhikr_session_id': null,
        'updated_at': now,
      });
    });
  }

  Future<void> close() async {
    await _database.close();
  }
}
