import 'package:flutter/foundation.dart';

@immutable
class DhikrSession {
  final String sessionId;
  final String dhikrId;
  final String category;
  final int targetCount;
  final int currentCount;
  final bool isCompleted;
  final String dateBucket;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DhikrSession({
    required this.sessionId,
    required this.dhikrId,
    required this.category,
    required this.targetCount,
    this.currentCount = 0,
    this.isCompleted = false,
    required this.dateBucket,
    required this.createdAt,
    required this.updatedAt,
  }) : assert(targetCount > 0, 'targetCount must be greater than zero'),
       assert(currentCount >= 0 && currentCount <= targetCount, 'currentCount must be between 0 and targetCount');

  double get progressRatio => targetCount > 0 ? (currentCount / targetCount).clamp(0.0, 1.0) : 0.0;
  int get remainingCount => (targetCount - currentCount).clamp(0, targetCount);

  DhikrSession copyWith({
    String? sessionId,
    String? dhikrId,
    String? category,
    int? targetCount,
    int? currentCount,
    bool? isCompleted,
    String? dateBucket,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DhikrSession(
      sessionId: sessionId ?? this.sessionId,
      dhikrId: dhikrId ?? this.dhikrId,
      category: category ?? this.category,
      targetCount: targetCount ?? this.targetCount,
      currentCount: currentCount ?? this.currentCount,
      isCompleted: isCompleted ?? this.isCompleted,
      dateBucket: dateBucket ?? this.dateBucket,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'session_id': sessionId,
      'dhikr_id': dhikrId,
      'category': category,
      'target_count': targetCount,
      'current_count': currentCount,
      'is_completed': isCompleted ? 1 : 0,
      'date_bucket': dateBucket,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DhikrSession.fromMap(Map<String, dynamic> map) {
    return DhikrSession(
      sessionId: map['session_id'] as String? ?? '',
      dhikrId: map['dhikr_id'] as String? ?? '',
      category: map['category'] as String? ?? '',
      targetCount: (map['target_count'] as num?)?.toInt() ?? 33,
      currentCount: (map['current_count'] as num?)?.toInt() ?? 0,
      isCompleted: (map['is_completed'] as num?)?.toInt() == 1,
      dateBucket: map['date_bucket'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DhikrSession &&
        other.sessionId == sessionId &&
        other.currentCount == currentCount &&
        other.isCompleted == isCompleted;
  }

  @override
  int get hashCode => Object.hash(sessionId, currentCount, isCompleted);

  @override
  String toString() => 'DhikrSession($sessionId: $currentCount/$targetCount, completed: $isCompleted)';
}
