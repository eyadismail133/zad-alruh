import 'package:flutter/foundation.dart';

@immutable
class ReadingProgress {
  final int lastPage;
  final int? selectedSurah;
  final int? selectedVerse;
  final DateTime? updatedAt;
  final int? nextResumePage;
  int get resumePage => nextResumePage ?? lastPage;

  const ReadingProgress({
    this.lastPage = 1,
    this.selectedSurah,
    this.selectedVerse,
    this.updatedAt,
    this.nextResumePage,
  }) : assert(
         lastPage >= 1 && lastPage <= 604,
         'lastPage must be between 1 and 604',
       );

  ReadingProgress copyWith({
    int? lastPage,
    int? selectedSurah,
    int? selectedVerse,
    DateTime? updatedAt,
    int? nextResumePage,
  }) {
    return ReadingProgress(
      lastPage: lastPage ?? this.lastPage,
      selectedSurah: selectedSurah ?? this.selectedSurah,
      selectedVerse: selectedVerse ?? this.selectedVerse,
      updatedAt: updatedAt ?? this.updatedAt,
      nextResumePage: nextResumePage ?? this.nextResumePage,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': 1,
      'last_page': lastPage,
      'selected_surah': selectedSurah,
      'selected_verse': selectedVerse,
      'resume_page': nextResumePage,
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory ReadingProgress.fromMap(Map<String, dynamic> map) {
    return ReadingProgress(
      lastPage: (map['last_page'] as num?)?.toInt() ?? 1,
      selectedSurah: (map['selected_surah'] as num?)?.toInt(),
      selectedVerse: (map['selected_verse'] as num?)?.toInt(),
      nextResumePage: (map['resume_page'] as num?)?.toInt(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReadingProgress &&
        other.lastPage == lastPage &&
        other.selectedSurah == selectedSurah &&
        other.selectedVerse == selectedVerse &&
        other.nextResumePage == nextResumePage;
  }

  @override
  int get hashCode =>
      Object.hash(lastPage, selectedSurah, selectedVerse, nextResumePage);

  @override
  String toString() =>
      'ReadingProgress(lastPage: $lastPage, surah: $selectedSurah, verse: $selectedVerse)';
}
