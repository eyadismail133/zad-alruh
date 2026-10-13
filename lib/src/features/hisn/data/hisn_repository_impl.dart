import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../quran/domain/utils/arabic_normalizer.dart';
import '../domain/models/hisn_chapter.dart';
import '../domain/models/hisn_item.dart';
import '../domain/models/hisn_metadata.dart';
import '../domain/repositories/hisn_repository.dart';

/// Exception thrown when Hisn al-Muslim asset bytes or structure fail validation.
class HisnValidationException implements Exception {
  final String message;
  const HisnValidationException(this.message);

  @override
  String toString() => 'HisnValidationException: $message';
}

/// Offline implementation of [HisnRepository] with fast in-memory indexing.
class HisnRepositoryImpl implements HisnRepository {
  /// Canonical SHA-256 hash of the bundled compact JSON asset.
  static const String canonicalJsonSha256 =
      '8655afe53935baf74fed92164fedb9f0ba7e989c23818f82bd231ebd6d7a773d';

  /// Expected count of Dhikr / Dua items in Hisn al-Muslim.
  static const int expectedItemsCount = 267;

  /// Expected count of chapters.
  static const int expectedChaptersCount = 132;

  /// Expected count of resolved footnotes.
  static const int expectedFootnotesCount = 300;

  @override
  final List<HisnItem> allItems;

  @override
  List<HisnItem> get supplementalItems => const [];

  @override
  final List<HisnChapter> allChapters;

  @override
  int get count => allItems.length;

  @override
  int get chaptersCount => allChapters.length;

  @override
  final HisnMetadata metadata;

  final Map<int, HisnItem> _byId;
  final Map<int, HisnChapter> _chapterByNumber;
  final Map<int, List<HisnItem>> _byChapter;
  final List<String> _normalizedSearchKeys;

  HisnRepositoryImpl({
    required this.metadata,
    required this.allChapters,
    required this.allItems,
  })  : _byId = {for (final item in allItems) item.id: item},
        _chapterByNumber = {for (final chap in allChapters) chap.number: chap},
        _byChapter = _buildChapterMap(allItems),
        _normalizedSearchKeys = [
          for (final item in allItems)
            '${item.id} ${ArabicNormalizer.normalize('${item.chapterTitle} ${item.text} ${item.footnotes.map((f) => f.text).join(' ')}')}'
        ];

  static Map<int, List<HisnItem>> _buildChapterMap(List<HisnItem> items) {
    final map = <int, List<HisnItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.chapterNumber, () => []).add(item);
    }
    return map;
  }

  /// Creates a repository from JSON asset bytes.
  ///
  /// Verifies canonical SHA-256 if [verifySha] is true, then decodes and validates structure.
  factory HisnRepositoryImpl.fromBytes(
    Uint8List jsonBytes, {
    bool verifySha = true,
  }) {
    if (verifySha) {
      final actualSha = sha256.convert(jsonBytes).toString().toLowerCase();
      if (actualSha != canonicalJsonSha256) {
        throw HisnValidationException(
          'Hisn al-Muslim JSON asset SHA-256 mismatch! Expected $canonicalJsonSha256, got $actualSha',
        );
      }
    }

    final String jsonString = utf8.decode(jsonBytes);
    final dynamic decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw const HisnValidationException('Hisn al-Muslim JSON root must be an object');
    }

    final metaRaw = decoded['metadata'];
    if (metaRaw is! Map<String, dynamic>) {
      throw const HisnValidationException('Missing or invalid "metadata" section');
    }
    final meta = HisnMetadata.fromJson(metaRaw);

    if (meta.totalChapters != expectedChaptersCount) {
      throw HisnValidationException(
        'Metadata total_chapters mismatch: expected $expectedChaptersCount, got ${meta.totalChapters}',
      );
    }
    if (meta.totalItems != expectedItemsCount) {
      throw HisnValidationException(
        'Metadata total_items mismatch: expected $expectedItemsCount, got ${meta.totalItems}',
      );
    }
    if (meta.totalFootnotes != expectedFootnotesCount) {
      throw HisnValidationException(
        'Metadata total_footnotes mismatch: expected $expectedFootnotesCount, got ${meta.totalFootnotes}',
      );
    }

    // Parse chapters
    final chaptersRaw = decoded['chapters'];
    if (chaptersRaw is! List) {
      throw const HisnValidationException('Missing or invalid "chapters" array');
    }

    final List<HisnChapter> chapters = [];
    final Set<int> seenChapterNums = {};

    for (int i = 0; i < chaptersRaw.length; i++) {
      final chapRaw = chaptersRaw[i];
      if (chapRaw is! Map<String, dynamic>) {
        throw HisnValidationException('Chapter at index $i is not a JSON object');
      }

      final chapter = HisnChapter.fromJson(chapRaw);

      if (seenChapterNums.contains(chapter.number)) {
        throw HisnValidationException('Duplicate chapter number: ${chapter.number}');
      }
      seenChapterNums.add(chapter.number);

      if (chapter.number != i + 1) {
        throw HisnValidationException(
          'Non-sequential chapter number at index $i: expected ${i + 1}, got ${chapter.number}',
        );
      }
      if (chapter.title.isEmpty) {
        throw HisnValidationException('Chapter ${chapter.number} has empty title');
      }
      if (chapter.itemsCount != chapter.itemIds.length) {
        throw HisnValidationException(
          'Chapter ${chapter.number} items_count (${chapter.itemsCount}) does not match item_ids length (${chapter.itemIds.length})',
        );
      }

      chapters.add(chapter);
    }

    if (chapters.length != expectedChaptersCount) {
      throw HisnValidationException(
        'Expected $expectedChaptersCount chapters, got ${chapters.length}',
      );
    }

    // Parse items
    final itemsRaw = decoded['items'];
    if (itemsRaw is! List) {
      throw const HisnValidationException('Missing or invalid "items" array');
    }

    final List<HisnItem> items = [];
    final Set<int> seenItemIds = {};
    int totalFootnotesFound = 0;

    for (int i = 0; i < itemsRaw.length; i++) {
      final itemRaw = itemsRaw[i];
      if (itemRaw is! Map<String, dynamic>) {
        throw HisnValidationException('Item at index $i is not a JSON object');
      }

      final item = HisnItem.fromJson(itemRaw);

      if (seenItemIds.contains(item.id)) {
        throw HisnValidationException('Duplicate item ID: ${item.id}');
      }
      seenItemIds.add(item.id);

      if (item.id != i + 1) {
        throw HisnValidationException(
          'Non-sequential item ID at index $i: expected ${i + 1}, got ${item.id}',
        );
      }
      if (item.text.isEmpty) {
        throw HisnValidationException('Item ID ${item.id} has empty text');
      }
      if (item.chapterTitle.isEmpty) {
        throw HisnValidationException('Item ID ${item.id} has empty chapterTitle');
      }
      if (item.paragraphs.isEmpty) {
        throw HisnValidationException('Item ID ${item.id} has empty paragraphs');
      }
      if (item.footnotes.isEmpty) {
        throw HisnValidationException('Item ID ${item.id} has no footnotes/references');
      }
      totalFootnotesFound += item.footnotes.length;

      items.add(item);
    }

    if (items.length != expectedItemsCount) {
      throw HisnValidationException(
        'Expected $expectedItemsCount items, got ${items.length}',
      );
    }
    if (totalFootnotesFound != expectedFootnotesCount) {
      throw HisnValidationException(
        'Expected $expectedFootnotesCount footnotes across all items, got $totalFootnotesFound',
      );
    }

    return HisnRepositoryImpl(
      metadata: meta,
      allChapters: chapters,
      allItems: items,
    );
  }

  @override
  HisnItem? getById(int id) => _byId[id];

  @override
  HisnChapter? getChapter(int chapterNumber) => _chapterByNumber[chapterNumber];

  @override
  List<HisnItem> getItemsByChapter(int chapterNumber) =>
      _byChapter[chapterNumber] ?? const [];

  @override
  List<HisnItem> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return allItems;
    }

    // Direct ID lookup if user typed pure number (ASCII, Arabic-Indic, or Persian digits)
    final intQuery = ArabicNormalizer.parseArabicInt(trimmed) ?? int.tryParse(trimmed);
    if (intQuery != null && _byId.containsKey(intQuery)) {
      final direct = _byId[intQuery]!;
      final result = <HisnItem>[direct];
      final normalizedQ = trimmed;
      for (int i = 0; i < allItems.length; i++) {
        if (allItems[i].id != intQuery &&
            _normalizedSearchKeys[i].contains(normalizedQ)) {
          result.add(allItems[i]);
        }
      }
      return result;
    }

    final normalizedQ = ArabicNormalizer.normalize(trimmed);
    if (normalizedQ.isEmpty) {
      return allItems;
    }

    final matches = <HisnItem>[];
    for (int i = 0; i < allItems.length; i++) {
      if (_normalizedSearchKeys[i].contains(normalizedQ)) {
        matches.add(allItems[i]);
      }
    }

    return matches;
  }
}
