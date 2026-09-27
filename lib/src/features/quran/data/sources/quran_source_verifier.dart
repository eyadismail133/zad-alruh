import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../parsers/quran_parser.dart';

/// Single source of truth for canonical Quran source SHA-256 hashes.
class QuranSourceConstants {
  QuranSourceConstants._();

  /// Canonical SHA-256 for Tanzil Uthmani text v1.1
  static const String canonicalTextSha256 =
      '7f30c647331a61100ebf24a80507dc0fcdd9f2df97f1312b5b2dfcb982a7f326';

  /// Canonical SHA-256 for Tanzil XML metadata v1.0
  static const String canonicalMetadataSha256 =
      '8867c1d88191472adec9db694b3cd9f135b1a2ef580574d32cf888dcb22c5c7a';
}

/// Holds decoded UTF-8 contents of verified Quran source files.
class VerifiedQuranSources {
  final String textContent;
  final String xmlMetadataContent;

  const VerifiedQuranSources({
    required this.textContent,
    required this.xmlMetadataContent,
  });
}

/// Pure Dart source byte verifier for the Holy Quran.
///
/// Strictly verifies canonical SHA-256 hashes BEFORE UTF-8 decoding or parsing.
/// Usable across CLI, Flutter runtime, and test environments with zero platform dependencies.
class QuranSourceVerifier {
  QuranSourceVerifier._();

  /// Verifies raw source bytes against canonical SHA-256 hashes before decoding.
  ///
  /// Throws [QuranValidationException] if either byte array fails canonical SHA-256
  /// verification or UTF-8 decoding.
  static VerifiedQuranSources verifyBytes({
    required Uint8List textBytes,
    required Uint8List xmlBytes,
  }) {
    final actualTextSha = sha256.convert(textBytes).toString();
    if (actualTextSha != QuranSourceConstants.canonicalTextSha256) {
      throw QuranValidationException(
        'Quran text SHA-256 hash mismatch! '
        'Expected ${QuranSourceConstants.canonicalTextSha256}, actual $actualTextSha',
      );
    }

    final actualXmlSha = sha256.convert(xmlBytes).toString();
    if (actualXmlSha != QuranSourceConstants.canonicalMetadataSha256) {
      throw QuranValidationException(
        'Quran metadata SHA-256 hash mismatch! '
        'Expected ${QuranSourceConstants.canonicalMetadataSha256}, actual $actualXmlSha',
      );
    }

    final String text;
    final String xml;
    try {
      text = utf8.decode(textBytes);
    } catch (e) {
      throw QuranValidationException(
        'Failed to decode Quran text bytes as UTF-8: $e',
        e,
      );
    }

    try {
      xml = utf8.decode(xmlBytes);
    } catch (e) {
      throw QuranValidationException(
        'Failed to decode Quran metadata bytes as UTF-8: $e',
        e,
      );
    }

    return VerifiedQuranSources(textContent: text, xmlMetadataContent: xml);
  }
}
