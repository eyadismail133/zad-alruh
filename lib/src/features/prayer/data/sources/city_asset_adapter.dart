import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle, AssetBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/city_repository.dart';
import '../repositories/in_memory_city_repository.dart';
import 'geonames_parser.dart';
import 'geonames_source_verifier.dart';

/// Top-level parser function executed off the UI isolate via Flutter `compute`.
InMemoryCityRepository _parseVerifiedBytesToRepository(Uint8List bytes) {
  final content = GeoNamesSourceVerifier.verifyBytes(bytes);
  final cities = GeoNamesParser.parse(content);

  if (cities.length != GeoNamesConstants.expectedRecordCount) {
    throw GeoNamesValidationException(
      'GeoNames record count mismatch! Expected ${GeoNamesConstants.expectedRecordCount}, parsed ${cities.length}',
    );
  }

  return InMemoryCityRepository(cities);
}

/// Flutter asset bundle loader adapter for the offline GeoNames world cities dataset.
///
/// Strictly enforces canonical SHA-256 verification and record count validation
/// BEFORE UTF-8 decoding or row parsing. Parses off the UI isolate via [compute].
class CityAssetAdapter {
  CityAssetAdapter._();

  static const String citiesAssetPath = 'assets/content/cities/cities15000.txt';

  /// Loads the bundled cities repository from an [AssetBundle] (defaults to [rootBundle]),
  /// executing SHA verification and parsing off the UI isolate via [compute].
  static Future<CityRepository> loadFromBundle({AssetBundle? bundle}) async {
    final effectiveBundle = bundle ?? rootBundle;
    final byteData = await effectiveBundle.load(citiesAssetPath);
    final bytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );

    return compute(_parseVerifiedBytesToRepository, bytes);
  }

  /// Verifies canonical SHA-256 hash and parses raw asset bytes into a [CityRepository].
  /// Suitable for pure Dart and headless testing.
  static CityRepository fromBytes(Uint8List bytes) {
    return _parseVerifiedBytesToRepository(bytes);
  }
}

/// Riverpod provider delivering the verified offline GeoNames city repository.
final cityRepositoryProvider = FutureProvider<CityRepository>((ref) async {
  return CityAssetAdapter.loadFromBundle();
});
