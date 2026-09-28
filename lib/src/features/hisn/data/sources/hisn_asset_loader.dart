import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import '../hisn_repository_impl.dart';
import '../../domain/repositories/hisn_repository.dart';

/// Flutter asset bundle loader adapter for the Hisn al-Muslim repository.
class HisnAssetLoader {
  HisnAssetLoader._();

  static const String hisnJsonAssetPath =
      'assets/content/hisn/hisn-muslim.json';

  /// Loads bundled Hisn al-Muslim JSON asset using the given [AssetBundle] (defaults to [rootBundle]).
  static Future<HisnRepository> loadBundledRepository({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;
    final byteData = await assetBundle.load(hisnJsonAssetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    return HisnRepositoryImpl.fromBytes(bytes);
  }
}
