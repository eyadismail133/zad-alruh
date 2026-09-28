import 'package:adhan/adhan.dart';
// ignore: implementation_imports
import 'package:adhan/src/data/calendar_util.dart';
// ignore: implementation_imports
import 'package:adhan/src/data/time_components.dart';
// ignore: implementation_imports
import 'package:adhan/src/internal/solar_time.dart';
import 'package:hijri/hijri_calendar.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/prayer_day.dart';
import '../models/prayer_event.dart';
import '../models/prayer_settings.dart';
import '../models/selected_city.dart';

/// Pure Dart service performing offline Adhan calculations for global cities.
///
/// Features:
/// - Pure Dart execution without dart:ui or Flutter dependencies for headless background scheduling.
/// - City-selected civil date and UTC event instants.
/// - Five prayers plus sunrise.
/// - Methods: Egyptian, MWL, Umm Al-Qura, Karachi, North America (ISNA), Moonsighting Committee.
/// - Shafi and Hanafi Asr madhabs.
/// - Additive minute offsets (bounded to ±120 minutes).
/// - High-latitude middle, seventh, and twilight angle rules with explicit estimation tracking.
/// - Polar day handling: returns actionable unresolved result or bounded nearest-valid-latitude (Aqrab Al-Balad).
/// - Umm Al-Qura Isha Ramadan +30 minute adjustment policy with Hijri range guarding.
/// - Deterministic next-prayer selection handling midnight and DST transitions.
class PrayerCalculator {
  static bool _timeZonesInitialized = false;

  /// Ensures that IANA timezone database is initialized for pure Dart environments.
  static void ensureTimeZonesInitialized() {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
  }

  /// Calculates the prayer times for a city on a specific civil date.
  ///
  /// [city]: The selected city providing coordinates and IANA timezone.
  /// [date]: The civil calendar date (year, month, day) in the city's calendar.
  /// [settings]: Optional custom settings. If omitted, uses defaults tailored to the city.
  PrayerDay calculatePrayerDay({
    required SelectedCity city,
    required DateTime date,
    PrayerSettings? settings,
  }) {
    if (date.year < 1 || date.year > 9999) {
      throw ArgumentError.value(
        date,
        'date',
        'Civil date year must be between 1 and 9999',
      );
    }
    if (!city.latitude.isFinite ||
        city.latitude < -90.0 ||
        city.latitude > 90.0) {
      throw ArgumentError.value(
        city.latitude,
        'city.latitude',
        'City latitude must be between -90 and 90 degrees',
      );
    }
    if (!city.longitude.isFinite ||
        city.longitude < -180.0 ||
        city.longitude > 180.0) {
      throw ArgumentError.value(
        city.longitude,
        'city.longitude',
        'City longitude must be between -180 and 180 degrees',
      );
    }

    ensureTimeZonesInitialized();

    final effectiveSettings =
        settings ??
        PrayerSettings(
          calculationMethod: city.defaultCalculationMethod,
          asrMadhab: Madhab.shafi,
          highLatitudeRule: HighLatitudeRule.middle_of_the_night,
        );

    final civilYear = date.year;
    final civilMonth = date.month;
    final civilDay = date.day;
    final civilDateUtc = DateTime.utc(civilYear, civilMonth, civilDay);
    final dateComponents = DateComponents(civilYear, civilMonth, civilDay);
    final coordinates = Coordinates(city.latitude, city.longitude);

    // Build Adhan calculation parameters
    final params = effectiveSettings.calculationMethod.getParameters();
    params.madhab = effectiveSettings.asrMadhab;
    params.highLatitudeRule = effectiveSettings.highLatitudeRule;
    params.adjustments = effectiveSettings.toAdhanAdjustments();

    // Check Umm Al-Qura Ramadan extra 30 minutes policy
    if (effectiveSettings.calculationMethod == CalculationMethod.umm_al_qura) {
      if (effectiveSettings.ummAlQuraRamadanPolicy !=
          UmmAlQuraRamadanPolicy.disabled) {
        final targetDate =
            effectiveSettings.ummAlQuraRamadanPolicy ==
                UmmAlQuraRamadanPolicy.eveningOfRamadan
            ? DateTime.utc(
                civilYear,
                civilMonth,
                civilDay + 1 + effectiveSettings.hijriDayAdjustment,
              )
            : DateTime.utc(
                civilYear,
                civilMonth,
                civilDay + effectiveSettings.hijriDayAdjustment,
              );

        // Pinned hijri 3.0.1 supported range: 1356-01-01 (1937-03-14 CE) to 1500-12-30 (2077-11-16 CE)
        final minSupported = DateTime.utc(1937, 3, 14);
        final maxSupported = DateTime.utc(2077, 11, 16);

        if (targetDate.isBefore(minSupported) ||
            targetDate.isAfter(maxSupported)) {
          return PrayerDay.unresolved(
            city: city,
            civilDate: civilDateUtc,
            settings: effectiveSettings,
            reason:
                'Umm Al-Qura automatic Ramadan adjustment is unsupported for date '
                '${civilYear.toString().padLeft(4, '0')}-${civilMonth.toString().padLeft(2, '0')}-${civilDay.toString().padLeft(2, '0')} '
                '(Hijri calendar supported range: 1356-01-01 / 1937-03-14 to 1500-12-30 / 2077-11-16). '
                'Use UmmAlQuraRamadanPolicy.disabled for standard 90-minute Isha outside this range.',
          );
        }

        try {
          final hijri = HijriCalendar.fromDate(targetDate);
          if (hijri.hMonth == 9) {
            params.ishaInterval = 120; // 90 + 30 extra minutes in Ramadan
          } else {
            params.ishaInterval = 90;
          }
        } on ArgumentError catch (e) {
          return PrayerDay.unresolved(
            city: city,
            civilDate: civilDateUtc,
            settings: effectiveSettings,
            reason:
                'Failed to determine Hijri calendar month for Umm Al-Qura Ramadan adjustment: ${e.message}',
          );
        }
      } else {
        params.ishaInterval = 90;
      }
    }

    try {
      final prayerTimes = PrayerTimes.utc(coordinates, dateComponents, params);

      final isHighLatitudeEstimated = _isHighLatitudeEstimated(
        civilDateUtc: civilDateUtc,
        coordinates: coordinates,
        params: params,
        prayerTimes: prayerTimes,
      );
      final String? estimationReason = isHighLatitudeEstimated
          ? 'High-latitude twilight estimation applied: astronomical twilight bounded by high-latitude rule or seasonal approximation'
          : null;

      return _buildValidatedPrayerDay(
        city: city,
        civilDate: civilDateUtc,
        settings: effectiveSettings,
        prayerTimes: prayerTimes,
        isEstimated: isHighLatitudeEstimated,
        estimationReason: estimationReason,
      );
    } on ArgumentError catch (e) {
      // ArgumentError from TimeComponents.fromDouble indicates sun never crosses horizon (polar day)
      if (effectiveSettings.polarResolution ==
          PolarDayResolution.nearestLatitude) {
        return _resolvePolarViaNearestLatitude(
          city: city,
          civilDate: civilDateUtc,
          dateComponents: dateComponents,
          params: params,
          settings: effectiveSettings,
        );
      }

      return PrayerDay.unresolved(
        city: city,
        civilDate: civilDateUtc,
        settings: effectiveSettings,
        reason:
            'Polar day: solar events undefined at latitude ${city.latitude}°: ${e.message}',
      );
    }
  }

  /// Returns the next upcoming prayer event after [utcNow].
  ///
  /// Bounded UTC chronological candidates are gathered across the previous civil day,
  /// today, and tomorrow in the city's local calendar. This ensures that cross-midnight
  /// events (such as high-latitude Isha occurring after local midnight on the following
  /// calendar day) are selected when strictly future, rather than skipped in favor of today's Fajr.
  ///
  /// Candidate selection:
  /// - Only events strictly after [utcNow] are considered.
  /// - Evaluates candidates chronologically by UTC instant.
  /// - Same-instant tie-breaking follows canonical prayer order:
  ///   Fajr < Sunrise < Dhuhr < Asr < Maghrib < Isha.
  ///
  /// [utcNow]: Injected current UTC instant. Must have `isUtc == true`.
  /// [city]: Selected city.
  /// [settings]: Optional calculation settings.
  /// [includeSunrise]: If true, includes Sunrise as an event; if false, only canonical 5 prayers.
  PrayerEvent nextPrayer({
    required DateTime utcNow,
    required SelectedCity city,
    PrayerSettings? settings,
    bool includeSunrise = false,
  }) {
    if (!utcNow.isUtc) {
      throw ArgumentError.value(
        utcNow,
        'utcNow',
        'nextPrayer requires a UTC DateTime instant',
      );
    }
    ensureTimeZonesInitialized();

    final cityLocation = tz.getLocation(city.timezone);
    final cityLocalTime = tz.TZDateTime.from(utcNow, cityLocation);
    final todayCivil = DateTime.utc(
      cityLocalTime.year,
      cityLocalTime.month,
      cityLocalTime.day,
    );

    final todayPrayerDay = calculatePrayerDay(
      city: city,
      date: todayCivil,
      settings: settings,
    );

    if (todayPrayerDay.isUnresolved) {
      throw StateError(
        'Cannot determine next prayer for an unresolved day in ${city.name}: ${todayPrayerDay.statusMessage ?? "unresolved"}',
      );
    }

    final yesterdayCivil = DateTime.utc(
      todayCivil.year,
      todayCivil.month,
      todayCivil.day - 1,
    );
    final tomorrowCivil = DateTime.utc(
      todayCivil.year,
      todayCivil.month,
      todayCivil.day + 1,
    );

    final candidates = <PrayerEvent>[];

    // 1. Previous civil day events (can cross midnight into today, e.g. high-latitude Isha)
    final yesterdayPrayerDay = calculatePrayerDay(
      city: city,
      date: yesterdayCivil,
      settings: settings,
    );
    if (!yesterdayPrayerDay.isUnresolved) {
      candidates.addAll(
        includeSunrise
            ? yesterdayPrayerDay.orderedEvents
            : yesterdayPrayerDay.canonicalPrayers,
      );
    }

    // 2. Today's civil day events
    candidates.addAll(
      includeSunrise
          ? todayPrayerDay.orderedEvents
          : todayPrayerDay.canonicalPrayers,
    );

    // 3. Tomorrow's civil day events (advancing past today's Isha)
    final tomorrowPrayerDay = calculatePrayerDay(
      city: city,
      date: tomorrowCivil,
      settings: settings,
    );
    if (!tomorrowPrayerDay.isUnresolved) {
      candidates.addAll(
        includeSunrise
            ? tomorrowPrayerDay.orderedEvents
            : tomorrowPrayerDay.canonicalPrayers,
      );
    }

    final futureCandidates = candidates
        .where((event) => event.utcDateTime.isAfter(utcNow))
        .toList();

    if (futureCandidates.isEmpty) {
      throw StateError(
        'Cannot determine next prayer for ${city.name} on ${todayCivil.year}-${todayCivil.month}-${todayCivil.day}',
      );
    }

    // Sort strictly chronological by UTC instant; break ties via canonical prayer order
    futureCandidates.sort((a, b) {
      final cmp = a.utcDateTime.compareTo(b.utcDateTime);
      if (cmp != 0) return cmp;
      return a.type.index.compareTo(b.type.index);
    });

    return futureCandidates.first;
  }

  /// Detects whether high-latitude rules, seasonal approximations, or angle bounds
  /// were applied by comparing the unbounded astronomical angle times (with manual/method offsets
  /// and minute rounding) against the engine's final computed prayer times.
  ///
  /// Minute precision: Both unbounded times and final engine times are rounded to the minute
  /// via [CalendarUtil.roundedMinute]. A difference between the unbounded calculation and the
  /// engine result proves that a high-latitude bound or seasonal override was actively applied.
  /// Fixed-interval Isha (e.g. Umm Al-Qura 90/120 min) is excluded from angle clamping checks.
  bool _isHighLatitudeEstimated({
    required DateTime civilDateUtc,
    required Coordinates coordinates,
    required CalculationParameters params,
    required PrayerTimes prayerTimes,
  }) {
    final solarTime = SolarTime(civilDateUtc, coordinates);

    // 1. Check Fajr angle:
    final rawFajrAngle = solarTime.hourAngle(-params.fajrAngle, false);
    if (!rawFajrAngle.isFinite || rawFajrAngle.isNaN) {
      // Astronomical twilight angle does not occur at this latitude/date
      return true;
    }
    final rawFajrComponents = TimeComponents.fromDouble(
      rawFajrAngle,
    ).dateComponents(civilDateUtc);
    final totalFajrOffset =
        params.adjustments.fajr + params.methodAdjustments.fajr;
    final unboundedFajr = CalendarUtil.roundedMinute(
      rawFajrComponents.add(Duration(minutes: totalFajrOffset)).toLocal(),
    ).toUtc();

    if (prayerTimes.fajr.toUtc() != unboundedFajr) {
      // Engine clamped Fajr to high-latitude rule or seasonal bound
      return true;
    }

    // 2. Check Isha angle (only if angle-based; fixed interval Isha excluded):
    if (params.ishaInterval <= 0 && params.ishaAngle != null) {
      final rawIshaAngle = solarTime.hourAngle(-params.ishaAngle!, true);
      if (!rawIshaAngle.isFinite || rawIshaAngle.isNaN) {
        // Astronomical evening twilight angle does not occur
        return true;
      }
      final rawIshaComponents = TimeComponents.fromDouble(
        rawIshaAngle,
      ).dateComponents(civilDateUtc);
      final totalIshaOffset =
          params.adjustments.isha + params.methodAdjustments.isha;
      final unboundedIsha = CalendarUtil.roundedMinute(
        rawIshaComponents.add(Duration(minutes: totalIshaOffset)).toLocal(),
      ).toUtc();

      if (prayerTimes.isha.toUtc() != unboundedIsha) {
        // Engine clamped Isha to high-latitude rule or seasonal bound
        return true;
      }
    }

    return false;
  }

  /// Constructs a [PrayerDay] requiring all 6 UTC events in strict chronological order.
  /// Shared between standard calculations and polar-estimated calculations to guarantee
  /// that manual offsets or coordinate shifts never mask invalid chronological sequences.
  PrayerDay _buildValidatedPrayerDay({
    required SelectedCity city,
    required DateTime civilDate,
    required PrayerSettings settings,
    required PrayerTimes prayerTimes,
    required bool isEstimated,
    required String? estimationReason,
  }) {
    final fajr = PrayerEvent(
      type: PrayerType.fajr,
      utcDateTime: prayerTimes.fajr.toUtc(),
    );
    final sunrise = PrayerEvent(
      type: PrayerType.sunrise,
      utcDateTime: prayerTimes.sunrise.toUtc(),
    );
    final dhuhr = PrayerEvent(
      type: PrayerType.dhuhr,
      utcDateTime: prayerTimes.dhuhr.toUtc(),
    );
    final asr = PrayerEvent(
      type: PrayerType.asr,
      utcDateTime: prayerTimes.asr.toUtc(),
    );
    final maghrib = PrayerEvent(
      type: PrayerType.maghrib,
      utcDateTime: prayerTimes.maghrib.toUtc(),
    );
    final isha = PrayerEvent(
      type: PrayerType.isha,
      utcDateTime: prayerTimes.isha.toUtc(),
    );

    // Validate strict chronological ordering of computed events
    if (fajr.utcDateTime.isAfter(sunrise.utcDateTime) ||
        sunrise.utcDateTime.isAfter(dhuhr.utcDateTime) ||
        dhuhr.utcDateTime.isAfter(asr.utcDateTime) ||
        asr.utcDateTime.isAfter(maghrib.utcDateTime) ||
        maghrib.utcDateTime.isAfter(isha.utcDateTime)) {
      throw StateError(
        'Computed prayer times resulted in invalid chronological sequence on '
        '${civilDate.year}-${civilDate.month}-${civilDate.day} for ${city.name} '
        '(Fajr: ${fajr.utcDateTime.toIso8601String()}, Sunrise: ${sunrise.utcDateTime.toIso8601String()}, '
        'Dhuhr: ${dhuhr.utcDateTime.toIso8601String()}, Asr: ${asr.utcDateTime.toIso8601String()}, '
        'Maghrib: ${maghrib.utcDateTime.toIso8601String()}, Isha: ${isha.utcDateTime.toIso8601String()})',
      );
    }

    return PrayerDay(
      city: city,
      civilDate: civilDate,
      settings: settings,
      fajr: fajr,
      sunrise: sunrise,
      dhuhr: dhuhr,
      asr: asr,
      maghrib: maghrib,
      isha: isha,
      isEstimated: isEstimated,
      estimationReason: estimationReason,
      isUnresolved: false,
    );
  }

  /// Resolves an undefined polar day using bounded nearest-valid-latitude strategy (Aqrab Al-Balad).
  ///
  /// Steps latitude towards the equator by 0.5° down to a bound of ±45.0°,
  /// executing the exact same Adhan calculation engine and shared validation at each step.
  PrayerDay _resolvePolarViaNearestLatitude({
    required SelectedCity city,
    required DateTime civilDate,
    required DateComponents dateComponents,
    required CalculationParameters params,
    required PrayerSettings settings,
  }) {
    final double step = city.latitude > 0 ? -0.5 : 0.5;
    final double boundLat = city.latitude > 0 ? 45.0 : -45.0;

    double testLat = city.latitude + step;
    while ((city.latitude > 0 && testLat >= boundLat) ||
        (city.latitude < 0 && testLat <= boundLat)) {
      try {
        final testCoords = Coordinates(testLat, city.longitude);
        final prayerTimes = PrayerTimes.utc(testCoords, dateComponents, params);

        return _buildValidatedPrayerDay(
          city: city,
          civilDate: civilDate,
          settings: settings,
          prayerTimes: prayerTimes,
          isEstimated: true,
          estimationReason:
              'Polar day: estimated using bounded nearest valid latitude (Aqrab Al-Balad at ${testLat.toStringAsFixed(1)}°)',
        );
      } on ArgumentError {
        // Genuine polar undefined solar altitude: continue to next latitude step
        testLat += step;
      }
    }

    return PrayerDay.unresolved(
      city: city,
      civilDate: civilDate,
      settings: settings,
      reason:
          'Polar day: sun does not cross horizon; nearest valid latitude exceeded bound of $boundLat°',
    );
  }
}
