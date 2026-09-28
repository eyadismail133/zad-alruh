import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/sources/hadith_asset_loader.dart';
import '../../domain/repositories/hadith_repository.dart';

/// Riverpod FutureProvider delivering the offline Hadith repository.
final hadithRepositoryProvider = FutureProvider<HadithRepository>((ref) async {
  return HadithAssetLoader.loadBundledRepository();
});
