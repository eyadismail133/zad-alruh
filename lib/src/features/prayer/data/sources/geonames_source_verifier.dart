import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Single source of truth for canonical GeoNames cities15000 source SHA-256 hashes.
class GeoNamesConstants {
  GeoNamesConstants._();

  /// Canonical SHA-256 for assets/content/cities/cities15000.txt
  static const String canonicalCitiesSha256 =
      'c8e0a782e44ba580a2c0f0e3c9538051351629b442d4e6ff244aa609bd790a8d';

  /// Canonical SHA-256 for assets/content/cities/GEONAMES-LICENSE-README.txt
  static const String canonicalReadmeSha256 =
      'b1957379b6c1242c700c98ac9a8aa0a09f56c3c0a50ee72175527005f48ef2c5';

  /// Expected exact record count in cities15000.txt
  static const int expectedRecordCount = 34149;
}

/// Exception thrown when GeoNames source assets fail integrity verification or parsing.
class GeoNamesValidationException implements Exception {
  final String message;
  final Object? cause;

  const GeoNamesValidationException(this.message, [this.cause]);

  @override
  String toString() => 'GeoNamesValidationException: $message';
}

/// Pure Dart source byte verifier for offline GeoNames city data.
class GeoNamesSourceVerifier {
  GeoNamesSourceVerifier._();

  /// Verifies raw source bytes against canonical SHA-256 hash before decoding.
  static String verifyBytes(Uint8List bytes) {
    final actualSha = sha256.convert(bytes).toString();
    if (actualSha != GeoNamesConstants.canonicalCitiesSha256) {
      throw GeoNamesValidationException(
        'GeoNames cities SHA-256 hash mismatch! '
        'Expected ${GeoNamesConstants.canonicalCitiesSha256}, actual $actualSha',
      );
    }

    try {
      return utf8.decode(bytes);
    } catch (e) {
      throw GeoNamesValidationException(
        'Failed to decode GeoNames cities bytes as UTF-8: $e',
        e,
      );
    }
  }
}
