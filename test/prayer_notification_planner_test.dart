import 'package:adhan/adhan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_day.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_event.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_notification_plan.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/prayer_settings.dart';
import 'package:zad_alruh/src/features/prayer/domain/models/selected_city.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_calculator.dart';
import 'package:zad_alruh/src/features/prayer/domain/services/prayer_notification_planner.dart';

/// Test fixture extending the real production PrayerCalculator to inject
/// exactly one canonical slot omission at the boundary, without fake planner math.
class _PartialCanonicalSlotCalculatorFixture extends PrayerCalculator {
  final DateTime targetDateUtc;
  final PrayerType absentPrayerType;

  _PartialCanonicalSlotCalculatorFixture({
    required this.targetDateUtc,
    required this.absentPrayerType,
  });

  @override
  PrayerDay calculatePrayerDay({
    required SelectedCity city,
    required DateTime date,
    PrayerSettings? settings,
  }) {
    final realDay = super.calculatePrayerDay(
      city: city,
      date: date,
      settings: settings,
    );

    if (date.year == targetDateUtc.year &&
        date.month == targetDateUtc.month &&
        date.day == targetDateUtc.day) {
      return PrayerDay(
        city: realDay.city,
        civilDate: realDay.civilDate,
        settings: realDay.settings,
        fajr: absentPrayerType == PrayerType.fajr ? null : realDay.fajr,
        sunrise: realDay.sunrise,
        dhuhr: absentPrayerType == PrayerType.dhuhr ? null : realDay.dhuhr,
        asr: absentPrayerType == PrayerType.asr ? null : realDay.asr,
        maghrib: absentPrayerType == PrayerType.maghrib ? null : realDay.maghrib,
        isha: absentPrayerType == PrayerType.isha ? null : realDay.isha,
        isEstimated: realDay.isEstimated,
        estimationReason: realDay.estimationReason,
        isUnresolved: false,
      );
    }

    return realDay;
  }
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('PrayerNotificationPlanner - Cairo Baseline & Full Capacity', () {
    final planner = PrayerNotificationPlanner();
    const cairo = SelectedCity.cairo;
    final settings = PrayerSettings.egyptDefault();

    test(
      'when before Fajr, full 50 future canonical events and renewal are planned with correct mode separation',
      () {
        // Cairo on 2026-10-07 at 01:00 UTC is 04:00 local time (before Fajr ~04:26 local)
        final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);

        final plan = planner.build(
          city: cairo,
          settings: settings,
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'malmo_fajr',
          mode: 'full_adhan',
          existingOtherIosPendingIds: const {},
        );

        expect(plan.retainedEventsCount, 50);
        expect(plan.events.length, 50);
        expect(plan.skippedPastCount, 0);
        expect(plan.unresolvedDaysCount, 0);
        expect(plan.missingCanonicalSlotsCount, 0);
        expect(plan.isPartialCoverage, isFalse);
        expect(plan.hasZeroScheduledEvents, isFalse);

        // Ten distinct calculation dates metadata
        expect(plan.calculationDateCount, 10);
        expect(plan.calculationStartDate, DateTime.utc(2026, 10, 7));
        expect(plan.calculationEndDate, DateTime.utc(2026, 10, 16));
        expect(plan.scheduledCoverageEndUtc, plan.events.last.triggerDateTimeUtc);
        expect(plan.coverageHorizonUtc, plan.events.last.triggerDateTimeUtc);

        // Native Android events retain requested full_adhan mode
        for (final event in plan.events) {
          expect(event.prayerKey, isNot('sunrise'));
          expect(event.mode, 'full_adhan');
          expect(event.triggerDateTimeUtc.isAfter(nowUtc), isTrue);
        }

        // Native map conforms strictly to ANDROID-NATIVE-ALARM-CONTRACT.md (no expectedToken)
        final nativeMap = plan.toNativeMap();
        expect(nativeMap['cityId'], cairo.id);
        expect(nativeMap['cityNameAr'], 'القاهرة');
        expect(nativeMap['timezone'], 'Africa/Cairo');
        expect(nativeMap['generalVoiceId'], 'adam');
        expect(nativeMap['fajrVoiceId'], 'malmo_fajr');
        expect(nativeMap['mode'], 'full_adhan');
        expect(nativeMap['coverageHorizonUtc'], plan.events.last.triggerEpochMillis);
        expect(nativeMap.containsKey('expectedToken'), isFalse);

        final eventsList = nativeMap['events'] as List<dynamic>;
        expect(eventsList.length, 50);

        final firstEvent = eventsList.first as Map<String, dynamic>;
        expect(firstEvent['eventKey'], '${cairo.id}:2026-10-07:fajr');
        expect(firstEvent['prayerKey'], 'fajr');
        expect(firstEvent['calculationCivilDate'], '2026-10-07');
        expect(firstEvent['triggerEpochMillis'], isA<int>());
        expect(firstEvent['voiceId'], 'malmo_fajr');
        expect(firstEvent['mode'], 'full_adhan');

        // iOS projection: MUST force mode to short_alert, never full_adhan!
        expect(plan.iosEvents.length, 50);
        for (final iosEvent in plan.iosEvents) {
          expect(iosEvent.mode, 'short_alert');
          expect(iosEvent.triggerEpochMillis, isNotNull);
        }
        expect(plan.iosRenewal, isNotNull);
        expect(plan.iosTruncationStatus, IosTruncationStatus.untruncated);
        expect(plan.iosProjection.totalPendingCount, 51);
        expect(plan.iosProjection.totalPendingCount, lessThanOrEqualTo(64));
      },
    );
  });

  group('PrayerNotificationPlanner - London & New York DST Transitions', () {
    final planner = PrayerNotificationPlanner();

    test(
      'London Spring DST 2026: calendar iteration DateTime.utc(y,m,d+i) maintains monotonic UTC order',
      () {
        const london = SelectedCity.london;
        final settings = PrayerSettings.mwlDefault();
        // 2026-03-25 is 4 days before Spring DST change on March 29, 2026
        final nowUtc = DateTime.utc(2026, 3, 25, 0, 0, 0);

        final plan = planner.build(
          city: london,
          settings: settings,
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'short_alert',
        );

        expect(plan.events.length, 50);
        for (int i = 0; i < plan.events.length - 1; i++) {
          final curr = plan.events[i].triggerDateTimeUtc;
          final next = plan.events[i + 1].triggerDateTimeUtc;
          expect(curr.isBefore(next), isTrue);
        }

        final dates = plan.events.map((e) => e.calculationCivilDate).toSet().toList();
        expect(dates.length, 10);
        expect(dates.first, '2026-03-25');
        expect(dates.last, '2026-04-03');
      },
    );

    test(
      'London Fall DST 2026: October fallback transition maintains monotonic UTC order',
      () {
        const london = SelectedCity.london;
        final settings = PrayerSettings.mwlDefault();
        // 2026-10-21 is before Fall DST change on October 25, 2026
        final nowUtc = DateTime.utc(2026, 10, 21, 0, 0, 0);

        final plan = planner.build(
          city: london,
          settings: settings,
          nowUtc: nowUtc,
          generalVoiceId: 'atcovi',
          fajrVoiceId: 'atcovi',
          mode: 'full_adhan',
        );

        expect(plan.events.length, 50);
        for (int i = 0; i < plan.events.length - 1; i++) {
          final curr = plan.events[i].triggerDateTimeUtc;
          final next = plan.events[i + 1].triggerDateTimeUtc;
          expect(curr.isBefore(next), isTrue);
        }
      },
    );

    test(
      'New York Spring DST 2026: March 8 spring forward maintains monotonic UTC order',
      () {
        const newYork = SelectedCity.newYork;
        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.north_america,
          asrMadhab: Madhab.shafi,
        );
        // Pre-DST New York is EST (UTC-5). Local midnight on 2026-03-05 corresponds to 05:00:00 UTC.
        // At local midnight before Fajr, the 10-day window starts on 2026-03-05, all 50 prayers across
        // March 5 to March 14 are in the future, and they span the March 8 DST spring forward.
        final nowUtc = DateTime.utc(2026, 3, 5, 5, 0, 0);

        final plan = planner.build(
          city: newYork,
          settings: settings,
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        );

        expect(plan.calculationStartDate, DateTime.utc(2026, 3, 5));
        expect(plan.events.length, 50);
        for (final event in plan.events) {
          expect(event.triggerDateTimeUtc.isAfter(nowUtc), isTrue);
        }
        for (int i = 0; i < plan.events.length - 1; i++) {
          expect(
            plan.events[i].triggerDateTimeUtc.isBefore(plan.events[i + 1].triggerDateTimeUtc),
            isTrue,
          );
        }
      },
    );

    test(
      'New York Fall DST 2026: November 1 fallback transition maintains monotonic UTC order',
      () {
        const newYork = SelectedCity.newYork;
        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.north_america,
          asrMadhab: Madhab.shafi,
        );
        // 2026-10-28 is before November 1 fallback in USA
        final nowUtc = DateTime.utc(2026, 10, 28, 4, 0, 0);

        final plan = planner.build(
          city: newYork,
          settings: settings,
          nowUtc: nowUtc,
          generalVoiceId: 'atcovi',
          fajrVoiceId: 'atcovi',
          mode: 'short_alert',
        );

        expect(plan.events.length, 50);
        for (int i = 0; i < plan.events.length - 1; i++) {
          expect(
            plan.events[i].triggerDateTimeUtc.isBefore(plan.events[i + 1].triggerDateTimeUtc),
            isTrue,
          );
        }
      },
    );
  });

  group('PrayerNotificationPlanner - Selected City Zone vs Machine Zone', () {
    final planner = PrayerNotificationPlanner();

    test(
      'calculates starting civil date in city timezone independently of host machine timezone',
      () {
        // Tokyo is UTC+9. At 2026-10-07 20:00 UTC, it is already 2026-10-08 05:00 in Tokyo!
        final tokyo = SelectedCity(
          id: 1850147,
          name: 'Tokyo',
          asciiName: 'Tokyo',
          countryCode: 'JP',
          latitude: 35.6895,
          longitude: 139.6917,
          timezone: 'Asia/Tokyo',
          population: 13960000,
        );

        final nowUtc = DateTime.utc(2026, 10, 7, 20, 0, 0);

        final plan = planner.build(
          city: tokyo,
          settings: PrayerSettings.mwlDefault(),
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        );

        expect(plan.calculationStartDate, DateTime.utc(2026, 10, 8));
        expect(plan.events.first.calculationCivilDate, '2026-10-08');

        // New York is EDT (UTC-4). At 2026-10-07 02:00 UTC, it is 2026-10-06 22:00 in New York.
        // The 10-day calculation window correctly begins on 2026-10-06 in the city's timezone.
        // At 22:00 EDT (after Isha), all 5 canonical prayers for October 6 have already elapsed.
        // The planner records skippedPastCount == 5, so the first future scheduled event belongs to 2026-10-07.
        const newYork = SelectedCity.newYork;
        final nyNowUtc = DateTime.utc(2026, 10, 7, 2, 0, 0);

        final nyPlan = planner.build(
          city: newYork,
          settings: PrayerSettings(
            calculationMethod: CalculationMethod.north_america,
          ),
          nowUtc: nyNowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        );

        expect(nyPlan.calculationStartDate, DateTime.utc(2026, 10, 6));
        expect(nyPlan.events.first.calculationCivilDate, '2026-10-07');
        expect(nyPlan.skippedPastCount, 5);
        expect(nyPlan.events.length, 45);
        for (final event in nyPlan.events) {
          expect(event.triggerDateTimeUtc.isAfter(nyNowUtc), isTrue);
        }
      },
    );
  });

  group('PrayerNotificationPlanner - Real Offset Cross-Midnight Identity Retention', () {
    final planner = PrayerNotificationPlanner();

    test(
      'retains original civil date key when prayer crosses midnight due to minute offset',
      () {
        const london = SelectedCity.london;
        // In London mid-summer (e.g. 2026-06-20), standard Isha is around 22:50 local (BST).
        // Adding +120 minutes pushes Isha past midnight to ~00:50 on 2026-06-21.
        final settings = PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          highLatitudeRule: HighLatitudeRule.seventh_of_the_night,
          ishaOffsetMinutes: 120,
        );

        final nowUtc = DateTime.utc(2026, 6, 20, 0, 0, 0);

        final plan = planner.build(
          city: london,
          settings: settings,
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        );

        final ishaEvent = plan.events.firstWhere(
          (e) => e.eventKey == '${london.id}:2026-06-20:isha',
        );

        expect(ishaEvent.calculationCivilDate, '2026-06-20');
        expect(ishaEvent.eventKey, '${london.id}:2026-06-20:isha');

        final localTrigger = tz.TZDateTime.from(
          ishaEvent.triggerDateTimeUtc,
          tz.getLocation(london.timezone),
        );
        expect(localTrigger.day, 21);
        expect(localTrigger.hour, lessThan(2));
      },
    );
  });

  group('PrayerNotificationPlanner - Sunrise Strictly Excluded & Past Events Skipped', () {
    final planner = PrayerNotificationPlanner();

    test('skips past prayers at midday, never includes sunrise, and explains skipped count', () {
      const cairo = SelectedCity.cairo;
      final settings = PrayerSettings.egyptDefault();

      // Cairo local time 13:00 on 2026-10-07 (10:00 UTC) -> Fajr, Sunrise, and Dhuhr are in the past
      final nowUtc = DateTime.utc(2026, 10, 7, 10, 0, 0);

      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      expect(plan.events.any((e) => e.prayerKey == 'sunrise'), isFalse);
      expect(plan.skippedPastCount, greaterThanOrEqualTo(2));
      expect(plan.events.first.triggerDateTimeUtc.isAfter(nowUtc), isTrue);
      expect(plan.isPartialCoverage, isTrue);
      expect(plan.coverageExplanation, contains('past canonical prayers skipped'));
    });
  });

  group('PrayerNotificationPlanner - Polar Unresolved, Zero Events & Truthful Horizon', () {
    final planner = PrayerNotificationPlanner();
    final tromso = SelectedCity(
      id: 3133880,
      name: 'Tromso',
      asciiName: 'Tromso',
      countryCode: 'NO',
      latitude: 69.6492,
      longitude: 18.9553,
      timezone: 'Europe/Oslo',
      population: 75000,
    );

    test('polar unresolved policy yields honest zero-event status with nowUtc numeric sentinel', () {
      final settings = PrayerSettings(
        calculationMethod: CalculationMethod.muslim_world_league,
        polarResolution: PolarDayResolution.unresolved,
      );
      final nowUtc = DateTime.utc(2026, 6, 20, 0, 0, 0);

      final plan = planner.build(
        city: tromso,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'short_alert',
      );

      expect(plan.unresolvedDaysCount, 10);
      expect(plan.unresolvedReasons.length, 10);
      expect(plan.hasZeroScheduledEvents, isTrue);
      expect(plan.scheduledCoverageEndUtc, isNull);

      // Truthful numeric sentinel matches nowUtc so native contract shape validation succeeds
      expect(plan.coverageHorizonUtc, nowUtc);
      expect(plan.toNativeMap()['coverageHorizonUtc'], nowUtc.millisecondsSinceEpoch);

      // iOS coverage is null when zero events are projected
      expect(plan.iosCoverageHorizonUtc, isNull);
      expect(plan.iosEvents, isEmpty);
      expect(plan.iosRenewal, isNull);
      expect(plan.isPartialCoverage, isTrue);
      expect(plan.coverageExplanation, contains('Zero future prayer events scheduled'));
    });

    test('polar nearestLatitude policy calculates estimated events via Aqrab Al-Balad', () {
      final settings = PrayerSettings(
        calculationMethod: CalculationMethod.muslim_world_league,
        polarResolution: PolarDayResolution.nearestLatitude,
      );
      final nowUtc = DateTime.utc(2026, 6, 20, 0, 0, 0);

      final plan = planner.build(
        city: tromso,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'short_alert',
      );

      expect(plan.unresolvedDaysCount, 0);
      expect(plan.estimatedDaysCount, greaterThan(0));
      expect(plan.estimatedReasons, isNotEmpty);
      expect(plan.events, isNotEmpty);
    });
  });

  group('PrayerNotificationPlanner - Partial Day with Absent Canonical Slot Diagnostics', () {
    test('reports missing canonical slot on resolved day without fabricating times', () {
      const cairo = SelectedCity.cairo;
      final settings = PrayerSettings.egyptDefault();
      final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);
      final absentDate = DateTime.utc(2026, 10, 9);

      // Inject fixture that leaves Fajr null on 2026-10-09
      final partialCalculator = _PartialCanonicalSlotCalculatorFixture(
        targetDateUtc: absentDate,
        absentPrayerType: PrayerType.fajr,
      );
      final planner = PrayerNotificationPlanner(calculator: partialCalculator);

      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      expect(plan.missingCanonicalSlotsCount, 1);
      expect(plan.missingCanonicalSlotDetails.length, 1);
      expect(
        plan.missingCanonicalSlotDetails.first,
        '2026-10-09: fajr is undefined (missing canonical solar event)',
      );
      expect(plan.retainedEventsCount, 49); // 50 - 1 missing slot
      expect(plan.isPartialCoverage, isTrue);
      expect(plan.coverageExplanation, contains('1 canonical prayer slot(s) missing'));
      // Unresolved days remains strictly 0
      expect(plan.unresolvedDaysCount, 0);
    });
  });

  group('PrayerNotificationPlanner - Voice Assignment Rules', () {
    final planner = PrayerNotificationPlanner();
    const cairo = SelectedCity.cairo;
    final settings = PrayerSettings.egyptDefault();
    final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);

    test('assigns malmo_fajr to Fajr and adam to all general prayers', () {
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      for (final event in plan.events) {
        if (event.prayerKey == 'fajr') {
          expect(event.voiceId, 'malmo_fajr');
        } else {
          expect(event.voiceId, 'adam');
        }
      }
    });

    test('assigns atcovi to both Fajr and general prayers when configured', () {
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'atcovi',
        fajrVoiceId: 'atcovi',
        mode: 'short_alert',
      );

      for (final event in plan.events) {
        expect(event.voiceId, 'atcovi');
      }
    });
  });

  group('PrayerNotificationPlanner - All Supported Settings Passed Verbatim', () {
    final planner = PrayerNotificationPlanner();
    const london = SelectedCity.london;
    final nowUtc = DateTime.utc(2026, 1, 1, 0, 0, 0);

    test('calculationMethod variations change prayer times', () {
      final planKarachi = planner.build(
        city: london,
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.karachi,
        ),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final planIsna = planner.build(
        city: london,
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.north_america,
        ),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final karachiFajr = planKarachi.events.firstWhere((e) => e.prayerKey == 'fajr');
      final isnaFajr = planIsna.events.firstWhere((e) => e.prayerKey == 'fajr');

      expect(karachiFajr.triggerEpochMillis, isNot(equals(isnaFajr.triggerEpochMillis)));
    });

    test('asrMadhab Hanafi vs Shafi changes Asr time', () {
      final planShafi = planner.build(
        city: london,
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          asrMadhab: Madhab.shafi,
        ),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final planHanafi = planner.build(
        city: london,
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          asrMadhab: Madhab.hanafi,
        ),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final shafiAsr = planShafi.events.firstWhere((e) => e.prayerKey == 'asr');
      final hanafiAsr = planHanafi.events.firstWhere((e) => e.prayerKey == 'asr');

      expect(hanafiAsr.triggerDateTimeUtc.isAfter(shafiAsr.triggerDateTimeUtc), isTrue);
    });

    test('minute offsets shift specific prayer times verbatim', () {
      final baseline = planner.build(
        city: london,
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          dhuhrOffsetMinutes: 0,
        ),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final shifted = planner.build(
        city: london,
        settings: PrayerSettings(
          calculationMethod: CalculationMethod.muslim_world_league,
          dhuhrOffsetMinutes: 15,
        ),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final baseDhuhr = baseline.events.firstWhere((e) => e.prayerKey == 'dhuhr');
      final shiftedDhuhr = shifted.events.firstWhere((e) => e.prayerKey == 'dhuhr');

      expect(
        shiftedDhuhr.triggerDateTimeUtc.difference(baseDhuhr.triggerDateTimeUtc).inMinutes,
        15,
      );
    });
  });

  group('PrayerNotificationPlanner - Deterministic IDs & External ID Collision Prevention', () {
    final planner = PrayerNotificationPlanner();
    const cairo = SelectedCity.cairo;
    final settings = PrayerSettings.egyptDefault();
    final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);

    test('generates strictly identical positive 31-bit IDs across repeated executions', () {
      final plan1 = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      final plan2 = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      expect(plan1.events.length, plan2.events.length);
      for (int i = 0; i < plan1.events.length; i++) {
        expect(plan1.events[i].notificationId, plan2.events[i].notificationId);
        expect(plan1.events[i].notificationId, greaterThan(0));
        expect(plan1.events[i].notificationId, lessThanOrEqualTo(0x7FFFFFFF));
      }

      expect(plan1.iosRenewal!.notificationId, plan2.iosRenewal!.notificationId);
    });

    test('collision with existing other iOS notification ID produces typed collision status without silent overwrite', () {
      // First generate baseline to discover a valid candidate prayer notification ID
      final baseline = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      final collidingPrayerId = baseline.events.first.notificationId;

      // Re-run providing collidingPrayerId in existingOtherIosPendingIds
      final collidingPlan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
        existingOtherIosPendingIds: {collidingPrayerId},
      );

      // Native Android plan remains completely valid and uncorrupted
      expect(collidingPlan.events.length, 50);

      // iOS projection detects collision and empties projection to protect third-party notification
      expect(collidingPlan.iosTruncationStatus, IosTruncationStatus.idCollision);
      expect(collidingPlan.iosEvents, isEmpty);
      expect(collidingPlan.iosRenewal, isNull);
      expect(collidingPlan.iosProjection.hasIdCollision, isTrue);
      expect(collidingPlan.iosProjection.collidingNotificationId, collidingPrayerId);
      expect(collidingPlan.iosCapacityMessage, contains('ID collision detected'));
    });

    test('collision with renewal ID produces typed collision status', () {
      final baseline = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
      );

      final collidingRenewalId = baseline.iosRenewal!.notificationId;

      final collidingPlan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'malmo_fajr',
        mode: 'full_adhan',
        existingOtherIosPendingIds: {collidingRenewalId},
      );

      expect(collidingPlan.events.length, 50);
      expect(collidingPlan.iosTruncationStatus, IosTruncationStatus.idCollision);
      expect(collidingPlan.iosEvents, isEmpty);
      expect(collidingPlan.iosRenewal, isNull);
      expect(collidingPlan.iosProjection.collidingNotificationId, collidingRenewalId);
    });
  });

  group('PrayerNotificationPlanner - iOS Budget Variations (0, 14, 63, 64, 70)', () {
    final planner = PrayerNotificationPlanner();
    const cairo = SelectedCity.cairo;
    final settings = PrayerSettings.egyptDefault();
    final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);

    test('budget 0 (existingOther = 0): schedules 50 prayers + 1 renewal (total 51 <= 64)', () {
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
        existingOtherIosPendingIds: const {},
      );

      final ios = plan.iosProjection;
      expect(ios.events.length, 50);
      expect(ios.hasRenewal, isTrue);
      expect(ios.totalPendingCount, 51);
      expect(ios.capacityStatus, IosTruncationStatus.untruncated);
      expect(ios.isTruncated, isFalse);

      expect(ios.renewalEvent!.scheduledTimeUtc.isBefore(ios.coverageHorizonUtc!), isTrue);
      expect(ios.renewalEvent!.scheduledTimeUtc.isAfter(nowUtc), isTrue);
    });

    test('budget 14 (existingOther = 14): schedules 49 prayers + 1 renewal (total 64 <= 64)', () {
      final otherIds = {for (int i = 1; i <= 14; i++) 880000 + i};
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
        existingOtherIosPendingIds: otherIds,
      );

      final ios = plan.iosProjection;
      expect(ios.events.length, 49);
      expect(ios.hasRenewal, isTrue);
      expect(ios.totalPendingCount, 64);
      expect(ios.capacityStatus, IosTruncationStatus.truncatedByBudget);
      expect(ios.isTruncated, isTrue);

      // Crucial: Renewal must trigger BEFORE actual truncated coverage expiry, NOT pretend 10-day coverage
      final actualExpiry = ios.coverageHorizonUtc!;
      expect(ios.renewalEvent!.scheduledTimeUtc.isBefore(actualExpiry), isTrue);
      expect(ios.renewalEvent!.scheduledTimeUtc.isAfter(nowUtc), isTrue);
    });

    test('budget 63 (existingOther = 63): exactly 1 slot available -> planned prayer only without delivery guarantee', () {
      final otherIds = {for (int i = 1; i <= 63; i++) 880000 + i};
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
        existingOtherIosPendingIds: otherIds,
      );

      final ios = plan.iosProjection;
      expect(ios.events.length, 1);
      expect(ios.events.first.prayerKey, 'fajr');
      expect(ios.hasRenewal, isFalse);
      expect(ios.renewalEvent, isNull);
      expect(ios.totalPendingCount, 64);
      expect(ios.capacityStatus, IosTruncationStatus.singleSlotPrayerOnly);
      // Status message must refer to planned prayer only, with no unsupported delivery guarantee claims
      expect(ios.statusMessage, contains('assigned to the planned imminent next prayer'));
      expect(ios.statusMessage, isNot(contains('guarantee immediate delivery')));
    });

    test('budget 64 (existingOther = 64): zero capacity honest status (0 events, 0 renewal)', () {
      final otherIds = {for (int i = 1; i <= 64; i++) 880000 + i};
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
        existingOtherIosPendingIds: otherIds,
      );

      final ios = plan.iosProjection;
      expect(ios.events, isEmpty);
      expect(ios.renewalEvent, isNull);
      expect(ios.totalPendingCount, 64);
      expect(ios.capacityStatus, IosTruncationStatus.zeroCapacity);
    });

    test('budget 70 (existingOther = 70): excess pending count yields honest zero capacity', () {
      final otherIds = {for (int i = 1; i <= 70; i++) 880000 + i};
      final plan = planner.build(
        city: cairo,
        settings: settings,
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
        existingOtherIosPendingIds: otherIds,
      );

      final ios = plan.iosProjection;
      expect(ios.events, isEmpty);
      expect(ios.renewalEvent, isNull);
      expect(ios.totalPendingCount, 70);
      expect(ios.capacityStatus, IosTruncationStatus.zeroCapacity);
    });
  });

  group('PrayerNotificationPlanner - Invalid Inputs Rejected', () {
    final planner = PrayerNotificationPlanner();
    const cairo = SelectedCity.cairo;
    final settings = PrayerSettings.egyptDefault();

    test('rejects non-UTC nowUtc with ArgumentError', () {
      expect(
        () => planner.build(
          city: cairo,
          settings: settings,
          nowUtc: DateTime(2026, 10, 7, 10, 0),
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        ),
        throwsArgumentError,
      );
    });

    test('rejects malmo_fajr as general voice with ArgumentError', () {
      expect(
        () => planner.build(
          city: cairo,
          settings: settings,
          nowUtc: DateTime.utc(2026, 10, 7, 10, 0),
          generalVoiceId: 'malmo_fajr',
          fajrVoiceId: 'malmo_fajr',
          mode: 'full_adhan',
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown generalVoiceId with ArgumentError', () {
      expect(
        () => planner.build(
          city: cairo,
          settings: settings,
          nowUtc: DateTime.utc(2026, 10, 7, 10, 0),
          generalVoiceId: 'custom_voice',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown fajrVoiceId with ArgumentError', () {
      expect(
        () => planner.build(
          city: cairo,
          settings: settings,
          nowUtc: DateTime.utc(2026, 10, 7, 10, 0),
          generalVoiceId: 'adam',
          fajrVoiceId: 'mishary',
          mode: 'full_adhan',
        ),
        throwsArgumentError,
      );
    });

    test('rejects unknown mode with ArgumentError', () {
      expect(
        () => planner.build(
          city: cairo,
          settings: settings,
          nowUtc: DateTime.utc(2026, 10, 7, 10, 0),
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'silent',
        ),
        throwsArgumentError,
      );
    });
  });

  group('PrayerNotificationPlanner - Arabic City Name Fallback & Metadata', () {
    final planner = PrayerNotificationPlanner();
    final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);

    test('uses existing Arabic name when available', () {
      const cairo = SelectedCity.cairo;
      final plan = planner.build(
        city: cairo,
        settings: PrayerSettings.egyptDefault(),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      expect(plan.cityNameAr, 'القاهرة');
      expect(plan.hasCustomArabicName, isTrue);
      expect(plan.usedFallbackCityName, isFalse);
      expect(plan.toNativeMap()['cityNameAr'], 'القاهرة');
    });

    test('falls back to non-empty English name when Arabic name is null', () {
      final cityWithoutArabic = SelectedCity(
        id: 777001,
        name: 'Reykjavik',
        asciiName: 'Reykjavik',
        arabicName: null,
        countryCode: 'IS',
        latitude: 64.1466,
        longitude: -21.9426,
        timezone: 'Atlantic/Reykjavik',
        population: 130000,
      );

      final plan = planner.build(
        city: cityWithoutArabic,
        settings: PrayerSettings.mwlDefault(),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'short_alert',
      );

      expect(plan.cityNameAr, 'Reykjavik');
      expect(plan.hasCustomArabicName, isFalse);
      expect(plan.usedFallbackCityName, isTrue);
      expect(plan.toNativeMap()['cityNameAr'], 'Reykjavik');
    });

    test('falls back to English name when Arabic name is whitespace', () {
      final cityBlankArabic = SelectedCity(
        id: 777002,
        name: 'Helsinki',
        asciiName: 'Helsinki',
        arabicName: '   ',
        countryCode: 'FI',
        latitude: 60.1699,
        longitude: 24.9384,
        timezone: 'Europe/Helsinki',
        population: 650000,
      );

      final plan = planner.build(
        city: cityBlankArabic,
        settings: PrayerSettings.mwlDefault(),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'short_alert',
      );

      expect(plan.cityNameAr, 'Helsinki');
      expect(plan.hasCustomArabicName, isFalse);
      expect(plan.usedFallbackCityName, isTrue);
    });
  });

  group('PrayerNotificationPlanner - Immutability & Side-Effect Freedom', () {
    final planner = PrayerNotificationPlanner();
    const cairo = SelectedCity.cairo;
    final nowUtc = DateTime.utc(2026, 10, 7, 1, 0, 0);

    test('collections are unmodifiable', () {
      final plan = planner.build(
        city: cairo,
        settings: PrayerSettings.egyptDefault(),
        nowUtc: nowUtc,
        generalVoiceId: 'adam',
        fajrVoiceId: 'adam',
        mode: 'full_adhan',
      );

      final dummyEvent = plan.events.first;
      expect(() => plan.events.add(dummyEvent), throwsUnsupportedError);
      expect(() => plan.iosEvents.add(dummyEvent), throwsUnsupportedError);
      expect(() => plan.unresolvedReasons.add('test'), throwsUnsupportedError);
      expect(() => plan.missingCanonicalSlotDetails.add('test'), throwsUnsupportedError);
      expect(() => plan.estimatedReasons.add('test'), throwsUnsupportedError);
    });

    test(
      'existingOtherIosPendingIds is snapshot immutably; caller mutation does not alter projection',
      () {
        // Build from mutable Set near budget (14 IDs -> 50 slots available -> 49 prayer events + 1 renewal)
        final mutableOtherIds = <int>{for (int i = 1; i <= 14; i++) 880000 + i};

        final plan = planner.build(
          city: cairo,
          settings: PrayerSettings.egyptDefault(),
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'malmo_fajr',
          mode: 'full_adhan',
          existingOtherIosPendingIds: mutableOtherIds,
        );

        final ios = plan.iosProjection;
        final originalOtherCount = ios.existingOtherPendingCount;
        final originalEventsCount = ios.events.length;
        final originalTotalPending = ios.totalPendingCount;
        final originalStatus = ios.capacityStatus;
        final knownOwnPrayerId = ios.events.first.notificationId;

        expect(originalOtherCount, 14);
        expect(originalEventsCount, 49);
        expect(originalTotalPending, 64);
        expect(originalStatus, IosTruncationStatus.truncatedByBudget);
        expect(ios.hasIdCollision, isFalse);

        // Mutate original caller set by adding known projected own ID and enough IDs to exceed 64
        mutableOtherIds.add(knownOwnPrayerId);
        for (int i = 100; i <= 200; i++) {
          mutableOtherIds.add(990000 + i);
        }
        expect(mutableOtherIds.length, greaterThan(64));

        // Immutable projection and counts/plan results must remain original
        expect(ios.existingOtherPendingCount, originalOtherCount);
        expect(ios.events.length, originalEventsCount);
        expect(ios.totalPendingCount, originalTotalPending);
        expect(ios.capacityStatus, originalStatus);
        expect(ios.existingOtherPendingIds.contains(knownOwnPrayerId), isFalse);
        expect(ios.hasIdCollision, isFalse);

        // Caller cannot mutate exposed Set either
        expect(
          () => ios.existingOtherPendingIds.add(knownOwnPrayerId),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'direct IosNotificationProjection constructor snapshots unmodifiable Set and List',
      () {
        final plan = planner.build(
          city: cairo,
          settings: PrayerSettings.egyptDefault(),
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'adam',
          mode: 'full_adhan',
        );

        final mutableSet = <int>{1, 2, 3};
        final mutableEvents = <PrayerNotificationEvent>[plan.events.first];

        final directProjection = IosNotificationProjection(
          events: mutableEvents,
          renewalEvent: null,
          existingOtherPendingIds: mutableSet,
          capacityStatus: IosTruncationStatus.singleSlotPrayerOnly,
          coverageHorizonUtc: plan.events.first.triggerDateTimeUtc,
          statusMessage: 'Direct construction test',
        );

        mutableSet.add(999);
        mutableEvents.clear();

        expect(directProjection.existingOtherPendingIds.length, 3);
        expect(directProjection.existingOtherPendingIds.contains(999), isFalse);
        expect(directProjection.events.length, 1);
        expect(
          () => directProjection.existingOtherPendingIds.add(1000),
          throwsUnsupportedError,
        );
        expect(
          () => directProjection.events.add(plan.events.first),
          throwsUnsupportedError,
        );
      },
    );

    test(
      'equality and hashCode contract: two equivalent existingOtherPendingIds in reverse insertion order yield equal projections, identical hashCodes, and Set lookup succeeds',
      () {
        final planForward = planner.build(
          city: cairo,
          settings: PrayerSettings.egyptDefault(),
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'malmo_fajr',
          mode: 'full_adhan',
          existingOtherIosPendingIds: {101, 102, 103},
        );

        final planReverse = planner.build(
          city: cairo,
          settings: PrayerSettings.egyptDefault(),
          nowUtc: nowUtc,
          generalVoiceId: 'adam',
          fajrVoiceId: 'malmo_fajr',
          mode: 'full_adhan',
          existingOtherIosPendingIds: {103, 102, 101},
        );

        final projForward = planForward.iosProjection;
        final projReverse = planReverse.iosProjection;

        // Projections must be equal
        expect(projForward == projReverse, isTrue);
        expect(projReverse == projForward, isTrue);

        // Hash codes must be identical (order-independent Set hashing via Object.hashAllUnordered)
        expect(projForward.hashCode, equals(projReverse.hashCode));

        // Set lookup with projReverse must successfully locate projForward
        final projectionSet = <IosNotificationProjection>{projForward};
        expect(projectionSet.contains(projReverse), isTrue);

        final planSet = <PrayerNotificationPlan>{planForward};
        expect(planSet.contains(planReverse), isTrue);
      },
    );
  });
}
