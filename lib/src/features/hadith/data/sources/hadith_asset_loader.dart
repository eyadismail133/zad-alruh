import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import '../hadith_repository_impl.dart';
import '../../domain/repositories/hadith_repository.dart';

/// Flutter asset bundle loader adapter for the Hadith repository.
class HadithAssetLoader {
  HadithAssetLoader._();

  static const String hadithJsonAssetPath =
      'assets/content/hadith/hadith-enc-sahih.json';

  /// Loads bundled Hadith JSON asset using the given [AssetBundle] (defaults to [rootBundle]).
  static Future<HadithRepository> loadBundledRepository({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final byteData = await assetBundle.load(hadithJsonAssetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return HadithRepositoryImpl.fromBytes(bytes);
  }
}
