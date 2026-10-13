import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:adhan/adhan.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/native_alarm_reset_boundary.dart';
import '../../../hisn/domain/models/hisn_daily_catalog.dart';
import '../../../prayer/domain/models/prayer_settings.dart';
import '../../../prayer/domain/models/selected_city.dart';
import '../../data/models/bookmark.dart';
import '../../data/models/daily_progress.dart';
import '../../data/models/daily_source_confirmation.dart';
import '../../data/models/dhikr_session.dart';
import '../../data/models/favorite.dart';
import '../../data/models/hisn_daily_item_progress.dart';
import '../../data/models/reading_progress.dart';
import '../../data/models/user_preferences.dart';
import '../../data/progress_mutation_barrier.dart';
import '../../data/progress_repository.dart';
import '../../../prayers/presentation/controllers/adhan_audio_controller.dart';
import '../../../quran/data/sources/quran_asset_loader.dart';

export '../../../../core/services/date_bucket_service.dart';
export '../../data/progress_mutation_barrier.dart';

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

/// Exposes the central mutation barrier fencing writes during reset.
final resetBarrierProvider = ChangeNotifierProvider<ProgressMutationBarrier>((ref) {
  return ref.watch(progressRepositoryProvider).mutationBarrier;
});

/// Exposes whether a reset operation is currently in progress.
final isResetInProgressProvider = Provider<bool>((ref) {
  return ref.watch(resetBarrierProvider).isResetInProgress;
});

/// Exposes whether media playback start is currently allowed.
final isAudioStartAllowedProvider = Provider<bool>((ref) {
  return ref.watch(resetBarrierProvider).isAudioStartAllowed;
});

// -------------------------------------------------------------
// Reading Progress Controller
// -------------------------------------------------------------

final readingProgressControllerProvider =
    AsyncNotifierProvider<ReadingProgressController, ReadingProgress>(
      ReadingProgressController.new,
    );

enum _ReadingIntentKind { navigation, exactStop, clearStop }

class _ReadingIntent {
  final _ReadingIntentKind kind;
  final int page;
  final int? surah;
  final int? verse;

  const _ReadingIntent._({
    required this.kind,
    required this.page,
    this.surah,
    this.verse,
  });

  factory _ReadingIntent.navigation(int page) =>
      _ReadingIntent._(kind: _ReadingIntentKind.navigation, page: page);

  factory _ReadingIntent.exactStop({
    required int page,
    required int surah,
    required int verse,
  }) => _ReadingIntent._(
    kind: _ReadingIntentKind.exactStop,
    page: page,
    surah: surah,
    verse: verse,
  );

  factory _ReadingIntent.clearStop(int page) =>
      _ReadingIntent._(kind: _ReadingIntentKind.clearStop, page: page);

  bool get isExactStop => kind == _ReadingIntentKind.exactStop;

  ReadingProgress applyTo(ReadingProgress current) {
    switch (kind) {
      case _ReadingIntentKind.navigation:
        if (current.lastPage == page && current.nextResumePage == null) {
          return current;
        }
        return ReadingProgress(
          lastPage: page,
          selectedSurah: current.lastPage == page ? current.selectedSurah : null,
          selectedVerse: current.lastPage == page ? current.selectedVerse : null,
          updatedAt: DateTime.now(),
        );
      case _ReadingIntentKind.exactStop:
        return ReadingProgress(
          lastPage: page,
          selectedSurah: surah,
          selectedVerse: verse,
          updatedAt: DateTime.now(),
        );
      case _ReadingIntentKind.clearStop:
        return ReadingProgress(
          lastPage: page,
          selectedSurah: null,
          selectedVerse: null,
          updatedAt: DateTime.now(),
        );
    }
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

  Future<void> reloadPersistedResume() async {
    final generation = _generation;
    final acceptedSeq = _acceptedSeq;
    await drainPendingWrites();
    final progress = await ref.read(progressRepositoryProvider).getReadingProgress();
    if (_generation != generation ||
        _isResetting ||
        _acceptedSeq != acceptedSeq) {
      return;
    }
    _latestIntended = progress;
    _bootstrapFuture = Future.value(progress);
    state = AsyncData(progress);
  }

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
          _hasSaveError = true;
          state = AsyncValue.error(err, stack);
          if (!completer.isCompleted) completer.completeError(err, stack);
        }
      },
      onError: (_) {},
    );

    return completer.future;
  }

  Future<void> _persistTarget({
    required ReadingProgress target,
    required ProgressRepository repo,
    required int gen,
    required Completer<void> completer,
  }) async {
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
      onError: (_) {},
    );

    return completer.future;
  }

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

  Future<void> drainPendingWrites() async {
    try {
      await _writeChain;
    } catch (_) {}
  }

  void prepareForReset() {
    _generation++;
    _bootstrapFuture = null;
    _latestIntended = null;
    _latestIntent = null;
    _latestAcceptedSeq = 0;
    _acceptedSeq = 0;
    _hasSaveError = false;
    _isResetting = true;
  }

  void cancelReset() {
    _isResetting = false;
  }

  void finishReset() {
    _bootstrapFuture = null;
    _latestIntended = const ReadingProgress(lastPage: 1);
    _latestIntent = null;
    _latestAcceptedSeq = 0;
    _acceptedSeq = 0;
    _hasSaveError = false;
    _isResetting = false;
    state = const AsyncValue.data(ReadingProgress(lastPage: 1));
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
  Future<void> _writeQueue = Future<void>.value();
  int _instanceEpoch = 0;
  bool _isDisposed = false;

  @override
  Future<UserPreferences> build() async {
    _instanceEpoch++;
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    final repo = ref.watch(progressRepositoryProvider);
    return repo.getPreferences();
  }

  Future<UserPreferences> _mutateFields({
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
  }) {
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('updatePreferencesFields');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int capturedEpoch = _instanceEpoch;
    final completer = Completer<UserPreferences>();

    Future<void> executeIntent() async {
      if (_isDisposed || _instanceEpoch != capturedEpoch) {
        completer.completeError(
          StateError('Controller was disposed or rebuilt prior to execution'),
        );
        return;
      }
      if (repo.mutationBarrier.isResetInProgress ||
          repo.mutationBarrier.currentGeneration != capturedGen) {
        completer.completeError(
          StateError(
            'Operation cancelled by reset: generation mismatch ($capturedGen vs ${repo.mutationBarrier.currentGeneration})',
          ),
        );
        return;
      }
      try {
        final updated = await repo.updatePreferencesFields(
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
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.complete(updated);
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset after persistence'),
          );
          return;
        }
        state = AsyncValue.data(updated);
        if (quranDefaultGoal != null) {
          ref.invalidate(dailyProgressControllerProvider);
        }
        completer.complete(updated);
      } catch (err, stack) {
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.completeError(err, stack);
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset: generation mismatch'),
          );
          return;
        }
        state = AsyncValue.error(err, stack);
        completer.completeError(err, stack);
      }
    }

    _writeQueue = _writeQueue.then(
      (_) => executeIntent(),
      onError: (_) => executeIntent(),
    );

    return completer.future;
  }

  @visibleForTesting
  Future<void> updatePreferences(UserPreferences prefs) async {
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('updatePreferences');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int capturedEpoch = _instanceEpoch;
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      if (_isDisposed || _instanceEpoch != capturedEpoch) {
        completer.completeError(
          StateError('Controller was disposed or rebuilt prior to execution'),
        );
        return;
      }
      if (repo.mutationBarrier.isResetInProgress ||
          repo.mutationBarrier.currentGeneration != capturedGen) {
        completer.completeError(
          StateError(
            'Operation cancelled by reset: generation mismatch ($capturedGen vs ${repo.mutationBarrier.currentGeneration})',
          ),
        );
        return;
      }
      try {
        await repo.savePreferences(prefs);
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.complete();
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset after persistence'),
          );
          return;
        }
        state = AsyncValue.data(prefs);
        ref.invalidate(dailyProgressControllerProvider);
        completer.complete();
      } catch (err, stack) {
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.completeError(err, stack);
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset: generation mismatch'),
          );
          return;
        }
        state = AsyncValue.error(err, stack);
        completer.completeError(err, stack);
      }
    }, onError: (_) async {
      if (_isDisposed || _instanceEpoch != capturedEpoch) {
        completer.completeError(
          StateError('Controller was disposed or rebuilt prior to execution'),
        );
        return;
      }
      if (repo.mutationBarrier.isResetInProgress ||
          repo.mutationBarrier.currentGeneration != capturedGen) {
        completer.completeError(
          StateError(
            'Operation cancelled by reset: generation mismatch ($capturedGen vs ${repo.mutationBarrier.currentGeneration})',
          ),
        );
        return;
      }
      try {
        await repo.savePreferences(prefs);
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.complete();
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset after persistence'),
          );
          return;
        }
        state = AsyncValue.data(prefs);
        ref.invalidate(dailyProgressControllerProvider);
        completer.complete();
      } catch (err, stack) {
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.completeError(err, stack);
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset: generation mismatch'),
          );
          return;
        }
        state = AsyncValue.error(err, stack);
        completer.completeError(err, stack);
      }
    });
    return completer.future;
  }

  Future<void> setDarkMode(String mode) async {
    await _mutateFields(darkMode: mode);
  }

  Future<void> setTextScale(double scale) async {
    await _mutateFields(textScale: scale);
  }

  Future<void> setCity(dynamic cityOrName, [String? timezone, int? cityId]) async {
    if (cityOrName is SelectedCity) {
      await setSelectedCity(cityOrName);
    } else {
      final String name = cityOrName as String;
      final String tz = timezone ?? 'Africa/Cairo';
      int? resolvedId = cityId;
      if (resolvedId == null) {
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
        resolvedId = legacyMap['$name|$tz'];
      }
      await _mutateFields(
        selectedCity: name,
        selectedTimezone: tz,
        selectedCityId: resolvedId ?? kPreferenceSentinel,
      );
    }
  }

  Future<void> setSelectedCity(SelectedCity city) async {
    await _mutateFields(
      selectedCityId: city.id,
      selectedCity: city.arabicName ?? city.name,
      selectedTimezone: city.timezone,
    );
  }

  Future<void> setCalculationMethodOverride(CalculationMethod? method) async {
    if (method == null) {
      await _mutateFields(clearCalculationMethodOverride: true);
    } else {
      if (!PrayerSettings.supportedMethods.contains(method)) {
        throw ArgumentError.value(
          method,
          'method',
          'Unsupported prayer calculation method: $method',
        );
      }
      await _mutateFields(calculationMethodOverride: method);
    }
  }

  Future<void> clearCalculationMethodOverride() async {
    await _mutateFields(clearCalculationMethodOverride: true);
  }

  Future<void> setAsrMadhab(Madhab madhab) async {
    await _mutateFields(asrMadhab: madhab);
  }

  Future<void> setHighLatitudeRule(HighLatitudeRule rule) async {
    await _mutateFields(highLatitudeRule: rule);
  }

  Future<void> setPolarResolution(PolarDayResolution resolution) async {
    await _mutateFields(polarResolution: resolution);
  }

  Future<void> setRamadanPolicy(UmmAlQuraRamadanPolicy policy) async {
    await _mutateFields(ramadanPolicy: policy);
  }

  Future<void> setHijriDayAdjustment(int days) async {
    if (days < -2 || days > 2) {
      throw ArgumentError.value(
        days,
        'days',
        'Hijri day adjustment must be between -2 and 2',
      );
    }
    await _mutateFields(hijriDayAdjustment: days);
  }

  Future<void> setPrayerOffsets({
    int? fajr,
    int? sunrise,
    int? dhuhr,
    int? asr,
    int? maghrib,
    int? isha,
  }) async {
    void check(int? v, String name) {
      if (v != null && (v < -120 || v > 120)) {
        throw ArgumentError.value(
          v,
          name,
          'Offset must be between -120 and 120',
        );
      }
    }

    check(fajr, 'fajr');
    check(sunrise, 'sunrise');
    check(dhuhr, 'dhuhr');
    check(asr, 'asr');
    check(maghrib, 'maghrib');
    check(isha, 'isha');
    await _mutateFields(
      fajrOffset: fajr,
      sunriseOffset: sunrise,
      dhuhrOffset: dhuhr,
      asrOffset: asr,
      maghribOffset: maghrib,
      ishaOffset: isha,
    );
  }

  Future<void> resetPrayerSettingsToDefaults() async {
    await _mutateFields(
      clearCalculationMethodOverride: true,
      asrMadhab: Madhab.shafi,
      highLatitudeRule: HighLatitudeRule.middle_of_the_night,
      polarResolution: PolarDayResolution.unresolved,
      ramadanPolicy: UmmAlQuraRamadanPolicy.eveningOfRamadan,
      hijriDayAdjustment: 0,
      fajrOffset: 0,
      sunriseOffset: 0,
      dhuhrOffset: 0,
      asrOffset: 0,
      maghribOffset: 0,
      ishaOffset: 0,
    );
  }

  Future<void> setQuranGoal(int goal) async {
    if (goal < 1 || goal > 604) {
      throw ArgumentError.value(
        goal,
        'goal',
        'هدف قراءة القرآن يجب أن يكون بين ١ و ٦٠٤ صفحة',
      );
    }
    await _mutateFields(quranDefaultGoal: goal);
  }

  Future<void> setGeneralAdhanVoice(String voiceId) async {
    if (!UserPreferences.allowedGeneralAdhanVoices.contains(voiceId)) {
      throw ArgumentError.value(
        voiceId,
        'voiceId',
        'Invalid general adhan voice: must be adam or atcovi',
      );
    }
    await _mutateFields(generalAdhanVoice: voiceId);
  }

  Future<void> setFajrAdhanVoice(String voiceId) async {
    if (!UserPreferences.allowedFajrAdhanVoices.contains(voiceId)) {
      throw ArgumentError.value(
        voiceId,
        'voiceId',
        'Invalid Fajr adhan voice: must be adam, atcovi, or malmo_fajr',
      );
    }
    await _mutateFields(fajrAdhanVoice: voiceId);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _mutateFields(notificationsEnabled: enabled);
  }

  Future<void> setActiveDhikrSessionId(String? sessionId) async {
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('setActiveDhikrSessionId');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int capturedEpoch = _instanceEpoch;
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      if (_isDisposed || _instanceEpoch != capturedEpoch) {
        completer.completeError(
          StateError('Controller was disposed or rebuilt prior to execution'),
        );
        return;
      }
      if (repo.mutationBarrier.isResetInProgress ||
          repo.mutationBarrier.currentGeneration != capturedGen) {
        completer.completeError(
          StateError(
            'Operation cancelled by reset: generation mismatch ($capturedGen vs ${repo.mutationBarrier.currentGeneration})',
          ),
        );
        return;
      }
      try {
        if (sessionId != null) {
          await repo.setActiveDhikrSession(sessionId);
        } else {
          await repo.clearActiveDhikrSession();
        }
        final fresh = await repo.getPreferences();
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.complete();
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset after persistence'),
          );
          return;
        }
        state = AsyncValue.data(fresh);
        completer.complete();
      } catch (err, stack) {
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.completeError(err, stack);
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset: generation mismatch'),
          );
          return;
        }
        state = AsyncValue.error(err, stack);
        completer.completeError(err, stack);
      }
    }, onError: (_) async {
      if (_isDisposed || _instanceEpoch != capturedEpoch) {
        completer.completeError(
          StateError('Controller was disposed or rebuilt prior to execution'),
        );
        return;
      }
      if (repo.mutationBarrier.isResetInProgress ||
          repo.mutationBarrier.currentGeneration != capturedGen) {
        completer.completeError(
          StateError(
            'Operation cancelled by reset: generation mismatch ($capturedGen vs ${repo.mutationBarrier.currentGeneration})',
          ),
        );
        return;
      }
      try {
        if (sessionId != null) {
          await repo.setActiveDhikrSession(sessionId);
        } else {
          await repo.clearActiveDhikrSession();
        }
        final fresh = await repo.getPreferences();
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.complete();
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset after persistence'),
          );
          return;
        }
        state = AsyncValue.data(fresh);
        completer.complete();
      } catch (err, stack) {
        if (_isDisposed || _instanceEpoch != capturedEpoch) {
          completer.completeError(err, stack);
          return;
        }
        if (repo.mutationBarrier.isResetInProgress ||
            repo.mutationBarrier.currentGeneration != capturedGen) {
          completer.completeError(
            StateError('Operation cancelled by reset: generation mismatch'),
          );
          return;
        }
        state = AsyncValue.error(err, stack);
        completer.completeError(err, stack);
      }
    });
    return completer.future;
  }

  Future<void> resetAllState({
    NativeAlarmResetBoundary? nativeBoundaryOverride,
    Duration? drainTimeoutOverride,
  }) async {
    final repo = ref.read(progressRepositoryProvider);
    final readingController = ref.read(
      readingProgressControllerProvider.notifier,
    );
    final audioController = ref.read(
      adhanAudioControllerProvider.notifier,
    );
    final NativeAlarmResetBoundary nativeBoundary = nativeBoundaryOverride ??
        ref.read(nativeAlarmResetBoundaryProvider);

    // 1. Begin reset synchronously AT INVOCATION! Immediately fences all subsequent acceptances.
    final int resetToken = repo.mutationBarrier.beginReset();

    // 2. Synchronously notify reading controller to gate new intents and bump generation
    readingController.prepareForReset();

    state = const AsyncValue.loading();
    final completer = Completer<void>();

    _writeQueue = _writeQueue.then((_) async {
      try {
        // 3. Drain pre-reset in-flight writes across all mutation families
        await readingController.drainPendingWrites();
        await repo.mutationBarrier.drainActiveOperations(
          timeout: drainTimeoutOverride ?? const Duration(seconds: 5),
        );

        // 3b. Reset-entry hook: durably disable native alarms before manual SDK audio cleanup
        await nativeBoundary.prepareReset();

        // 4. Await actual audio stop
        await audioController.stop();

        // 5. Await native OS alarm cancellation
        await nativeBoundary.resetAll();

        // 6. Execute atomic SQLite reset across all 9 tables in one transaction
        await repo.resetLocalState();

        // 7. Finish reading controller reset
        readingController.finishReset();

        // 8. Invalidate all Riverpod views
        ref.invalidate(bookmarksControllerProvider);
        ref.invalidate(favoritesControllerProvider);
        ref.invalidate(dailyProgressControllerProvider);
        ref.invalidate(dhikrSessionsControllerProvider);
        ref.invalidate(unfinishedDhikrSessionsProvider);
        ref.invalidate(hisnDailyItemProgressControllerProvider);
        ref.invalidate(dailyQuranPagesControllerProvider);
        ref.invalidate(dailySourceConfirmationControllerProvider);

        repo.mutationBarrier.endReset(token: resetToken, success: true);

        final freshPrefs = await repo.getPreferences();
        state = AsyncValue.data(freshPrefs);
        completer.complete();
      } catch (err, stack) {
        readingController.cancelReset();
        repo.mutationBarrier.endReset(token: resetToken, success: false);
        state = AsyncValue.error(err, stack);
        completer.completeError(err, stack);
      }
    }, onError: (Object err, StackTrace stack) {
      readingController.cancelReset();
      repo.mutationBarrier.endReset(token: resetToken, success: false);
      state = AsyncValue.error(err, stack);
      completer.completeError(err, stack);
    });
    return completer.future;
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
  }

  Future<void> updateBookmark(Bookmark bookmark) async {
    final repo = ref.read(progressRepositoryProvider);
    await repo.updateBookmark(bookmark);
    final updated = await repo.getBookmarks();
    state = AsyncData(updated);
  }

  Future<void> deleteBookmark(int id) async {
    final repo = ref.read(progressRepositoryProvider);
    await repo.deleteBookmark(id);
    final updated = await repo.getBookmarks();
    state = AsyncData(updated);
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
  }

  Future<void> removeFavorite(String kind, String stableId) async {
    final repo = ref.read(progressRepositoryProvider);
    await repo.removeFavorite(kind, stableId);
    ref.invalidateSelf();
  }

  Future<void> retry() async {
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Hisn Daily Checklist Controller (Morning 22 / Evening 20 / Shared 100)
// -------------------------------------------------------------

@immutable
class HisnItemProgressKey {
  final String dateBucket;
  final DhikrPeriod period;

  const HisnItemProgressKey({
    required this.dateBucket,
    required this.period,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HisnItemProgressKey &&
          other.dateBucket == dateBucket &&
          other.period == period;

  @override
  int get hashCode => Object.hash(dateBucket, period);
}

class _HisnItemIntent {
  final String dateBucket;
  final DhikrPeriod period;
  final int itemId;
  final bool isCompleted;
  final int seq;
  final int generation;

  const _HisnItemIntent({
    required this.dateBucket,
    required this.period,
    required this.itemId,
    required this.isCompleted,
    required this.seq,
    required this.generation,
  });
}

final hisnDailyItemProgressControllerProvider =
    AsyncNotifierProvider.family<
      HisnDailyItemProgressController,
      List<HisnDailyItemProgress>,
      HisnItemProgressKey
    >(HisnDailyItemProgressController.new);

class HisnDailyItemProgressController
    extends
        FamilyAsyncNotifier<List<HisnDailyItemProgress>, HisnItemProgressKey> {
  int _latestAcceptedSeq = 0;
  _HisnItemIntent? _lastFailedIntent;
  bool _hasSaveError = false;
  String? _saveErrorMessageArabic;
  bool _isDisposed = false;
  Future<void> _writeQueue = Future<void>.value();

  bool get hasSaveError => _hasSaveError;
  String? get saveErrorMessageArabic => _saveErrorMessageArabic;

  @override
  Future<List<HisnDailyItemProgress>> build(HisnItemProgressKey arg) async {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    final repo = ref.watch(progressRepositoryProvider);
    if (_lastFailedIntent != null &&
        _lastFailedIntent!.generation != repo.mutationBarrier.currentGeneration) {
      _lastFailedIntent = null;
      _hasSaveError = false;
      _saveErrorMessageArabic = null;
    }
    return repo.getHisnDailyItemProgress(arg.dateBucket, arg.period);
  }

  Future<void> setItemProgress({
    required int itemId,
    required bool isCompleted,
  }) async {
    if (_isDisposed) {
      throw StateError('Controller is disposed');
    }
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('setHisnDailyItemProgress');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int seq = ++_latestAcceptedSeq;
    final intent = _HisnItemIntent(
      dateBucket: arg.dateBucket,
      period: arg.period,
      itemId: itemId,
      isCompleted: isCompleted,
      seq: seq,
      generation: capturedGen,
    );

    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(intent, completer);
    }, onError: (_) async {
      await _processIntent(intent, completer);
    });
    return completer.future;
  }

  Future<void> _processIntent(
    _HisnItemIntent intent,
    Completer<void> completer,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    if (_isDisposed) {
      if (!completer.isCompleted) completer.completeError(StateError('Controller disposed'));
      return;
    }
    if (intent.generation != repo.mutationBarrier.currentGeneration) {
      if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
      return;
    }
    final previousList = state.valueOrNull ?? <HisnDailyItemProgress>[];
    try {
      await repo.setHisnDailyItemProgress(
        dateBucket: intent.dateBucket,
        period: intent.period,
        itemId: intent.itemId,
        isCompleted: intent.isCompleted,
      );

      // Recheck after repo write
      if (_isDisposed || intent.generation != repo.mutationBarrier.currentGeneration) {
        if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
        return;
      }

      final updated = await repo.getHisnDailyItemProgress(
        intent.dateBucket,
        intent.period,
      );

      // Recheck after reload query immediately BEFORE adopting state
      if (_isDisposed || intent.generation != repo.mutationBarrier.currentGeneration) {
        if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
        return;
      }

      if (intent.seq >= _latestAcceptedSeq) {
        _hasSaveError = false;
        _saveErrorMessageArabic = null;
        _lastFailedIntent = null;
        state = AsyncData(updated);
        ref.invalidate(dailyProgressControllerProvider(intent.dateBucket));
      }
      if (!completer.isCompleted) completer.complete();
    } catch (err, st) {
      // Recheck before publishing error or adopting failed intent
      if (!_isDisposed && intent.generation == repo.mutationBarrier.currentGeneration) {
        if (intent.seq >= _latestAcceptedSeq) {
          _hasSaveError = true;
          _saveErrorMessageArabic = 'تعذر حفظ حالة الذكر. يرجى إعادة المحاولة.';
          _lastFailedIntent = intent;
          state = AsyncData(previousList);
        }
      }
      if (!completer.isCompleted) completer.completeError(err, st);
    }
  }

  Future<void> retryFailedIntent() async {
    if (_isDisposed || _lastFailedIntent == null) return;
    final repo = ref.read(progressRepositoryProvider);
    // Stale generation check: failed intent from before reset cannot be retried!
    if (_lastFailedIntent!.generation != repo.mutationBarrier.currentGeneration) {
      _lastFailedIntent = null;
      _hasSaveError = false;
      _saveErrorMessageArabic = null;
      return;
    }
    final original = _lastFailedIntent!;
    final seq = ++_latestAcceptedSeq;
    final retryIntent = _HisnItemIntent(
      dateBucket: original.dateBucket,
      period: original.period,
      itemId: original.itemId,
      isCompleted: original.isCompleted,
      seq: seq,
      generation: original.generation,
    );
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(retryIntent, completer);
    }, onError: (_) async {
      await _processIntent(retryIntent, completer);
    });
    return completer.future;
  }

  Future<void> retry() async {
    if (_isDisposed) return;
    _hasSaveError = false;
    _saveErrorMessageArabic = null;
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Daily Quran Confirmed Pages Controller (1..604)
// -------------------------------------------------------------

final dailyQuranPagesControllerProvider =
    AsyncNotifierProvider.family<
      DailyQuranPagesController,
      Set<int>,
      String
    >(DailyQuranPagesController.new);

enum _QuranPageAction { confirm, undo }

class _QuranPageIntent {
  final String dateBucket;
  final int pageNumber;
  final _QuranPageAction action;
  final int seq;
  final int generation;

  const _QuranPageIntent({
    required this.dateBucket,
    required this.pageNumber,
    required this.action,
    required this.seq,
    required this.generation,
  });
}

class DailyQuranPagesController
    extends FamilyAsyncNotifier<Set<int>, String> {
  int _latestAcceptedSeq = 0;
  _QuranPageIntent? _lastFailedIntent;
  bool _hasSaveError = false;
  String? _saveErrorMessageArabic;
  bool _isDisposed = false;
  Future<void> _writeQueue = Future<void>.value();

  bool get hasSaveError => _hasSaveError;
  String? get saveErrorMessageArabic => _saveErrorMessageArabic;

  @override
  Future<Set<int>> build(String arg) async {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    final repo = ref.watch(progressRepositoryProvider);
    if (_lastFailedIntent != null &&
        _lastFailedIntent!.generation != repo.mutationBarrier.currentGeneration) {
      _lastFailedIntent = null;
      _hasSaveError = false;
      _saveErrorMessageArabic = null;
    }
    return repo.getConfirmedQuranPages(arg);
  }

  Future<void> confirmPage(int pageNumber) async {
    if (_isDisposed) {
      throw StateError('Controller is disposed');
    }
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('confirmQuranPage');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int seq = ++_latestAcceptedSeq;
    final intent = _QuranPageIntent(
      dateBucket: arg,
      pageNumber: pageNumber,
      action: _QuranPageAction.confirm,
      seq: seq,
      generation: capturedGen,
    );

    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(intent, completer);
    }, onError: (_) async {
      await _processIntent(intent, completer);
    });
    return completer.future;
  }

  Future<void> undoPage(int pageNumber) async {
    if (_isDisposed) {
      throw StateError('Controller is disposed');
    }
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('undoQuranPage');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int seq = ++_latestAcceptedSeq;
    final intent = _QuranPageIntent(
      dateBucket: arg,
      pageNumber: pageNumber,
      action: _QuranPageAction.undo,
      seq: seq,
      generation: capturedGen,
    );

    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(intent, completer);
    }, onError: (_) async {
      await _processIntent(intent, completer);
    });
    return completer.future;
  }

  Future<void> _processIntent(
    _QuranPageIntent intent,
    Completer<void> completer,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    if (_isDisposed) {
      if (!completer.isCompleted) completer.completeError(StateError('Controller disposed'));
      return;
    }
    if (intent.generation != repo.mutationBarrier.currentGeneration) {
      if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
      return;
    }
    final previousSet = state.valueOrNull ?? <int>{};
    try {
      if (intent.action == _QuranPageAction.confirm) {
        final readingController = ref.exists(readingProgressControllerProvider)
            ? ref.read(readingProgressControllerProvider.notifier) : null;
        await readingController?.drainPendingWrites();
        await repo.confirmQuranPage(
          dateBucket: intent.dateBucket,
          pageNumber: intent.pageNumber,
        );
        await readingController?.reloadPersistedResume();
      } else {
        await repo.undoQuranPage(
          dateBucket: intent.dateBucket,
          pageNumber: intent.pageNumber,
        );
      }

      // Recheck after write await
      if (_isDisposed || intent.generation != repo.mutationBarrier.currentGeneration) {
        if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
        return;
      }

      final updated = await repo.getConfirmedQuranPages(intent.dateBucket);

      // Recheck after reload query immediately BEFORE adopting state
      if (_isDisposed || intent.generation != repo.mutationBarrier.currentGeneration) {
        if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
        return;
      }

      if (intent.seq >= _latestAcceptedSeq) {
        _hasSaveError = false;
        _saveErrorMessageArabic = null;
        _lastFailedIntent = null;
        state = AsyncData(updated);
        ref.invalidate(dailyProgressControllerProvider(intent.dateBucket));
      }
      if (!completer.isCompleted) completer.complete();
    } catch (err, st) {
      if (!_isDisposed && intent.generation == repo.mutationBarrier.currentGeneration) {
        if (intent.seq >= _latestAcceptedSeq) {
          _hasSaveError = true;
          _saveErrorMessageArabic = 'تعذر حفظ تأكيد الصفحة. يرجى إعادة المحاولة.';
          _lastFailedIntent = intent;
          state = AsyncData(previousSet);
        }
      }
      if (!completer.isCompleted) completer.completeError(err, st);
    }
  }

  Future<void> retryFailedIntent() async {
    if (_isDisposed || _lastFailedIntent == null) return;
    final repo = ref.read(progressRepositoryProvider);
    if (_lastFailedIntent!.generation != repo.mutationBarrier.currentGeneration) {
      _lastFailedIntent = null;
      _hasSaveError = false;
      _saveErrorMessageArabic = null;
      return;
    }
    final original = _lastFailedIntent!;
    final seq = ++_latestAcceptedSeq;
    final retryIntent = _QuranPageIntent(
      dateBucket: original.dateBucket,
      pageNumber: original.pageNumber,
      action: original.action,
      seq: seq,
      generation: original.generation,
    );
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(retryIntent, completer);
    }, onError: (_) async {
      await _processIntent(retryIntent, completer);
    });
    return completer.future;
  }

  Future<void> retry() async {
    if (_isDisposed) return;
    _hasSaveError = false;
    _saveErrorMessageArabic = null;
    ref.invalidateSelf();
  }
}

// -------------------------------------------------------------
// Daily Source Confirmation Controller (Daily Dua & Post-Prayer)
// -------------------------------------------------------------

@immutable
class DailySourceKey {
  final String dateBucket;
  final String taskKey;

  const DailySourceKey({
    required this.dateBucket,
    required this.taskKey,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailySourceKey &&
          other.dateBucket == dateBucket &&
          other.taskKey == taskKey;

  @override
  int get hashCode => Object.hash(dateBucket, taskKey);
}

class _SourceIntent {
  final String dateBucket;
  final String taskKey;
  final int? hisnItemId;
  final bool isCompleted;
  final int seq;
  final int generation;

  const _SourceIntent({
    required this.dateBucket,
    required this.taskKey,
    required this.hisnItemId,
    required this.isCompleted,
    required this.seq,
    required this.generation,
  });
}

final dailySourceConfirmationControllerProvider =
    AsyncNotifierProvider.family<
      DailySourceConfirmationController,
      DailySourceConfirmation?,
      DailySourceKey
    >(DailySourceConfirmationController.new);

class DailySourceConfirmationController
    extends FamilyAsyncNotifier<DailySourceConfirmation?, DailySourceKey> {
  int _latestAcceptedSeq = 0;
  _SourceIntent? _lastFailedIntent;
  bool _hasSaveError = false;
  String? _saveErrorMessageArabic;
  bool _isDisposed = false;
  Future<void> _writeQueue = Future<void>.value();

  bool get hasSaveError => _hasSaveError;
  String? get saveErrorMessageArabic => _saveErrorMessageArabic;

  @override
  Future<DailySourceConfirmation?> build(DailySourceKey arg) async {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });
    final repo = ref.watch(progressRepositoryProvider);
    if (_lastFailedIntent != null &&
        _lastFailedIntent!.generation != repo.mutationBarrier.currentGeneration) {
      _lastFailedIntent = null;
      _hasSaveError = false;
      _saveErrorMessageArabic = null;
    }
    return repo.getSourceConfirmation(arg.dateBucket, arg.taskKey);
  }

  Future<void> setConfirmation({
    required bool isCompleted,
    int? hisnItemId,
  }) async {
    if (_isDisposed) {
      throw StateError('Controller is disposed');
    }
    final repo = ref.read(progressRepositoryProvider);
    repo.mutationBarrier.checkMutationAllowed('setSourceConfirmation');
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    final int seq = ++_latestAcceptedSeq;
    final intent = _SourceIntent(
      dateBucket: arg.dateBucket,
      taskKey: arg.taskKey,
      hisnItemId: hisnItemId,
      isCompleted: isCompleted,
      seq: seq,
      generation: capturedGen,
    );

    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(intent, completer);
    }, onError: (_) async {
      await _processIntent(intent, completer);
    });
    return completer.future;
  }

  Future<void> _processIntent(
    _SourceIntent intent,
    Completer<void> completer,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    if (_isDisposed) {
      if (!completer.isCompleted) completer.completeError(StateError('Controller disposed'));
      return;
    }
    if (intent.generation != repo.mutationBarrier.currentGeneration) {
      if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
      return;
    }
    final previousState = state.valueOrNull;
    try {
      final updated = await repo.setSourceConfirmation(
        dateBucket: intent.dateBucket,
        taskKey: intent.taskKey,
        hisnItemId: intent.hisnItemId,
        isCompleted: intent.isCompleted,
      );

      // Recheck after repo write
      if (_isDisposed || intent.generation != repo.mutationBarrier.currentGeneration) {
        if (!completer.isCompleted) completer.completeError(StateError('Operation cancelled by reset: generation mismatch'));
        return;
      }

      if (intent.seq >= _latestAcceptedSeq) {
        _hasSaveError = false;
        _saveErrorMessageArabic = null;
        _lastFailedIntent = null;
        state = AsyncData(updated);
        ref.invalidate(dailyProgressControllerProvider(intent.dateBucket));
      }
      if (!completer.isCompleted) completer.complete();
    } catch (err, st) {
      if (!_isDisposed && intent.generation == repo.mutationBarrier.currentGeneration) {
        if (intent.seq >= _latestAcceptedSeq) {
          _hasSaveError = true;
          _saveErrorMessageArabic = 'تعذر حفظ حالة الذكر. يرجى إعادة المحاولة.';
          _lastFailedIntent = intent;
          state = AsyncData(previousState);
        }
      }
      if (!completer.isCompleted) completer.completeError(err, st);
    }
  }

  Future<void> retryFailedIntent() async {
    if (_isDisposed || _lastFailedIntent == null) return;
    final repo = ref.read(progressRepositoryProvider);
    if (_lastFailedIntent!.generation != repo.mutationBarrier.currentGeneration) {
      _lastFailedIntent = null;
      _hasSaveError = false;
      _saveErrorMessageArabic = null;
      return;
    }
    final original = _lastFailedIntent!;
    final seq = ++_latestAcceptedSeq;
    final retryIntent = _SourceIntent(
      dateBucket: original.dateBucket,
      taskKey: original.taskKey,
      hisnItemId: original.hisnItemId,
      isCompleted: original.isCompleted,
      seq: seq,
      generation: original.generation,
    );
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      await _processIntent(retryIntent, completer);
    }, onError: (_) async {
      await _processIntent(retryIntent, completer);
    });
    return completer.future;
  }

  Future<void> retry() async {
    if (_isDisposed) return;
    _hasSaveError = false;
    _saveErrorMessageArabic = null;
    ref.invalidateSelf();
  }
}
