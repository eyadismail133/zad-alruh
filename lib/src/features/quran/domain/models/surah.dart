/// Immutable representation of a Quran Chapter (Surah).
class Surah {
  /// 1-based Surah index (1 to 114).
  final int number;

  /// Arabic Surah name (e.g. "الفاتحة").
  final String name;

  /// Transliterated Surah name (e.g. "Al-Faatiha").
  final String transliteration;

  /// English translation of Surah name (e.g. "The Opening").
  final String englishName;

  /// Revelation type ("Meccan" or "Medinan").
  final String type;

  /// Chronological order of revelation (1 to 114).
  final int revelationOrder;

  /// Number of Rukus (sections) in this Surah.
  final int rukusCount;

  /// Total number of Ayas (verses) in this Surah.
  final int versesCount;

  /// 0-based global verse index where this Surah begins (0 to 6235).
  final int startVerseIndex;

  const Surah({
    required this.number,
    required this.name,
    required this.transliteration,
    required this.englishName,
    required this.type,
    required this.revelationOrder,
    required this.rukusCount,
    required this.versesCount,
    required this.startVerseIndex,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Surah &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          name == other.name &&
          versesCount == other.versesCount &&
          startVerseIndex == other.startVerseIndex;

  @override
  int get hashCode =>
      number.hashCode ^
      name.hashCode ^
      versesCount.hashCode ^
      startVerseIndex.hashCode;

  @override
  String toString() =>
      'Surah($number: $name / $transliteration, $versesCount verses)';
}
