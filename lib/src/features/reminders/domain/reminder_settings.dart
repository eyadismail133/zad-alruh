import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A short, well-known dhikr phrase that can be used in periodic reminders.
@immutable
class DhikrPhrase {
  final String id;
  final String text;

  const DhikrPhrase(this.id, this.text);

  static const List<DhikrPhrase> all = [
    DhikrPhrase('subhan', 'سبحان الله'),
    DhikrPhrase('hamd', 'الحمد لله'),
    DhikrPhrase('tahlil', 'لا إله إلا الله'),
    DhikrPhrase('takbir', 'الله أكبر'),
    DhikrPhrase('subhan_azim', 'سبحان الله وبحمده، سبحان الله العظيم'),
    DhikrPhrase('istighfar', 'أستغفر الله وأتوب إليه'),
    DhikrPhrase('hawqala', 'لا حول ولا قوة إلا بالله'),
    DhikrPhrase('salawat', 'اللهم صلِّ وسلِّم على نبينا محمد'),
    DhikrPhrase('yunus', 'لا إله إلا أنت سبحانك إني كنت من الظالمين'),
  ];

  static DhikrPhrase? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// User configuration for offline reminders (persisted as JSON).
@immutable
class ReminderSettings {
  /// Periodic dhikr reminders.
  final bool dhikrEnabled;
  final int intervalMinutes;
  final int startHour;
  final int endHour;
  final List<String> phraseIds;

  /// Show as a heads-up pop-up over the current screen (high importance)
  /// instead of a quiet notification in the shade.
  final bool popUp;

  /// 'overlay' = gentle floating card on screen; 'notification' = regular
  /// notification (heads-up when [popUp]).
  final String displayStyle;

  /// Where the floating card appears: 'top' | 'center' | 'bottom'.
  final String overlayPosition;

  /// Seconds the floating card stays before fading out.
  final int overlaySeconds;

  bool get useOverlay => displayStyle == 'overlay';

  /// Fixed daily/weekly reminders.
  final bool morningAdhkar;
  final bool eveningAdhkar;
  final bool sleepAdhkar;
  final bool fridayKahf;
  final bool dailyWird;

  const ReminderSettings({
    this.dhikrEnabled = false,
    this.intervalMinutes = 60,
    this.startHour = 8,
    this.endHour = 22,
    this.phraseIds = const ['subhan', 'hamd', 'tahlil', 'takbir', 'istighfar', 'salawat'],
    this.popUp = true,
    this.displayStyle = 'overlay',
    this.overlayPosition = 'top',
    this.overlaySeconds = 8,
    this.morningAdhkar = false,
    this.eveningAdhkar = false,
    this.sleepAdhkar = false,
    this.fridayKahf = false,
    this.dailyWird = false,
  });

  static const List<int> intervalOptions = [15, 30, 60, 120, 180];

  bool get anyEnabled =>
      dhikrEnabled ||
      morningAdhkar ||
      eveningAdhkar ||
      sleepAdhkar ||
      fridayKahf ||
      dailyWird;

  List<DhikrPhrase> get phrases {
    final list = phraseIds.map(DhikrPhrase.byId).whereType<DhikrPhrase>().toList();
    return list.isEmpty ? [DhikrPhrase.all.first] : list;
  }

  ReminderSettings copyWith({
    bool? dhikrEnabled,
    int? intervalMinutes,
    int? startHour,
    int? endHour,
    List<String>? phraseIds,
    bool? popUp,
    String? displayStyle,
    String? overlayPosition,
    int? overlaySeconds,
    bool? morningAdhkar,
    bool? eveningAdhkar,
    bool? sleepAdhkar,
    bool? fridayKahf,
    bool? dailyWird,
  }) {
    return ReminderSettings(
      dhikrEnabled: dhikrEnabled ?? this.dhikrEnabled,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      startHour: startHour ?? this.startHour,
      endHour: endHour ?? this.endHour,
      phraseIds: phraseIds ?? this.phraseIds,
      popUp: popUp ?? this.popUp,
      displayStyle: displayStyle ?? this.displayStyle,
      overlayPosition: overlayPosition ?? this.overlayPosition,
      overlaySeconds: overlaySeconds ?? this.overlaySeconds,
      morningAdhkar: morningAdhkar ?? this.morningAdhkar,
      eveningAdhkar: eveningAdhkar ?? this.eveningAdhkar,
      sleepAdhkar: sleepAdhkar ?? this.sleepAdhkar,
      fridayKahf: fridayKahf ?? this.fridayKahf,
      dailyWird: dailyWird ?? this.dailyWird,
    );
  }

  Map<String, Object> toJson() => {
        'dhikrEnabled': dhikrEnabled,
        'intervalMinutes': intervalMinutes,
        'startHour': startHour,
        'endHour': endHour,
        'phraseIds': phraseIds,
        'popUp': popUp,
        'displayStyle': displayStyle,
        'overlayPosition': overlayPosition,
        'overlaySeconds': overlaySeconds,
        'morningAdhkar': morningAdhkar,
        'eveningAdhkar': eveningAdhkar,
        'sleepAdhkar': sleepAdhkar,
        'fridayKahf': fridayKahf,
        'dailyWird': dailyWird,
      };

  String encode() => jsonEncode(toJson());

  static ReminderSettings decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ReminderSettings();
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      bool b(String k, bool d) => m[k] is bool ? m[k] as bool : d;
      int i(String k, int d) => m[k] is int ? m[k] as int : d;
      final ids = (m['phraseIds'] is List)
          ? (m['phraseIds'] as List).whereType<String>().toList()
          : const ReminderSettings().phraseIds;
      const d = ReminderSettings();
      return ReminderSettings(
        dhikrEnabled: b('dhikrEnabled', d.dhikrEnabled),
        intervalMinutes: intervalOptions.contains(i('intervalMinutes', 60))
            ? i('intervalMinutes', 60)
            : 60,
        startHour: i('startHour', d.startHour).clamp(0, 23),
        endHour: i('endHour', d.endHour).clamp(1, 24),
        phraseIds: ids,
        popUp: b('popUp', d.popUp),
        displayStyle: m['displayStyle'] == 'notification' ? 'notification' : 'overlay',
        overlayPosition: const ['top', 'center', 'bottom'].contains(m['overlayPosition'])
            ? m['overlayPosition'] as String
            : 'top',
        overlaySeconds: i('overlaySeconds', 8).clamp(3, 60),
        morningAdhkar: b('morningAdhkar', d.morningAdhkar),
        eveningAdhkar: b('eveningAdhkar', d.eveningAdhkar),
        sleepAdhkar: b('sleepAdhkar', d.sleepAdhkar),
        fridayKahf: b('fridayKahf', d.fridayKahf),
        dailyWird: b('dailyWird', d.dailyWird),
      );
    } catch (_) {
      return const ReminderSettings();
    }
  }
}

/// One concrete notification to schedule.
@immutable
class PlannedReminder {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
  final bool popUp;

  const PlannedReminder({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    required this.payload,
    required this.popUp,
  });
}

/// Pure planning logic (unit-testable): which reminders fire in the next
/// [days] days after [now]. IDs live in [idBase]..[idBase]+[maxCount].
List<PlannedReminder> planReminders(
  ReminderSettings s,
  DateTime now, {
  int days = 3,
  int maxCount = 300,
  int idBase = 70000,
}) {
  final out = <PlannedReminder>[];
  var nextId = idBase;

  void add(DateTime at, String title, String body, String payload, bool popUp) {
    if (!at.isAfter(now) || out.length >= maxCount) return;
    out.add(PlannedReminder(
      id: nextId++,
      at: at,
      title: title,
      body: body,
      payload: payload,
      popUp: popUp,
    ));
  }

  final startDay = DateTime(now.year, now.month, now.day);
  for (var d = 0; d < days; d++) {
    final day = startDay.add(Duration(days: d));
    if (s.morningAdhkar) {
      add(DateTime(day.year, day.month, day.day, 7, 0), 'أذكار الصباح',
          'حان وقت أذكار الصباح، حصّن يومك بذكر الله', 'open:morning', s.popUp);
    }
    if (s.eveningAdhkar) {
      add(DateTime(day.year, day.month, day.day, 17, 0), 'أذكار المساء',
          'حان وقت أذكار المساء', 'open:evening', s.popUp);
    }
    if (s.dailyWird) {
      add(DateTime(day.year, day.month, day.day, 20, 0), 'وِردك اليومي',
          'لا تنسَ وِردك من القرآن اليوم', 'open:quran', s.popUp);
    }
    if (s.sleepAdhkar) {
      add(DateTime(day.year, day.month, day.day, 22, 30), 'أذكار النوم',
          'اختم يومك بأذكار النوم', 'open:hisn', s.popUp);
    }
    if (s.fridayKahf && day.weekday == DateTime.friday) {
      add(DateTime(day.year, day.month, day.day, 10, 0), 'يوم الجمعة',
          'لا تنسَ قراءة سورة الكهف والإكثار من الصلاة على النبي ﷺ',
          'open:kahf', s.popUp);
    }
  }

  if (s.dhikrEnabled) {
    final phrases = s.phrases;
    var phraseIndex = 0;
    var t = DateTime(now.year, now.month, now.day, s.startHour);
    final end = startDay.add(Duration(days: days));
    while (t.isBefore(end) && out.length < maxCount) {
      final inWindow = s.endHour > s.startHour
          ? (t.hour >= s.startHour && t.hour < s.endHour)
          : (t.hour >= s.startHour || t.hour < s.endHour);
      if (inWindow && t.isAfter(now)) {
        final p = phrases[phraseIndex % phrases.length];
        phraseIndex++;
        add(t, 'ذكر', p.text, 'dhikr:${p.id}', s.popUp);
      }
      t = t.add(Duration(minutes: s.intervalMinutes));
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}
