import 'package:adhan/adhan.dart';
import 'package:adhan/src/data/calendar_util.dart';
import 'package:adhan/src/extensions/datetime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_event.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_settings.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/selected_city.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_calculator.dart';

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('PrayerCalculator - Four Literal Reference City Fixtures', () {
    final calculator = PrayerCalculator();

    // Source fixture provenance:
    // Cairo 2020-01-01: Adhan JS reference fixture (lat 30.028703, lon 31.249528).
    // Makkah 2016-01-05: Upstream Adhan Umm Al-Qura JSON reference (lat 21.427009, lon 39.828685).
    // London 2016-01-01: Moonsighting Committee / Hanafi reference (lat 51.507194, lon -0.116711).
    // NYC 2024-01-15: adhan_dart 2.0.1 test/locations_test.dart regression fixture from v1.2.0 (lat 40.7128, lon -74.0060).
    // Note: These fixtures serve as algorithmic regression baselines and do not certify exact local mosque calendars.

    test(
      'Cairo 2020-01-01 Egyptian General Authority of Survey matches literal times',
      () {
        final city = SelectedCity(
          id: 900001,
          name: 'Cairo Fixture',
          asciiName: 'Cairo Fixture',
          countryCode: 'EG',
          latitude: 30.028703,
          longitude: 31.249528,
          timezone: 'Africa/Cairo',
          population: 9000000,
        );

        final day = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2020, 1, 1),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.egyptian,
            asrMadhab: Madhab.shafi,
          ),
        );

        expect(day.isUnresolved, isFalse);
        expect(day.isEstimated, isFalse);

        final times = [
          day.fajr!.formatCityTime(city.timezone),
          day.sunrise!.formatCityTime(city.timezone),
          day.dhuhr!.formatCityTime(city.timezone),
          day.asr!.formatCityTime(city.timezone),
          day.maghrib!.formatCityTime(city.timezone),
          day.isha!.formatCityTime(city.timezone),
        ];

        expect(times, ['05:18', '06:51', '11:59', '14:47', '17:06', '18:29']);
      },
    );

    test(
      'Makkah 2016-01-05 Umm Al-Qura matches literal times (Maghrib + 90 min Isha)',
      () {
        final city = SelectedCity(
          id: 900002,
          name: 'Makkah Fixture',
          asciiName: 'Makkah Fixture',
          countryCode: 'SA',
          latitude: 21.427009,
          longitude: 39.828685,
          timezone: 'Asia/Riyadh',
          population: 1500000,
        );

        final day = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2016, 1, 5),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.umm_al_qura,
            asrMadhab: Madhab.shafi,
          ),
        );

        expect(day.isUnresolved, isFalse);
        expect(day.isEstimated, isFalse);

        final times = [
          day.fajr!.formatCityTime(city.timezone),
          day.sunrise!.formatCityTime(city.timezone),
          day.dhuhr!.formatCityTime(city.timezone),
          day.asr!.formatCityTime(city.timezone),
          day.maghrib!.formatCityTime(city.timezone),
          day.isha!.formatCityTime(city.timezone),
        ];

        expect(times, ['05:38', '07:00', '12:26', '15:31', '17:52', '19:22']);
      },
    );

    test(
      'London 2016-01-01 Moonsighting Committee Hanafi matches literal times',
      () {
        final city = SelectedCity(
          id: 900003,
          name: 'London Fixture',
          asciiName: 'London Fixture',
          countryCode: 'GB',
          latitude: 51.507194,
          longitude: -0.116711,
          timezone: 'Europe/London',
          population: 8900000,
        );

        final day = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2016, 1, 1),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.moon_sighting_committee,
            asrMadhab: Madhab.hanafi,
          ),
        );

        expect(day.isUnresolved, isFalse);
        expect(day.isEstimated, isTrue);
        expect(
          day.estimationReason,
          contains('High-latitude twilight estimation applied'),
        );

        final times = [
          day.fajr!.formatCityTime(city.timezone),
          day.sunrise!.formatCityTime(city.timezone),
          day.dhuhr!.formatCityTime(city.timezone),
          day.asr!.formatCityTime(city.timezone),
          day.maghrib!.formatCityTime(city.timezone),
          day.isha!.formatCityTime(city.timezone),
        ];

        expect(times, ['06:25', '08:06', '12:09', '14:15', '16:05', '17:38']);
      },
    );

    test('NYC 2024-01-15 ISNA (North America) matches literal times', () {
      final city = SelectedCity(
        id: 900004,
        name: 'NYC Fixture',
        asciiName: 'NYC Fixture',
        countryCode: 'US',
        latitude: 40.7128,
        longitude: -74.0060,
        timezone: 'America/New_York',
        population: 8800000,
      );

      final day = calculator.calculatePrayerDay(
        city: city,
        date: DateTime.utc(2024, 1, 15),
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.north_america,
          asrMadhab: Madhab.shafi,
        ),
      );

      expect(day.isUnresolved, isFalse);
      expect(day.isEstimated, isFalse);

      final times = [
        day.fajr!.formatCityTime(city.timezone),
        day.sunrise!.formatCityTime(city.timezone),
        day.dhuhr!.formatCityTime(city.timezone),
        day.asr!.formatCityTime(city.timezone),
        day.maghrib!.formatCityTime(city.timezone),
        day.isha!.formatCityTime(city.timezone),
      ];

      expect(times, ['05:58', '07:18', '12:06', '14:34', '16:53', '18:13']);
    });
  });

  group('PrayerCalculator - Three Vendor Patch Regressions', () {
    test(
      'Patch 1: dayOfYear civil calendar arithmetic on DST and timezone boundaries',
      () {
        // Cairo 2026-04-25 = day 115 (upstream returned 114 with DST offset distortion)
        final cairoSpring = DateTime(2026, 4, 25);
        expect(cairoSpring.dayOfYear, 115);

        // Cairo 2026-09-27 = day 270 (upstream returned 269)
        final cairoAutumn = DateTime(2026, 9, 27);
        expect(cairoAutumn.dayOfYear, 270);

        // Kiritimati 2026-02-01 = day 32 (upstream returned 31)
        final kiritimati = DateTime(2026, 2, 1);
        expect(kiritimati.dayOfYear, 32);

        // Leap year check: 2024-03-01 = day 61 (Jan 31 + Feb 29 + Mar 1)
        expect(DateTime(2024, 3, 1).dayOfYear, 61);
      },
    );

    test(
      'Patch 2: CalendarUtil.roundedMinute preserves exact UTC instant across repeated DST fall-back hour',
      () {
        // Cairo repeated local hour 2026-10-29:
        // First occurrence: UTC 20:30:15 (+03:00)
        final firstOccurrence = DateTime.utc(2026, 10, 29, 20, 30, 15);
        final roundedFirst = CalendarUtil.roundedMinute(
          firstOccurrence.toLocal(),
        ).toUtc();
        expect(roundedFirst, DateTime.utc(2026, 10, 29, 20, 30, 0));

        // Second occurrence: UTC 21:30:15 (+02:00)
        final secondOccurrence15 = DateTime.utc(2026, 10, 29, 21, 30, 15);
        final roundedSecond15 = CalendarUtil.roundedMinute(
          secondOccurrence15.toLocal(),
        ).toUtc();
        expect(roundedSecond15, DateTime.utc(2026, 10, 29, 21, 30, 0));

        // Second occurrence: UTC 21:30:45 (+02:00) rounds up to 21:31:00
        final secondOccurrence45 = DateTime.utc(2026, 10, 29, 21, 30, 45);
        final roundedSecond45 = CalendarUtil.roundedMinute(
          secondOccurrence45.toLocal(),
        ).toUtc();
        expect(roundedSecond45, DateTime.utc(2026, 10, 29, 21, 31, 0));
      },
    );

    test(
      'Patch 3: Makkah 2016-01-05 Umm Al-Qura with twilight_angle executes without throwing FormatException',
      () {
        final calculator = PrayerCalculator();
        const city = SelectedCity.makkah;

        for (final rule in [
          HighLatitudeRule.middle_of_the_night,
          HighLatitudeRule.seventh_of_the_night,
          HighLatitudeRule.twilight_angle,
        ]) {
          final day = calculator.calculatePrayerDay(
            city: city,
            date: DateTime.utc(2016, 1, 5),
            settings: PrayerSettings(
              calculationMethod: CalculationMethod.umm_al_qura,
              highLatitudeRule: rule,
            ),
          );

          expect(day.isUnresolved, isFalse);
          expect(day.fajr!.formatCityTime(city.timezone), '05:38');
          expect(day.isha!.formatCityTime(city.timezone), '19:22');
        }
      },
    );

    test(
      'Angle-based Isha calculation requires ishaAngle when ishaInterval is 0',
      () {
        final params = CalculationParameters(
          fajrAngle: 18.0,
          highLatitudeRule: HighLatitudeRule.twilight_angle,
          ishaInterval: 0,
          ishaAngle: null,
        );
        expect(() => params.nightPortions(), throwsA(isA<FormatException>()));
      },
    );
  });

  group('PrayerCalculator - Method, Madhab, & Rule Matrix', () {
    final calculator = PrayerCalculator();
    const city = SelectedCity.cairo;

    test('Shafi vs Hanafi Asr Madhab produces later Asr time for Hanafi', () {
      final shafiDay = calculator.calculatePrayerDay(
        city: city,
        date: DateTime.utc(2020, 1, 1),
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.egyptian,
          asrMadhab: Madhab.shafi,
        ),
      );

      final hanafiDay = calculator.calculatePrayerDay(
        city: city,
        date: DateTime.utc(2020, 1, 1),
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.egyptian,
          asrMadhab: Madhab.hanafi,
        ),
      );

      // Shafi Asr is 14:47, Hanafi Asr is shadow length 2 and occurs later
      expect(
        shafiDay.asr!.utcDateTime.isBefore(hanafiDay.asr!.utcDateTime),
        isTrue,
      );
      expect(shafiDay.asr!.formatCityTime(city.timezone), '14:47');
    });

    test(
      'High latitude rules middle_of_the_night and seventh_of_the_night produce valid chronological sequences',
      () {
        for (final rule in [
          HighLatitudeRule.middle_of_the_night,
          HighLatitudeRule.seventh_of_the_night,
        ]) {
          final day = calculator.calculatePrayerDay(
            city: SelectedCity.london,
            date: DateTime.utc(2016, 6, 21), // Summer solstice
            settings: PrayerSettings(
              calculationMethod: CalculationMethod.muslim_world_league,
              highLatitudeRule: rule,
            ),
          );

          expect(day.isUnresolved, isFalse);
          expect(
            day.fajr!.utcDateTime.isBefore(day.sunrise!.utcDateTime),
            isTrue,
          );
          expect(
            day.maghrib!.utcDateTime.isBefore(day.isha!.utcDateTime),
            isTrue,
          );
        }
      },
    );
  });

  group('PrayerCalculator - Next Prayer Selection, DST, & Midnight Transitions', () {
    final calculator = PrayerCalculator();
    const city = SelectedCity.cairo;

    test(
      'nextPrayer advances through today prayers sequentially in UTC order',
      () {
        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.egyptian,
        );

        // In Cairo on 2020-01-01:
        // Fajr: 05:18 (03:18 UTC)
        // Sunrise: 06:51 (04:51 UTC)
        // Dhuhr: 11:59 (09:59 UTC)
        // Asr: 14:47 (12:47 UTC)
        // Maghrib: 17:06 (15:06 UTC)
        // Isha: 18:29 (16:29 UTC)

        // At 02:00 UTC (before Fajr):
        final next1 = calculator.nextPrayer(
          utcNow: DateTime.utc(2020, 1, 1, 2, 0),
          city: city,
          settings: settings,
        );
        expect(next1.type, PrayerType.fajr);

        // At 04:00 UTC (after Fajr, before Sunrise):
        // When includeSunrise = false, next canonical prayer is Dhuhr
        final next2 = calculator.nextPrayer(
          utcNow: DateTime.utc(2020, 1, 1, 4, 0),
          city: city,
          settings: settings,
          includeSunrise: false,
        );
        expect(next2.type, PrayerType.dhuhr);

        // When includeSunrise = true, next event is Sunrise
        final next2Event = calculator.nextPrayer(
          utcNow: DateTime.utc(2020, 1, 1, 4, 0),
          city: city,
          settings: settings,
          includeSunrise: true,
        );
        expect(next2Event.type, PrayerType.sunrise);

        // At 10:00 UTC (after Dhuhr, before Asr):
        final next3 = calculator.nextPrayer(
          utcNow: DateTime.utc(2020, 1, 1, 10, 0),
          city: city,
          settings: settings,
        );
        expect(next3.type, PrayerType.asr);

        // At 16:00 UTC (after Maghrib, before Isha):
        final next4 = calculator.nextPrayer(
          utcNow: DateTime.utc(2020, 1, 1, 16, 0),
          city: city,
          settings: settings,
        );
        expect(next4.type, PrayerType.isha);
      },
    );

    test(
      'nextPrayer after Isha advances to tomorrow Fajr across Cairo DST fall-back day (civil Oct 30, not same Oct 29)',
      () {
        // Cairo 2026-10-29 has repeated 23:00 hour (25-hour day).
        // After Isha on 2026-10-29 (local Isha ~18:15 / 15:15 UTC):
        // Check at 20:00 UTC (23:00 Cairo time):
        final nextFajr = calculator.nextPrayer(
          utcNow: DateTime.utc(2026, 10, 29, 20, 0),
          city: city,
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.egyptian,
          ),
        );

        expect(nextFajr.type, PrayerType.fajr);
        // Must advance to civil date October 30, 2026
        final localFajr = nextFajr.toCityTime(city.timezone);
        expect(localFajr.year, 2026);
        expect(localFajr.month, 10);
        expect(localFajr.day, 30);
        expect(localFajr.day, isNot(equals(29)));
      },
    );

    test(
      'nextPrayer cross-midnight selection: Reykjavik selects previous civil-day Isha at 00:30 UTC, today Fajr at 01:00 UTC, next day Fajr at Jun 22 01:00 UTC',
      () {
        final reykjavik = SelectedCity(
          id: 3413829,
          name: 'Reykjavik',
          asciiName: 'Reykjavik',
          countryCode: 'IS',
          latitude: 64.13548,
          longitude: -21.89541,
          timezone: 'Atlantic/Reykjavik',
          population: 118918,
        );

        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          highLatitudeRule: HighLatitudeRule.twilight_angle,
        );

        // 1. At 2026-06-21T00:30:00Z (after local midnight, but before yesterday's Isha at 00:52 UTC):
        // Previous civil-day (Jun 20) Isha is at 2026-06-21T00:52:00Z.
        // Today's (Jun 21) Fajr is at 2026-06-21T02:04:00Z.
        // Next prayer must be yesterday's Isha (00:52 UTC), not skipped for today's Fajr (02:04 UTC).
        final nextAt0030 = calculator.nextPrayer(
          utcNow: DateTime.utc(2026, 6, 21, 0, 30),
          city: reykjavik,
          settings: settings,
        );
        expect(nextAt0030.type, PrayerType.isha);
        expect(nextAt0030.utcDateTime, DateTime.utc(2026, 6, 21, 0, 52));

        // 2. At 2026-06-21T01:00:00Z (after yesterday's Isha at 00:52, before today's Fajr at 02:04):
        // Next prayer must advance to today's Fajr (02:04 UTC).
        final nextAt0100 = calculator.nextPrayer(
          utcNow: DateTime.utc(2026, 6, 21, 1, 0),
          city: reykjavik,
          settings: settings,
        );
        expect(nextAt0100.type, PrayerType.fajr);
        expect(nextAt0100.utcDateTime, DateTime.utc(2026, 6, 21, 2, 4));

        // 3. At 2026-06-22T01:00:00Z (after Jun 21 Isha at 00:52 UTC on Jun 22, before Jun 22 Fajr at 02:04 UTC):
        // Next prayer must advance to Jun 22 Fajr (02:04 UTC).
        final nextAtJun22 = calculator.nextPrayer(
          utcNow: DateTime.utc(2026, 6, 22, 1, 0),
          city: reykjavik,
          settings: settings,
        );
        expect(nextAtJun22.type, PrayerType.fajr);
        expect(nextAtJun22.utcDateTime, DateTime.utc(2026, 6, 22, 2, 4));
      },
    );

    test('non-UTC nextPrayer throws ArgumentError at runtime', () {
      final nonUtc = DateTime(2026, 5, 1, 12, 0); // device local
      expect(
        () => calculator.nextPrayer(utcNow: nonUtc, city: city),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('PrayerCalculator - Umm Al-Qura Ramadan Policy, Supported Range, & Offsets', () {
    final calculator = PrayerCalculator();
    const city = SelectedCity.makkah;

    // Primary references:
    // SPA https://www.spa.gov.sa/en/w2062566: First Ramadan fasting/calendar day March 11, 2024 based on moon sighted at March 10 sunset.
    // SPA https://spa.gov.sa/en/N2081393: Eid Al-Fitr prayers nationwide April 10, 2024, corroborating first Shawwal civil day.
    // Evening policy schedule:
    // - March 9 evening (Sha'ban 29 night): 90 minutes.
    // - March 10 evening (eve of 1 Ramadan / Tarawih night): 120 minutes (+30 min).
    // - April 8 evening (night of 30 Ramadan): 120 minutes.
    // - April 9 evening (eve of Eid / 1 Shawwal night): 90 minutes.

    test(
      'Umm Al-Qura Ramadan evening boundary transitions: March 9=90, March 10=120, April 8=120, April 9=90',
      () {
        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.umm_al_qura,
          ummAlQuraRamadanPolicy: UmmAlQuraRamadanPolicy.eveningOfRamadan,
        );

        // March 9, 2024 (evening before Ramadan):
        final dayMar9 = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2024, 3, 9),
          settings: settings,
        );
        final mar9Diff = dayMar9.isha!.utcDateTime
            .difference(dayMar9.maghrib!.utcDateTime)
            .inMinutes;
        expect(mar9Diff, 90);

        // March 10, 2024 (first Ramadan evening / Tarawih starts):
        final dayMar10 = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2024, 3, 10),
          settings: settings,
        );
        final mar10Diff = dayMar10.isha!.utcDateTime
            .difference(dayMar10.maghrib!.utcDateTime)
            .inMinutes;
        expect(mar10Diff, 120);

        // April 8, 2024 (last Ramadan night):
        final dayApr8 = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2024, 3, 8),
          settings: settings,
        );
        final apr8Diff = dayApr8.isha!.utcDateTime
            .difference(dayApr8.maghrib!.utcDateTime)
            .inMinutes;
        expect(apr8Diff, 90); // March 8 is still Sha'ban

        // April 8, 2024 (29 Ramadan night):
        final dayApr08 = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2024, 4, 8),
          settings: settings,
        );
        final apr08Diff = dayApr08.isha!.utcDateTime
            .difference(dayApr08.maghrib!.utcDateTime)
            .inMinutes;
        expect(apr08Diff, 120);

        // April 9, 2024 (evening of Eid / 1 Shawwal):
        final dayApr9 = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2024, 4, 9),
          settings: settings,
        );
        final apr9Diff = dayApr9.isha!.utcDateTime
            .difference(dayApr9.maghrib!.utcDateTime)
            .inMinutes;
        expect(apr9Diff, 90);
      },
    );

    test(
      'manual additive offsets remain strictly additive on top of 120 minute Ramadan interval',
      () {
        final settingsWithOffset = PrayerSettings(
          calculationMethod: CalculationMethod.umm_al_qura,
          ummAlQuraRamadanPolicy: UmmAlQuraRamadanPolicy.eveningOfRamadan,
          ishaOffsetMinutes: 10,
        );

        final day = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2024, 3, 10),
          settings: settingsWithOffset,
        );

        final diff = day.isha!.utcDateTime
            .difference(day.maghrib!.utcDateTime)
            .inMinutes;
        expect(diff, 130); // 120 + 10 manual offset
      },
    );

    test(
      'unsupported Hijri date outside 1937..2077 returns actionable unresolved status under automatic policy',
      () {
        // 1936-01-01 is outside supported Hijri range (starts 1937-03-14)
        final pastDay = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(1936, 1, 1),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.umm_al_qura,
            ummAlQuraRamadanPolicy: UmmAlQuraRamadanPolicy.eveningOfRamadan,
          ),
        );

        expect(pastDay.isUnresolved, isTrue);
        expect(pastDay.statusMessage, contains('unsupported'));

        // With disabled policy, calculating standard 90 minutes succeeds
        final disabledPastDay = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(1936, 1, 1),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.umm_al_qura,
            ummAlQuraRamadanPolicy: UmmAlQuraRamadanPolicy.disabled,
          ),
        );
        expect(disabledPastDay.isUnresolved, isFalse);
        final diff = disabledPastDay.isha!.utcDateTime
            .difference(disabledPastDay.maghrib!.utcDateTime)
            .inMinutes;
        expect(diff, 90);
      },
    );
  });

  group('PrayerCalculator - High-Latitude Estimation & Polar Days', () {
    final calculator = PrayerCalculator();

    test(
      'London winter day with MWL standard angle rule is NOT estimated; London summer day IS marked estimated',
      () {
        // London winter 2016-01-01 with MWL: astronomical twilight angles (18° Fajr, 17° Isha)
        // are fully within bounds and unconstrained by high-latitude rules, so isEstimated is false.
        final winterDay = calculator.calculatePrayerDay(
          city: SelectedCity.london,
          date: DateTime.utc(2016, 1, 1),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.muslim_world_league,
            highLatitudeRule: HighLatitudeRule.middle_of_the_night,
          ),
        );
        expect(winterDay.isUnresolved, isFalse);
        expect(winterDay.isEstimated, isFalse);
        expect(winterDay.estimationReason, isNull);

        // London summer 2016-06-21: solar depression angle for 18° is never reached, high-latitude rule estimated
        final summerDay = calculator.calculatePrayerDay(
          city: SelectedCity.london,
          date: DateTime.utc(2016, 6, 21),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.moon_sighting_committee,
            asrMadhab: Madhab.hanafi,
          ),
        );
        expect(summerDay.isUnresolved, isFalse);
        expect(summerDay.isEstimated, isTrue);
        expect(
          summerDay.estimationReason,
          contains('High-latitude twilight estimation applied'),
        );
      },
    );

    test(
      'Tromso polar summer day returns actionable unresolved by default, or bounded estimation with nearestLatitude',
      () {
        final tromso = SelectedCity(
          id: 900005,
          name: 'Tromso',
          asciiName: 'Tromso',
          countryCode: 'NO',
          latitude: 69.6492,
          longitude: 18.9553,
          timezone: 'Europe/Oslo',
          population: 75000,
        );

        // Default: unresolved
        final unresolvedDay = calculator.calculatePrayerDay(
          city: tromso,
          date: DateTime.utc(2026, 6, 21),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.muslim_world_league,
            polarResolution: PolarDayResolution.unresolved,
          ),
        );
        expect(unresolvedDay.isUnresolved, isTrue);
        expect(unresolvedDay.isEstimated, isFalse);
        expect(unresolvedDay.orderedEvents, isEmpty);
        expect(unresolvedDay.statusMessage, contains('Polar day'));

        // Configured nearestLatitude (Aqrab Al-Balad): estimated with finite valid events
        final resolvedDay = calculator.calculatePrayerDay(
          city: tromso,
          date: DateTime.utc(2026, 6, 21),
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.muslim_world_league,
            polarResolution: PolarDayResolution.nearestLatitude,
          ),
        );
        expect(resolvedDay.isUnresolved, isFalse);
        expect(resolvedDay.isEstimated, isTrue);
        expect(resolvedDay.orderedEvents.length, 6);
        expect(resolvedDay.estimationReason, contains('Aqrab Al-Balad'));
      },
    );

    test(
      'finite angle bound applies isEstimated: London 2026-04-10 MWL/seventh clamps raw Fajr (03:12 -> 03:47), winter 2026-01-10 is unbounded false',
      () {
        const city = SelectedCity.london;
        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          highLatitudeRule: HighLatitudeRule.seventh_of_the_night,
        );

        // April 10, 2026: Raw solar Fajr angle is finite (03:12 UTC), but clamped by 1/7 night rule to 03:47 UTC (+35 min)
        final springDay = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2026, 4, 10),
          settings: settings,
        );
        expect(springDay.isUnresolved, isFalse);
        expect(springDay.isEstimated, isTrue);
        expect(springDay.fajr!.formatCityTime(city.timezone), '04:47');
        expect(
          springDay.estimationReason,
          contains('High-latitude twilight estimation applied'),
        );

        // January 10, 2026: Raw solar Fajr angle is strictly within 1/7 night bound, not clamped
        final winterDay = calculator.calculatePrayerDay(
          city: city,
          date: DateTime.utc(2026, 1, 10),
          settings: settings,
        );
        expect(winterDay.isUnresolved, isFalse);
        expect(winterDay.isEstimated, isFalse);
      },
    );

    test(
      'polar nearestLatitude with invalid manual offsets (+120 min Fajr) throws actionable StateError instead of masking invalid order',
      () {
        final tromso = SelectedCity(
          id: 3133895,
          name: 'Tromso Fixture',
          asciiName: 'Tromso Fixture',
          countryCode: 'NO',
          latitude: 69.6492,
          longitude: 18.9553,
          timezone: 'Europe/Oslo',
          population: 65000,
        );

        expect(
          () => calculator.calculatePrayerDay(
            city: tromso,
            date: DateTime.utc(2026, 6, 21),
            settings: PrayerSettings(
              calculationMethod: CalculationMethod.muslim_world_league,
              polarResolution: PolarDayResolution.nearestLatitude,
              fajrOffsetMinutes: 120, // Forces Fajr after sunrise
            ),
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  group('PrayerCalculator - Runtime Input Validation', () {
    test(
      'SelectedCity constructor rejects invalid coordinates, empty name, negative population, unknown timezone',
      () {
        expect(
          () => SelectedCity(
            id: 1,
            name: '',
            asciiName: 'Test',
            countryCode: 'EG',
            latitude: 30.0,
            longitude: 31.0,
            timezone: 'Africa/Cairo',
            population: 1000,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => SelectedCity(
            id: 1,
            name: 'Test',
            asciiName: 'Test',
            countryCode: 'EG',
            latitude: double.nan,
            longitude: 31.0,
            timezone: 'Africa/Cairo',
            population: 1000,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => SelectedCity(
            id: 1,
            name: 'Test',
            asciiName: 'Test',
            countryCode: 'EG',
            latitude: 95.0,
            longitude: 31.0,
            timezone: 'Africa/Cairo',
            population: 1000,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => SelectedCity(
            id: 1,
            name: 'Test',
            asciiName: 'Test',
            countryCode: 'EG',
            latitude: 30.0,
            longitude: 31.0,
            timezone: 'Planet/Mars',
            population: 1000,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'PrayerSettings constructor rejects out of bounds offsets, invalid hijri adjustment, unsupported methods',
      () {
        expect(
          () => PrayerSettings(fajrOffsetMinutes: 150), // > 120
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => PrayerSettings(hijriDayAdjustment: 5), // > 2
          throwsA(isA<ArgumentError>()),
        );
        expect(
          () => PrayerSettings(calculationMethod: CalculationMethod.other),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
