import 'package:flutter/foundation.dart';

const Object _kSentinel = Object();

/// Shared stable task key constants for source-linked confirmations.
class DailySourceTasks {
  DailySourceTasks._();
  static const String dailyDua = 'daily_dua';
  static const String postPrayer = 'post_prayer';
}

@immutable
class DailySourceConfirmation {
  final String dateBucket;
  final String taskKey;
  final int? hisnItemId;
  final bool isCompleted;
  final DateTime updatedAt;

  const DailySourceConfirmation({
    required this.dateBucket,
    required this.taskKey,
    this.hisnItemId,
    required this.isCompleted,
    required this.updatedAt,
  });

  DailySourceConfirmation copyWith({
    String? dateBucket,
    String? taskKey,
    Object? hisnItemId = _kSentinel,
    bool? isCompleted,
    DateTime? updatedAt,
  }) {
    return DailySourceConfirmation(
      dateBucket: dateBucket ?? this.dateBucket,
      taskKey: taskKey ?? this.taskKey,
      hisnItemId: identical(hisnItemId, _kSentinel)
          ? this.hisnItemId
          : hisnItemId as int?,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'date_bucket': dateBucket,
      'task_key': taskKey,
      'hisn_item_id': hisnItemId,
      'is_completed': isCompleted ? 1 : 0,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DailySourceConfirmation.fromMap(Map<String, dynamic> map) {
    return DailySourceConfirmation(
      dateBucket: map['date_bucket'] as String? ?? '',
      taskKey: map['task_key'] as String? ?? '',
      hisnItemId: (map['hisn_item_id'] as num?)?.toInt(),
      isCompleted: (map['is_completed'] as num?)?.toInt() == 1,
      updatedAt: map['updated_at'] != null
          ? (DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DailySourceConfirmation &&
        other.dateBucket == dateBucket &&
        other.taskKey == taskKey &&
        other.hisnItemId == hisnItemId &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(dateBucket, taskKey, hisnItemId, isCompleted);

  @override
  String toString() =>
      'DailySourceConfirmation($dateBucket, $taskKey, item: $hisnItemId, completed: $isCompleted)';
}
