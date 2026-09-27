import 'dart:typed_data';
import '../domain/models/juz.dart';
import '../domain/models/quran_page.dart';
import '../domain/models/surah.dart';
import '../domain/models/verse.dart';
import '../domain/utils/arabic_normalizer.dart';
import 'parsers/quran_parser.dart';
import 'sources/quran_source_verifier.dart';

/// Trusted offline repository for the Holy Quran.
///
/// Pure Dart implementation without Flutter or platform dependencies.
/// Provides immutable access to chapters, pages, juzs, verses, and
/// diacritic-insensitive Arabic search while guaranteeing verbatim preservation
/// of the original Uthmani text.
class QuranRepository {
  final List<Surah> _surahs;
  final List<Juz> _juzs;
  final List<QuranPage> _pages;
  final List<Verse> _verses;

  // Pre-indexed lookups for O(1) retrieval
  late final Map<int, Surah> _surahMap;
  late final Map<int, Juz> _juzMap;
  late final Map<int, QuranPage> _pageMap;
  late final Map<int, List<Verse>> _versesBySurah;
  late final Map<int, List<Verse>> _versesByPage;
  late final Map<int, List<Verse>> _versesByJuz;
  late final Map<String, Verse> _verseLookup;

  QuranRepository(QuranParsedData data)
    : _surahs = data.surahs,
      _juzs = data.juzs,
      _pages = data.pages,
      _verses = data.verses {
    _initIndices();
  }

  /// Creates a repository by verifying canonical source bytes before decoding or parsing.
  ///
  /// Throws [QuranValidationException] if either source fails SHA verification or structural parsing.
  factory QuranRepository.fromBytes({
    required Uint8List textBytes,
    required Uint8List xmlBytes,
  }) {
    final verified = QuranSourceVerifier.verifyBytes(
      textBytes: textBytes,
      xmlBytes: xmlBytes,
    );
    return QuranRepository.fromContent(
      textContent: verified.textContent,
      xmlMetadataContent: verified.xmlMetadataContent,
    );
  }

  /// Creates a repository by parsing text and XML contents with strict validation.
  ///
  /// Throws [QuranValidationException] if content is corrupt, incomplete, or invalid.
  factory QuranRepository.fromContent({
    required String textContent,
    required String xmlMetadataContent,
  }) {
    final parsed = QuranParser.parse(
      textContent: textContent,
      xmlMetadataContent: xmlMetadataContent,
    );
    return QuranRepository(parsed);
  }

  void _initIndices() {
    _surahMap = {for (final s in _surahs) s.number: s};
    _juzMap = {for (final j in _juzs) j.number: j};
    _pageMap = {for (final p in _pages) p.pageNumber: p};

    final bySurah = <int, List<Verse>>{};
    final byPage = <int, List<Verse>>{};
    final byJuz = <int, List<Verse>>{};
    final lookup = <String, Verse>{};

    for (final v in _verses) {
      bySurah.putIfAbsent(v.surahNumber, () => []).add(v);
      byPage.putIfAbsent(v.pageNumber, () => []).add(v);
      byJuz.putIfAbsent(v.juzNumber, () => []).add(v);
      lookup[v.id] = v;
    }

    _versesBySurah = {
      for (final entry in bySurah.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    _versesByPage = {
      for (final entry in byPage.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    _versesByJuz = {
      for (final entry in byJuz.entries)
        entry.key: List.unmodifiable(entry.value),
    };
    _verseLookup = lookup;
  }

  /// Returns all 114 Surahs in Quranic order.
  List<Surah> getSurahs() => _surahs;

  /// Returns a specific Surah by its 1-based number (1 to 114).
  Surah getSurah(int surahNumber) {
    final s = _surahMap[surahNumber];
    if (s == null) {
      throw RangeError.range(surahNumber, 1, 114, 'surahNumber');
    }
    return s;
  }

  /// Returns all 30 Juz in order.
  List<Juz> getJuzs() => _juzs;

  /// Returns a specific Juz by its 1-based number (1 to 30).
  Juz getJuz(int juzNumber) {
    final j = _juzMap[juzNumber];
    if (j == null) {
      throw RangeError.range(juzNumber, 1, 30, 'juzNumber');
    }
    return j;
  }

  /// Returns all 604 Medina Mushaf pages in order.
  List<QuranPage> getPages() => _pages;

  /// Returns a specific Page by its 1-based number (1 to 604).
  QuranPage getPage(int pageNumber) {
    final p = _pageMap[pageNumber];
    if (p == null) {
      throw RangeError.range(pageNumber, 1, 604, 'pageNumber');
    }
    return p;
  }

  /// Returns all 6,236 verses of the Quran.
  List<Verse> getVerses() => _verses;

  /// Returns all verses belonging to a specific Surah.
  List<Verse> getVersesForSurah(int surahNumber) {
    final list = _versesBySurah[surahNumber];
    if (list == null) {
      throw RangeError.range(surahNumber, 1, 114, 'surahNumber');
    }
    return list;
  }

  /// Returns all verses displayed on a specific Medina Mushaf page (1 to 604).
  List<Verse> getVersesForPage(int pageNumber) {
    final list = _versesByPage[pageNumber];
    if (list == null) {
      throw RangeError.range(pageNumber, 1, 604, 'pageNumber');
    }
    return list;
  }

  /// Returns all verses belonging to a specific Juz (1 to 30).
  List<Verse> getVersesForJuz(int juzNumber) {
    final list = _versesByJuz[juzNumber];
    if (list == null) {
      throw RangeError.range(juzNumber, 1, 30, 'juzNumber');
    }
    return list;
  }

  /// Returns a specific verse by Surah number and Verse number.
  Verse getVerse(int surahNumber, int verseNumber) {
    final v = _verseLookup['$surahNumber:$verseNumber'];
    if (v == null) {
      throw ArgumentError('Verse not found: $surahNumber:$verseNumber');
    }
    return v;
  }

  /// Searches verses matching the query string.
  ///
  /// The search normalizes both the query and the verses (removing diacritics,
  /// tatweel, and normalizing alef variants).
  ///
  /// The returned [Verse] instances retain their original verbatim Uthmani text
  /// without any alteration.
  List<Verse> search(String query) {
    final normalizedQuery = ArabicNormalizer.normalize(query);
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final results = <Verse>[];
    for (final v in _verses) {
      if (v.normalizedText.contains(normalizedQuery)) {
        results.add(v);
      }
    }
    return List.unmodifiable(results);
  }
}
