import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../quran_repository.dart';

/// Flutter asset bundle loader adapter for the Holy Quran repository.
///
/// Loads bundled source asset bytes from Flutter rootBundle and forwards them
/// directly to [QuranRepository.fromBytes], which enforces canonical SHA-256
/// verification BEFORE UTF-8 decoding or parsing.
class QuranAssetLoader {
  QuranAssetLoader._();

  static const String textAssetPath = 'assets/content/quran/quran-uthmani.txt';
  static const String xmlAssetPath = 'assets/content/quran/quran-data.xml';
  static const String boundsAssetPath =
      'assets/content/quran/kfqc-page-bounds.json';

  /// Loads bundled Quran source assets using the given [AssetBundle] (defaults to [rootBundle]).
  ///
  /// Throws [QuranValidationException] if either source fails SHA verification or structural parsing.
  static Future<QuranRepository> loadBundledRepository({
    AssetBundle? bundle,
  }) async {
    final assetBundle = bundle ?? rootBundle;

    final textByteData = await assetBundle.load(textAssetPath);
    final xmlByteData = await assetBundle.load(xmlAssetPath);

    final textBytes = textByteData.buffer.asUint8List(
      textByteData.offsetInBytes,
      textByteData.lengthInBytes,
    );
    final xmlBytes = xmlByteData.buffer.asUint8List(
      xmlByteData.offsetInBytes,
      xmlByteData.lengthInBytes,
    );

    final boundsByteData = await assetBundle.load(boundsAssetPath);
    final boundsBytes = boundsByteData.buffer.asUint8List(
      boundsByteData.offsetInBytes,
      boundsByteData.lengthInBytes,
    );

    return QuranRepository.fromBytes(
      textBytes: textBytes,
      xmlBytes: xmlBytes,
      boundsBytes: boundsBytes,
    );
  }
}

/// Riverpod provider delivering the verified offline Holy Quran repository.
final quranRepositoryProvider = FutureProvider<QuranRepository>((ref) async {
  return QuranAssetLoader.loadBundledRepository();
});
