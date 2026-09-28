import 'dart:async';
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
import '../../../quran/data/sources/quran_asset_loader.dart';

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
  return ProgressRepository(
    database,
    versePageValidator:
        ({
          required int pageNumber,
          required int surahNumber,
          required int verseNumber,
        }) async {
          final quranRepo = await ref.read(quranRepositoryProvider.future);
          return quranRepo.isValidVerseOnPage(
            pageNumber: pageNumber,
            surahNumber: surahNumber,
            verseNumber: verseNumber,
          );
        },
  );
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
    AsyncNotifierProvider<ReadingProgressController, ReadingProgress>(
      ReadingProgressController.new,
    );

class _ReadingIntent {
  final int page;
  final int? surah;
  final int? verse;
  final bool isNavigation;
  final bool isClearStop;
  final bool isExactStop;

  const _ReadingIntent.navigation(this.page)
    : surah = null,
      verse = null,
      isNavigation = true,
      isClearStop = false,
      isExactStop = false;

  const _ReadingIntent.exactStop({
    required this.page,
    required this.surah,
    required this.verse,
  }) : isNavigation = false,
       isClearStop = false,
       isExactStop = true;

  const _ReadingIntent.clearStop(this.page)
    : surah = null,
      verse = null,
      isNavigation = false,
      isClearStop = true,
      isExactStop = false;

  ReadingProgress applyTo(ReadingProgress current) {
    if (isNavigation) {
      final int? preservedSurah = (current.lastPage == page)
          ? current.selectedSurah
          : null;
      final int? preservedVerse = (current.lastPage == page)
          ? current.selectedVerse
          : null;
      return ReadingProgress(
        lastPage: page,
        selectedSurah: preservedSurah,
        selectedVerse: preservedVerse,
        updatedAt: DateTime.now(),
      );
    } else if (isExactStop) {
      return ReadingProgress(
        lastPage: page,
        selectedSurah: surah,
        selectedVerse: verse,
        updatedAt: DateTime.now(),
      );
    } else if (isClearStop) {
      return ReadingProgress(
        lastPage: page,
        selectedSurah: null,
        selectedVerse: null,
        updatedAt: DateTime.now(),
      );
    }
    return current;
  }
}

class ReadingProgressController extends AsyncNotifier<ReadingProgress> {
  int _generation = 0;
  int _acceptedSeq = 0;
  int _latestAcceptedSeq = 0;
  Future<ReadingProgress>? _bootstrapFuture;
  Future<void> _writeChain = Future<void>.value();
  ReadingProgress? _latestIntended;
  _ReadingIntent? _latestIntent;
  bool _hasSaveError = false;
  bool _isResetting = false;

  bool get hasSaveError => _hasSaveError;
  bool get isResetting => _isResetting;
  ReadingProgress? get latestIntended => _latestIntended;

  Future<ReadingProgress> _ensureInitialized(ProgressRepository repo) {
    if (_bootstrapFuture != null) return _bootstrapFuture!;
    final int gen = _generation;
    _bootstrapFuture = () async {
      try {
        final quranRepo = await ref.read(quranRepositoryProvider.future);
        await repo.reconcileWithQuranMapping(
          getCanonicalPage: (s, v) => quranRepo.getVerse(s, v).pageNumber,
        );
        final persisted = await repo.getReadingProgress();
        if (_generation != gen) {
          throw StateError('Generation superseded by reset');
        }
        _latestIntended = persisted;
        return persisted;
      } catch (err) {
        _bootstrapFuture = null;
        rethrow;
      }
    }();
    return _bootstrapFuture!;
  }

  @override
  Future<ReadingProgress> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    final persisted = await _ensureInitialized(repo);
    return _latestIntended ?? persisted;
  }

  /// Internal enqueue helper that serializes mutations in FIFO order.
  /// Awaits unified bootstrap so initial navigation serializes correctly
  /// with database bootstrap without erasing existing stop verses.
  /// Gates new mutations while reset is in progress.
  Future<void> _enqueueIntent(_ReadingIntent intent, int seq) {
    if (_isResetting) {
      return Future.error(
        StateError(
          'Cannot accept reading navigation while reset is in progress',
        ),
      );
    }
    final completer = Completer<void>();
    final int gen = _generation;

    _writeChain = _writeChain.then(
      (_) async {
        if (_generation != gen || _isResetting) {
          if (!completer.isCompleted) {
            completer.completeError(StateError('Operation cancelled by reset'));
          }
          return;
        }
        try {
          final repo = ref.read(progressRepositoryProvider);

          // Validate exact-stop INSIDE queued turn BEFORE adopting _latestIntended
          if (intent.isExactStop) {
            final isValid = await repo.isValidVerseOnPage(
              pageNumber: intent.page,
              surahNumber: intent.surah!,
              verseNumber: intent.verse!,
            );
            if (!isValid) {
              throw ArgumentError(
                'Invalid verse ${intent.surah}:${intent.verse} for page ${intent.page}',
              );
            }
            // Adopt VALIDATED retry intent only if sequence not older than latest accepted VALID intent
            if (seq >= _latestAcceptedSeq) {
              _latestAcceptedSeq = seq;
              _latestIntent = intent;
            }
          }

          final initial = await _ensureInitialized(repo);
          if (_generation != gen || _isResetting) {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('Operation cancelled by reset'),
              );
            }
            return;
          }
          final current = _latestIntended ?? initial;
          final target = intent.applyTo(current);

          await _persistTarget(
            target: target,
            repo: repo,
            gen: gen,
            completer: completer,
          );
        } catch (err, stack) {
          // If this was a validation failure (ArgumentError), target was invalid.
          // If this was a persistence failure, target was valid and remains adopted for retry.
          _hasSaveError = true;
          state = AsyncValue.error(err, stack);
          if (!completer.isCompleted) completer.completeError(err, stack);
        }
      },
      onError: (_) {
        // Prevents previous failure from stalling the chain
      },
    );

    return completer.future;
  }

  Future<void> _persistTarget({
    required ReadingProgress target,
    required ProgressRepository repo,
    required int gen,
    required Completer<void> completer,
  }) async {
    // Validation of target stop verse if preserved from current
    if (target.selectedSurah != null && target.selectedVerse != null) {
      final isValid = await repo.isValidVerseOnPage(
        pageNumber: target.lastPage,
        surahNumber: target.selectedSurah!,
        verseNumber: target.selectedVerse!,
      );
      if (!isValid) {
        throw ArgumentError(
          'Invalid verse ${target.selectedSurah}:${target.selectedVerse} for page ${target.lastPage}',
        );
      }
    }

    // Adopt target so observers know this execution reached persistence
    _latestIntended = target;

    await repo.saveReadingProgress(target);

    if (_generation != gen || _isResetting) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Operation cancelled by reset'));
      }
      return;
    }
    _hasSaveError = false;
    state = AsyncValue.data(target);
    if (!completer.isCompleted) completer.complete();
  }

  /// Saves an accepted page navigation.
  /// If the destination is the SAME page as currently persisted/intended,
  /// preserves any existing explicit stop verse.
  /// If navigating to a DIFFERENT page, clears any stale stop verse.
  Future<void> savePageNavigation(int page) {
    if (page < 1 || page > 604) {
      throw ArgumentError.value(page, 'page', 'الصفحة يجب أن تكون بين ١ و ٦٠٤');
    }
    if (_isResetting) {
      return Future.error(
        StateError(
          'Cannot accept reading navigation while reset is in progress',
        ),
      );
    }
    final intent = _ReadingIntent.navigation(page);
    final seq = ++_acceptedSeq;
    if (seq >= _latestAcceptedSeq) {
      _latestAcceptedSeq = seq;
      _latestIntent = intent;
    }
    return _enqueueIntent(intent, seq);
  }

  /// Explicitly selects an exact stop verse on the current page.
  /// Reserves FIFO position synchronously and validates verse reference inside queued turn.
  Future<void> saveExactStopVerse({
    required int page,
    required int surah,
    required int verse,
  }) {
    if (page < 1 || page > 604) {
      throw ArgumentError.value(page, 'page', 'الصفحة يجب أن تكون بين ١ و ٦٠٤');
    }
    if (_isResetting) {
      return Future.error(
        StateError(
          'Cannot accept reading navigation while reset is in progress',
        ),
      );
    }
    final intent = _ReadingIntent.exactStop(
      page: page,
      surah: surah,
      verse: verse,
    );
    final seq = ++_acceptedSeq;
    return _enqueueIntent(intent, seq);
  }

  /// Explicitly clears the stop verse on the given page.
  Future<void> clearStopVerse(int page) {
    if (page < 1 || page > 604) {
      throw ArgumentError.value(page, 'page', 'الصفحة يجب أن تكون بين ١ و ٦٠٤');
    }
    if (_isResetting) {
      return Future.error(
        StateError(
          'Cannot accept reading navigation while reset is in progress',
        ),
      );
    }
    final intent = _ReadingIntent.clearStop(page);
    final seq = ++_acceptedSeq;
    if (seq >= _latestAcceptedSeq) {
      _latestAcceptedSeq = seq;
      _latestIntent = intent;
    }
    return _enqueueIntent(intent, seq);
  }

  /// Retries saving the CURRENT intended progress.
  /// Does not regress to a stale target if newer navigation succeeded.
  /// Retries initialization if bootstrap failed and saves the accepted destination.
  /// Resolves the valid retry target INSIDE its queued turn without advancing sequence.
  Future<void> retrySave() {
    if (_isResetting) {
      return Future.error(
        StateError('Cannot retry save while reset is in progress'),
      );
    }
    final completer = Completer<void>();
    final int gen = _generation;

    _writeChain = _writeChain.then(
      (_) async {
        if (_generation != gen || _isResetting) {
          if (!completer.isCompleted) {
            completer.completeError(StateError('Operation cancelled by reset'));
          }
          return;
        }
        try {
          final repo = ref.read(progressRepositoryProvider);
          final initial = await _ensureInitialized(repo);
          if (_generation != gen || _isResetting) {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('Operation cancelled by reset'),
              );
            }
            return;
          }

          final ReadingProgress target;
          if (_latestIntent != null) {
            final current = _latestIntended ?? initial;
            target = _latestIntent!.applyTo(current);
          } else if (_latestIntended != null) {
            target = _latestIntended!;
          } else {
            target = initial;
          }

          await _persistTarget(
            target: target,
            repo: repo,
            gen: gen,
            completer: completer,
          );
        } catch (err, stack) {
          _hasSaveError = true;
          state = AsyncValue.error(err, stack);
          if (!completer.isCompleted) completer.completeError(err, stack);
        }
      },
      onError: (_) {
        // Prevents previous failure from stalling the chain
      },
    );

    return completer.future;
  }

  /// Prior contract: page-only save CLEARS verse.
  /// Rejects exactly-one supplied ref.
  /// Validates page bounds.
  Future<void> savePage(int page, {int? surah, int? verse}) {
    if (page < 1 || page > 604) {
      throw ArgumentError.value(page, 'page', 'الصفحة يجب أن تكون بين ١ و ٦٠٤');
    }
    if ((surah == null) != (verse == null)) {
      throw ArgumentError(
        'surah and verse must both be specified or both null',
      );
    }
    if (surah != null && verse != null) {
      return saveExactStopVerse(page: page, surah: surah, verse: verse);
    } else {
      return clearStopVerse(page);
    }
  }

  Future<void> retry() async {
    _bootstrapFuture = null;
    ref.invalidateSelf();
  }

  /// Serializes reset on the SAME queue as reading mutations.
  /// Gates new reading intents during reset.
  Future<void> executeReset(Future<void> Function() performDbReset) {
    _isResetting = true;
    final completer = Completer<void>();
    ++_generation;

    _writeChain = _writeChain.then(
      (_) async {
        try {
          await performDbReset();

          _bootstrapFuture = null;
          _latestIntended = const ReadingProgress(lastPage: 1);
          _latestIntent = null;
          _latestAcceptedSeq = 0;
          _acceptedSeq = 0;
          _hasSaveError = false;
          _isResetting = false;

          state = const AsyncValue.data(ReadingProgress(lastPage: 1));
          if (!completer.isCompleted) completer.complete();
        } catch (err, stack) {
          _isResetting = false;
          _hasSaveError = true;
          state = AsyncValue.error(err, stack);
          if (!completer.isCompleted) completer.completeError(err, stack);
        }
      },
      onError: (_) async {
        try {
          await performDbReset();

          _bootstrapFuture = null;
          _latestIntended = const ReadingProgress(lastPage: 1);
          _latestIntent = null;
          _latestAcceptedSeq = 0;
          _acceptedSeq = 0;
          _hasSaveError = false;
          _isResetting = false;

          state = const AsyncValue.data(ReadingProgress(lastPage: 1));
          if (!completer.isCompleted) completer.complete();
        } catch (err, stack) {
          _isResetting = false;
          _hasSaveError = true;
          state = AsyncValue.error(err, stack);
          if (!completer.isCompleted) completer.completeError(err, stack);
        }
      },
    );
    return completer.future;
  }

  /// Drains any in-flight pending writes.
  Future<void> drainPendingWrites() async {
    try {
      await _writeChain;
    } catch (_) {}
  }

  /// Clears controller cache, intents, bootstrap, and advances generation.
  void prepareForReset() {
    _generation++;
    _bootstrapFuture = null;
    _latestIntended = null;
    _latestIntent = null;
    _latestAcceptedSeq = 0;
    _acceptedSeq = 0;
    _hasSaveError = false;
  }
}

// -------------------------------------------------------------
// User Preferences Controller
// -------------------------------------------------------------

final preferencesControllerProvider =
    AsyncNotifierProvider<PreferencesController, UserPreferences>(
      PreferencesController.new,
    );

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
    await updatePreferences(
      current.copyWith(selectedCity: city, selectedTimezone: timezone),
    );
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
      final readingController = ref.read(
        readingProgressControllerProvider.notifier,
      );

      // 1. Coordinate reset through reading controller queue to serialize with pending writes
      // and gate new reading mutations while reset is in progress.
      await readingController.executeReset(() => repo.resetLocalState());

      // 2. Invalidate other singleton and family providers so fresh state is loaded
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
    AsyncNotifierProvider.family<
      DailyProgressController,
      DailyProgress,
      String
    >(DailyProgressController.new);

class DailyProgressController
    extends FamilyAsyncNotifier<DailyProgress, String> {
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

final unfinishedDhikrSessionsProvider = FutureProvider<List<DhikrSession>>((
  ref,
) async {
  final repo = ref.watch(progressRepositoryProvider);
  return repo.getUnfinishedDhikrSessions();
});

final dhikrSessionsControllerProvider =
    AsyncNotifierProvider.family<
      DhikrSessionsController,
      List<DhikrSession>,
      String
    >(DhikrSessionsController.new);

class DhikrSessionsController
    extends FamilyAsyncNotifier<List<DhikrSession>, String> {
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

  Future<DhikrSession> incrementSession(
    String sessionId, {
    int step = 1,
  }) async {
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
    AsyncNotifierProvider<BookmarksController, List<Bookmark>>(
      BookmarksController.new,
    );

class BookmarksController extends AsyncNotifier<List<Bookmark>> {
  @override
  Future<List<Bookmark>> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    final quranRepo = await ref.read(quranRepositoryProvider.future);
    await repo.reconcileWithQuranMapping(
      getCanonicalPage: (s, v) => quranRepo.getVerse(s, v).pageNumber,
    );
    return repo.getBookmarks();
  }

  Future<int> addBookmark({
    required String name,
    required int pageNumber,
    int? surahNumber,
    int? verseNumber,
  }) async {
    if (pageNumber < 1 || pageNumber > 604) {
      throw ArgumentError.value(
        pageNumber,
        'pageNumber',
        'الصفحة يجب أن تكون بين ١ و ٦٠٤',
      );
    }
    try {
      final repo = ref.read(progressRepositoryProvider);
      final id = await repo.createBookmark(
        name: name,
        pageNumber: pageNumber,
        surahNumber: surahNumber,
        verseNumber: verseNumber,
      );
      final updated = await repo.getBookmarks();
      state = AsyncData(updated);
      return id;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.updateBookmark(bookmark);
      final updated = await repo.getBookmarks();
      state = AsyncData(updated);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteBookmark(int id) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      await repo.deleteBookmark(id);
      final updated = await repo.getBookmarks();
      state = AsyncData(updated);
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
    AsyncNotifierProvider<FavoritesController, List<Favorite>>(
      FavoritesController.new,
    );

class FavoritesController extends AsyncNotifier<List<Favorite>> {
  @override
  Future<List<Favorite>> build() async {
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getFavorites();
  }

  Future<void> toggleFavorite(Favorite favorite) async {
    try {
      final repo = ref.read(progressRepositoryProvider);
      final exists = await repo.isFavorite(
        favorite.contentKind,
        favorite.stableId,
      );
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
