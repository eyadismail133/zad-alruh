import 'package:adhan/adhan.dart';

/// Strategy for resolving high-latitude and polar days where the sun never crosses the horizon.
enum PolarDayResolution {
  /// Returns an actionable unresolved-day result without fabricating events (safe default).
  unresolved,

  /// Bounded nearest-valid-latitude strategy (Aqrab Al-Balad) using the same Adhan calculation engine.
  nearestLatitude,
}

/// Explicit policy for applying the Umm Al-Qura extra 30 minutes to Isha during Ramadan.
enum UmmAlQuraRamadanPolicy {
  /// Islamic evening policy (default): Maghrib begins the Islamic date. The evening following
  /// the sighting of the Ramadan crescent (night of 1 Ramadan / eve of March 11, 2024) is the
  /// first Tarawih night and receives +30 minutes (120 minutes total). The evening of the 30th
  /// of Ramadan (night of 1 Shawwal / Eid night) concludes Ramadan at Maghrib and returns to 90 minutes.
  eveningOfRamadan,

  /// Daytime civil date policy: applies the +30 minute adjustment strictly on calendar days
  /// where the daytime Hijri month is Ramadan (Month 9).
  civilDay,

  /// Disables automatic Ramadan extra minutes (Isha remains 90 minutes after Maghrib).
  disabled,
}

/// Immutable configuration controlling offline prayer calculations with strict runtime validation.
class PrayerSettings {
  final CalculationMethod calculationMethod;
  final Madhab asrMadhab;
  final HighLatitudeRule highLatitudeRule;
  final PolarDayResolution polarResolution;
  final UmmAlQuraRamadanPolicy ummAlQuraRamadanPolicy;
  final int hijriDayAdjustment;

  // Additive minute offsets (bounded to ±120 minutes)
  final int fajrOffsetMinutes;
  final int sunriseOffsetMinutes;
  final int dhuhrOffsetMinutes;
  final int asrOffsetMinutes;
  final int maghribOffsetMinutes;
  final int ishaOffsetMinutes;

  /// The set of calculation methods verified and supported by this application.
  static const Set<CalculationMethod> supportedMethods = {
    CalculationMethod.egyptian,
    CalculationMethod.muslim_world_league,
    CalculationMethod.umm_al_qura,
    CalculationMethod.karachi,
    CalculationMethod.north_america,
    CalculationMethod.moon_sighting_committee,
  };

  /// Public constructor enforcing comprehensive runtime validation.
  PrayerSettings({
    this.calculationMethod = CalculationMethod.egyptian,
    this.asrMadhab = Madhab.shafi,
    this.highLatitudeRule = HighLatitudeRule.middle_of_the_night,
    this.polarResolution = PolarDayResolution.unresolved,
    this.ummAlQuraRamadanPolicy = UmmAlQuraRamadanPolicy.eveningOfRamadan,
    this.hijriDayAdjustment = 0,
    this.fajrOffsetMinutes = 0,
    this.sunriseOffsetMinutes = 0,
    this.dhuhrOffsetMinutes = 0,
    this.asrOffsetMinutes = 0,
    this.maghribOffsetMinutes = 0,
    this.ishaOffsetMinutes = 0,
  }) {
    if (!supportedMethods.contains(calculationMethod)) {
      throw ArgumentError.value(
        calculationMethod,
        'calculationMethod',
        'Unsupported prayer calculation method. Supported methods: $supportedMethods',
      );
    }
    if (hijriDayAdjustment < -2 || hijriDayAdjustment > 2) {
      throw ArgumentError.value(
        hijriDayAdjustment,
        'hijriDayAdjustment',
        'Hijri day adjustment must be between -2 and 2 days',
      );
    }
    _validateOffset(fajrOffsetMinutes, 'fajrOffsetMinutes');
    _validateOffset(sunriseOffsetMinutes, 'sunriseOffsetMinutes');
    _validateOffset(dhuhrOffsetMinutes, 'dhuhrOffsetMinutes');
    _validateOffset(asrOffsetMinutes, 'asrOffsetMinutes');
    _validateOffset(maghribOffsetMinutes, 'maghribOffsetMinutes');
    _validateOffset(ishaOffsetMinutes, 'ishaOffsetMinutes');
  }

  static void _validateOffset(int offset, String name) {
    if (offset < -120 || offset > 120) {
      throw ArgumentError.value(
        offset,
        name,
        'Minute offset must be between -120 and 120 minutes',
      );
    }
  }

  /// Factory creating default settings for Egypt (Egyptian General Authority of Survey).
  factory PrayerSettings.egyptDefault() => PrayerSettings(
    calculationMethod: CalculationMethod.egyptian,
    asrMadhab: Madhab.shafi,
    highLatitudeRule: HighLatitudeRule.middle_of_the_night,
  );

  /// Factory creating default settings for other countries (Muslim World League).
  factory PrayerSettings.mwlDefault() => PrayerSettings(
    calculationMethod: CalculationMethod.muslim_world_league,
    asrMadhab: Madhab.shafi,
    highLatitudeRule: HighLatitudeRule.middle_of_the_night,
  );

  /// Converts the manual minute offsets into an Adhan [PrayerAdjustments] object.
  PrayerAdjustments toAdhanAdjustments() {
    return PrayerAdjustments(
      fajr: fajrOffsetMinutes,
      sunrise: sunriseOffsetMinutes,
      dhuhr: dhuhrOffsetMinutes,
      asr: asrOffsetMinutes,
      maghrib: maghribOffsetMinutes,
      isha: ishaOffsetMinutes,
    );
  }

  PrayerSettings copyWith({
    CalculationMethod? calculationMethod,
    Madhab? asrMadhab,
    HighLatitudeRule? highLatitudeRule,
    PolarDayResolution? polarResolution,
    UmmAlQuraRamadanPolicy? ummAlQuraRamadanPolicy,
    int? hijriDayAdjustment,
    int? fajrOffsetMinutes,
    int? sunriseOffsetMinutes,
    int? dhuhrOffsetMinutes,
    int? asrOffsetMinutes,
    int? maghribOffsetMinutes,
    int? ishaOffsetMinutes,
  }) {
    return PrayerSettings(
      calculationMethod: calculationMethod ?? this.calculationMethod,
      asrMadhab: asrMadhab ?? this.asrMadhab,
      highLatitudeRule: highLatitudeRule ?? this.highLatitudeRule,
      polarResolution: polarResolution ?? this.polarResolution,
      ummAlQuraRamadanPolicy:
          ummAlQuraRamadanPolicy ?? this.ummAlQuraRamadanPolicy,
      hijriDayAdjustment: hijriDayAdjustment ?? this.hijriDayAdjustment,
      fajrOffsetMinutes: fajrOffsetMinutes ?? this.fajrOffsetMinutes,
      sunriseOffsetMinutes: sunriseOffsetMinutes ?? this.sunriseOffsetMinutes,
      dhuhrOffsetMinutes: dhuhrOffsetMinutes ?? this.dhuhrOffsetMinutes,
      asrOffsetMinutes: asrOffsetMinutes ?? this.asrOffsetMinutes,
      maghribOffsetMinutes: maghribOffsetMinutes ?? this.maghribOffsetMinutes,
      ishaOffsetMinutes: ishaOffsetMinutes ?? this.ishaOffsetMinutes,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PrayerSettings &&
        other.calculationMethod == calculationMethod &&
        other.asrMadhab == asrMadhab &&
        other.highLatitudeRule == highLatitudeRule &&
        other.polarResolution == polarResolution &&
        other.ummAlQuraRamadanPolicy == ummAlQuraRamadanPolicy &&
        other.hijriDayAdjustment == hijriDayAdjustment &&
        other.fajrOffsetMinutes == fajrOffsetMinutes &&
        other.sunriseOffsetMinutes == sunriseOffsetMinutes &&
        other.dhuhrOffsetMinutes == dhuhrOffsetMinutes &&
        other.asrOffsetMinutes == asrOffsetMinutes &&
        other.maghribOffsetMinutes == maghribOffsetMinutes &&
        other.ishaOffsetMinutes == ishaOffsetMinutes;
  }

  @override
  int get hashCode => Object.hash(
    calculationMethod,
    asrMadhab,
    highLatitudeRule,
    polarResolution,
    ummAlQuraRamadanPolicy,
    hijriDayAdjustment,
    fajrOffsetMinutes,
    sunriseOffsetMinutes,
    dhuhrOffsetMinutes,
    asrOffsetMinutes,
    maghribOffsetMinutes,
    ishaOffsetMinutes,
  );

  @override
  String toString() =>
      'PrayerSettings(method: ${calculationMethod.name}, madhab: ${asrMadhab.name}, highLat: ${highLatitudeRule.name}, polar: ${polarResolution.name}, ramadanPolicy: ${ummAlQuraRamadanPolicy.name})';
}
