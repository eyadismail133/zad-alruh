import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/sources/hisn_asset_loader.dart';
import '../../domain/models/hisn_chapter.dart';
import '../../domain/models/hisn_item.dart';
import '../../domain/repositories/hisn_repository.dart';

/// Riverpod FutureProvider delivering the offline Hisn al-Muslim repository.
final hisnRepositoryProvider = FutureProvider<HisnRepository>((ref) async {
  return HisnAssetLoader.loadBundledRepository();
});

/// Provider for all Hisn chapters.
final hisnChaptersProvider = Provider<List<HisnChapter>>((ref) {
  final repoAsync = ref.watch(hisnRepositoryProvider);
  return repoAsync.when(
    data: (repo) => repo.allChapters,
    loading: () => const [],
    error: (_, __) => const [],
  );
});

/// Provider family for items in a specific chapter.
final hisnChapterItemsProvider =
    Provider.family<List<HisnItem>, int>((ref, chapterNumber) {
  final repoAsync = ref.watch(hisnRepositoryProvider);
  return repoAsync.when(
    data: (repo) => repo.getItemsByChapter(chapterNumber),
    loading: () => const [],
    error: (_, __) => const [],
  );
});
