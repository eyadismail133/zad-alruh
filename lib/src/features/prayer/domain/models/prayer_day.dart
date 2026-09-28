import 'prayer_event.dart';
import 'prayer_settings.dart';
import 'selected_city.dart';

/// Immutable representation of the calculated prayer events for a single civil calendar day.
class PrayerDay {
  final SelectedCity city;
  final DateTime civilDate;
  final PrayerSettings settings;

  final PrayerEvent? fajr;
  final PrayerEvent? sunrise;
  final PrayerEvent? dhuhr;
  final PrayerEvent? asr;
  final PrayerEvent? maghrib;
  final PrayerEvent? isha;

  /// Whether any prayer times on this day were estimated via a high-latitude approximation
  /// (such as bounded nearest-valid-latitude / Aqrab Al-Balad for polar days).
  final bool isEstimated;
  final String? estimationReason;

  /// Whether this day is an unresolved polar day where solar events could not be computed
  /// and no estimation strategy was activated.
  final bool isUnresolved;
  final String? statusMessage;

  PrayerDay({
    required this.city,
    required DateTime civilDate,
    required this.settings,
    this.fajr,
    this.sunrise,
    this.dhuhr,
    this.asr,
    this.maghrib,
    this.isha,
    this.isEstimated = false,
    this.estimationReason,
    this.isUnresolved = false,
    this.statusMessage,
  }) : civilDate = DateTime.utc(civilDate.year, civilDate.month, civilDate.day);

  /// Factory creating an actionable unresolved-day result when solar events cannot be computed.
  factory PrayerDay.unresolved({
    required SelectedCity city,
    required DateTime civilDate,
    required PrayerSettings settings,
    required String reason,
  }) {
    return PrayerDay(
      city: city,
      civilDate: civilDate,
      settings: settings,
      isUnresolved: true,
      isEstimated: false,
      statusMessage: reason,
    );
  }

  /// All non-null prayer events ordered chronologically in UTC.
  List<PrayerEvent> get orderedEvents {
    if (isUnresolved) return const [];
    final events = <PrayerEvent>[
      if (fajr != null) fajr!,
      if (sunrise != null) sunrise!,
      if (dhuhr != null) dhuhr!,
      if (asr != null) asr!,
      if (maghrib != null) maghrib!,
      if (isha != null) isha!,
    ];
    events.sort((a, b) => a.utcDateTime.compareTo(b.utcDateTime));
    return List.unmodifiable(events);
  }

  /// All five canonical daily prayers (excluding sunrise) ordered chronologically in UTC.
  List<PrayerEvent> get canonicalPrayers {
    if (isUnresolved) return const [];
    final events = <PrayerEvent>[
      if (fajr != null) fajr!,
      if (dhuhr != null) dhuhr!,
      if (asr != null) asr!,
      if (maghrib != null) maghrib!,
      if (isha != null) isha!,
    ];
    events.sort((a, b) => a.utcDateTime.compareTo(b.utcDateTime));
    return List.unmodifiable(events);
  }

  /// Retrieves the event for a specific prayer type, or null if undefined.
  PrayerEvent? eventFor(PrayerType type) {
    switch (type) {
      case PrayerType.fajr:
        return fajr;
      case PrayerType.sunrise:
        return sunrise;
      case PrayerType.dhuhr:
        return dhuhr;
      case PrayerType.asr:
        return asr;
      case PrayerType.maghrib:
        return maghrib;
      case PrayerType.isha:
        return isha;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrayerDay &&
        other.city == city &&
        other.civilDate.year == civilDate.year &&
        other.civilDate.month == civilDate.month &&
        other.civilDate.day == civilDate.day &&
        other.settings == settings &&
        other.fajr == fajr &&
        other.sunrise == sunrise &&
        other.dhuhr == dhuhr &&
        other.asr == asr &&
        other.maghrib == maghrib &&
        other.isha == isha &&
        other.isEstimated == isEstimated &&
        other.isUnresolved == isUnresolved;
  }

  @override
  int get hashCode => Object.hash(
    city,
    civilDate.year,
    civilDate.month,
    civilDate.day,
    settings,
    fajr,
    sunrise,
    dhuhr,
    asr,
    maghrib,
    isha,
    isEstimated,
    isUnresolved,
  );

  @override
  String toString() =>
      'PrayerDay(city: ${city.name}, date: ${civilDate.year}-${civilDate.month}-${civilDate.day}, estimated: $isEstimated, unresolved: $isUnresolved)';
}
