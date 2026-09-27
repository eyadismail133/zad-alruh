import 'package:flutter/foundation.dart';

@immutable
class DailyProgress {
  final String dateBucket;
  final bool quranCompleted;
  final bool morningDhikrCompleted;
  final bool eveningDhikrCompleted;
  final bool postPrayerDhikrCompleted;
  final bool dailyDuaCompleted;
  final int quranGoalPages;
  final int quranPagesRead;
  final DateTime? updatedAt;

  const DailyProgress({
    required this.dateBucket,
    this.quranCompleted = false,
    this.morningDhikrCompleted = false,
    this.eveningDhikrCompleted = false,
    this.postPrayerDhikrCompleted = false,
    this.dailyDuaCompleted = false,
    this.quranGoalPages = 2,
    this.quranPagesRead = 0,
    this.updatedAt,
  });

  int get completedTasksCount {
    int count = 0;
    if (quranCompleted) count++;
    if (morningDhikrCompleted) count++;
    if (eveningDhikrCompleted) count++;
    if (postPrayerDhikrCompleted) count++;
    if (dailyDuaCompleted) count++;
    return count;
  }

  static const int totalTasksCount = 5;

  double get completionRatio => completedTasksCount / totalTasksCount;
  int get completionPercentage => (completionRatio * 100).round();

  DailyProgress copyWith({
    String? dateBucket,
    bool? quranCompleted,
    bool? morningDhikrCompleted,
    bool? eveningDhikrCompleted,
    bool? postPrayerDhikrCompleted,
    bool? dailyDuaCompleted,
    int? quranGoalPages,
    int? quranPagesRead,
    DateTime? updatedAt,
  }) {
    return DailyProgress(
      dateBucket: dateBucket ?? this.dateBucket,
      quranCompleted: quranCompleted ?? this.quranCompleted,
      morningDhikrCompleted: morningDhikrCompleted ?? this.morningDhikrCompleted,
      eveningDhikrCompleted: eveningDhikrCompleted ?? this.eveningDhikrCompleted,
      postPrayerDhikrCompleted: postPrayerDhikrCompleted ?? this.postPrayerDhikrCompleted,
      dailyDuaCompleted: dailyDuaCompleted ?? this.dailyDuaCompleted,
      quranGoalPages: quranGoalPages ?? this.quranGoalPages,
      quranPagesRead: quranPagesRead ?? this.quranPagesRead,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'date_bucket': dateBucket,
      'quran_completed': quranCompleted ? 1 : 0,
      'morning_dhikr_completed': morningDhikrCompleted ? 1 : 0,
      'evening_dhikr_completed': eveningDhikrCompleted ? 1 : 0,
      'post_prayer_dhikr_completed': postPrayerDhikrCompleted ? 1 : 0,
      'daily_dua_completed': dailyDuaCompleted ? 1 : 0,
      'quran_goal_pages': quranGoalPages,
      'quran_pages_read': quranPagesRead,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory DailyProgress.fromMap(Map<String, dynamic> map) {
    return DailyProgress(
      dateBucket: map['date_bucket'] as String? ?? '',
      quranCompleted: (map['quran_completed'] as num?)?.toInt() == 1,
      morningDhikrCompleted: (map['morning_dhikr_completed'] as num?)?.toInt() == 1,
      eveningDhikrCompleted: (map['evening_dhikr_completed'] as num?)?.toInt() == 1,
      postPrayerDhikrCompleted: (map['post_prayer_dhikr_completed'] as num?)?.toInt() == 1,
      dailyDuaCompleted: (map['daily_dua_completed'] as num?)?.toInt() == 1,
      quranGoalPages: (map['quran_goal_pages'] as num?)?.toInt() ?? 2,
      quranPagesRead: (map['quran_pages_read'] as num?)?.toInt() ?? 0,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailyProgress &&
        other.dateBucket == dateBucket &&
        other.quranCompleted == quranCompleted &&
        other.morningDhikrCompleted == morningDhikrCompleted &&
        other.eveningDhikrCompleted == eveningDhikrCompleted &&
        other.postPrayerDhikrCompleted == postPrayerDhikrCompleted &&
        other.dailyDuaCompleted == dailyDuaCompleted &&
        other.quranGoalPages == quranGoalPages &&
        other.quranPagesRead == quranPagesRead;
  }

  @override
  int get hashCode => Object.hash(
        dateBucket,
        quranCompleted,
        morningDhikrCompleted,
        eveningDhikrCompleted,
        postPrayerDhikrCompleted,
        dailyDuaCompleted,
        quranGoalPages,
        quranPagesRead,
      );

  @override
  String toString() => 'DailyProgress($dateBucket: $completedTasksCount/5, Quran: $quranPagesRead/$quranGoalPages)';
}
