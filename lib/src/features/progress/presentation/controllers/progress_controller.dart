import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../data/models/bookmark.dart';
import '../../data/models/daily_progress.dart';
import '../../data/models/dhikr_session.dart';
import '../../data/models/favorite.dart';
import '../../data/models/reading_progress.dart';
import '../../data/models/user_preferences.dart';
import '../../data/progress_repository.dart';

export '../../../../core/services/date_bucket_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() {
    db.close();
  });
  return db;
});

final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return ProgressRepository(database);
});

// Helper for collision-resistant dhikr session IDs
String generateSessionId({String prefix = 'dhikr'}) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  final rand = Random().nextInt(999999).toString().padLeft(6, '0');
  return '${prefix}_${micros}_$rand';
}

// -------------------------------------------------------------
// Reading Progress Controller
// -------------------------------------------------------------

final readingProgressControllerProvider =
    AsyncNotifierProvider<ReadingProgressController, ReadingProgress>(ReadingProgressController.new);

class ReadingProgressController extends AsyncNotifier<ReadingProgress> {
  @override
  Future<ReadingProgress> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getReadingProgress();
  }

  Future<void> savePage(int page, {int? surah, int? verse}) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(progressRepositoryProvider);
      final updated = ReadingProgress(
        lastPage: page,
        selectedSurah: surah,
        selectedVerse: verse,
        updatedAt: DateTime.now(),
      );
      await repo.saveReadingProgress(updated);
      state = AsyncValue.data(updated);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// User Preferences Controller
// -------------------------------------------------------------

final preferencesControllerProvider =
    AsyncNotifierProvider<PreferencesController, UserPreferences>(PreferencesController.new);

class PreferencesController extends AsyncNotifier<UserPreferences> {
  @override
  Future<UserPreferences> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getPreferences();
  }

  Future<void> updatePreferences(UserPreferences prefs) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.savePreferences(prefs);
      state = AsyncValue.data(prefs);
      // Refresh daily projections when goal changes
      ref.invalidate(dailyProgressControllerProvider);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> setDarkMode(String mode) async {
    final current = state.valueOrNull ?? const UserPreferences();
    await updatePreferences(current.copyWith(darkMode: mode));
  }

  Future<void> setTextScale(double scale) async {
    final current = state.valueOrNull ?? const UserPreferences();
    await updatePreferences(current.copyWith(textScale: scale));
  }

  Future<void> setCity(String city, String timezone) async {
    final current = state.valueOrNull ?? const UserPreferences();
    await updatePreferences(current.copyWith(
      selectedCity: city,
      selectedTimezone: timezone,
    ));
  }

  Future<void> setActiveDhikrSessionId(String? sessionId) async {
    final repo = ref.read(progressRepositoryProvider);
    if (sessionId != null) {
      await repo.setActiveDhikrSession(sessionId);
    } else {
      await repo.clearActiveDhikrSession();
    }
    final fresh = await repo.getPreferences();
    state = AsyncValue.data(fresh);
  }

  Future<void> resetAllState() async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.resetLocalState();

      // Invalidate all singleton and family providers so no stale cache persists
      ref.invalidate(readingProgressControllerProvider);
      ref.invalidate(bookmarksControllerProvider);
      ref.invalidate(favoritesControllerProvider);
      ref.invalidate(dailyProgressControllerProvider);
      ref.invalidate(dhikrSessionsControllerProvider);
      ref.invalidate(unfinishedDhikrSessionsProvider);

      final freshPrefs = await repo.getPreferences();
      state = AsyncValue.data(freshPrefs);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Daily Progress Controller
// -------------------------------------------------------------

final dailyProgressControllerProvider =
    AsyncNotifierProvider.family<DailyProgressController, DailyProgress, String>(DailyProgressController.new);

class DailyProgressController extends FamilyAsyncNotifier<DailyProgress, String> {
  @override
  Future<DailyProgress> build(String arg) async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getDailyProgress(arg);
  }

  Future<void> toggleTask({
    bool? quranCompleted,
    bool? morningDhikrCompleted,
    bool? eveningDhikrCompleted,
    bool? postPrayerDhikrCompleted,
    bool? dailyDuaCompleted,
    int? quranGoalPages,
    int? quranPagesRead,
  }) async {
    state = const AsyncValue.loading();
    try {
      final repo = ref.read(progressRepositoryProvider);
      final updated = await repo.updateDailyTask(
        dateBucket: arg,
        quranCompleted: quranCompleted,
        morningDhikrCompleted: morningDhikrCompleted,
        eveningDhikrCompleted: eveningDhikrCompleted,
        postPrayerDhikrCompleted: postPrayerDhikrCompleted,
        dailyDuaCompleted: dailyDuaCompleted,
        quranGoalPages: quranGoalPages,
        quranPagesRead: quranPagesRead,
      );
      state = AsyncValue.data(updated);
    } catch (err, stack) {
      state = AsyncValue.error(err, stack);
      rethrow;
    }
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Dhikr Sessions Controller & Unfinished Sessions Provider
// -------------------------------------------------------------

final unfinishedDhikrSessionsProvider = FutureProvider<List<DhikrSession>>((ref) async {
  final repo = ref.watch(progressRepositoryProvider);
  return repo.getUnfinishedDhikrSessions();
});

final dhikrSessionsControllerProvider =
    AsyncNotifierProvider.family<DhikrSessionsController, List<DhikrSession>, String>(DhikrSessionsController.new);

class DhikrSessionsController extends FamilyAsyncNotifier<List<DhikrSession>, String> {
  @override
  Future<List<DhikrSession>> build(String arg) async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getDhikrSessionsForDate(arg);
  }

  Future<DhikrSession> startSession({
    required String sessionId,
    required String dhikrId,
    required String category,
    required int targetCount,
  }) async {
    final repo = ref.read(progressRepositoryProvider);
    final session = await repo.startDhikrSession(
      sessionId: sessionId,
      dhikrId: dhikrId,
      category: category,
      targetCount: targetCount,
      dateBucket: arg,
    );
    ref.invalidateSelf();
    ref.invalidate(unfinishedDhikrSessionsProvider);
    ref.invalidate(preferencesControllerProvider);
    return session;
  }

  Future<DhikrSession> incrementSession(String sessionId, {int step = 1}) async {
    final repo = ref.read(progressRepositoryProvider);
    final updated = await repo.incrementDhikrSession(sessionId, step: step);
    ref.invalidateSelf();
    ref.invalidate(unfinishedDhikrSessionsProvider);
    return updated;
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Bookmarks Controller
// -------------------------------------------------------------

final bookmarksControllerProvider =
    AsyncNotifierProvider<BookmarksController, List<Bookmark>>(BookmarksController.new);

class BookmarksController extends AsyncNotifier<List<Bookmark>> {
  @override
  Future<List<Bookmark>> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getBookmarks();
  }

  Future<int> addBookmark({
    required String name,
    required int pageNumber,
    int? surahNumber,
    int? verseNumber,
  }) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      final id = await repo.createBookmark(
        name: name,
        pageNumber: pageNumber,
        surahNumber: surahNumber,
        verseNumber: verseNumber,
      );
      ref.invalidateSelf();
      return id;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.updateBookmark(bookmark);
      ref.invalidateSelf();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteBookmark(int id) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.deleteBookmark(id);
      ref.invalidateSelf();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Favorites Controller
// -------------------------------------------------------------

final favoritesControllerProvider =
    AsyncNotifierProvider<FavoritesController, List<Favorite>>(FavoritesController.new);

class FavoritesController extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getFavorites();
  }

  Future<void> toggleFavorite(Favorite favorite) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      final exists = await repo.isFavorite(favorite.contentKind, favorite.stableId);
      if (exists) {
        await repo.removeFavorite(favorite.contentKind, favorite.stableId);
      } else {
        await repo.addFavorite(favorite);
      }
      ref.invalidateSelf();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeFavorite(String kind, String stableId) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.removeFavorite(kind, stableId);
      ref.invalidateSelf();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}
