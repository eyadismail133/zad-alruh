import 'dart:convert';
import 'package:xml/xml.dart';
import '../../domain/models/juz.dart';
import '../../domain/models/quran_page.dart';
import '../../domain/models/surah.dart';
import '../../domain/models/verse.dart';
import '../../domain/utils/arabic_normalizer.dart';
import '../sources/kfqc_mushaf_catalog.dart';

/// Exception thrown when Quran source content fails integrity or structural validation.
class QuranValidationException implements Exception {
  final String message;
  final dynamic cause;

  const QuranValidationException(this.message, [this.cause]);

  @override
  String toString() =>
      'QuranValidationException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}

/// Container for completely parsed and verified Quran content.
class QuranParsedData {
  final List<Surah> surahs;
  final List<Juz> juzs;
  final List<QuranPage> pages;
  final List<Verse> verses;

  const QuranParsedData({
    required this.surahs,
    required this.juzs,
    required this.pages,
    required this.verses,
  });
}

class _RawVerse {
  final int surahNumber;
  final int verseNumber;
  final String text;

  const _RawVerse({
    required this.surahNumber,
    required this.verseNumber,
    required this.text,
  });
}

/// Pure Dart parser for Tanzil Uthmani text and XML metadata.
///
/// Can be executed in any Dart environment (Flutter runtime, CLI, tests)
/// without importing Flutter or platform-specific packages.
class QuranParser {
  QuranParser._();

  static const int expectedChaptersCount = 114;
  static const int expectedVersesCount = 6236;
  static const int expectedPagesCount = 604;
  static const int expectedJuzCount = 30;

  /// Compares two verse positions (surah, aya).
  static int compareVerseRef(int s1, int a1, int s2, int a2) {
    if (s1 != s2) return s1.compareTo(s2);
    return a1.compareTo(a2);
  }

  /// Parses text content and XML metadata into strongly-typed domain models.
  ///
  /// Enforces:
  /// - Exact 114 chapters
  /// - Exact 6,236 sequential verses
  /// - Contiguous 604 Medina Mushaf pages
  /// - Contiguous 30 Juz
  /// - Ascending and valid verse start boundaries
  /// - Absence of duplicates or gaps
  /// - Preserves verbatim text strings
  static QuranParsedData parse({
    required String textContent,
    required String xmlMetadataContent,
    String? kfqcPageBoundsJson,
  }) {
    if (textContent.trim().isEmpty) {
      throw const QuranValidationException('Quran text content is empty');
    }
    if (xmlMetadataContent.trim().isEmpty) {
      throw const QuranValidationException(
        'Quran XML metadata content is empty',
      );
    }

    // 1. Parse XML Metadata
    final XmlDocument xmlDoc;
    try {
      xmlDoc = XmlDocument.parse(xmlMetadataContent);
    } catch (e) {
      throw QuranValidationException(
        'Failed to parse Quran XML metadata: $e',
        e,
      );
    }

    final root = xmlDoc.rootElement;
    if (root.name.local != 'quran') {
      throw QuranValidationException(
        'Expected root element <quran>, found <${root.name.local}>',
      );
    }

    final metadataVersion = root.getAttribute('version');
    if (metadataVersion != '1.0') {
      throw QuranValidationException(
        'Expected metadata version 1.0, found "$metadataVersion"',
      );
    }

    // Parse Chapters (Suras) from XML
    final surasElement = root.findElements('suras').firstOrNull;
    if (surasElement == null) {
      throw const QuranValidationException(
        'Missing <suras> element in metadata',
      );
    }

    final suraElements = surasElement
        .findElements('sura')
        .toList(growable: false);
    if (suraElements.length != expectedChaptersCount) {
      throw QuranValidationException(
        'Expected $expectedChaptersCount chapters in metadata, found ${suraElements.length}',
      );
    }

    final surahs = <Surah>[];
    int cumulativePrecedingVerses = 0;
    final seenRevelationOrders = <int>{};

    for (int i = 0; i < suraElements.length; i++) {
      final el = suraElements[i];
      final indexStr = el.getAttribute('index');
      final index = indexStr != null ? int.tryParse(indexStr) : null;
      final expectedIndex = i + 1;
      if (index == null || index != expectedIndex) {
        throw QuranValidationException(
          'Expected sura index $expectedIndex, found "$indexStr"',
        );
      }

      final ayasStr = el.getAttribute('ayas');
      final ayas = ayasStr != null ? int.tryParse(ayasStr) : null;
      if (ayas == null || ayas <= 0) {
        throw QuranValidationException(
          'Invalid or missing ayas count for surah $expectedIndex',
        );
      }

      final startStr = el.getAttribute('start');
      final start = startStr != null ? int.tryParse(startStr) : null;
      if (start == null || start != cumulativePrecedingVerses) {
        throw QuranValidationException(
          'Surah $expectedIndex start index mismatch: expected cumulative $cumulativePrecedingVerses, found "$startStr"',
        );
      }

      final name = el.getAttribute('name');
      final tname = el.getAttribute('tname');
      final ename = el.getAttribute('ename');
      final type = el.getAttribute('type');
      final orderStr = el.getAttribute('order');
      final order = orderStr != null ? int.tryParse(orderStr) : null;
      final rukusStr = el.getAttribute('rukus');
      final rukus = rukusStr != null ? int.tryParse(rukusStr) : null;

      if (name == null ||
          name.isEmpty ||
          tname == null ||
          tname.isEmpty ||
          ename == null ||
          ename.isEmpty ||
          type == null ||
          type.isEmpty ||
          order == null ||
          rukus == null) {
        throw QuranValidationException(
          'Missing required attribute in surah $expectedIndex metadata',
        );
      }

      if (order < 1 ||
          order > expectedChaptersCount ||
          !seenRevelationOrders.add(order)) {
        throw QuranValidationException(
          'Surah $expectedIndex has invalid or duplicate revelation order: "$orderStr"',
        );
      }

      if (rukus <= 0) {
        throw QuranValidationException(
          'Surah $expectedIndex ruku count must be positive, found "$rukusStr"',
        );
      }

      surahs.add(
        Surah(
          number: index,
          name: name,
          transliteration: tname,
          englishName: ename,
          type: type,
          revelationOrder: order,
          rukusCount: rukus,
          versesCount: ayas,
          startVerseIndex: start,
        ),
      );

      cumulativePrecedingVerses += ayas;
    }

    if (cumulativePrecedingVerses != expectedVersesCount) {
      throw QuranValidationException(
        'Total cumulative verses in metadata ($cumulativePrecedingVerses) does not match expected $expectedVersesCount',
      );
    }

    // Parse Juzs from XML
    final juzsElement = root.findElements('juzs').firstOrNull;
    if (juzsElement == null) {
      throw const QuranValidationException(
        'Missing <juzs> element in metadata',
      );
    }

    final juzElements = juzsElement.findElements('juz').toList(growable: false);
    if (juzElements.length != expectedJuzCount) {
      throw QuranValidationException(
        'Expected $expectedJuzCount juz in metadata, found ${juzElements.length}',
      );
    }

    final juzs = <Juz>[];
    for (int i = 0; i < juzElements.length; i++) {
      final el = juzElements[i];
      final indexStr = el.getAttribute('index');
      final index = indexStr != null ? int.tryParse(indexStr) : null;
      final expectedIndex = i + 1;
      if (index == null || index != expectedIndex) {
        throw QuranValidationException(
          'Expected juz index $expectedIndex, found "$indexStr"',
        );
      }

      final suraStr = el.getAttribute('sura');
      final sura = suraStr != null ? int.tryParse(suraStr) : null;
      final ayaStr = el.getAttribute('aya');
      final aya = ayaStr != null ? int.tryParse(ayaStr) : null;
      if (sura == null ||
          sura < 1 ||
          sura > expectedChaptersCount ||
          aya == null ||
          aya < 1) {
        throw QuranValidationException(
          'Invalid boundary for juz $expectedIndex: sura=$suraStr, aya=$ayaStr',
        );
      }

      if (expectedIndex == 1 && (sura != 1 || aya != 1)) {
        throw QuranValidationException(
          'First juz must start at 1:1, found $sura:$aya',
        );
      }

      if (i > 0) {
        final prev = juzs[i - 1];
        if (compareVerseRef(
              prev.startSurahNumber,
              prev.startVerseNumber,
              sura,
              aya,
            ) >=
            0) {
          throw QuranValidationException(
            'Juz $expectedIndex boundary ($sura:$aya) is not strictly after previous juz (${prev.startSurahNumber}:${prev.startVerseNumber})',
          );
        }
      }

      juzs.add(
        Juz(number: index, startSurahNumber: sura, startVerseNumber: aya),
      );
    }

    // Parse Pages from XML
    final pagesElement = root.findElements('pages').firstOrNull;
    if (pagesElement == null) {
      throw const QuranValidationException(
        'Missing <pages> element in metadata',
      );
    }

    final pageElements = pagesElement
        .findElements('page')
        .toList(growable: false);
    if (pageElements.length != expectedPagesCount) {
      throw QuranValidationException(
        'Expected $expectedPagesCount pages in metadata, found ${pageElements.length}',
      );
    }

    final xmlPages = <QuranPage>[];
    for (int i = 0; i < pageElements.length; i++) {
      final el = pageElements[i];
      final indexStr = el.getAttribute('index');
      final index = indexStr != null ? int.tryParse(indexStr) : null;
      final expectedIndex = i + 1;
      if (index == null || index != expectedIndex) {
        throw QuranValidationException(
          'Expected page index $expectedIndex, found "$indexStr"',
        );
      }

      final suraStr = el.getAttribute('sura');
      final sura = suraStr != null ? int.tryParse(suraStr) : null;
      final ayaStr = el.getAttribute('aya');
      final aya = ayaStr != null ? int.tryParse(ayaStr) : null;
      if (sura == null ||
          sura < 1 ||
          sura > expectedChaptersCount ||
          aya == null ||
          aya < 1) {
        throw QuranValidationException(
          'Invalid boundary for page $expectedIndex: sura=$suraStr, aya=$ayaStr',
        );
      }

      if (expectedIndex == 1 && (sura != 1 || aya != 1)) {
        throw QuranValidationException(
          'First page must start at 1:1, found $sura:$aya',
        );
      }

      if (i > 0) {
        final prev = xmlPages[i - 1];
        if (compareVerseRef(
              prev.startSurahNumber,
              prev.startVerseNumber,
              sura,
              aya,
            ) >=
            0) {
          throw QuranValidationException(
            'Page $expectedIndex boundary ($sura:$aya) is not strictly after previous page (${prev.startSurahNumber}:${prev.startVerseNumber})',
          );
        }
      }

      xmlPages.add(
        QuranPage(
          pageNumber: index,
          startSurahNumber: sura,
          startVerseNumber: aya,
        ),
      );
    }

    // Canonical KFQC Hafs Medina Mushaf pages for runtime mapping
    final List<QuranPage> pages;
    if (kfqcPageBoundsJson != null) {
      pages = parseKfqcPageBounds(kfqcPageBoundsJson);
    } else {
      pages = KfqcMushafCatalog.pages
          .map(
            (e) => QuranPage(
              pageNumber: e.page,
              startSurahNumber: e.startSurah,
              startVerseNumber: e.startAyah,
            ),
          )
          .toList(growable: false);
    }

    // 2. Parse Uthmani Text
    final lines = textContent.split(RegExp(r'\r?\n'));
    final rawVerses = <_RawVerse>[];
    final surahVerseCounts = <int, int>{};

    int currentSurah = 1;
    int expectedVerseInSurah = 1;

    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      var rawLine = lines[lineIndex];
      // Strip only record line delimiters (carriage return)
      if (rawLine.endsWith('\r')) {
        rawLine = rawLine.substring(0, rawLine.length - 1);
      }
      // Skip empty lines and trailing comment / copyright block
      if (rawLine.isEmpty || rawLine.startsWith('#')) {
        continue;
      }

      final parts = rawLine.split('|');
      if (parts.length != 3) {
        throw QuranValidationException(
          'Malformed verse line at index $lineIndex: "$rawLine". Expected format "surah|verse|text"',
        );
      }

      final sNum = int.tryParse(parts[0]);
      final vNum = int.tryParse(parts[1]);
      final text = parts[2]; // Preserved verbatim, no trimRight!

      if (sNum == null || vNum == null || text.isEmpty) {
        throw QuranValidationException(
          'Invalid verse fields at line $lineIndex: surah=$sNum, verse=$vNum',
        );
      }

      if (sNum < 1 || sNum > expectedChaptersCount) {
        throw QuranValidationException(
          'Surah number $sNum out of valid range (1..$expectedChaptersCount)',
        );
      }

      if (sNum == currentSurah) {
        if (vNum != expectedVerseInSurah) {
          throw QuranValidationException(
            'Non-sequential verse in surah $currentSurah: expected $expectedVerseInSurah, got $vNum',
          );
        }
        expectedVerseInSurah++;
      } else if (sNum == currentSurah + 1) {
        // Transition to next surah
        currentSurah = sNum;
        if (vNum != 1) {
          throw QuranValidationException(
            'First verse in surah $currentSurah must be 1, got $vNum',
          );
        }
        expectedVerseInSurah = 2;
      } else {
        throw QuranValidationException(
          'Unexpected jump in surah sequence: from $currentSurah to $sNum',
        );
      }

      surahVerseCounts[sNum] = (surahVerseCounts[sNum] ?? 0) + 1;

      rawVerses.add(
        _RawVerse(surahNumber: sNum, verseNumber: vNum, text: text),
      );
    }

    if (rawVerses.length != expectedVersesCount) {
      throw QuranValidationException(
        'Expected $expectedVersesCount verses in corpus, parsed ${rawVerses.length}',
      );
    }

    if (surahVerseCounts.length != expectedChaptersCount) {
      throw QuranValidationException(
        'Expected $expectedChaptersCount chapters with verses, found ${surahVerseCounts.length}',
      );
    }

    // Cross-validate sura verse counts with metadata
    for (final s in surahs) {
      final parsedCount = surahVerseCounts[s.number] ?? 0;
      if (parsedCount != s.versesCount) {
        throw QuranValidationException(
          'Verse count mismatch for surah ${s.number} (${s.name}): '
          'metadata expects ${s.versesCount}, text contains $parsedCount',
        );
      }
    }

    // Verify every page boundary resolves to an actual verse in the corpus
    final verseKeySet = <String>{
      for (final v in rawVerses) '${v.surahNumber}:${v.verseNumber}',
    };

    // Verify XML page boundaries resolve to actual verses in the corpus
    for (final p in xmlPages) {
      final key = '${p.startSurahNumber}:${p.startVerseNumber}';
      if (!verseKeySet.contains(key)) {
        throw QuranValidationException(
          'Page ${p.pageNumber} start boundary ($key) does not resolve to an actual verse in the corpus',
        );
      }
    }

    // Verify every juz boundary resolves to an actual verse in the corpus
    for (final j in juzs) {
      final key = '${j.startSurahNumber}:${j.startVerseNumber}';
      if (!verseKeySet.contains(key)) {
        throw QuranValidationException(
          'Juz ${j.number} start boundary ($key) does not resolve to an actual verse in the corpus',
        );
      }
    }

    // Verify first and last verse references
    final firstVerse = rawVerses.first;
    if (firstVerse.surahNumber != 1 || firstVerse.verseNumber != 1) {
      throw QuranValidationException(
        'First verse must be 1:1, got ${firstVerse.surahNumber}:${firstVerse.verseNumber}',
      );
    }

    final lastVerse = rawVerses.last;
    if (lastVerse.surahNumber != expectedChaptersCount ||
        lastVerse.verseNumber != surahs.last.versesCount) {
      throw QuranValidationException(
        'Last verse must be $expectedChaptersCount:${surahs.last.versesCount}, '
        'got ${lastVerse.surahNumber}:${lastVerse.verseNumber}',
      );
    }

    // Verify canonical KFQC page boundaries resolve to actual verses in the corpus
    for (final p in pages) {
      final key = '${p.startSurahNumber}:${p.startVerseNumber}';
      if (!verseKeySet.contains(key)) {
        throw QuranValidationException(
          'KFQC Page ${p.pageNumber} start boundary ($key) does not resolve to an actual verse in the corpus',
        );
      }
    }

    // Verify first page starts at 1:1
    if (pages[0].startSurahNumber != 1 || pages[0].startVerseNumber != 1) {
      throw QuranValidationException(
        'First page must start at 1:1, got ${pages[0].startSurahNumber}:${pages[0].startVerseNumber}',
      );
    }

    // Verify Page 121 starts at Chapter 5 Aya 78 in KFQC (differs from Tanzil 5:77)
    if (pages[120].startSurahNumber != 5 || pages[120].startVerseNumber != 78) {
      throw QuranValidationException(
        'Page 121 must start at Chapter 5 Aya 78 in KFQC, got '
        '${pages[120].startSurahNumber}:${pages[120].startVerseNumber}',
      );
    }

    // Check Chapter 9 / Page 187 specifically
    if (pages[186].startSurahNumber != 9 || pages[186].startVerseNumber != 1) {
      throw QuranValidationException(
        'Page 187 must start at Chapter 9 Aya 1, got '
        '${pages[186].startSurahNumber}:${pages[186].startVerseNumber}',
      );
    }

    // Verify Page 600 starts at Chapter 100 Aya 6 in KFQC (differs from Tanzil 100:10)
    if (pages[599].startSurahNumber != 100 || pages[599].startVerseNumber != 6) {
      throw QuranValidationException(
        'Page 600 must start at Chapter 100 Aya 6 in KFQC, got '
        '${pages[599].startSurahNumber}:${pages[599].startVerseNumber}',
      );
    }

    // Check Page 604 specifically
    if (pages[603].startSurahNumber != 112 ||
        pages[603].startVerseNumber != 1) {
      throw QuranValidationException(
        'Page 604 must start at Chapter 112 Aya 1, got '
        '${pages[603].startSurahNumber}:${pages[603].startVerseNumber}',
      );
    }

    // Check Juz 30 specifically
    if (juzs[29].startSurahNumber != 78 || juzs[29].startVerseNumber != 1) {
      throw QuranValidationException(
        'Juz 30 must start at Chapter 78 Aya 1, got '
        '${juzs[29].startSurahNumber}:${juzs[29].startVerseNumber}',
      );
    }

    // 3. Map Verses to Pages and Juzs
    final verses = <Verse>[];
    final versesPerPage = <int, int>{};
    final versesPerJuz = <int, int>{};
    int pageIdx = 0;
    int juzIdx = 0;

    for (final raw in rawVerses) {
      // Advance page index if this verse reaches or passes next page start
      while (pageIdx + 1 < pages.length &&
          compareVerseRef(
                raw.surahNumber,
                raw.verseNumber,
                pages[pageIdx + 1].startSurahNumber,
                pages[pageIdx + 1].startVerseNumber,
              ) >=
              0) {
        pageIdx++;
      }

      // Advance juz index if this verse reaches or passes next juz start
      while (juzIdx + 1 < juzs.length &&
          compareVerseRef(
                raw.surahNumber,
                raw.verseNumber,
                juzs[juzIdx + 1].startSurahNumber,
                juzs[juzIdx + 1].startVerseNumber,
              ) >=
              0) {
        juzIdx++;
      }

      final pageNumber = pageIdx + 1;
      final juzNumber = juzIdx + 1;

      versesPerPage[pageNumber] = (versesPerPage[pageNumber] ?? 0) + 1;
      versesPerJuz[juzNumber] = (versesPerJuz[juzNumber] ?? 0) + 1;

      verses.add(
        Verse(
          surahNumber: raw.surahNumber,
          verseNumber: raw.verseNumber,
          text: raw.text,
          normalizedText: ArabicNormalizer.normalize(raw.text),
          pageNumber: pageNumber,
          juzNumber: juzNumber,
        ),
      );
    }

    // Enforce every page and juz is a non-empty interval
    for (int p = 1; p <= expectedPagesCount; p++) {
      if ((versesPerPage[p] ?? 0) == 0) {
        throw QuranValidationException(
          'Page $p has an empty verse interval (0 verses assigned)',
        );
      }
    }

    for (int j = 1; j <= expectedJuzCount; j++) {
      if ((versesPerJuz[j] ?? 0) == 0) {
        throw QuranValidationException(
          'Juz $j has an empty verse interval (0 verses assigned)',
        );
      }
    }

    return QuranParsedData(
      surahs: List.unmodifiable(surahs),
      juzs: List.unmodifiable(juzs),
      pages: List.unmodifiable(pages),
      verses: List.unmodifiable(verses),
    );
  }

  /// Parses and validates a KFQC page-bounds JSON string into a strongly-typed list of [QuranPage]s.
  static List<QuranPage> parseKfqcPageBounds(String jsonStr) {
    if (jsonStr.trim().isEmpty) {
      throw const QuranValidationException('KFQC page bounds JSON is empty');
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonStr);
    } catch (e) {
      throw QuranValidationException('Failed to parse KFQC page bounds JSON: $e', e);
    }
    if (decoded is! Map || decoded['pages'] is! List) {
      throw const QuranValidationException('KFQC page bounds JSON missing "pages" array');
    }
    final rawList = decoded['pages'] as List;
    if (rawList.length != expectedPagesCount) {
      throw QuranValidationException(
        'Expected $expectedPagesCount pages in KFQC bounds, found ${rawList.length}',
      );
    }
    final result = <QuranPage>[];
    int totalCoveredVerses = 0;
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is! Map) {
        throw QuranValidationException('Malformed KFQC page entry at index $i');
      }
      final pageNum = item['page'] as int?;
      final start = item['start'] as Map?;
      final end = item['end'] as Map?;
      final startSurah = start?['surah'] as int?;
      final startAyah = start?['ayah'] as int?;
      final endSurah = end?['surah'] as int?;
      final endAyah = end?['ayah'] as int?;
      final count = item['verse_count'] as int?;
      if (pageNum == null ||
          startSurah == null ||
          startAyah == null ||
          endSurah == null ||
          endAyah == null ||
          count == null ||
          count <= 0) {
        throw QuranValidationException('Incomplete KFQC page bounds at index $i');
      }
      final canonical = KfqcMushafCatalog.pages[i];
      if (pageNum != canonical.page ||
          startSurah != canonical.startSurah ||
          startAyah != canonical.startAyah ||
          endSurah != canonical.endSurah ||
          endAyah != canonical.endAyah ||
          count != canonical.verseCount) {
        throw QuranValidationException(
          'KFQC page $pageNum boundary mismatch against canonical catalog: '
          'got ($startSurah:$startAyah..$endSurah:$endAyah, count=$count), '
          'expected (${canonical.startSurah}:${canonical.startAyah}..${canonical.endSurah}:${canonical.endAyah}, count=${canonical.verseCount})',
        );
      }
      totalCoveredVerses += count;
      result.add(
        QuranPage(
          pageNumber: pageNum,
          startSurahNumber: startSurah,
          startVerseNumber: startAyah,
        ),
      );
    }
    if (totalCoveredVerses != KfqcMushafCatalog.expectedTotalVerses) {
      throw QuranValidationException(
        'KFQC bounds total verses ($totalCoveredVerses) != ${KfqcMushafCatalog.expectedTotalVerses}',
      );
    }
    return List.unmodifiable(result);
  }
}
