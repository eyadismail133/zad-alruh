import 'package:adhan/adhan.dart';
import 'package:flutter/foundation.dart';
import '../../../prayer/domain/models/prayer_settings.dart';

const Object kPreferenceSentinel = Object();

@immutable
class UserPreferences {
  static const int defaultSelectedCityId = 360630;
  static const String defaultGeneralAdhanVoice = 'adam';
  static const String defaultFajrAdhanVoice = 'malmo_fajr';
  static const Set<String> allowedGeneralAdhanVoices = {'adam', 'atcovi'};
  static const Set<String> allowedFajrAdhanVoices = {
    'adam',
    'atcovi',
    'malmo_fajr',
  };

  final String darkMode;
  final double textScale;
  final int? selectedCityId;
  final String selectedCity;
  final String selectedTimezone;
  final CalculationMethod? calculationMethodOverride;
  final Madhab asrMadhab;
  final HighLatitudeRule highLatitudeRule;
  final PolarDayResolution polarResolution;
  final UmmAlQuraRamadanPolicy ramadanPolicy;
  final int hijriDayAdjustment;
  final int fajrOffset;
  final int sunriseOffset;
  final int dhuhrOffset;
  final int asrOffset;
  final int maghribOffset;
  final int ishaOffset;
  final int quranDefaultGoal;
  final bool notificationsEnabled;
  final String? activeDhikrSessionId;
  final String generalAdhanVoice;
  final String fajrAdhanVoice;
  final bool voiceRecoveryNotice;
  final bool prayerSettingsRecoveryNotice;
  final DateTime? updatedAt;

  const UserPreferences({
    this.darkMode = 'system',
    this.textScale = 1.0,
    this.selectedCityId = defaultSelectedCityId,
    this.selectedCity = 'القاهرة',
    this.selectedTimezone = 'Africa/Cairo',
    this.calculationMethodOverride,
    this.asrMadhab = Madhab.shafi,
    this.highLatitudeRule = HighLatitudeRule.middle_of_the_night,
    this.polarResolution = PolarDayResolution.unresolved,
    this.ramadanPolicy = UmmAlQuraRamadanPolicy.eveningOfRamadan,
    this.hijriDayAdjustment = 0,
    this.fajrOffset = 0,
    this.sunriseOffset = 0,
    this.dhuhrOffset = 0,
    this.asrOffset = 0,
    this.maghribOffset = 0,
    this.ishaOffset = 0,
    this.quranDefaultGoal = 2,
    this.notificationsEnabled = false,
    this.activeDhikrSessionId,
    this.generalAdhanVoice = defaultGeneralAdhanVoice,
    this.fajrAdhanVoice = defaultFajrAdhanVoice,
    this.voiceRecoveryNotice = false,
    this.prayerSettingsRecoveryNotice = false,
    this.updatedAt,
  });

  UserPreferences copyWith({
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
    Object? activeDhikrSessionId = kPreferenceSentinel,
    bool clearActiveDhikrSession = false,
    String? generalAdhanVoice,
    String? fajrAdhanVoice,
    bool? voiceRecoveryNotice,
    bool? prayerSettingsRecoveryNotice,
    DateTime? updatedAt,
  }) {
    if (generalAdhanVoice != null &&
        !allowedGeneralAdhanVoices.contains(generalAdhanVoice)) {
      throw ArgumentError.value(
        generalAdhanVoice,
        'generalAdhanVoice',
        'Invalid general adhan voice ID: must be adam or atcovi',
      );
    }
    if (fajrAdhanVoice != null &&
        !allowedFajrAdhanVoices.contains(fajrAdhanVoice)) {
      throw ArgumentError.value(
        fajrAdhanVoice,
        'fajrAdhanVoice',
        'Invalid Fajr adhan voice ID: must be adam, atcovi, or malmo_fajr',
      );
    }
    if (hijriDayAdjustment != null &&
        (hijriDayAdjustment < -2 || hijriDayAdjustment > 2)) {
      throw ArgumentError.value(
        hijriDayAdjustment,
        'hijriDayAdjustment',
        'Hijri day adjustment must be between -2 and 2 days',
      );
    }
    void validateOffset(int? offset, String name) {
      if (offset != null && (offset < -120 || offset > 120)) {
        throw ArgumentError.value(
          offset,
          name,
          'Minute offset must be between -120 and 120 minutes',
        );
      }
    }

    validateOffset(fajrOffset, 'fajrOffset');
    validateOffset(sunriseOffset, 'sunriseOffset');
    validateOffset(dhuhrOffset, 'dhuhrOffset');
    validateOffset(asrOffset, 'asrOffset');
    validateOffset(maghribOffset, 'maghribOffset');
    validateOffset(ishaOffset, 'ishaOffset');

    final int? resolvedCityId;
    if (clearSelectedCityId) {
      resolvedCityId = null;
    } else if (!identical(selectedCityId, kPreferenceSentinel)) {
      resolvedCityId = selectedCityId as int?;
    } else {
      resolvedCityId = this.selectedCityId;
    }

    final CalculationMethod? resolvedCalcMethod;
    if (clearCalculationMethodOverride) {
      resolvedCalcMethod = null;
    } else if (!identical(calculationMethodOverride, kPreferenceSentinel)) {
      final override = calculationMethodOverride as CalculationMethod?;
      if (override != null &&
          !PrayerSettings.supportedMethods.contains(override)) {
        throw ArgumentError.value(
          override,
          'calculationMethodOverride',
          'Unsupported prayer calculation method: $override',
        );
      }
      resolvedCalcMethod = override;
    } else {
      resolvedCalcMethod = this.calculationMethodOverride;
    }

    final String? resolvedSessionId;
    if (clearActiveDhikrSession) {
      resolvedSessionId = null;
    } else if (!identical(activeDhikrSessionId, kPreferenceSentinel)) {
      resolvedSessionId = activeDhikrSessionId as String?;
    } else {
      resolvedSessionId = this.activeDhikrSessionId;
    }

    return UserPreferences(
      darkMode: darkMode ?? this.darkMode,
      textScale: textScale ?? this.textScale,
      selectedCityId: resolvedCityId,
      selectedCity: selectedCity ?? this.selectedCity,
      selectedTimezone: selectedTimezone ?? this.selectedTimezone,
      calculationMethodOverride: resolvedCalcMethod,
      asrMadhab: asrMadhab ?? this.asrMadhab,
      highLatitudeRule: highLatitudeRule ?? this.highLatitudeRule,
      polarResolution: polarResolution ?? this.polarResolution,
      ramadanPolicy: ramadanPolicy ?? this.ramadanPolicy,
      hijriDayAdjustment: hijriDayAdjustment ?? this.hijriDayAdjustment,
      fajrOffset: fajrOffset ?? this.fajrOffset,
      sunriseOffset: sunriseOffset ?? this.sunriseOffset,
      dhuhrOffset: dhuhrOffset ?? this.dhuhrOffset,
      asrOffset: asrOffset ?? this.asrOffset,
      maghribOffset: maghribOffset ?? this.maghribOffset,
      ishaOffset: ishaOffset ?? this.ishaOffset,
      quranDefaultGoal: quranDefaultGoal ?? this.quranDefaultGoal,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      activeDhikrSessionId: resolvedSessionId,
      generalAdhanVoice: generalAdhanVoice ?? this.generalAdhanVoice,
      fajrAdhanVoice: fajrAdhanVoice ?? this.fajrAdhanVoice,
      voiceRecoveryNotice: voiceRecoveryNotice ?? this.voiceRecoveryNotice,
      prayerSettingsRecoveryNotice:
          prayerSettingsRecoveryNotice ?? this.prayerSettingsRecoveryNotice,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': 1,
      'dark_mode': darkMode,
      'text_scale': textScale,
      'selected_city_id': selectedCityId,
      'selected_city': selectedCity,
      'selected_timezone': selectedTimezone,
      'calculation_method': calculationMethodOverride?.name,
      'asr_madhab': asrMadhab.name,
      'high_latitude_rule': highLatitudeRule.name,
      'polar_resolution': polarResolution.name,
      'ramadan_policy': ramadanPolicy.name,
      'hijri_day_adjustment': hijriDayAdjustment,
      'fajr_offset': fajrOffset,
      'sunrise_offset': sunriseOffset,
      'dhuhr_offset': dhuhrOffset,
      'asr_offset': asrOffset,
      'maghrib_offset': maghribOffset,
      'isha_offset': ishaOffset,
      'quran_default_goal': quranDefaultGoal,
      'notifications_enabled': notificationsEnabled ? 1 : 0,
      'active_dhikr_session_id': activeDhikrSessionId,
      'general_adhan_voice': generalAdhanVoice,
      'fajr_adhan_voice': fajrAdhanVoice,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory UserPreferences.fromMap(Map<String, dynamic> map) {
    final rawGeneral = map['general_adhan_voice'] as String?;
    final rawFajr = map['fajr_adhan_voice'] as String?;

    final bool generalInvalid =
        rawGeneral != null && !allowedGeneralAdhanVoices.contains(rawGeneral);
    final bool fajrInvalid =
        rawFajr != null && !allowedFajrAdhanVoices.contains(rawFajr);
    final bool voiceRecoveryNotice = generalInvalid || fajrInvalid;

    final resolvedGeneral =
        (rawGeneral != null && allowedGeneralAdhanVoices.contains(rawGeneral))
            ? rawGeneral
            : defaultGeneralAdhanVoice;

    final resolvedFajr =
        (rawFajr != null && allowedFajrAdhanVoices.contains(rawFajr))
            ? rawFajr
            : defaultFajrAdhanVoice;

    final int? resolvedCityId;
    if (map.containsKey('selected_city_id')) {
      resolvedCityId = (map['selected_city_id'] as num?)?.toInt();
    } else {
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
      final legacyCity = map['selected_city'] as String? ?? 'القاهرة';
      final legacyTz = map['selected_timezone'] as String? ?? 'Africa/Cairo';
      resolvedCityId = legacyMap['$legacyCity|$legacyTz'];
    }

    bool settingsCorrupted = false;

    final rawMethod = map['calculation_method'] as String?;
    CalculationMethod? resolvedCalcMethod;
    if (rawMethod != null) {
      try {
        final parsed = CalculationMethod.values.firstWhere(
          (m) => m.name == rawMethod,
        );
        if (PrayerSettings.supportedMethods.contains(parsed)) {
          resolvedCalcMethod = parsed;
        } else {
          settingsCorrupted = true;
        }
      } catch (_) {
        settingsCorrupted = true;
      }
    }

    final rawMadhab = map['asr_madhab'] as String?;
    Madhab resolvedMadhab = Madhab.shafi;
    if (rawMadhab != null) {
      if (rawMadhab == 'shafi') {
        resolvedMadhab = Madhab.shafi;
      } else if (rawMadhab == 'hanafi') {
        resolvedMadhab = Madhab.hanafi;
      } else {
        settingsCorrupted = true;
      }
    }

    final rawRule = map['high_latitude_rule'] as String?;
    HighLatitudeRule resolvedRule = HighLatitudeRule.middle_of_the_night;
    if (rawRule != null) {
      try {
        resolvedRule = HighLatitudeRule.values.firstWhere(
          (r) => r.name == rawRule,
        );
      } catch (_) {
        settingsCorrupted = true;
      }
    }

    final rawPolar = map['polar_resolution'] as String?;
    PolarDayResolution resolvedPolar = PolarDayResolution.unresolved;
    if (rawPolar != null) {
      try {
        resolvedPolar = PolarDayResolution.values.firstWhere(
          (PolarDayResolution p) => p.name == rawPolar,
        );
      } catch (_) {
        settingsCorrupted = true;
      }
    }

    final rawPolicy = map['ramadan_policy'] as String?;
    UmmAlQuraRamadanPolicy resolvedPolicy =
        UmmAlQuraRamadanPolicy.eveningOfRamadan;
    if (rawPolicy != null) {
      try {
        resolvedPolicy = UmmAlQuraRamadanPolicy.values.firstWhere(
          (UmmAlQuraRamadanPolicy p) => p.name == rawPolicy,
        );
      } catch (_) {
        settingsCorrupted = true;
      }
    }

    final rawHijri = (map['hijri_day_adjustment'] as num?)?.toInt() ?? 0;
    int resolvedHijri = rawHijri;
    if (rawHijri < -2 || rawHijri > 2) {
      settingsCorrupted = true;
      resolvedHijri = 0;
    }

    int resolveOffset(dynamic val) {
      final numVal = (val as num?)?.toInt() ?? 0;
      if (numVal < -120 || numVal > 120) {
        settingsCorrupted = true;
        return 0;
      }
      return numVal;
    }

    final resolvedFajrOffset = resolveOffset(map['fajr_offset']);
    final resolvedSunriseOffset = resolveOffset(map['sunrise_offset']);
    final resolvedDhuhrOffset = resolveOffset(map['dhuhr_offset']);
    final resolvedAsrOffset = resolveOffset(map['asr_offset']);
    final resolvedMaghribOffset = resolveOffset(map['maghrib_offset']);
    final resolvedIshaOffset = resolveOffset(map['isha_offset']);

    return UserPreferences(
      darkMode: map['dark_mode'] as String? ?? 'system',
      textScale: (map['text_scale'] as num?)?.toDouble() ?? 1.0,
      selectedCityId: resolvedCityId,
      selectedCity: map['selected_city'] as String? ?? 'القاهرة',
      selectedTimezone: map['selected_timezone'] as String? ?? 'Africa/Cairo',
      calculationMethodOverride: resolvedCalcMethod,
      asrMadhab: resolvedMadhab,
      highLatitudeRule: resolvedRule,
      polarResolution: resolvedPolar,
      ramadanPolicy: resolvedPolicy,
      hijriDayAdjustment: resolvedHijri,
      fajrOffset: resolvedFajrOffset,
      sunriseOffset: resolvedSunriseOffset,
      dhuhrOffset: resolvedDhuhrOffset,
      asrOffset: resolvedAsrOffset,
      maghribOffset: resolvedMaghribOffset,
      ishaOffset: resolvedIshaOffset,
      quranDefaultGoal: (map['quran_default_goal'] as num?)?.toInt() ?? 2,
      notificationsEnabled:
          (map['notifications_enabled'] as num?)?.toInt() == 1,
      activeDhikrSessionId: map['active_dhikr_session_id'] as String?,
      generalAdhanVoice: resolvedGeneral,
      fajrAdhanVoice: resolvedFajr,
      voiceRecoveryNotice: voiceRecoveryNotice,
      prayerSettingsRecoveryNotice: settingsCorrupted,
      updatedAt:
          map['updated_at'] != null
              ? DateTime.tryParse(map['updated_at'] as String)
              : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserPreferences &&
        other.darkMode == darkMode &&
        other.textScale == textScale &&
        other.selectedCityId == selectedCityId &&
        other.selectedCity == selectedCity &&
        other.selectedTimezone == selectedTimezone &&
        other.calculationMethodOverride == calculationMethodOverride &&
        other.asrMadhab == asrMadhab &&
        other.highLatitudeRule == highLatitudeRule &&
        other.polarResolution == polarResolution &&
        other.ramadanPolicy == ramadanPolicy &&
        other.hijriDayAdjustment == hijriDayAdjustment &&
        other.fajrOffset == fajrOffset &&
        other.sunriseOffset == sunriseOffset &&
        other.dhuhrOffset == dhuhrOffset &&
        other.asrOffset == asrOffset &&
        other.maghribOffset == maghribOffset &&
        other.ishaOffset == ishaOffset &&
        other.quranDefaultGoal == quranDefaultGoal &&
        other.notificationsEnabled == notificationsEnabled &&
        other.activeDhikrSessionId == activeDhikrSessionId &&
        other.generalAdhanVoice == generalAdhanVoice &&
        other.fajrAdhanVoice == fajrAdhanVoice &&
        other.voiceRecoveryNotice == voiceRecoveryNotice &&
        other.prayerSettingsRecoveryNotice == prayerSettingsRecoveryNotice;
  }

  @override
  int get hashCode => Object.hashAll([
    darkMode,
    textScale,
    selectedCityId,
    selectedCity,
    selectedTimezone,
    calculationMethodOverride,
    asrMadhab,
    highLatitudeRule,
    polarResolution,
    ramadanPolicy,
    hijriDayAdjustment,
    fajrOffset,
    sunriseOffset,
    dhuhrOffset,
    asrOffset,
    maghribOffset,
    ishaOffset,
    quranDefaultGoal,
    notificationsEnabled,
    activeDhikrSessionId,
    generalAdhanVoice,
    fajrAdhanVoice,
    voiceRecoveryNotice,
    prayerSettingsRecoveryNotice,
  ]);

  @override
  String toString() =>
      'UserPreferences(dark: $darkMode, textScale: $textScale, cityId: $selectedCityId, city: $selectedCity, method: ${calculationMethodOverride?.name}, madhab: ${asrMadhab.name}, voices: $generalAdhanVoice/$fajrAdhanVoice, recovery: voice=$voiceRecoveryNotice/settings=$prayerSettingsRecoveryNotice)';
}
