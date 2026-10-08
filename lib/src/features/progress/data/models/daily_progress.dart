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
  final Set<int> confirmedPages;
  final int morningCompletedCount;
  final int eveningCompletedCount;
  final bool shared100Completed;
  final int? dailyDuaItemId;
  final bool isLegacyRecord;
  final DateTime? updatedAt;

  // Separately labelled historical metadata from legacy bare or pre-v3 rows
  final bool? legacyQuranCompleted;
  final bool? legacyMorningDhikrCompleted;
  final bool? legacyEveningDhikrCompleted;
  final bool? legacyPostPrayerDhikrCompleted;
  final bool? legacyDailyDuaCompleted;
  final int? legacyQuranPagesRead;

  const DailyProgress({
    required this.dateBucket,
    this.quranCompleted = false,
    this.morningDhikrCompleted = false,
    this.eveningDhikrCompleted = false,
    this.postPrayerDhikrCompleted = false,
    this.dailyDuaCompleted = false,
    this.quranGoalPages = 2,
    this.quranPagesRead = 0,
    this.confirmedPages = const <int>{},
    this.morningCompletedCount = 0,
    this.eveningCompletedCount = 0,
    this.shared100Completed = false,
    this.dailyDuaItemId,
    this.isLegacyRecord = false,
    this.updatedAt,
    this.legacyQuranCompleted,
    this.legacyMorningDhikrCompleted,
    this.legacyEveningDhikrCompleted,
    this.legacyPostPrayerDhikrCompleted,
    this.legacyDailyDuaCompleted,
    this.legacyQuranPagesRead,
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
    Set<int>? confirmedPages,
    int? morningCompletedCount,
    int? eveningCompletedCount,
    bool? shared100Completed,
    int? dailyDuaItemId,
    bool? isLegacyRecord,
    DateTime? updatedAt,
    bool? legacyQuranCompleted,
    bool? legacyMorningDhikrCompleted,
    bool? legacyEveningDhikrCompleted,
    bool? legacyPostPrayerDhikrCompleted,
    bool? legacyDailyDuaCompleted,
    int? legacyQuranPagesRead,
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
      confirmedPages: confirmedPages ?? this.confirmedPages,
      morningCompletedCount: morningCompletedCount ?? this.morningCompletedCount,
      eveningCompletedCount: eveningCompletedCount ?? this.eveningCompletedCount,
      shared100Completed: shared100Completed ?? this.shared100Completed,
      dailyDuaItemId: dailyDuaItemId ?? this.dailyDuaItemId,
      isLegacyRecord: isLegacyRecord ?? this.isLegacyRecord,
      updatedAt: updatedAt ?? this.updatedAt,
      legacyQuranCompleted: legacyQuranCompleted ?? this.legacyQuranCompleted,
      legacyMorningDhikrCompleted: legacyMorningDhikrCompleted ?? this.legacyMorningDhikrCompleted,
      legacyEveningDhikrCompleted: legacyEveningDhikrCompleted ?? this.legacyEveningDhikrCompleted,
      legacyPostPrayerDhikrCompleted: legacyPostPrayerDhikrCompleted ?? this.legacyPostPrayerDhikrCompleted,
      legacyDailyDuaCompleted: legacyDailyDuaCompleted ?? this.legacyDailyDuaCompleted,
      legacyQuranPagesRead: legacyQuranPagesRead ?? this.legacyQuranPagesRead,
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

  factory DailyProgress.fromMap(Map<String, dynamic> map, {
    Set<int> confirmedPages = const <int>{},
    int morningCompletedCount = 0,
    int eveningCompletedCount = 0,
    bool shared100Completed = false,
    int? dailyDuaItemId,
    bool isLegacyRecord = false,
  }) {
    final bucket = map['date_bucket'] as String? ?? '';
    final legacy = isLegacyRecord || !bucket.contains('|');
    return DailyProgress(
      dateBucket: bucket,
      quranCompleted: (map['quran_completed'] as num?)?.toInt() == 1,
      morningDhikrCompleted: (map['morning_dhikr_completed'] as num?)?.toInt() == 1,
      eveningDhikrCompleted: (map['evening_dhikr_completed'] as num?)?.toInt() == 1,
      postPrayerDhikrCompleted: (map['post_prayer_dhikr_completed'] as num?)?.toInt() == 1,
      dailyDuaCompleted: (map['daily_dua_completed'] as num?)?.toInt() == 1,
      quranGoalPages: (map['quran_goal_pages'] as num?)?.toInt() ?? 2,
      quranPagesRead: (map['quran_pages_read'] as num?)?.toInt() ?? 0,
      confirmedPages: confirmedPages,
      morningCompletedCount: morningCompletedCount,
      eveningCompletedCount: eveningCompletedCount,
      shared100Completed: shared100Completed,
      dailyDuaItemId: dailyDuaItemId,
      isLegacyRecord: legacy,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      legacyQuranCompleted: (map['quran_completed'] as num?)?.toInt() == 1,
      legacyMorningDhikrCompleted: (map['morning_dhikr_completed'] as num?)?.toInt() == 1,
      legacyEveningDhikrCompleted: (map['evening_dhikr_completed'] as num?)?.toInt() == 1,
      legacyPostPrayerDhikrCompleted: (map['post_prayer_dhikr_completed'] as num?)?.toInt() == 1,
      legacyDailyDuaCompleted: (map['daily_dua_completed'] as num?)?.toInt() == 1,
      legacyQuranPagesRead: (map['quran_pages_read'] as num?)?.toInt() ?? 0,
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
        other.quranPagesRead == quranPagesRead &&
        setEquals(other.confirmedPages, confirmedPages) &&
        other.morningCompletedCount == morningCompletedCount &&
        other.eveningCompletedCount == eveningCompletedCount &&
        other.shared100Completed == shared100Completed &&
        other.dailyDuaItemId == dailyDuaItemId &&
        other.isLegacyRecord == isLegacyRecord &&
        other.legacyQuranCompleted == legacyQuranCompleted &&
        other.legacyMorningDhikrCompleted == legacyMorningDhikrCompleted &&
        other.legacyEveningDhikrCompleted == legacyEveningDhikrCompleted &&
        other.legacyPostPrayerDhikrCompleted == legacyPostPrayerDhikrCompleted &&
        other.legacyDailyDuaCompleted == legacyDailyDuaCompleted &&
        other.legacyQuranPagesRead == legacyQuranPagesRead;
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
        Object.hashAll(confirmedPages),
        morningCompletedCount,
        eveningCompletedCount,
        shared100Completed,
        dailyDuaItemId,
        isLegacyRecord,
      );

  @override
  String toString() => 'DailyProgress($dateBucket: $completedTasksCount/5, Quran: $quranPagesRead/$quranGoalPages, morning: $morningCompletedCount/22, evening: $eveningCompletedCount/20)';
}
