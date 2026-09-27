import 'package:flutter/foundation.dart';

@immutable
class Bookmark {
  final int? id;
  final String name;
  final int pageNumber;
  final int? surahNumber;
  final int? verseNumber;
  final DateTime createdAt;

  const Bookmark({
    this.id,
    required this.name,
    required this.pageNumber,
    this.surahNumber,
    this.verseNumber,
    required this.createdAt,
  }) : assert(pageNumber >= 1 && pageNumber <= 604, 'pageNumber must be between 1 and 604');

  Bookmark copyWith({
    int? id,
    String? name,
    int? pageNumber,
    int? surahNumber,
    int? verseNumber,
    DateTime? createdAt,
  }) {
    return Bookmark(
      id: id ?? this.id,
      name: name ?? this.name,
      pageNumber: pageNumber ?? this.pageNumber,
      surahNumber: surahNumber ?? this.surahNumber,
      verseNumber: verseNumber ?? this.verseNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'page_number': pageNumber,
      'surah_number': surahNumber,
      'verse_number': verseNumber,
      'created_at': createdAt.toIso8601String(),
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: (map['id'] as num?)?.toInt(),
      name: map['name'] as String? ?? '',
      pageNumber: (map['page_number'] as num?)?.toInt() ?? 1,
      surahNumber: (map['surah_number'] as num?)?.toInt(),
      verseNumber: (map['verse_number'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Bookmark &&
        other.id == id &&
        other.name == name &&
        other.pageNumber == pageNumber &&
        other.surahNumber == surahNumber &&
        other.verseNumber == verseNumber;
  }

  @override
  int get hashCode => Object.hash(id, name, pageNumber, surahNumber, verseNumber);

  @override
  String toString() => 'Bookmark(id: $id, name: $name, page: $pageNumber)';
}
