import '../../data/sources/quran_asset_loader.dart';

export '../../data/sources/quran_asset_loader.dart'
    show QuranAssetLoader, quranRepositoryProvider;

/// Canonical asset path constants pointing to bundled Holy Quran corpus.
const String kQuranTextAssetPath = QuranAssetLoader.textAssetPath;
const String kQuranMetadataAssetPath = QuranAssetLoader.xmlAssetPath;
