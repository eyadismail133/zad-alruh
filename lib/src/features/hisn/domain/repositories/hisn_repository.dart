import '../models/hisn_chapter.dart';
import '../models/hisn_item.dart';
import '../models/hisn_metadata.dart';

/// Contract for offline Hisn al-Muslim (حصن المسلم) repository.
abstract class HisnRepository {
  /// All 267 Dhikr / Dua items in stable book order.
  List<HisnItem> get allItems;
  List<HisnItem> get supplementalItems;

  /// All 132 Chapters in stable book order.
  List<HisnChapter> get allChapters;

  /// Provenance and version metadata.
  HisnMetadata get metadata;

  /// Total number of items (expected 267).
  int get count => allItems.length;

  /// Total number of chapters (expected 132).
  int get chaptersCount => allChapters.length;

  /// Retrieves an item by unique 1-indexed ID (1..267). Returns null if not found.
  HisnItem? getById(int id);

  /// Retrieves a chapter by 1-indexed number (1..132). Returns null if not found.
  HisnChapter? getChapter(int chapterNumber);

  /// Retrieves all items belonging to a specific chapter.
  List<HisnItem> getItemsByChapter(int chapterNumber);

  /// Performs offline diacritic-insensitive search across chapter titles,
  /// item numbers, texts, and footnote citations.
  List<HisnItem> search(String query);
}
