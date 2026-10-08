import 'dart:async';
import 'package:adhan/adhan.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../prayer/data/sources/city_asset_adapter.dart';
import '../../../prayer/domain/models/prayer_day.dart';
import '../../../prayer/domain/models/prayer_event.dart';
import '../../../prayer/domain/models/prayer_settings.dart';
import '../../../prayer/domain/models/selected_city.dart';
import '../../../prayer/domain/services/prayer_calculator.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';

/// Exact mapping of supported legacy city and IANA timezone pairs to canonical GeoNames IDs.
/// Both city name and timezone must match exactly.
const Map<String, int> legacySupportedCitiesMap = {
  'القاهرة|Africa/Cairo': 360630,
  'مكة المكرمة|Asia/Riyadh': 104515,
  'المدينة المنورة|Asia/Riyadh': 109223,
  'الرياض|Asia/Riyadh': 108410,
  'دبي|Asia/Dubai': 292223,
  'القدس الشريف|Asia/Jerusalem': 281184,
  'إسطنبول|Europe/Istanbul': 745044,
  'لندن|Europe/London': 2643743,
};

/// Exception thrown when the stored city ID cannot be found in the cities dataset.
class CityNotFoundException implements Exception {
  final String message;
  const CityNotFoundException(this.message);
  @override
  String toString() => message;
}

/// Exception thrown when stored city preferences cannot be resolved to a valid city.
class UnresolvedCityException implements Exception {
  final String message;
  const UnresolvedCityException(this.message);
  @override
  String toString() => message;
}

/// Exception thrown when stored prayer calculation settings are corrupted and require explicit repair.
class PrayerSettingsCorruptedException implements Exception {
  final String message;
  const PrayerSettingsCorruptedException(this.message);
  @override
  String toString() => message;
}

/// Exception thrown when the stored canonical city and stored timezone are incoherent.
class IncoherentCityTimezoneException implements Exception {
  final String message;
  const IncoherentCityTimezoneException(this.message);
  @override
  String toString() => message;
}

/// Immutable snapshot containing the resolved city and effective prayer settings.
@immutable
class EffectivePrayerSettings {
  final SelectedCity city;
  final PrayerSettings settings;

  const EffectivePrayerSettings({
    required this.city,
    required this.settings,
  });

  int get cityId => city.id;
  String get timezone => city.timezone;

  /// Stable fingerprint covering every calculation input for coordinator change detection.
  String get fingerprint =>
      '${city.id}|${city.timezone}|${city.latitude}|${city.longitude}|'
      '${settings.calculationMethod.name}|${settings.asrMadhab.name}|'
      '${settings.highLatitudeRule.name}|${settings.polarResolution.name}|'
      '${settings.ummAlQuraRamadanPolicy.name}|${settings.hijriDayAdjustment}|'
      '${settings.fajrOffsetMinutes}|${settings.sunriseOffsetMinutes}|'
      '${settings.dhuhrOffsetMinutes}|${settings.asrOffsetMinutes}|'
      '${settings.maghribOffsetMinutes}|${settings.ishaOffsetMinutes}';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EffectivePrayerSettings &&
        other.city == city &&
        other.settings == settings;
  }

  @override
  int get hashCode => Object.hash(city, settings);

  @override
  String toString() =>
      'EffectivePrayerSettings(city: ${city.name}, method: ${settings.calculationMethod.name})';
}

/// Returns standard Arabic name for a calculation method.
String getCalculationMethodArabicName(CalculationMethod method) {
  switch (method) {
    case CalculationMethod.egyptian:
      return 'الهيئة المصرية العامة للمساحة';
    case CalculationMethod.muslim_world_league:
      return 'رابطة العالم الإسلامي';
    case CalculationMethod.umm_al_qura:
      return 'أم القرى (مكة المكرمة)';
    case CalculationMethod.karachi:
      return 'جامعة العلوم الإسلامية بكراتشي';
    case CalculationMethod.north_america:
      return 'الجمعية الإسلامية لأمريكا الشمالية (ISNA)';
    case CalculationMethod.moon_sighting_committee:
      return 'لجنة رصد الأهلة';
    default:
      return method.name;
  }
}

/// Formats a prayer time in the city's timezone.
String formatPrayerTime(
  PrayerEvent event,
  String timezone, {
  bool use12Hour = true,
}) {
  final cityTime = event.toCityTime(timezone);
  if (!use12Hour) {
    final hour = cityTime.hour.toString().padLeft(2, '0');
    final minute = cityTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final h24 = cityTime.hour;
  final minute = cityTime.minute.toString().padLeft(2, '0');
  final isPm = h24 >= 12;
  final h12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
  final period = isPm ? 'م' : 'ص';
  return '$h12:$minute $period';
}

/// Formats remaining duration into short 'HH:mm' representation.
String formatCountdownShort(Duration duration) {
  if (duration.isNegative) {
    return '00:00';
  }
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  final hStr = hours.toString().padLeft(2, '0');
  final mStr = minutes.toString().padLeft(2, '0');
  return '$hStr:$mStr';
}

/// Formats remaining duration into Arabic text.
String formatCountdownHuman(Duration duration) {
  if (duration.isNegative) {
    return 'الآن';
  }
  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return '$minutes دقيقة';
  }
  if (minutes == 0) {
    return '$hours ساعة';
  }
  return '$hours س و $minutes د';
}

/// Provider delivering the effective calculation snapshot containing city and resolved PrayerSettings.
/// Derived synchronously from the SAME preference snapshot and city repository.
/// Calculation method is resolved as city default if override is null, while explicit overrides survive city transitions.
final effectivePrayerSettingsProvider =
    Provider<AsyncValue<EffectivePrayerSettings>>((ref) {
  final prefsAsync = ref.watch(preferencesControllerProvider);
  final cityRepoAsync = ref.watch(cityRepositoryProvider);

  if (prefsAsync.isLoading || cityRepoAsync.isLoading) {
    return const AsyncValue.loading();
  }

  if (prefsAsync.hasError) {
    return AsyncValue.error(prefsAsync.error!, prefsAsync.stackTrace!);
  }
  if (cityRepoAsync.hasError) {
    return AsyncValue.error(cityRepoAsync.error!, cityRepoAsync.stackTrace!);
  }

  final prefs = prefsAsync.requireValue;
  final cityRepo = cityRepoAsync.requireValue;

  if (prefs.prayerSettingsRecoveryNotice) {
    return AsyncValue.error(
      const PrayerSettingsCorruptedException(
        'إعدادات حساب الصلاة المحفوظة تحتوي على قيم غير صالحة وتتطلب الإصلاح.',
      ),
      StackTrace.current,
    );
  }

  SelectedCity? city;
  if (prefs.selectedCityId != null) {
    city = cityRepo.getCityById(prefs.selectedCityId!);
    if (city == null) {
      return AsyncValue.error(
        CityNotFoundException(
          'المدينة المحددة غير موجودة في قاعدة بيانات المدن (ID: ${prefs.selectedCityId})',
        ),
        StackTrace.current,
      );
    }
    if (city.timezone != prefs.selectedTimezone) {
      return AsyncValue.error(
        IncoherentCityTimezoneException(
          'المنطقة الزمنية المحفوظة (${prefs.selectedTimezone}) غير متطابقة مع المدينة (${city.timezone}) وتتطلب إعادة التحديد.',
        ),
        StackTrace.current,
      );
    }
  } else {
    final key = '${prefs.selectedCity}|${prefs.selectedTimezone}';
    final legacyId = legacySupportedCitiesMap[key];
    if (legacyId != null) {
      city = cityRepo.getCityById(legacyId);
    }
    if (city == null) {
      return AsyncValue.error(
        UnresolvedCityException(
          'لم يتم العثور على المدينة المحددة (${prefs.selectedCity})',
        ),
        StackTrace.current,
      );
    }
    if (city.timezone != prefs.selectedTimezone) {
      return AsyncValue.error(
        IncoherentCityTimezoneException(
          'المنطقة الزمنية المحفوظة (${prefs.selectedTimezone}) غير متطابقة مع المدينة (${city.timezone}) وتتطلب إعادة التحديد.',
        ),
        StackTrace.current,
      );
    }
  }

  final method = prefs.calculationMethodOverride ?? city.defaultCalculationMethod;
  final settings = PrayerSettings(
    calculationMethod: method,
    asrMadhab: prefs.asrMadhab,
    highLatitudeRule: prefs.highLatitudeRule,
    polarResolution: prefs.polarResolution,
    ummAlQuraRamadanPolicy: prefs.ramadanPolicy,
    hijriDayAdjustment: prefs.hijriDayAdjustment,
    fajrOffsetMinutes: prefs.fajrOffset,
    sunriseOffsetMinutes: prefs.sunriseOffset,
    dhuhrOffsetMinutes: prefs.dhuhrOffset,
    asrOffsetMinutes: prefs.asrOffset,
    maghribOffsetMinutes: prefs.maghribOffset,
    ishaOffsetMinutes: prefs.ishaOffset,
  );

  return AsyncValue.data(
    EffectivePrayerSettings(
      city: city,
      settings: settings,
    ),
  );
});

/// Provider exposing the selected prayer city, derived directly from the effective snapshot.
final selectedPrayerCityProvider = Provider<AsyncValue<SelectedCity>>((ref) {
  final snapshotAsync = ref.watch(effectivePrayerSettingsProvider);
  return snapshotAsync.whenData((snapshot) => snapshot.city);
});

/// Immutable state representing calculated prayer times and countdown for display.
@immutable
class PrayerState {
  final SelectedCity? city;
  final PrayerDay? prayerDay;
  final PrayerEvent? nextPrayer;
  final Duration? timeToNextPrayer;
  final DateTime civilDate;
  final CalculationMethod calculationMethod;
  final bool isUnsupported;
  final String? unsupportedCity;
  final String? unsupportedTimezone;
  final EffectivePrayerSettings? effectiveSettings;

  const PrayerState({
    this.city,
    this.prayerDay,
    this.nextPrayer,
    this.timeToNextPrayer,
    required this.civilDate,
    this.calculationMethod = CalculationMethod.egyptian,
    this.isUnsupported = false,
    this.unsupportedCity,
    this.unsupportedTimezone,
    this.effectiveSettings,
  });

  bool get isEstimated => prayerDay?.isEstimated ?? false;
  bool get isUnresolved => prayerDay?.isUnresolved ?? false;
  String? get estimationReason => prayerDay?.estimationReason;
  String? get unresolvedReason => prayerDay?.statusMessage;
  String get calculationMethodArabicName =>
      getCalculationMethodArabicName(calculationMethod);

  String get countdownString {
    if (timeToNextPrayer == null) return '--:--';
    return formatCountdownShort(timeToNextPrayer!);
  }

  String get countdownHumanString {
    if (timeToNextPrayer == null) return '';
    return formatCountdownHuman(timeToNextPrayer!);
  }

  List<PrayerEvent> get dailyEvents {
    if (prayerDay == null || prayerDay!.isUnresolved) return const [];
    return prayerDay!.orderedEvents;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrayerState &&
        other.city == city &&
        other.prayerDay == prayerDay &&
        other.nextPrayer == nextPrayer &&
        other.timeToNextPrayer == timeToNextPrayer &&
        other.civilDate == civilDate &&
        other.calculationMethod == calculationMethod &&
        other.isUnsupported == isUnsupported &&
        other.unsupportedCity == unsupportedCity &&
        other.unsupportedTimezone == unsupportedTimezone &&
        other.effectiveSettings == effectiveSettings;
  }

  @override
  int get hashCode => Object.hash(
        city,
        prayerDay,
        nextPrayer,
        timeToNextPrayer,
        civilDate,
        calculationMethod,
        isUnsupported,
        unsupportedCity,
        unsupportedTimezone,
        effectiveSettings,
      );
}

final prayerCalculatorProvider = Provider<PrayerCalculator>((ref) {
  return PrayerCalculator();
});

/// Shared provider delivering real offline calculated prayer times and next prayer.
final prayerTimesControllerProvider =
    NotifierProvider<PrayerTimesNotifier, AsyncValue<PrayerState>>(
  PrayerTimesNotifier.new,
);

/// Backwards compatibility provider alias consumed by Home screen.
final currentPrayerDisplayProvider = prayerTimesControllerProvider;

class PrayerTimesNotifier extends Notifier<AsyncValue<PrayerState>>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _isObserverAdded = false;

  @visibleForTesting
  Timer? get activeTimer => _timer;

  @override
  AsyncValue<PrayerState> build() {
    ensureTimeZonesInitialized();
    final clock = ref.watch(clockProvider);
    final effectiveAsync = ref.watch(effectivePrayerSettingsProvider);

    if (!_isObserverAdded) {
      try {
        WidgetsBinding.instance.addObserver(this);
        _isObserverAdded = true;
      } catch (_) {
        // Test environment without WidgetsBinding initialized
      }
    }

    ref.onDispose(() {
      if (_isObserverAdded) {
        try {
          WidgetsBinding.instance.removeObserver(this);
        } catch (_) {}
        _isObserverAdded = false;
      }
      _timer?.cancel();
      _timer = null;
    });

    if (effectiveAsync.isLoading) {
      return const AsyncValue.loading();
    }

    if (effectiveAsync.hasError) {
      return AsyncValue.error(
        effectiveAsync.error!,
        effectiveAsync.stackTrace!,
      );
    }

    final snapshot = effectiveAsync.requireValue;
    final stateData = _computeState(snapshot, clock);
    _scheduleNextTick(clock, snapshot.city.timezone);
    return AsyncValue.data(stateData);
  }

  PrayerState _computeState(
    EffectivePrayerSettings snapshot,
    DateTime Function() clock,
  ) {
    final city = snapshot.city;
    final settings = snapshot.settings;
    final nowUtc = clock().toUtc();
    final cityLocation = tz.getLocation(city.timezone);
    final cityLocalNow = tz.TZDateTime.from(nowUtc, cityLocation);
    final civilDateUtc = DateTime.utc(
      cityLocalNow.year,
      cityLocalNow.month,
      cityLocalNow.day,
    );

    final calculator = ref.read(prayerCalculatorProvider);
    final prayerDay = calculator.calculatePrayerDay(
      city: city,
      date: civilDateUtc,
      settings: settings,
    );

    PrayerEvent? nextPrayer;
    Duration? timeToNext;
    if (!prayerDay.isUnresolved) {
      try {
        nextPrayer = calculator.nextPrayer(
          utcNow: nowUtc,
          city: city,
          settings: settings,
          includeSunrise: false,
        );
        timeToNext = nextPrayer.utcDateTime.difference(nowUtc);
      } catch (e) {
        return PrayerState(
          city: city,
          prayerDay: PrayerDay.unresolved(
            city: city,
            civilDate: civilDateUtc,
            settings: prayerDay.settings,
            reason: 'تعذر تحديد الصلاة القادمة: $e',
          ),
          civilDate: civilDateUtc,
          calculationMethod: settings.calculationMethod,
          isUnsupported: false,
          effectiveSettings: snapshot,
        );
      }
    }

    return PrayerState(
      city: city,
      prayerDay: prayerDay,
      nextPrayer: nextPrayer,
      timeToNextPrayer: timeToNext,
      civilDate: civilDateUtc,
      calculationMethod: settings.calculationMethod,
      isUnsupported: false,
      effectiveSettings: snapshot,
    );
  }

  void _scheduleNextTick(DateTime Function() clock, String tzName) {
    _timer?.cancel();
    final now = clock();
    final secondsUntilNextMinute = 60 - (now.second % 60);
    final msUntilNextSecond = 1000 - (now.millisecond % 1000);
    final totalMs = (secondsUntilNextMinute - 1) * 1000 + msUntilNextSecond + 50;
    final delay = totalMs > 100 ? Duration(milliseconds: totalMs) : const Duration(seconds: 1);

    _timer = Timer(delay, () {
      _tick();
    });
  }

  void _tick() {
    final snapshotAsync = ref.read(effectivePrayerSettingsProvider);
    if (!snapshotAsync.hasValue) return;
    final snapshot = snapshotAsync.requireValue;

    final clock = ref.read(clockProvider);
    final newState = _computeState(snapshot, clock);
    state = AsyncValue.data(newState);
    _scheduleNextTick(clock, snapshot.city.timezone);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _tick();
    }
  }

  /// Manually refreshes calculation and countdown.
  void refresh() {
    _tick();
  }

  /// Retries loading city repository and user preferences.
  void retry() {
    ref.invalidate(cityRepositoryProvider);
    ref.invalidate(preferencesControllerProvider);
    ref.invalidateSelf();
  }
}
