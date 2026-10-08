import 'package:flutter/foundation.dart';
import '../../../hisn/domain/models/hisn_daily_catalog.dart';

@immutable
class HisnDailyItemProgress {
  final String dateBucket;
  final DhikrPeriod period;
  final int itemId;
  final bool isCompleted;
  final DateTime updatedAt;

  const HisnDailyItemProgress({
    required this.dateBucket,
    required this.period,
    required this.itemId,
    required this.isCompleted,
    required this.updatedAt,
  });

  HisnDailyItemProgress copyWith({
    String? dateBucket,
    DhikrPeriod? period,
    int? itemId,
    bool? isCompleted,
    DateTime? updatedAt,
  }) {
    return HisnDailyItemProgress(
      dateBucket: dateBucket ?? this.dateBucket,
      period: period ?? this.period,
      itemId: itemId ?? this.itemId,
      isCompleted: isCompleted ?? this.isCompleted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'date_bucket': dateBucket,
      'period': period.key,
      'item_id': itemId,
      'is_completed': isCompleted ? 1 : 0,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory HisnDailyItemProgress.fromMap(Map<String, dynamic> map) {
    return HisnDailyItemProgress(
      dateBucket: map['date_bucket'] as String? ?? '',
      period: DhikrPeriod.fromKey(map['period'] as String? ?? 'morning'),
      itemId: (map['item_id'] as num?)?.toInt() ?? 0,
      isCompleted: (map['is_completed'] as num?)?.toInt() == 1,
      updatedAt: map['updated_at'] != null
          ? (DateTime.tryParse(map['updated_at'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HisnDailyItemProgress &&
        other.dateBucket == dateBucket &&
        other.period == period &&
        other.itemId == itemId &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(dateBucket, period, itemId, isCompleted);

  @override
  String toString() =>
      'HisnDailyItemProgress($dateBucket, ${period.key}, #$itemId, completed: $isCompleted)';
}
