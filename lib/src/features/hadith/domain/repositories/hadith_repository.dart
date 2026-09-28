import '../models/hadith_item.dart';
import '../models/hadith_metadata.dart';

/// Contract for offline Hadith repository.
abstract class HadithRepository {
  /// All verified authentic Hadith records in stable workbook order.
  List<HadithItem> get allHadiths;

  /// Provenance and version metadata.
  HadithMetadata get metadata;

  /// Total number of records (expected 3,213).
  int get count => allHadiths.length;

  /// Retrieves a Hadith by unique ID. Returns null if not found.
  HadithItem? getById(int id);

  /// Performs offline, diacritic-insensitive search across titles, texts, and takhrij.
  List<HadithItem> search(String query);
}
