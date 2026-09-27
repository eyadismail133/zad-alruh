import 'package:flutter/foundation.dart';

@immutable
class Favorite {
  final int? id;
  final String contentKind;
  final String stableId;
  final String title;
  final String? subtitle;
  final DateTime? createdAt;

  const Favorite({
    this.id,
    required this.contentKind,
    required this.stableId,
    required this.title,
    this.subtitle,
    this.createdAt,
  });

  Favorite copyWith({
    int? id,
    String? contentKind,
    String? stableId,
    String? title,
    String? subtitle,
    DateTime? createdAt,
  }) {
    return Favorite(
      id: id ?? this.id,
      contentKind: contentKind ?? this.contentKind,
      stableId: stableId ?? this.stableId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'content_kind': contentKind,
      'stable_id': stableId,
      'title': title,
      'subtitle': subtitle,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory Favorite.fromMap(Map<String, dynamic> map) {
    return Favorite(
      id: (map['id'] as num?)?.toInt(),
      contentKind: map['content_kind'] as String? ?? '',
      stableId: map['stable_id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      subtitle: map['subtitle'] as String?,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Favorite &&
        other.contentKind == contentKind &&
        other.stableId == stableId;
  }

  @override
  int get hashCode => Object.hash(contentKind, stableId);

  @override
  String toString() => 'Favorite(kind: $contentKind, id: $stableId, title: $title)';
}
