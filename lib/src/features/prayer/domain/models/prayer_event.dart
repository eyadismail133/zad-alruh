import 'package:timezone/timezone.dart' as tz;

/// Enumeration of all five canonical daily prayers plus sunrise.
enum PrayerType {
  fajr(arabicName: 'الفجر', englishName: 'Fajr', isPrayer: true),
  sunrise(arabicName: 'الشروق', englishName: 'Sunrise', isPrayer: false),
  dhuhr(arabicName: 'الظهر', englishName: 'Dhuhr', isPrayer: true),
  asr(arabicName: 'العصر', englishName: 'Asr', isPrayer: true),
  maghrib(arabicName: 'المغرب', englishName: 'Maghrib', isPrayer: true),
  isha(arabicName: 'العشاء', englishName: 'Isha', isPrayer: true);

  final String arabicName;
  final String englishName;
  final bool isPrayer;

  const PrayerType({
    required this.arabicName,
    required this.englishName,
    required this.isPrayer,
  });
}

/// An immutable point-in-time prayer event strictly anchored to a UTC instant.
class PrayerEvent implements Comparable<PrayerEvent> {
  final PrayerType type;
  final DateTime utcDateTime;

  PrayerEvent({required this.type, required this.utcDateTime}) {
    if (!utcDateTime.isUtc) {
      throw ArgumentError.value(
        utcDateTime,
        'utcDateTime',
        'PrayerEvent utcDateTime must be a UTC DateTime',
      );
    }
  }

  /// Converts the UTC instant to a local timezone representation using the IANA timezone ID.
  tz.TZDateTime toCityTime(String ianaTimezone) {
    final location = tz.getLocation(ianaTimezone);
    return tz.TZDateTime.from(utcDateTime, location);
  }

  /// Formatted 'HH:mm' representation in the specified city IANA timezone.
  String formatCityTime(String ianaTimezone) {
    final cityTime = toCityTime(ianaTimezone);
    final hour = cityTime.hour.toString().padLeft(2, '0');
    final minute = cityTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  int compareTo(PrayerEvent other) => utcDateTime.compareTo(other.utcDateTime);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrayerEvent &&
        other.type == type &&
        other.utcDateTime.isAtSameMomentAs(utcDateTime);
  }

  @override
  int get hashCode => Object.hash(type, utcDateTime.millisecondsSinceEpoch);

  @override
  String toString() =>
      'PrayerEvent(${type.englishName}, UTC: ${utcDateTime.toIso8601String()})';
}
