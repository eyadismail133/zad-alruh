/// Immutable representation of a Quran Juz (Part).
class Juz {
  /// 1-based Juz index (1 to 30).
  final int number;

  /// Surah number where this Juz begins (1 to 114).
  final int startSurahNumber;

  /// Verse number within the starting Surah where this Juz begins.
  final int startVerseNumber;

  const Juz({
    required this.number,
    required this.startSurahNumber,
    required this.startVerseNumber,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Juz &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          startSurahNumber == other.startSurahNumber &&
          startVerseNumber == other.startVerseNumber;

  @override
  int get hashCode =>
      number.hashCode ^ startSurahNumber.hashCode ^ startVerseNumber.hashCode;

  @override
  String toString() =>
      'Juz($number: starts at $startSurahNumber:$startVerseNumber)';
}
