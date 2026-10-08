import 'package:flutter/foundation.dart';
import 'prayer_event.dart';
import 'prayer_settings.dart';
import 'selected_city.dart';

/// Single prayer notification event within an immutable prayer schedule plan.
@immutable
class PrayerNotificationEvent implements Comparable<PrayerNotificationEvent> {
  /// Unique architectural event key: "$cityId:$calculationCivilDate:$prayerKey".
  final String eventKey;

  /// Canonical prayer identifier: 'fajr', 'dhuhr', 'asr', 'maghrib', or 'isha'.
  final String prayerKey;

  /// Civil calendar calculation date formatted as 'YYYY-MM-DD' in the selected city's timezone.
  final String calculationCivilDate;

  /// Trigger instant anchored strictly to UTC.
  final DateTime triggerDateTimeUtc;

  /// Epoch millisecond timestamp of the trigger instant.
  final int triggerEpochMillis;

  /// Voice audio identifier for this specific event ('adam', 'atcovi', or 'malmo_fajr').
  final String voiceId;

  /// Delivery mode ('full_adhan' or 'short_alert').
  final String mode;

  /// Deterministic positive 31-bit integer notification identifier (CRC32 IEEE 802.3).
  final int notificationId;

  /// Domain canonical prayer type enum.
  final PrayerType prayerType;

  const PrayerNotificationEvent({
    required this.eventKey,
    required this.prayerKey,
    required this.calculationCivilDate,
    required this.triggerDateTimeUtc,
    required this.triggerEpochMillis,
    required this.voiceId,
    required this.mode,
    required this.notificationId,
    required this.prayerType,
  });

  /// Serializes into the exact shape expected by the native Android MethodChannel contract
  /// and `PrayerPlanValidator.kt` (excluding expectedToken which is injected at bridge level).
  Map<String, dynamic> toNativeMap() => {
    'eventKey': eventKey,
    'prayerKey': prayerKey,
    'calculationCivilDate': calculationCivilDate,
    'triggerEpochMillis': triggerEpochMillis,
    'voiceId': voiceId,
    'mode': mode,
  };

  /// Returns an immutable copy with optional overridden fields.
  PrayerNotificationEvent copyWith({
    String? eventKey,
    String? prayerKey,
    String? calculationCivilDate,
    DateTime? triggerDateTimeUtc,
    int? triggerEpochMillis,
    String? voiceId,
    String? mode,
    int? notificationId,
    PrayerType? prayerType,
  }) {
    return PrayerNotificationEvent(
      eventKey: eventKey ?? this.eventKey,
      prayerKey: prayerKey ?? this.prayerKey,
      calculationCivilDate: calculationCivilDate ?? this.calculationCivilDate,
      triggerDateTimeUtc: triggerDateTimeUtc ?? this.triggerDateTimeUtc,
      triggerEpochMillis: triggerEpochMillis ?? this.triggerEpochMillis,
      voiceId: voiceId ?? this.voiceId,
      mode: mode ?? this.mode,
      notificationId: notificationId ?? this.notificationId,
      prayerType: prayerType ?? this.prayerType,
    );
  }

  /// Creates a projected event for iOS where mode is strictly 'short_alert'.
  PrayerNotificationEvent toIosProjectedEvent() => copyWith(mode: 'short_alert');

  @override
  int compareTo(PrayerNotificationEvent other) {
    final cmp = triggerDateTimeUtc.compareTo(other.triggerDateTimeUtc);
    if (cmp != 0) return cmp;
    return prayerType.index.compareTo(other.prayerType.index);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerNotificationEvent &&
          other.eventKey == eventKey &&
          other.prayerKey == prayerKey &&
          other.calculationCivilDate == calculationCivilDate &&
          other.triggerEpochMillis == triggerEpochMillis &&
          other.voiceId == voiceId &&
          other.mode == mode &&
          other.notificationId == notificationId &&
          other.prayerType == prayerType;

  @override
  int get hashCode => Object.hash(
    eventKey,
    prayerKey,
    calculationCivilDate,
    triggerEpochMillis,
    voiceId,
    mode,
    notificationId,
    prayerType,
  );

  @override
  String toString() =>
      'PrayerNotificationEvent(key: $eventKey, id: $notificationId, triggerUtc: $triggerDateTimeUtc, voice: $voiceId, mode: $mode)';
}

/// Renewal notification scheduled on iOS prompting the user to reopen the app
/// to renew the bounded prayer schedule before it expires.
@immutable
class PrayerRenewalNotification {
  /// Distinct deterministic key for the renewal notification.
  final String renewalKey;

  /// Trigger instant strictly in UTC.
  final DateTime scheduledTimeUtc;

  /// Epoch millisecond timestamp of the renewal trigger.
  final int scheduledEpochMillis;

  /// Deterministic positive 31-bit integer identifier.
  final int notificationId;

  /// Display title for the renewal notification.
  final String title;

  /// Display body message for the renewal notification.
  final String body;

  const PrayerRenewalNotification({
    required this.renewalKey,
    required this.scheduledTimeUtc,
    required this.scheduledEpochMillis,
    required this.notificationId,
    required this.title,
    required this.body,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerRenewalNotification &&
          other.renewalKey == renewalKey &&
          other.scheduledEpochMillis == scheduledEpochMillis &&
          other.notificationId == notificationId &&
          other.title == title &&
          other.body == body;

  @override
  int get hashCode => Object.hash(
    renewalKey,
    scheduledEpochMillis,
    notificationId,
    title,
    body,
  );

  @override
  String toString() =>
      'PrayerRenewalNotification(key: $renewalKey, id: $notificationId, time: $scheduledTimeUtc)';
}

/// Truncation and capacity status of the iOS notification projection.
enum IosTruncationStatus {
  /// All planned future events fit within the available iOS budget alongside a renewal slot.
  untruncated,

  /// Planned events were truncated to fit within the system budget of 64 while reserving 1 renewal slot.
  truncatedByBudget,

  /// Exactly 1 slot was available; assigned to the planned imminent next prayer without renewal.
  singleSlotPrayerOnly,

  /// Zero slots available because existing other notifications consume the entire budget of 64.
  zeroCapacity,

  /// An intended prayer or renewal notification ID collided with an existing other notification ID.
  /// Projection was emptied to protect third-party notifications from silent overwrite.
  idCollision,
}

/// iOS projection representing the subset of planned events and renewal slot
/// fitting within iOS's hard 64 pending notification ceiling.
@immutable
class IosNotificationProjection {
  /// Planned prayer events scheduled on iOS (at most 50, strictly mode: short_alert).
  final List<PrayerNotificationEvent> events;

  /// Reserved renewal notification if capacity and a useful future instant exist.
  final PrayerRenewalNotification? renewalEvent;

  /// Unmodifiable set of pending notification IDs belonging to other app features/owners.
  final Set<int> existingOtherPendingIds;

  /// Capacity status explaining whether and why truncation or collision occurred.
  final IosTruncationStatus capacityStatus;

  /// Coverage horizon for the iOS projection (instant of the last scheduled prayer event, or null if no events).
  final DateTime? coverageHorizonUtc;

  /// Human-readable explanation of capacity allocation and policy choices.
  final String statusMessage;

  /// If capacityStatus is idCollision, the specific notification ID that collided.
  final int? collidingNotificationId;

  IosNotificationProjection({
    required List<PrayerNotificationEvent> events,
    this.renewalEvent,
    required Set<int> existingOtherPendingIds,
    required this.capacityStatus,
    this.coverageHorizonUtc,
    required this.statusMessage,
    this.collidingNotificationId,
  })  : events = List.unmodifiable(events),
        existingOtherPendingIds = Set.unmodifiable(existingOtherPendingIds);

  /// Count of existing pending notifications belonging to other owners.
  int get existingOtherPendingCount => existingOtherPendingIds.length;

  /// Total count of scheduled items belonging to this plan (prayers + renewal).
  int get planScheduledCount => events.length + (renewalEvent != null ? 1 : 0);

  /// Grand total of all pending notifications on iOS including other owners.
  int get totalPendingCount => planScheduledCount + existingOtherPendingCount;

  /// Whether any planned events were omitted due to budget constraints or collision.
  bool get isTruncated => capacityStatus != IosTruncationStatus.untruncated;

  /// Whether a renewal notification was successfully scheduled.
  bool get hasRenewal => renewalEvent != null;

  /// Whether an ID collision with other notifications was detected.
  bool get hasIdCollision => capacityStatus == IosTruncationStatus.idCollision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IosNotificationProjection &&
          listEquals(other.events, events) &&
          other.renewalEvent == renewalEvent &&
          setEquals(other.existingOtherPendingIds, existingOtherPendingIds) &&
          other.capacityStatus == capacityStatus &&
          other.coverageHorizonUtc == coverageHorizonUtc &&
          other.statusMessage == statusMessage &&
          other.collidingNotificationId == collidingNotificationId;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(events),
    renewalEvent,
    Object.hashAllUnordered(existingOtherPendingIds),
    capacityStatus,
    coverageHorizonUtc,
    statusMessage,
    collidingNotificationId,
  );

  @override
  String toString() =>
      'IosNotificationProjection(events: ${events.length}, renewal: $hasRenewal, total: $totalPendingCount, status: $capacityStatus)';
}

/// Complete, immutable multi-day prayer notification schedule plan.
@immutable
class PrayerNotificationPlan {
  /// Selected city for which prayers were computed.
  final SelectedCity city;

  /// Prayer settings used for calculation.
  final PrayerSettings settings;

  /// Audio voice identifier applied to general prayers ('adam' or 'atcovi').
  final String generalVoiceId;

  /// Audio voice identifier applied to Fajr ('adam', 'atcovi', or 'malmo_fajr').
  final String fajrVoiceId;

  /// Delivery mode for native alarms ('full_adhan' or 'short_alert').
  final String mode;

  /// Resolved Arabic name for the city (guaranteed non-empty; falls back to city.name if blank/null).
  final String cityNameAr;

  /// Whether the city provided a non-empty native Arabic name.
  final bool hasCustomArabicName;

  /// Whether the fallback English name was used due to missing/blank Arabic name.
  final bool usedFallbackCityName;

  /// Start date of the 10-date calculation range (UTC civil date).
  final DateTime calculationStartDate;

  /// End date of the 10-date calculation range (UTC civil date).
  final DateTime calculationEndDate;

  /// Number of distinct city calendar dates calculated (strictly 10).
  final int calculationDateCount;

  /// Exact start instant of the 10-day civil calculation window in UTC.
  final DateTime calculationWindowStartUtc;

  /// Exact end instant of the 10-day civil calculation window in UTC.
  final DateTime calculationWindowEndUtc;

  /// Actual scheduled coverage expiry instant in UTC (trigger instant of the last retained future event).
  /// Null if zero future events were scheduled.
  final DateTime? scheduledCoverageEndUtc;

  /// Truthful numeric coverage horizon instant in UTC. When zero events are scheduled,
  /// this is set to nowUtc as a truthful sentinel so native contract shape validation succeeds.
  final DateTime coverageHorizonUtc;

  /// Whether zero future events were retained in this plan.
  final bool hasZeroScheduledEvents;

  /// Chronologically ordered list of future canonical prayer events across the 10-day window (<= 50).
  final List<PrayerNotificationEvent> events;

  /// iOS-specific projection observing the 64-notification platform ceiling and forcing short_alert.
  final IosNotificationProjection iosProjection;

  /// Number of past canonical prayer events that were evaluated and skipped (utc <= nowUtc).
  final int skippedPastCount;

  /// Number of calendar days within the 10-day window where solar times were entirely unresolved.
  final int unresolvedDaysCount;

  /// Diagnostic reasons for any unresolved days.
  final List<String> unresolvedReasons;

  /// Number of canonical prayer slots that were null/undefined on resolved calendar days.
  final int missingCanonicalSlotsCount;

  /// Diagnostic details for each missing canonical prayer slot on resolved days.
  final List<String> missingCanonicalSlotDetails;

  /// Number of calendar days where high-latitude or polar estimation was applied.
  final int estimatedDaysCount;

  /// Diagnostic reasons for any estimated days.
  final List<String> estimatedReasons;

  /// Total valid canonical prayer events evaluated across all 10 calendar days (future + past).
  final int totalCanonicalEventsEvaluated;

  /// Number of future canonical events retained in this plan (events.length).
  final int retainedEventsCount;

  /// Whether coverage is partial (due to past events, missing slots, unresolved days, or truncated budget).
  final bool isPartialCoverage;

  /// Detailed human-readable explanation of coverage status.
  final String coverageExplanation;

  PrayerNotificationPlan({
    required this.city,
    required this.settings,
    required this.generalVoiceId,
    required this.fajrVoiceId,
    required this.mode,
    required this.cityNameAr,
    required this.hasCustomArabicName,
    required this.usedFallbackCityName,
    required this.calculationStartDate,
    required this.calculationEndDate,
    required this.calculationDateCount,
    required this.calculationWindowStartUtc,
    required this.calculationWindowEndUtc,
    required this.scheduledCoverageEndUtc,
    required this.coverageHorizonUtc,
    required this.hasZeroScheduledEvents,
    required List<PrayerNotificationEvent> events,
    required this.iosProjection,
    required this.skippedPastCount,
    required this.unresolvedDaysCount,
    required List<String> unresolvedReasons,
    required this.missingCanonicalSlotsCount,
    required List<String> missingCanonicalSlotDetails,
    required this.estimatedDaysCount,
    required List<String> estimatedReasons,
    required this.totalCanonicalEventsEvaluated,
    required this.retainedEventsCount,
    required this.isPartialCoverage,
    required this.coverageExplanation,
  })  : events = List.unmodifiable(events),
        unresolvedReasons = List.unmodifiable(unresolvedReasons),
        missingCanonicalSlotDetails = List.unmodifiable(missingCanonicalSlotDetails),
        estimatedReasons = List.unmodifiable(estimatedReasons);

  /// Native Android MethodChannel map representation matching `ANDROID-NATIVE-ALARM-CONTRACT.md`.
  /// Note: `expectedToken` is intentionally omitted here as it is attached atomically by the bridge.
  Map<String, dynamic> toNativeMap() => {
    'cityId': city.id,
    'cityNameAr': cityNameAr,
    'timezone': city.timezone,
    'generalVoiceId': generalVoiceId,
    'fajrVoiceId': fajrVoiceId,
    'mode': mode,
    'coverageHorizonUtc': coverageHorizonUtc.millisecondsSinceEpoch,
    'events': events.map((e) => e.toNativeMap()).toList(),
  };

  /// Convenience getter for iOS projection planned events.
  List<PrayerNotificationEvent> get iosEvents => iosProjection.events;

  /// Convenience getter for iOS renewal notification.
  PrayerRenewalNotification? get iosRenewal => iosProjection.renewalEvent;

  /// Convenience getter for iOS coverage horizon.
  DateTime? get iosCoverageHorizonUtc => iosProjection.coverageHorizonUtc;

  /// Convenience getter for iOS truncation status.
  IosTruncationStatus get iosTruncationStatus => iosProjection.capacityStatus;

  /// Convenience getter for iOS capacity diagnostic message.
  String get iosCapacityMessage => iosProjection.statusMessage;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrayerNotificationPlan &&
          other.city == city &&
          other.settings == settings &&
          other.generalVoiceId == generalVoiceId &&
          other.fajrVoiceId == fajrVoiceId &&
          other.mode == mode &&
          other.cityNameAr == cityNameAr &&
          other.calculationStartDate == calculationStartDate &&
          other.calculationEndDate == calculationEndDate &&
          other.calculationDateCount == calculationDateCount &&
          other.calculationWindowStartUtc == calculationWindowStartUtc &&
          other.calculationWindowEndUtc == calculationWindowEndUtc &&
          other.scheduledCoverageEndUtc == scheduledCoverageEndUtc &&
          other.coverageHorizonUtc == coverageHorizonUtc &&
          other.hasZeroScheduledEvents == hasZeroScheduledEvents &&
          listEquals(other.events, events) &&
          other.iosProjection == iosProjection;

  @override
  int get hashCode => Object.hashAll([
    city,
    settings,
    generalVoiceId,
    fajrVoiceId,
    mode,
    cityNameAr,
    calculationStartDate,
    calculationEndDate,
    calculationDateCount,
    calculationWindowStartUtc,
    calculationWindowEndUtc,
    scheduledCoverageEndUtc,
    coverageHorizonUtc,
    hasZeroScheduledEvents,
    Object.hashAll(events),
    iosProjection,
  ]);

  @override
  String toString() =>
      'PrayerNotificationPlan(city: ${city.name}, events: ${events.length}, ios: ${iosProjection.events.length}, horizon: $coverageHorizonUtc, zeroEvents: $hasZeroScheduledEvents)';
}
