import 'package:flutter_test/flutter_test.dart';
import 'package:zad_alruh/src/features/reminders/domain/reminder_settings.dart';

void main() {
  group('planReminders', () {
    final now = DateTime(2026, 11, 9, 9, 10); // Monday 09:10

    test('nothing planned when everything is off', () {
      expect(planReminders(const ReminderSettings(), now), isEmpty);
    });

    test('hourly dhikr stays inside the active window and after now', () {
      const s = ReminderSettings(
        dhikrEnabled: true,
        intervalMinutes: 60,
        startHour: 8,
        endHour: 22,
        phraseIds: ['subhan', 'takbir'],
      );
      final plan = planReminders(s, now, days: 1);
      expect(plan, isNotEmpty);
      expect(plan.every((r) => r.at.isAfter(now)), isTrue);
      expect(plan.every((r) => r.at.hour >= 8 && r.at.hour < 22), isTrue);
      expect(plan.first.at, DateTime(2026, 11, 9, 10));
      expect(plan.length, 12); // 10:00 … 21:00
      expect(plan.map((r) => r.body).toSet(), {'سبحان الله', 'الله أكبر'});
      expect(plan.map((r) => r.id).toSet().length, plan.length);
    });

    test('fixed reminders and Friday Kahf', () {
      const s = ReminderSettings(
        morningAdhkar: true,
        eveningAdhkar: true,
        fridayKahf: true,
      );
      final plan = planReminders(s, now, days: 7);
      // Morning 07:00 today already passed → 6 mornings, 7 evenings, 1 Friday.
      expect(plan.where((r) => r.payload == 'open:morning').length, 6);
      expect(plan.where((r) => r.payload == 'open:evening').length, 7);
      final kahf = plan.where((r) => r.payload == 'open:kahf').toList();
      expect(kahf.length, 1);
      expect(kahf.single.at.weekday, DateTime.friday);
    });

    test('settings survive encode/decode', () {
      const s = ReminderSettings(
        dhikrEnabled: true,
        intervalMinutes: 30,
        popUp: false,
        phraseIds: ['hamd'],
      );
      final back = ReminderSettings.decode(s.encode());
      expect(back.dhikrEnabled, isTrue);
      expect(back.intervalMinutes, 30);
      expect(back.popUp, isFalse);
      expect(back.phraseIds, ['hamd']);
      expect(ReminderSettings.decode('not json').dhikrEnabled, isFalse);
    });
  });
}
