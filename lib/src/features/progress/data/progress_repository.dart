import '../../hisn/domain/models/hisn_invocation_catalog.dart';
import 'dart:async';
import 'dart:math';
import 'package:adhan/adhan.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/date_bucket_service.dart';
import '../../hisn/domain/models/hisn_daily_catalog.dart';
import '../../prayer/domain/models/prayer_settings.dart';
import 'models/bookmark.dart';
import 'models/daily_progress.dart';
import 'models/daily_source_confirmation.dart';
import 'models/dhikr_session.dart';
import 'models/favorite.dart';
import 'models/hisn_daily_item_progress.dart';
import 'models/reading_progress.dart';
import 'models/user_preferences.dart';
import 'progress_mutation_barrier.dart';

typedef QuranVersePageValidator =
    FutureOr<bool> Function({
      required int pageNumber,
      required int surahNumber,
      required int verseNumber,
    });

class ProgressRepository {
  final AppDatabase _database;
  final ProgressMutationBarrier _barrier;
  QuranVersePageValidator? _versePageValidator;

  ProgressRepository(
    this._database, {
    ProgressMutationBarrier? mutationBarrier,
    QuranVersePageValidator? versePageValidator,
  }) : _barrier = mutationBarrier ?? ProgressMutationBarrier(),
       _versePageValidator = versePageValidator;

  ProgressMutationBarrier get mutationBarrier => _barrier;
  bool get isResetInProgress => _barrier.isResetInProgress;
  bool get isAudioStartAllowed => _barrier.isAudioStartAllowed;

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

  Future<void> close() async {
    await _database.close();
  }

  // -------------------------------------------------------------
  // Reading Progress (1..604, optional verse)
  // -------------------------------------------------------------

  Future<ReadingProgress> getReadingProgress() async {
    return _barrier.runTrackedMutation('getReadingProgress', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'getReadingProgress');

      final results = await db.query(
        'reading_progress',
        where: 'id = 1',
        limit: 1,
      );
      _barrier.checkGeneration(gen, 'getReadingProgress');

      if (results.isNotEmpty) {
        return ReadingProgress.fromMap(results.first);
      }

      if (_barrier.isResetInProgress) {
        return const ReadingProgress();
      }

      // Transactional insert-if-absent + requery to prevent races and stale overwrites
      await db.transaction((txn) async {
        _barrier.checkGeneration(gen, 'getReadingProgress');
        final current = await txn.query(
          'reading_progress',
          where: 'id = 1',
          limit: 1,
        );
        if (current.isEmpty) {
          _barrier.checkGeneration(gen, 'getReadingProgress');
          await txn.insert(
            'reading_progress',
            const ReadingProgress().toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });

      _barrier.checkGeneration(gen, 'getReadingProgress');
      final afterInsert = await db.query(
        'reading_progress',
        where: 'id = 1',
        limit: 1,
      );
      _barrier.checkGeneration(gen, 'getReadingProgress');
      if (afterInsert.isNotEmpty) {
        return ReadingProgress.fromMap(afterInsert.first);
      }
      return const ReadingProgress();
    });
  }

  Future<void> saveReadingProgress(ReadingProgress progress) async {
    return _barrier.runTrackedMutation('saveReadingProgress', (gen) async {
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
        _barrier.checkGeneration(gen, 'saveReadingProgress');
        if (!isValid) {
          throw ArgumentError(
            'Invalid verse ${progress.selectedSurah}:${progress.selectedVerse} for page ${progress.lastPage}',
          );
        }
      }
      final db = await _db;
      _barrier.checkGeneration(gen, 'saveReadingProgress');
      await db.insert(
        'reading_progress',
        progress.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
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
    return _barrier.runTrackedMutation('createBookmark', (gen) async {
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
        _barrier.checkGeneration(gen, 'createBookmark');
        if (!isValid) {
          throw ArgumentError(
            'Invalid verse $surahNumber:$verseNumber for page $pageNumber',
          );
        }
      }
      final db = await _db;
      _barrier.checkGeneration(gen, 'createBookmark');
      final bookmark = Bookmark(
        name: name,
        pageNumber: pageNumber,
        surahNumber: surahNumber,
        verseNumber: verseNumber,
        createdAt: DateTime.now(),
      );
      return await db.insert('bookmarks', bookmark.toMap());
    });
  }

  Future<List<Bookmark>> getBookmarks() async {
    final db = await _db;
    final results = await db.query('bookmarks', orderBy: 'id DESC');
    return results.map((m) => Bookmark.fromMap(m)).toList();
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    return _barrier.runTrackedMutation('updateBookmark', (gen) async {
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
        _barrier.checkGeneration(gen, 'updateBookmark');
        if (!isValid) {
          throw ArgumentError(
            'Invalid verse ${bookmark.surahNumber}:${bookmark.verseNumber} for page ${bookmark.pageNumber}',
          );
        }
      }
      final db = await _db;
      _barrier.checkGeneration(gen, 'updateBookmark');
      await db.update(
        'bookmarks',
        bookmark.toMap(),
        where: 'id = ?',
        whereArgs: [bookmark.id],
      );
    });
  }

  Future<void> deleteBookmark(int id) async {
    return _barrier.runTrackedMutation('deleteBookmark', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'deleteBookmark');
      await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void>? _reconciliationFuture;

  /// Reconciles stored reading progress and bookmarks with the canonical KFQC Quran page mapping.
  Future<void> reconcileWithQuranMapping({
    required int Function(int surahNumber, int verseNumber) getCanonicalPage,
  }) {
    if (_reconciliationFuture != null) return _reconciliationFuture!;
    _reconciliationFuture = _barrier.runTrackedMutation(
      'reconcileWithQuranMapping',
      (gen) async {
        try {
          final db = await _db;
          _barrier.checkGeneration(gen, 'reconcileWithQuranMapping');

          // 1. Reconcile Bookmarks with specific verse references
          final bookmarkRows = await db.query('bookmarks');
          for (final row in bookmarkRows) {
            final id = (row['id'] as num?)?.toInt();
            final surah = (row['surah_number'] as num?)?.toInt();
            final verse = (row['verse_number'] as num?)?.toInt();
            final currentPage = (row['page_number'] as num?)?.toInt() ?? 1;

            if (id != null && surah != null && verse != null) {
              final canonicalPage = getCanonicalPage(surah, verse);
              if (canonicalPage != currentPage &&
                  canonicalPage >= 1 &&
                  canonicalPage <= 604) {
                _barrier.checkGeneration(gen, 'reconcileWithQuranMapping');
                await db.update(
                  'bookmarks',
                  {'page_number': canonicalPage},
                  where: 'id = ?',
                  whereArgs: [id],
                );
              }
            }
          }

          // 2. Reconcile Reading Progress
          final progressRows = await db.query(
            'reading_progress',
            where: 'id = 1',
            limit: 1,
          );
          if (progressRows.isNotEmpty) {
            final row = progressRows.first;
            final surah = (row['selected_surah'] as num?)?.toInt();
            final verse = (row['selected_verse'] as num?)?.toInt();
            final currentPage = (row['last_page'] as num?)?.toInt() ?? 1;

            if (surah != null && verse != null) {
              final canonicalPage = getCanonicalPage(surah, verse);
              if (canonicalPage != currentPage &&
                  canonicalPage >= 1 &&
                  canonicalPage <= 604) {
                _barrier.checkGeneration(gen, 'reconcileWithQuranMapping');
                await db.update('reading_progress', {
                  'last_page': canonicalPage,
                }, where: 'id = 1');
              }
            }
          }
        } finally {
          _reconciliationFuture = null;
        }
      },
    );
    return _reconciliationFuture!;
  }

  // -------------------------------------------------------------
  // Favorites (Unique by content_kind & stable_id)
  // -------------------------------------------------------------

  Future<void> addFavorite(Favorite favorite) async {
    return _barrier.runTrackedMutation('addFavorite', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'addFavorite');
      await db.insert(
        'favorites',
        favorite.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> removeFavorite(String contentKind, String stableId) async {
    return _barrier.runTrackedMutation('removeFavorite', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'removeFavorite');
      await db.delete(
        'favorites',
        where: 'content_kind = ? AND stable_id = ?',
        whereArgs: [contentKind, stableId],
      );
    });
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
    return _barrier.runTrackedMutation('startDhikrSession', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'startDhikrSession');
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
        _barrier.checkGeneration(gen, 'startDhikrSession');
        await txn.insert(
          'dhikr_sessions',
          session.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        if (setActive) {
          _barrier.checkGeneration(gen, 'startDhikrSession');
          await txn.update('user_preferences', {
            'active_dhikr_session_id': sessionId,
            'updated_at': now.toIso8601String(),
          }, where: 'id = 1');
        }

        return session;
      });
    });
  }

  Future<void> setActiveDhikrSession(String? sessionId) async {
    return _barrier.runTrackedMutation('setActiveDhikrSession', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'setActiveDhikrSession');
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
      _barrier.checkGeneration(gen, 'setActiveDhikrSession');
      await db.update('user_preferences', {
        'active_dhikr_session_id': sessionId,
        'updated_at': DateTime.now().toIso8601String(),
      }, where: 'id = 1');
    });
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
    return _barrier.runTrackedMutation('incrementDhikrSession', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'incrementDhikrSession');
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

        _barrier.checkGeneration(gen, 'incrementDhikrSession');
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

    // 1. Exact match query first
    final exactRows = await db.query(
      'daily_progress',
      where: 'date_bucket = ?',
      whereArgs: [dateBucket],
      limit: 1,
    );

    // 2. Query source-based progress from v3 tables
    final morningItemRows = await db.query(
      'hisn_daily_item_progress',
      where: 'date_bucket = ? AND period = ? AND is_completed = 1',
      whereArgs: [dateBucket, DhikrPeriod.morning.key],
    );
    final morningCompletedCount = morningItemRows.length;

    final eveningItemRows = await db.query(
      'hisn_daily_item_progress',
      where: 'date_bucket = ? AND period = ? AND is_completed = 1',
      whereArgs: [dateBucket, DhikrPeriod.evening.key],
    );
    final eveningCompletedCount = eveningItemRows.length;

    final shared100Rows = await db.query(
      'hisn_daily_item_progress',
      where:
          'date_bucket = ? AND period = ? AND item_id = ? AND is_completed = 1',
      whereArgs: [
        dateBucket,
        DhikrPeriod.shared100.key,
        HisnDailyCatalog.sharedDaily100ItemId,
      ],
      limit: 1,
    );
    final shared100Completed = shared100Rows.isNotEmpty;

    final quranPageRows = await db.query(
      'daily_quran_pages',
      where: 'date_bucket = ?',
      whereArgs: [dateBucket],
    );
    final confirmedPages = quranPageRows
        .map((r) => (r['page_number'] as num).toInt())
        .toSet();

    final sourceConfRows = await db.query(
      'daily_source_confirmations',
      where: 'date_bucket = ?',
      whereArgs: [dateBucket],
    );
    bool? sourcePostPrayerCompleted;
    bool? sourceDailyDuaCompleted;
    int? dailyDuaItemId;
    for (final r in sourceConfRows) {
      final taskKey = r['task_key'] as String?;
      final isComp = (r['is_completed'] as num?)?.toInt() == 1;
      if (taskKey == DailySourceTasks.postPrayer) {
        sourcePostPrayerCompleted = isComp;
      } else if (taskKey == DailySourceTasks.dailyDua) {
        sourceDailyDuaCompleted = isComp;
        dailyDuaItemId = (r['hisn_item_id'] as num?)?.toInt();
      }
    }

    final prefs = await getPreferences();
    final defaultGoal = prefs.quranDefaultGoal;

    // 3. Fallback to bare date ONLY if exact row does not exist AND dateBucket is qualified
    Map<String, dynamic>? legacyRow;
    bool isLegacy = false;
    if (exactRows.isEmpty && dateBucket.contains('|')) {
      final bareDate = dateBucket.split('|').last;
      final bareRows = await db.query(
        'daily_progress',
        where: 'date_bucket = ?',
        whereArgs: [bareDate],
        limit: 1,
      );
      if (bareRows.isNotEmpty) {
        legacyRow = bareRows.first;
        isLegacy = true;
      }
    }

    final effectiveRow = exactRows.isNotEmpty ? exactRows.first : legacyRow;

    final int goalPages = effectiveRow != null
        ? ((effectiveRow['quran_goal_pages'] as num?)?.toInt() ?? defaultGoal)
        : defaultGoal;

    // Solely 22 / 20 source checks determine current morning/evening status.
    // Legacy booleans are NEVER used as current task completion; empty new dataset means ZERO/false.
    final bool morningCompleted =
        morningCompletedCount >= HisnDailyCatalog.morningTotalCount;

    final bool eveningCompleted =
        eveningCompletedCount >= HisnDailyCatalog.eveningTotalCount;

    // Quran completed is strictly derived from unique confirmed page IDs >= goal.
    final bool quranCompleted =
        confirmedPages.isNotEmpty && confirmedPages.length >= goalPages;

    final int pagesRead = confirmedPages.length;

    // Source confirmations derive from explicit self-report rows.
    final bool postPrayerCompleted = sourcePostPrayerCompleted ?? false;

    final bool dailyDuaCompleted = sourceDailyDuaCompleted ?? false;

    return DailyProgress(
      dateBucket: dateBucket,
      quranCompleted: quranCompleted,
      morningDhikrCompleted: morningCompleted,
      eveningDhikrCompleted: eveningCompleted,
      postPrayerDhikrCompleted: postPrayerCompleted,
      dailyDuaCompleted: dailyDuaCompleted,
      quranGoalPages: goalPages,
      quranPagesRead: pagesRead,
      confirmedPages: confirmedPages,
      morningCompletedCount: morningCompletedCount,
      eveningCompletedCount: eveningCompletedCount,
      shared100Completed: shared100Completed,
      dailyDuaItemId: dailyDuaItemId,
      isLegacyRecord: isLegacy,
      updatedAt: effectiveRow != null && effectiveRow['updated_at'] != null
          ? DateTime.tryParse(effectiveRow['updated_at'] as String)
          : null,
      legacyQuranCompleted: effectiveRow != null
          ? ((effectiveRow['quran_completed'] as num?)?.toInt() == 1)
          : null,
      legacyMorningDhikrCompleted: effectiveRow != null
          ? ((effectiveRow['morning_dhikr_completed'] as num?)?.toInt() == 1)
          : null,
      legacyEveningDhikrCompleted: effectiveRow != null
          ? ((effectiveRow['evening_dhikr_completed'] as num?)?.toInt() == 1)
          : null,
      legacyPostPrayerDhikrCompleted: effectiveRow != null
          ? ((effectiveRow['post_prayer_dhikr_completed'] as num?)?.toInt() ==
                1)
          : null,
      legacyDailyDuaCompleted: effectiveRow != null
          ? ((effectiveRow['daily_dua_completed'] as num?)?.toInt() == 1)
          : null,
      legacyQuranPagesRead: effectiveRow != null
          ? ((effectiveRow['quran_pages_read'] as num?)?.toInt() ?? 0)
          : null,
    );
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
    return _barrier.runTrackedMutation('updateDailyTask', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'updateDailyTask');
      return await db.transaction<DailyProgress>((txn) async {
        final exactRows = await txn.query(
          'daily_progress',
          where: 'date_bucket = ?',
          whereArgs: [dateBucket],
          limit: 1,
        );

        Map<String, dynamic>? fallbackRow;
        if (exactRows.isEmpty && dateBucket.contains('|')) {
          final bareDate = dateBucket.split('|').last;
          final bareRows = await txn.query(
            'daily_progress',
            where: 'date_bucket = ?',
            whereArgs: [bareDate],
            limit: 1,
          );
          if (bareRows.isNotEmpty) {
            fallbackRow = bareRows.first;
          }
        }

        final sourceRow = exactRows.isNotEmpty ? exactRows.first : fallbackRow;

        final DailyProgress current;
        if (sourceRow == null) {
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
          current = DailyProgress.fromMap(sourceRow);
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

        // NOTICE: We do NOT delete any bare-date rows.
        // Qualified exact-key state must never delete or destroy legacy records.
        _barrier.checkGeneration(gen, 'updateDailyTask');
        await txn.insert(
          'daily_progress',
          updated.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        return updated;
      });
    });
  }

  // -------------------------------------------------------------
  // Hisn Daily Checklist (Morning 22 / Evening 20 / Shared 100)
  // -------------------------------------------------------------

  Future<List<HisnDailyItemProgress>> getHisnDailyItemProgress(
    String dateBucket,
    DhikrPeriod period,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'hisn_daily_item_progress',
      where: 'date_bucket = ? AND period = ?',
      whereArgs: [dateBucket, period.key],
      orderBy: 'item_id ASC',
    );
    return rows.map((r) => HisnDailyItemProgress.fromMap(r)).toList();
  }

  Future<HisnDailyItemProgress> setHisnDailyItemProgress({
    required String dateBucket,
    required DhikrPeriod period,
    required int itemId,
    required bool isCompleted,
  }) async {
    return _barrier.runTrackedMutation('setHisnDailyItemProgress', (gen) async {
      if (!isValidQualifiedDateBucket(dateBucket)) {
        throw ArgumentError.value(
          dateBucket,
          'dateBucket',
          'Must be a valid qualified date bucket format: <IANA>|<YYYY-MM-DD>',
        );
      }
      if (!HisnDailyCatalog.isValidPeriodItem(period, itemId)) {
        throw ArgumentError(
          'Item ID $itemId is not valid for period ${period.key}',
        );
      }
      if (itemId < 1 || itemId > 267) {
        throw ArgumentError.value(
          itemId,
          'itemId',
          'Item ID must be between 1 and 267',
        );
      }

      final db = await _db;
      _barrier.checkGeneration(gen, 'setHisnDailyItemProgress');
      final now = DateTime.now();
      final progress = HisnDailyItemProgress(
        dateBucket: dateBucket,
        period: period,
        itemId: itemId,
        isCompleted: isCompleted,
        updatedAt: now,
      );

      await db.insert(
        'hisn_daily_item_progress',
        progress.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return progress;
    });
  }

  // -------------------------------------------------------------
  // Daily Quran Confirmed Pages (1..604)
  // -------------------------------------------------------------

  Future<Set<int>> getConfirmedQuranPages(String dateBucket) async {
    final db = await _db;
    final rows = await db.query(
      'daily_quran_pages',
      where: 'date_bucket = ?',
      whereArgs: [dateBucket],
    );
    return rows.map((r) => (r['page_number'] as num).toInt()).toSet();
  }

  Future<void> confirmQuranPage({
    required String dateBucket,
    required int pageNumber,
  }) async {
    return _barrier.runTrackedMutation('confirmQuranPage', (gen) async {
      if (!isValidQualifiedDateBucket(dateBucket)) {
        throw ArgumentError.value(
          dateBucket,
          'dateBucket',
          'Must be a valid qualified date bucket format: <IANA>|<YYYY-MM-DD>',
        );
      }
      if (pageNumber < 1 || pageNumber > 604) {
        throw ArgumentError.value(
          pageNumber,
          'pageNumber',
          'Page number must be between 1 and 604',
        );
      }

      final db = await _db;
      _barrier.checkGeneration(gen, 'confirmQuranPage');
      await db.transaction((txn) async {
        _barrier.checkGeneration(gen, 'confirmQuranPage');
        final existing = await txn.query('daily_quran_pages',
          where: 'date_bucket = ? AND page_number = ?', whereArgs: [dateBucket, pageNumber], limit: 1);
        if (existing.isNotEmpty) return;
        await txn.insert('daily_quran_pages', <String, dynamic>{
          'date_bucket': dateBucket,
          'page_number': pageNumber,
          'confirmed_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        _barrier.checkGeneration(gen, 'confirmQuranPage');
        await txn.update('reading_progress', {'resume_page': (pageNumber + 1).clamp(1, 604)},
          where: 'id = 1 AND last_page = ?', whereArgs: [pageNumber]);
      });
    });
  }

  Future<void> undoQuranPage({
    required String dateBucket,
    required int pageNumber,
  }) async {
    return _barrier.runTrackedMutation('undoQuranPage', (gen) async {
      if (!isValidQualifiedDateBucket(dateBucket)) {
        throw ArgumentError.value(
          dateBucket,
          'dateBucket',
          'Must be a valid qualified date bucket format: <IANA>|<YYYY-MM-DD>',
        );
      }
      if (pageNumber < 1 || pageNumber > 604) {
        throw ArgumentError.value(
          pageNumber,
          'pageNumber',
          'Page number must be between 1 and 604',
        );
      }
      final db = await _db;
      _barrier.checkGeneration(gen, 'undoQuranPage');
      await db.delete(
        'daily_quran_pages',
        where: 'date_bucket = ? AND page_number = ?',
        whereArgs: [dateBucket, pageNumber],
      );
    });
  }

  // -------------------------------------------------------------
  // Daily Source-Linked Confirmations (Daily Dua & Post-Prayer)
  // -------------------------------------------------------------

  Future<DailySourceConfirmation?> getSourceConfirmation(
    String dateBucket,
    String taskKey,
  ) async {
    final db = await _db;
    final rows = await db.query(
      'daily_source_confirmations',
      where: 'date_bucket = ? AND task_key = ?',
      whereArgs: [dateBucket, taskKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DailySourceConfirmation.fromMap(rows.first);
  }

  Future<DailySourceConfirmation> setSourceConfirmation({
    required String dateBucket,
    required String taskKey,
    int? hisnItemId,
    required bool isCompleted,
  }) async {
    return _barrier.runTrackedMutation('setSourceConfirmation', (gen) async {
      if (!isValidQualifiedDateBucket(dateBucket)) {
        throw ArgumentError.value(
          dateBucket,
          'dateBucket',
          'Must be a valid qualified date bucket format: <IANA>|<YYYY-MM-DD>',
        );
      }
      if (taskKey != DailySourceTasks.dailyDua &&
          taskKey != DailySourceTasks.postPrayer) {
        throw ArgumentError.value(taskKey, 'taskKey', 'Invalid taskKey');
      }

      if (taskKey == DailySourceTasks.dailyDua) {
        if (isCompleted && hisnItemId == null) {
          throw ArgumentError(
            'Daily dua requires a valid chosen Hisn item ID (1..267) when confirmed',
          );
        }
        if (hisnItemId != null && !HisnInvocationCatalog.contains(hisnItemId)) {
          throw ArgumentError.value(
            hisnItemId,
            'hisnItemId',
            'Daily dua requires an item from the Hisn invocation catalog',
          );
        }
      }

      if (taskKey == DailySourceTasks.postPrayer) {
        if (hisnItemId != null &&
            !HisnDailyCatalog.postPrayerItemIds.contains(hisnItemId)) {
          throw ArgumentError.value(
            hisnItemId,
            'hisnItemId',
            'Post-prayer item ID must belong to Chapter 25 (66..73)',
          );
        }
      }

      final db = await _db;
      _barrier.checkGeneration(gen, 'setSourceConfirmation');
      final now = DateTime.now();
      final confirmation = DailySourceConfirmation(
        dateBucket: dateBucket,
        taskKey: taskKey,
        hisnItemId: hisnItemId,
        isCompleted: isCompleted,
        updatedAt: now,
      );

      await db.insert(
        'daily_source_confirmations',
        confirmation.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return confirmation;
    });
  }

  // -------------------------------------------------------------
  // User Preferences
  // -------------------------------------------------------------

  Future<UserPreferences> getPreferences() async {
    return _barrier.runTrackedMutation('getPreferences', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'getPreferences');

      final rows = await db.query(
        'user_preferences',
        where: 'id = 1',
        limit: 1,
      );
      _barrier.checkGeneration(gen, 'getPreferences');

      if (rows.isNotEmpty) {
        return UserPreferences.fromMap(rows.first);
      }

      if (_barrier.isResetInProgress) {
        return const UserPreferences();
      }

      // Transactional insert-if-absent + requery
      await db.transaction((txn) async {
        _barrier.checkGeneration(gen, 'getPreferences');
        final current = await txn.query(
          'user_preferences',
          where: 'id = 1',
          limit: 1,
        );
        if (current.isEmpty) {
          _barrier.checkGeneration(gen, 'getPreferences');
          await txn.insert(
            'user_preferences',
            const UserPreferences().toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      });

      _barrier.checkGeneration(gen, 'getPreferences');
      final afterInsert = await db.query(
        'user_preferences',
        where: 'id = 1',
        limit: 1,
      );
      _barrier.checkGeneration(gen, 'getPreferences');
      if (afterInsert.isNotEmpty) {
        return UserPreferences.fromMap(afterInsert.first);
      }
      return const UserPreferences();
    });
  }

  Future<void> savePreferences(UserPreferences preferences) async {
    return _barrier.runTrackedMutation('savePreferences', (gen) async {
      final db = await _db;
      _barrier.checkGeneration(gen, 'savePreferences');
      await db.insert(
        'user_preferences',
        preferences.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

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
    return _barrier.runTrackedMutation('updatePreferencesFields', (gen) async {
      if (quranDefaultGoal != null &&
          (quranDefaultGoal < 1 || quranDefaultGoal > 604)) {
        throw ArgumentError.value(
          quranDefaultGoal,
          'quranDefaultGoal',
          'Goal must be between 1 and 604',
        );
      }
      if (generalAdhanVoice != null &&
          !UserPreferences.allowedGeneralAdhanVoices.contains(
            generalAdhanVoice,
          )) {
        throw ArgumentError.value(
          generalAdhanVoice,
          'generalAdhanVoice',
          'Invalid general adhan voice ID: must be adam or atcovi',
        );
      }
      if (fajrAdhanVoice != null &&
          !UserPreferences.allowedFajrAdhanVoices.contains(fajrAdhanVoice)) {
        throw ArgumentError.value(
          fajrAdhanVoice,
          'fajrAdhanVoice',
          'Invalid Fajr adhan voice ID: must be adam, atcovi, or malmo_fajr',
        );
      }
      if (hijriDayAdjustment != null &&
          (hijriDayAdjustment < -2 || hijriDayAdjustment > 2)) {
        throw ArgumentError.value(
          hijriDayAdjustment,
          'hijriDayAdjustment',
          'Hijri day adjustment must be between -2 and 2 days',
        );
      }
      void validateOffset(int? offset, String name) {
        if (offset != null && (offset < -120 || offset > 120)) {
          throw ArgumentError.value(
            offset,
            name,
            'Minute offset must be between -120 and 120 minutes',
          );
        }
      }

      validateOffset(fajrOffset, 'fajrOffset');
      validateOffset(sunriseOffset, 'sunriseOffset');
      validateOffset(dhuhrOffset, 'dhuhrOffset');
      validateOffset(asrOffset, 'asrOffset');
      validateOffset(maghribOffset, 'maghribOffset');
      validateOffset(ishaOffset, 'ishaOffset');

      if (!identical(calculationMethodOverride, kPreferenceSentinel) &&
          calculationMethodOverride != null) {
        final method = calculationMethodOverride as CalculationMethod;
        if (!PrayerSettings.supportedMethods.contains(method)) {
          throw ArgumentError.value(
            method,
            'calculationMethodOverride',
            'Unsupported prayer calculation method',
          );
        }
      }

      final db = await _db;
      _barrier.checkGeneration(gen, 'updatePreferencesFields');
      return await db.transaction<UserPreferences>((txn) async {
        final rows = await txn.query(
          'user_preferences',
          where: 'id = 1',
          limit: 1,
        );
        if (rows.isEmpty) {
          final resolvedCityId = clearSelectedCityId
              ? null
              : (!identical(selectedCityId, kPreferenceSentinel)
                    ? selectedCityId as int?
                    : UserPreferences.defaultSelectedCityId);
          final resolvedCalcMethod = clearCalculationMethodOverride
              ? null
              : (!identical(calculationMethodOverride, kPreferenceSentinel)
                    ? calculationMethodOverride as CalculationMethod?
                    : null);
          final initial = UserPreferences(
            darkMode: darkMode ?? 'system',
            textScale: textScale ?? 1.0,
            selectedCityId: resolvedCityId,
            selectedCity: selectedCity ?? 'القاهرة',
            selectedTimezone: selectedTimezone ?? 'Africa/Cairo',
            calculationMethodOverride: resolvedCalcMethod,
            asrMadhab: asrMadhab ?? Madhab.shafi,
            highLatitudeRule:
                highLatitudeRule ?? HighLatitudeRule.middle_of_the_night,
            polarResolution: polarResolution ?? PolarDayResolution.unresolved,
            ramadanPolicy:
                ramadanPolicy ?? UmmAlQuraRamadanPolicy.eveningOfRamadan,
            hijriDayAdjustment: hijriDayAdjustment ?? 0,
            fajrOffset: fajrOffset ?? 0,
            sunriseOffset: sunriseOffset ?? 0,
            dhuhrOffset: dhuhrOffset ?? 0,
            asrOffset: asrOffset ?? 0,
            maghribOffset: maghribOffset ?? 0,
            ishaOffset: ishaOffset ?? 0,
            quranDefaultGoal: quranDefaultGoal ?? 2,
            notificationsEnabled: notificationsEnabled ?? false,
            generalAdhanVoice:
                generalAdhanVoice ?? UserPreferences.defaultGeneralAdhanVoice,
            fajrAdhanVoice:
                fajrAdhanVoice ?? UserPreferences.defaultFajrAdhanVoice,
            updatedAt: DateTime.now(),
          );
          _barrier.checkGeneration(gen, 'updatePreferencesFields');
          await txn.insert('user_preferences', initial.toMap());
          return initial;
        }

        final updateMap = <String, dynamic>{
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (darkMode != null) updateMap['dark_mode'] = darkMode;
        if (textScale != null) updateMap['text_scale'] = textScale;
        if (clearSelectedCityId) {
          updateMap['selected_city_id'] = null;
        } else if (!identical(selectedCityId, kPreferenceSentinel)) {
          updateMap['selected_city_id'] = selectedCityId as int?;
        }
        if (selectedCity != null) updateMap['selected_city'] = selectedCity;
        if (selectedTimezone != null) {
          updateMap['selected_timezone'] = selectedTimezone;
        }
        if (clearCalculationMethodOverride) {
          updateMap['calculation_method'] = null;
        } else if (!identical(calculationMethodOverride, kPreferenceSentinel)) {
          updateMap['calculation_method'] =
              (calculationMethodOverride as CalculationMethod?)?.name;
        }
        if (asrMadhab != null) updateMap['asr_madhab'] = asrMadhab.name;
        if (highLatitudeRule != null) {
          updateMap['high_latitude_rule'] = highLatitudeRule.name;
        }
        if (polarResolution != null) {
          updateMap['polar_resolution'] = polarResolution.name;
        }
        if (ramadanPolicy != null) {
          updateMap['ramadan_policy'] = ramadanPolicy.name;
        }
        if (hijriDayAdjustment != null) {
          updateMap['hijri_day_adjustment'] = hijriDayAdjustment;
        }
        if (fajrOffset != null) updateMap['fajr_offset'] = fajrOffset;
        if (sunriseOffset != null) updateMap['sunrise_offset'] = sunriseOffset;
        if (dhuhrOffset != null) updateMap['dhuhr_offset'] = dhuhrOffset;
        if (asrOffset != null) updateMap['asr_offset'] = asrOffset;
        if (maghribOffset != null) updateMap['maghrib_offset'] = maghribOffset;
        if (ishaOffset != null) updateMap['isha_offset'] = ishaOffset;
        if (quranDefaultGoal != null) {
          updateMap['quran_default_goal'] = quranDefaultGoal;
        }
        if (notificationsEnabled != null) {
          updateMap['notifications_enabled'] = notificationsEnabled ? 1 : 0;
        }
        if (generalAdhanVoice != null) {
          updateMap['general_adhan_voice'] = generalAdhanVoice;
        }
        if (fajrAdhanVoice != null) {
          updateMap['fajr_adhan_voice'] = fajrAdhanVoice;
        }
        if (clearActiveDhikrSession) {
          updateMap['active_dhikr_session_id'] = null;
        } else if (!identical(activeDhikrSessionId, kPreferenceSentinel)) {
          updateMap['active_dhikr_session_id'] =
              activeDhikrSessionId as String?;
        }

        _barrier.checkGeneration(gen, 'updatePreferencesFields');
        await txn.update('user_preferences', updateMap, where: 'id = 1');

        final updatedRows = await txn.query(
          'user_preferences',
          where: 'id = 1',
          limit: 1,
        );
        return UserPreferences.fromMap(updatedRows.first);
      });
    });
  }

  // -------------------------------------------------------------
  // Full Local Reset (Single transaction across all 9 tables)
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
      await txn.delete('hisn_daily_item_progress');
      await txn.delete('daily_quran_pages');
      await txn.delete('daily_source_confirmations');

      final now = DateTime.now().toIso8601String();
      await txn.insert('reading_progress', <String, dynamic>{
        'id': 1,
        'last_page': 1,
        'updated_at': now,
      });

      await txn.insert('user_preferences', <String, dynamic>{
        'id': 1,
        'dark_mode': 'system',
        'text_scale': 1.0,
        'selected_city_id': UserPreferences.defaultSelectedCityId,
        'selected_city': 'القاهرة',
        'selected_timezone': 'Africa/Cairo',
        'calculation_method': null,
        'asr_madhab': 'shafi',
        'high_latitude_rule': 'middle_of_the_night',
        'polar_resolution': 'unresolved',
        'ramadan_policy': 'eveningOfRamadan',
        'hijri_day_adjustment': 0,
        'fajr_offset': 0,
        'sunrise_offset': 0,
        'dhuhr_offset': 0,
        'asr_offset': 0,
        'maghrib_offset': 0,
        'isha_offset': 0,
        'quran_default_goal': 2,
        'notifications_enabled': 0,
        'active_dhikr_session_id': null,
        'general_adhan_voice': UserPreferences.defaultGeneralAdhanVoice,
        'fajr_adhan_voice': UserPreferences.defaultFajrAdhanVoice,
        'updated_at': now,
      });
    });
  }
}
