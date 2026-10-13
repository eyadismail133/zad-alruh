import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../../quran/domain/utils/arabic_normalizer.dart';
import '../domain/models/hadith_item.dart';
import '../domain/models/hadith_metadata.dart';
import '../domain/repositories/hadith_repository.dart';

/// Exception thrown when Hadith source bytes or structure fail validation.
class HadithValidationException implements Exception {
  final String message;
  const HadithValidationException(this.message);

  @override
  String toString() => 'HadithValidationException: $message';
}

/// Offline implementation of [HadithRepository] with fast in-memory indexing.
class HadithRepositoryImpl implements HadithRepository {
  /// Canonical SHA-256 hash of the bundled compact JSON asset.
  static const String canonicalJsonSha256 =
      '94a69dbdb44144d2dad2ba0a3fa1ee73c7f7b456c46d945ea15f4332a2eeeda7';

  /// Expected count of authentic records.
  static const int expectedCount = 3213;

  @override
  final List<HadithItem> allHadiths;

  @override
  int get count => allHadiths.length;

  @override
  final HadithMetadata metadata;

  final Map<int, HadithItem> _byId;
  final List<String> _normalizedSearchKeys;

  factory HadithRepositoryImpl({
    required HadithMetadata metadata,
    required List<HadithItem> allHadiths,
  }) {
    final ordered = allHadiths.toList()..sort((a, b) => a.id.compareTo(b.id));
    return HadithRepositoryImpl._(
      metadata: metadata,
      allHadiths: List.unmodifiable(ordered),
    );
  }

  HadithRepositoryImpl._({required this.metadata, required this.allHadiths})
    : _byId = {for (final item in allHadiths) item.id: item},
      _normalizedSearchKeys = [
        for (final item in allHadiths)
          '${item.id} ${ArabicNormalizer.normalize('${item.title} ${item.hadithText} ${item.takhrij}')}',
      ];

  /// Creates a repository from JSON asset bytes.
  ///
  /// Verifies canonical SHA-256 if [verifySha] is true, then decodes and validates structure.
  factory HadithRepositoryImpl.fromBytes(
    Uint8List jsonBytes, {
    bool verifySha = true,
  }) {
    if (verifySha) {
      final actualSha = sha256.convert(jsonBytes).toString().toLowerCase();
      if (actualSha != canonicalJsonSha256) {
        throw HadithValidationException(
          'Hadith JSON asset SHA-256 mismatch! Expected $canonicalJsonSha256, got $actualSha',
        );
      }
    }

    final String jsonString = utf8.decode(jsonBytes);
    final dynamic decoded = jsonDecode(jsonString);

    if (decoded is! Map<String, dynamic>) {
      throw const HadithValidationException(
        'Hadith JSON root must be an object',
      );
    }

    final metaRaw = decoded['metadata'];
    if (metaRaw is! Map<String, dynamic>) {
      throw const HadithValidationException(
        'Missing or invalid "metadata" section',
      );
    }
    final meta = HadithMetadata.fromJson(metaRaw);

    final itemsRaw = decoded['items'];
    if (itemsRaw is! List) {
      throw const HadithValidationException('Missing or invalid "items" array');
    }

    final List<HadithItem> items = [];
    final Set<int> seenIds = {};

    for (int i = 0; i < itemsRaw.length; i++) {
      final itemRaw = itemsRaw[i];
      if (itemRaw is! Map<String, dynamic>) {
        throw HadithValidationException(
          'Item at index $i is not a JSON object',
        );
      }

      final item = HadithItem.fromJson(itemRaw);

      if (seenIds.contains(item.id)) {
        throw HadithValidationException('Duplicate Hadith ID: ${item.id}');
      }
      seenIds.add(item.id);

      if (item.title.isEmpty) {
        throw HadithValidationException('Hadith ID ${item.id} has empty title');
      }
      if (item.hadithText.isEmpty) {
        throw HadithValidationException(
          'Hadith ID ${item.id} has empty hadith_text',
        );
      }
      if (item.grade != 'صحيح') {
        throw HadithValidationException(
          'Hadith ID ${item.id} has unverified grade: "${item.grade}". Expected "صحيح"',
        );
      }
      if (item.takhrij.isEmpty) {
        throw HadithValidationException(
          'Hadith ID ${item.id} has empty takhrij',
        );
      }
      if (item.link.isEmpty) {
        throw HadithValidationException('Hadith ID ${item.id} has empty link');
      }

      items.add(item);
    }

    if (items.length != expectedCount) {
      throw HadithValidationException(
        'Expected $expectedCount Hadith items, got ${items.length}',
      );
    }

    return HadithRepositoryImpl(metadata: meta, allHadiths: items);
  }

  @override
  HadithItem? getById(int id) => _byId[id];

  @override
  List<HadithItem> search(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return allHadiths;
    }

    // Direct ID lookup if user typed numbers (ASCII, Arabic-Indic, or Persian digits)
    final intQuery =
        ArabicNormalizer.parseArabicInt(trimmed) ?? int.tryParse(trimmed);
    if (intQuery != null && _byId.containsKey(intQuery)) {
      final direct = _byId[intQuery]!;
      final result = <HadithItem>[direct];
      // Also include any other hadiths whose text contains this number
      final normalizedQ = trimmed;
      for (int i = 0; i < allHadiths.length; i++) {
        if (allHadiths[i].id != intQuery &&
            _normalizedSearchKeys[i].contains(normalizedQ)) {
          result.add(allHadiths[i]);
        }
      }
      return result..sort((a, b) => a.id.compareTo(b.id));
    }

    final normalizedQ = ArabicNormalizer.normalize(trimmed);
    if (normalizedQ.isEmpty) {
      return allHadiths;
    }

    final matches = <HadithItem>[];
    for (int i = 0; i < allHadiths.length; i++) {
      if (_normalizedSearchKeys[i].contains(normalizedQ)) {
        matches.add(allHadiths[i]);
      }
    }

    return matches;
  }
}
