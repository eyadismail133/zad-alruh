/// Immutable representation of a Quran Verse (Aya).
///
/// Contains the unmodified original verbatim Uthmani text for display
/// and a pre-calculated normalized Arabic search key.
class Verse {
  /// 1-based Surah index (1 to 114).
  final int surahNumber;

  /// 1-based Verse number within the Surah.
  final int verseNumber;

  /// Verbatim original Uthmani text with full diacritics and signs.
  /// Never modified or altered during search.
  final String text;

  /// Separate normalized Arabic string for search without diacritics/tatweel.
  final String normalizedText;

  /// 1-based page number in the standard 604-page Medina Mushaf.
  final int pageNumber;

  /// 1-based Juz number (1 to 30).
  final int juzNumber;

  const Verse({
    required this.surahNumber,
    required this.verseNumber,
    required this.text,
    required this.normalizedText,
    required this.pageNumber,
    required this.juzNumber,
  });

  /// Stable composite reference identifier (e.g. "1:1", "2:255").
  String get id => '$surahNumber:$verseNumber';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Verse &&
          runtimeType == other.runtimeType &&
          surahNumber == other.surahNumber &&
          verseNumber == other.verseNumber &&
          text == other.text &&
          pageNumber == other.pageNumber &&
          juzNumber == other.juzNumber;

  @override
  int get hashCode =>
      surahNumber.hashCode ^
      verseNumber.hashCode ^
      text.hashCode ^
      pageNumber.hashCode ^
      juzNumber.hashCode;

  @override
  String toString() => 'Verse($id, page $pageNumber, juz $juzNumber)';
}
