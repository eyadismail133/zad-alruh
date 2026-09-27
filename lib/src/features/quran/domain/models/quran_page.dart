/// Immutable representation of a Quran Page boundary (1 to 604) in Medina Mushaf.
class QuranPage {
  /// 1-based page number (1 to 604).
  final int pageNumber;

  /// Surah number where this page begins (1 to 114).
  final int startSurahNumber;

  /// Verse number within the starting Surah where this page begins.
  final int startVerseNumber;

  const QuranPage({
    required this.pageNumber,
    required this.startSurahNumber,
    required this.startVerseNumber,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuranPage &&
          runtimeType == other.runtimeType &&
          pageNumber == other.pageNumber &&
          startSurahNumber == other.startSurahNumber &&
          startVerseNumber == other.startVerseNumber;

  @override
  int get hashCode =>
      pageNumber.hashCode ^
      startSurahNumber.hashCode ^
      startVerseNumber.hashCode;

  @override
  String toString() =>
      'QuranPage($pageNumber: starts at $startSurahNumber:$startVerseNumber)';
}
