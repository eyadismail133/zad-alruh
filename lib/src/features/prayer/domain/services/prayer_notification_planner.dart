import 'dart:convert';
import 'dart:math' as math;
import 'package:timezone/timezone.dart' as tz;

import '../models/prayer_event.dart';
import '../models/prayer_notification_plan.dart';
import '../models/prayer_settings.dart';
import '../models/selected_city.dart';
import 'prayer_calculator.dart';

/// Pure Dart implementation of IEEE 802.3 32-bit Cyclic Redundancy Check (CRC-32)
/// generating deterministic positive 31-bit integers for notification and alarm identifiers.
class Crc32Util {
  static final List<int> _table = _initTable();

  static List<int> _initTable() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int crc = i;
      for (int j = 0; j < 8; j++) {
        if ((crc & 1) != 0) {
          crc = (crc >>> 1) ^ 0xEDB88320;
        } else {
          crc = crc >>> 1;
        }
      }
      table[i] = crc & 0xFFFFFFFF;
    }
    return table;
  }

  /// Computes the standard IEEE 802.3 CRC-32 checksum over the provided byte sequence.
  static int compute(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc = (crc >>> 8) ^ _table[(crc ^ byte) & 0xFF];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// Generates a deterministic strictly positive 31-bit integer (`1` to `0x7FFFFFFF`)
  /// from the UTF-8 bytes of [input]. Matches the 31-bit request code algorithm in Android native.
  static int positive31Bit(String input) {
    final bytes = utf8.encode(input);
    final raw = compute(bytes);
    final masked = raw & 0x7FFFFFFF;
    return masked == 0 ? 1 : masked;
  }
}

/// Pure Dart domain service responsible for generating immutable, multi-day
/// prayer notification schedules for native Android AlarmManager and iOS platform projections.
///
/// Complies with Sol6.1 approved architecture:
/// - Side-effect free, headless, non-global execution without Flutter UI or platform plugin dependencies.
/// - Calculates exactly TEN consecutive civil calendar dates starting on the selected city's current local civil date.
/// - Uses calendar iteration `DateTime.utc(y, m, d + index)` to avoid DST duration pitfalls.
/// - Retains canonical prayers only (Fajr, Dhuhr, Asr, Maghrib, Isha; Sunrise strictly excluded).
/// - Filters out past events (`utcDateTime > nowUtc`), retaining at most 50 future canonical events.
/// - Retains cross-midnight events (e.g. ±120 minute offsets) while strictly preserving original calculation civil date keys.
/// - Generates stable positive 31-bit IDs with explicit internal and external collision prevention.
/// - Projects iOS schedule respecting the hard platform ceiling of 64 pending notifications and forcing short_alert mode.
class PrayerNotificationPlanner {
  final PrayerCalculator _calculator;

  static const Set<String> _supportedGeneralVoices = {'adam', 'atcovi'};
  static const Set<String> _supportedFajrVoices = {
    'adam',
    'atcovi',
    'malmo_fajr',
  };
  static const Set<String> _supportedModes = {'full_adhan', 'short_alert'};
  static const int _maxIosPlatformLimit = 64;
  static const int _maxPlanEvents = 50;

  /// Creates a planner with an optional injected [PrayerCalculator].
  PrayerNotificationPlanner({PrayerCalculator? calculator})
    : _calculator = calculator ?? PrayerCalculator();

  /// Builds a complete immutable [PrayerNotificationPlan].
  ///
  /// [city]: Validated selected city.
  /// [settings]: Adhan calculation settings and minute offsets.
  /// [nowUtc]: Injected current reference instant. Must have `isUtc == true`.
  /// [generalVoiceId]: Adhan voice identifier for general prayers ('adam' or 'atcovi').
  /// [fajrVoiceId]: Adhan voice identifier for Fajr ('adam', 'atcovi', or 'malmo_fajr').
  /// [mode]: Alarm delivery mode ('full_adhan' or 'short_alert').
  /// [existingOtherIosPendingIds]: Set of notification IDs currently pending for other features/owners on iOS.
  PrayerNotificationPlan build({
    required SelectedCity city,
    required PrayerSettings settings,
    required DateTime nowUtc,
    required String generalVoiceId,
    required String fajrVoiceId,
    required String mode,
    Set<int> existingOtherIosPendingIds = const {},
  }) {
    // Snapshot immutable Set immediately at entry so caller mutation cannot affect planning
    final sanitizedOtherIosPendingIds = Set<int>.unmodifiable(
      existingOtherIosPendingIds,
    );

    // 1. Strict input validation
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(
        nowUtc,
        'nowUtc',
        'Current timestamp must be an explicit UTC DateTime (nowUtc.isUtc must be true).',
      );
    }
    if (!_supportedGeneralVoices.contains(generalVoiceId)) {
      throw ArgumentError.value(
        generalVoiceId,
        'generalVoiceId',
        'Unsupported general voice "$generalVoiceId". Supported voices: $_supportedGeneralVoices',
      );
    }
    if (!_supportedFajrVoices.contains(fajrVoiceId)) {
      throw ArgumentError.value(
        fajrVoiceId,
        'fajrVoiceId',
        'Unsupported Fajr voice "$fajrVoiceId". Supported voices: $_supportedFajrVoices',
      );
    }
    if (!_supportedModes.contains(mode)) {
      throw ArgumentError.value(
        mode,
        'mode',
        'Unsupported alarm mode "$mode". Supported modes: $_supportedModes',
      );
    }

    // 2. Initialize timezone data
    PrayerCalculator.ensureTimeZonesInitialized();
    final cityLocation = tz.getLocation(city.timezone);
    final cityLocalNow = tz.TZDateTime.from(nowUtc, cityLocation);

    final startYear = cityLocalNow.year;
    final startMonth = cityLocalNow.month;
    final startDay = cityLocalNow.day;

    final calculationStartDate = DateTime.utc(startYear, startMonth, startDay);
    final calculationEndDate = DateTime.utc(startYear, startMonth, startDay + 9);
    const calculationDateCount = 10;

    final calculationWindowStartUtc = tz.TZDateTime(
      cityLocation,
      startYear,
      startMonth,
      startDay,
      0,
      0,
      0,
    ).toUtc();
    final calculationWindowEndUtc = tz.TZDateTime(
      cityLocation,
      startYear,
      startMonth,
      startDay + 9,
      23,
      59,
      59,
      999,
    ).toUtc();

    // 3. Ten consecutive calendar dates iteration
    int skippedPastCount = 0;
    int unresolvedDaysCount = 0;
    final unresolvedReasons = <String>[];
    int missingCanonicalSlotsCount = 0;
    final missingCanonicalSlotDetails = <String>[];
    int estimatedDaysCount = 0;
    final estimatedReasons = <String>[];
    int totalCanonicalEventsEvaluated = 0;
    final futureEvents = <PrayerNotificationEvent>[];

    const canonicalTypes = [
      PrayerType.fajr,
      PrayerType.dhuhr,
      PrayerType.asr,
      PrayerType.maghrib,
      PrayerType.isha,
    ];

    for (int index = 0; index < 10; index++) {
      final civilDate = DateTime.utc(startYear, startMonth, startDay + index);
      final civilDateString = _formatCivilDate(civilDate);

      final prayerDay = _calculator.calculatePrayerDay(
        city: city,
        date: civilDate,
        settings: settings,
      );

      if (prayerDay.isUnresolved) {
        unresolvedDaysCount++;
        unresolvedReasons.add(
          '$civilDateString: ${prayerDay.statusMessage ?? "unresolved solar events"}',
        );
        continue;
      }

      if (prayerDay.isEstimated) {
        estimatedDaysCount++;
        if (prayerDay.estimationReason != null) {
          estimatedReasons.add(
            '$civilDateString: ${prayerDay.estimationReason}',
          );
        }
      }

      // Check all 5 canonical prayer slots individually on resolved days
      for (final prayerType in canonicalTypes) {
        final event = prayerDay.eventFor(prayerType);
        if (event == null) {
          missingCanonicalSlotsCount++;
          missingCanonicalSlotDetails.add(
            '$civilDateString: ${prayerType.name} is undefined (missing canonical solar event)',
          );
          continue;
        }

        totalCanonicalEventsEvaluated++;

        if (!event.utcDateTime.isAfter(nowUtc)) {
          skippedPastCount++;
          continue;
        }

        final prayerKey = event.type.name;
        // Key is strictly anchored to original civilDate, even if cross-midnight offset fired next day
        final eventKey = '${city.id}:$civilDateString:$prayerKey';
        final eventVoiceId = event.type == PrayerType.fajr
            ? fajrVoiceId
            : generalVoiceId;
        final notificationId = Crc32Util.positive31Bit(eventKey);

        futureEvents.add(
          PrayerNotificationEvent(
            eventKey: eventKey,
            prayerKey: prayerKey,
            calculationCivilDate: civilDateString,
            triggerDateTimeUtc: event.utcDateTime,
            triggerEpochMillis: event.utcDateTime.millisecondsSinceEpoch,
            voiceId: eventVoiceId,
            mode: mode,
            notificationId: notificationId,
            prayerType: event.type,
          ),
        );
      }
    }

    // 4. Chronological sorting and maximum 50 events limit
    futureEvents.sort();
    final retainedEvents = List<PrayerNotificationEvent>.unmodifiable(
      futureEvents.take(_maxPlanEvents),
    );

    // 5. Explicit internal ID collision detection across retained events
    final seenIds = <int, String>{};
    for (final event in retainedEvents) {
      if (seenIds.containsKey(event.notificationId)) {
        throw StateError(
          'Deterministic 31-bit ID collision detected: ID ${event.notificationId} generated for both "${seenIds[event.notificationId]}" and "${event.eventKey}".',
        );
      }
      seenIds[event.notificationId] = event.eventKey;
    }

    // 6. Arabic city name fallback and metadata
    final hasCustomArabicName =
        city.arabicName != null && city.arabicName!.trim().isNotEmpty;
    final usedFallbackCityName = !hasCustomArabicName;
    final cityNameAr = hasCustomArabicName
        ? city.arabicName!.trim()
        : city.name.trim();

    // 7. Actual coverage horizon calculation (truthful numeric sentinel when zero events)
    final hasZeroScheduledEvents = retainedEvents.isEmpty;
    final scheduledCoverageEndUtc = hasZeroScheduledEvents
        ? null
        : retainedEvents.last.triggerDateTimeUtc;
    final coverageHorizonUtc = scheduledCoverageEndUtc ?? nowUtc;

    // 8. Build iOS projection respecting budget of 64 and preventing ID collision with other notifications
    final iosProjection = _buildIosProjection(
      plannedEvents: retainedEvents,
      existingOtherIosPendingIds: sanitizedOtherIosPendingIds,
      city: city,
      lastCivilDate: calculationEndDate,
      nowUtc: nowUtc,
      cityLocation: cityLocation,
      seenPlannedEventIds: seenIds,
    );

    // 9. Coverage diagnostic reporting without false audible delivery claims
    final isPartialCoverage =
        unresolvedDaysCount > 0 ||
        missingCanonicalSlotsCount > 0 ||
        skippedPastCount > 0 ||
        retainedEvents.length < totalCanonicalEventsEvaluated ||
        retainedEvents.length < 50;

    final diagBuffer = StringBuffer();
    diagBuffer.write(
      'Calculated 10 civil dates (${_formatCivilDate(calculationStartDate)} to ${_formatCivilDate(calculationEndDate)}). ',
    );
    if (hasZeroScheduledEvents) {
      diagBuffer.write('Zero future prayer events scheduled. ');
    } else {
      diagBuffer.write('Retained ${retainedEvents.length} future events. ');
    }
    if (skippedPastCount > 0) {
      diagBuffer.write('$skippedPastCount past canonical prayers skipped. ');
    }
    if (missingCanonicalSlotsCount > 0) {
      diagBuffer.write(
        '$missingCanonicalSlotsCount canonical prayer slot(s) missing: ${missingCanonicalSlotDetails.join("; ")}. ',
      );
    }
    if (unresolvedDaysCount > 0) {
      diagBuffer.write(
        '$unresolvedDaysCount unresolved day(s): ${unresolvedReasons.join("; ")}. ',
      );
    }
    if (estimatedDaysCount > 0) {
      diagBuffer.write(
        '$estimatedDaysCount estimated day(s): ${estimatedReasons.join("; ")}. ',
      );
    }

    return PrayerNotificationPlan(
      city: city,
      settings: settings,
      generalVoiceId: generalVoiceId,
      fajrVoiceId: fajrVoiceId,
      mode: mode,
      cityNameAr: cityNameAr,
      hasCustomArabicName: hasCustomArabicName,
      usedFallbackCityName: usedFallbackCityName,
      calculationStartDate: calculationStartDate,
      calculationEndDate: calculationEndDate,
      calculationDateCount: calculationDateCount,
      calculationWindowStartUtc: calculationWindowStartUtc,
      calculationWindowEndUtc: calculationWindowEndUtc,
      scheduledCoverageEndUtc: scheduledCoverageEndUtc,
      coverageHorizonUtc: coverageHorizonUtc,
      hasZeroScheduledEvents: hasZeroScheduledEvents,
      events: retainedEvents,
      iosProjection: iosProjection,
      skippedPastCount: skippedPastCount,
      unresolvedDaysCount: unresolvedDaysCount,
      unresolvedReasons: List.unmodifiable(unresolvedReasons),
      missingCanonicalSlotsCount: missingCanonicalSlotsCount,
      missingCanonicalSlotDetails: List.unmodifiable(missingCanonicalSlotDetails),
      estimatedDaysCount: estimatedDaysCount,
      estimatedReasons: List.unmodifiable(estimatedReasons),
      totalCanonicalEventsEvaluated: totalCanonicalEventsEvaluated,
      retainedEventsCount: retainedEvents.length,
      isPartialCoverage: isPartialCoverage,
      coverageExplanation: diagBuffer.toString().trim(),
    );
  }

  /// Builds the iOS notification projection conforming strictly to the iOS 64 pending limit.
  /// All planned prayer events are forced to mode: 'short_alert'.
  IosNotificationProjection _buildIosProjection({
    required List<PrayerNotificationEvent> plannedEvents,
    required Set<int> existingOtherIosPendingIds,
    required SelectedCity city,
    required DateTime lastCivilDate,
    required DateTime nowUtc,
    required tz.Location cityLocation,
    required Map<int, String> seenPlannedEventIds,
  }) {
    final availableTotalSlots =
        _maxIosPlatformLimit - existingOtherIosPendingIds.length;

    // Case 1: Zero or negative capacity available
    if (availableTotalSlots <= 0) {
      return IosNotificationProjection(
        events: const [],
        renewalEvent: null,
        existingOtherPendingIds: existingOtherIosPendingIds,
        capacityStatus: IosTruncationStatus.zeroCapacity,
        coverageHorizonUtc: null,
        statusMessage:
            'Existing pending notifications (${existingOtherIosPendingIds.length}) exhaust or exceed the platform limit of 64. Zero capacity available for prayer events or renewal.',
      );
    }

    // Case 2: Exactly 1 slot available
    if (availableTotalSlots == 1) {
      if (plannedEvents.isEmpty) {
        return IosNotificationProjection(
          events: const [],
          renewalEvent: null,
          existingOtherPendingIds: existingOtherIosPendingIds,
          capacityStatus: IosTruncationStatus.zeroCapacity,
          coverageHorizonUtc: null,
          statusMessage:
              'Exactly 1 notification slot is available, but zero upcoming prayer events exist.',
        );
      }
      final singlePrayer = plannedEvents.first.toIosProjectedEvent();

      // Check external ID collision with existing other notifications
      if (existingOtherIosPendingIds.contains(singlePrayer.notificationId)) {
        return IosNotificationProjection(
          events: const [],
          renewalEvent: null,
          existingOtherPendingIds: existingOtherIosPendingIds,
          capacityStatus: IosTruncationStatus.idCollision,
          coverageHorizonUtc: null,
          collidingNotificationId: singlePrayer.notificationId,
          statusMessage:
              'ID collision detected: planned prayer event "${singlePrayer.eventKey}" ID ${singlePrayer.notificationId} collides with an existing other iOS notification ID. iOS projection emptied to protect existing notifications.',
        );
      }

      return IosNotificationProjection(
        events: List.unmodifiable([singlePrayer]),
        renewalEvent: null,
        existingOtherPendingIds: existingOtherIosPendingIds,
        capacityStatus: IosTruncationStatus.singleSlotPrayerOnly,
        coverageHorizonUtc: singlePrayer.triggerDateTimeUtc,
        statusMessage:
            'Exactly 1 notification slot is available (${existingOtherIosPendingIds.length} occupied by other features). Under the single-slot policy, the solitary slot is assigned to the planned imminent next prayer (${singlePrayer.prayerKey}) without renewal.',
      );
    }

    // Case 3: 2 or more slots available
    if (plannedEvents.isEmpty) {
      return IosNotificationProjection(
        events: const [],
        renewalEvent: null,
        existingOtherPendingIds: existingOtherIosPendingIds,
        capacityStatus: IosTruncationStatus.untruncated,
        coverageHorizonUtc: null,
        statusMessage:
            'Zero upcoming future prayer events available to project onto iOS.',
      );
    }

    final maxPrayerSlots = math.min(_maxPlanEvents, availableTotalSlots - 1);
    final isTruncatedByBudget = plannedEvents.length > maxPrayerSlots;

    // Projected payload explicitly forces short_alert mode on iOS
    final List<PrayerNotificationEvent> candidatePrayerEvents =
        (isTruncatedByBudget
                ? plannedEvents.take(maxPrayerSlots)
                : plannedEvents)
            .map((e) => e.toIosProjectedEvent())
            .toList();

    final actualCoverageExpiryUtc =
        candidatePrayerEvents.last.triggerDateTimeUtc;

    // Calculate deterministic useful future renewal timestamp strictly BEFORE actual coverage expiry
    DateTime renewalTimeUtc;
    if (!isTruncatedByBudget) {
      // Full coverage: city-local last calculation date midday converted to UTC
      final lastMiddayLocal = tz.TZDateTime(
        cityLocation,
        lastCivilDate.year,
        lastCivilDate.month,
        lastCivilDate.day,
        12,
        0,
        0,
      );
      final lastMiddayUtc = lastMiddayLocal.toUtc();
      if (lastMiddayUtc.isAfter(nowUtc) &&
          lastMiddayUtc.isBefore(actualCoverageExpiryUtc)) {
        renewalTimeUtc = lastMiddayUtc;
      } else if (actualCoverageExpiryUtc.isAfter(nowUtc)) {
        final candidate = actualCoverageExpiryUtc.subtract(
          const Duration(hours: 2),
        );
        if (candidate.isAfter(nowUtc)) {
          renewalTimeUtc = candidate;
        } else {
          final halfMs =
              actualCoverageExpiryUtc.difference(nowUtc).inMilliseconds ~/ 2;
          renewalTimeUtc = nowUtc.add(Duration(milliseconds: halfMs));
        }
      } else {
        renewalTimeUtc = nowUtc.add(const Duration(hours: 1));
      }
    } else {
      // Short projected budget: renewal must trigger strictly BEFORE actual projected coverage expiry
      final civilDateParts = candidatePrayerEvents.last.calculationCivilDate
          .split('-')
          .map(int.parse)
          .toList();
      final lastCoveredMiddayLocal = tz.TZDateTime(
        cityLocation,
        civilDateParts[0],
        civilDateParts[1],
        civilDateParts[2],
        12,
        0,
        0,
      );
      final lastCoveredMiddayUtc = lastCoveredMiddayLocal.toUtc();

      if (lastCoveredMiddayUtc.isAfter(nowUtc) &&
          lastCoveredMiddayUtc.isBefore(actualCoverageExpiryUtc)) {
        renewalTimeUtc = lastCoveredMiddayUtc;
      } else {
        final candidate = actualCoverageExpiryUtc.subtract(
          const Duration(hours: 2),
        );
        if (candidate.isAfter(nowUtc)) {
          renewalTimeUtc = candidate;
        } else {
          final halfMs =
              actualCoverageExpiryUtc.difference(nowUtc).inMilliseconds ~/ 2;
          renewalTimeUtc = nowUtc.add(Duration(milliseconds: halfMs));
        }
      }
    }

    final renewalKey =
        '${city.id}:${candidatePrayerEvents.last.calculationCivilDate}:renewal';
    final renewalId = Crc32Util.positive31Bit(renewalKey);

    // Internal collision detection against own planned prayer event IDs
    if (seenPlannedEventIds.containsKey(renewalId)) {
      throw StateError(
        'Deterministic 31-bit ID collision detected: Renewal ID $renewalId matches prayer event "${seenPlannedEventIds[renewalId]}".',
      );
    }

    // External collision detection against existing other iOS notification IDs
    for (final event in candidatePrayerEvents) {
      if (existingOtherIosPendingIds.contains(event.notificationId)) {
        return IosNotificationProjection(
          events: const [],
          renewalEvent: null,
          existingOtherPendingIds: existingOtherIosPendingIds,
          capacityStatus: IosTruncationStatus.idCollision,
          coverageHorizonUtc: null,
          collidingNotificationId: event.notificationId,
          statusMessage:
              'ID collision detected: planned prayer event "${event.eventKey}" ID ${event.notificationId} collides with an existing other iOS notification ID. iOS projection emptied to protect existing notifications.',
        );
      }
    }

    if (existingOtherIosPendingIds.contains(renewalId)) {
      return IosNotificationProjection(
        events: const [],
        renewalEvent: null,
        existingOtherPendingIds: existingOtherIosPendingIds,
        capacityStatus: IosTruncationStatus.idCollision,
        coverageHorizonUtc: null,
        collidingNotificationId: renewalId,
        statusMessage:
            'ID collision detected: renewal notification ID $renewalId collides with an existing other iOS notification ID. iOS projection emptied to protect existing notifications.',
      );
    }

    final renewalEvent = PrayerRenewalNotification(
      renewalKey: renewalKey,
      scheduledTimeUtc: renewalTimeUtc,
      scheduledEpochMillis: renewalTimeUtc.millisecondsSinceEpoch,
      notificationId: renewalId,
      title: 'تحديث مواعيد الصلاة',
      body: 'يرجى فتح تطبيق زاد الروح لتجديد جدول مواعيد الأذان للأيام القادمة.',
    );

    final capacityStatus = isTruncatedByBudget
        ? IosTruncationStatus.truncatedByBudget
        : IosTruncationStatus.untruncated;

    final statusMessage = isTruncatedByBudget
        ? 'Planned prayer events truncated from ${plannedEvents.length} to ${candidatePrayerEvents.length} due to iOS pending budget (${existingOtherIosPendingIds.length} other pending, 1 renewal slot reserved). Renewal scheduled before actual projected coverage expiry.'
        : 'All ${candidatePrayerEvents.length} planned future events scheduled alongside 1 renewal slot (${candidatePrayerEvents.length + 1 + existingOtherIosPendingIds.length} of 64 total pending notifications).';

    return IosNotificationProjection(
      events: List.unmodifiable(candidatePrayerEvents),
      renewalEvent: renewalEvent,
      existingOtherPendingIds: existingOtherIosPendingIds,
      capacityStatus: capacityStatus,
      coverageHorizonUtc: actualCoverageExpiryUtc,
      statusMessage: statusMessage,
    );
  }

  static String _formatCivilDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
