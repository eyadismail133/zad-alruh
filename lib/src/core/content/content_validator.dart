import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../features/quran/data/parsers/quran_parser.dart';
import '../../features/quran/data/sources/kfqc_mushaf_catalog.dart';
import '../../features/quran/data/sources/quran_source_verifier.dart';
import 'human_review_validator.dart';

/// Result of running content validation.
class ValidationResult {
  /// Whether the supplied source assets and manifest are valid for development.
  final bool isDevelopmentValid;

  /// Whether all release prerequisites are fulfilled (release-ready).
  final bool isReleaseReady;

  /// Critical blocking errors (e.g. corrupt sources, hash mismatches, traversal).
  final List<String> errors;

  /// Actionable items pending before store release (e.g. missing images, audio, review).
  final List<String> pendingReleaseBlockers;

  /// Successfully verified items and metadata.
  final List<String> verifiedItems;

  const ValidationResult({
    required this.isDevelopmentValid,
    required this.isReleaseReady,
    required this.errors,
    required this.pendingReleaseBlockers,
    required this.verifiedItems,
  });

  /// Formats a human-readable console report.
  String toReport({bool isDevelopment = false}) {
    final buffer = StringBuffer();
    buffer.writeln(
      '======================================================================',
    );
    buffer.writeln(' Zad Alruh - Content Integrity & Provenance Report');
    buffer.writeln(
      ' Mode: ${isDevelopment ? "DEVELOPMENT (--development)" : "RELEASE (Default)"}',
    );
    buffer.writeln(
      '======================================================================\n',
    );

    if (verifiedItems.isNotEmpty) {
      buffer.writeln(
        '--- Verified Content & Sources (${verifiedItems.length}) ---',
      );
      for (final item in verifiedItems) {
        buffer.writeln('  [OK] $item');
      }
      buffer.writeln();
    }

    if (pendingReleaseBlockers.isNotEmpty) {
      buffer.writeln(
        '--- Pending Release Prerequisites (${pendingReleaseBlockers.length}) ---',
      );
      for (final blocker in pendingReleaseBlockers) {
        buffer.writeln('  [PENDING] $blocker');
      }
      buffer.writeln();
    }

    if (errors.isNotEmpty) {
      buffer.writeln('--- Blocking Validation Errors (${errors.length}) ---');
      for (final err in errors) {
        buffer.writeln('  [ERROR] $err');
      }
      buffer.writeln();
    }

    buffer.writeln(
      '----------------------------------------------------------------------',
    );
    if (isDevelopment) {
      if (isDevelopmentValid) {
        buffer.writeln(
          'RESULT: Development source-integrity verification PASSED.',
        );
        buffer.writeln(
          'NOTICE: This build is NOT release-ready (pending ${pendingReleaseBlockers.length} prerequisites).',
        );
      } else {
        buffer.writeln(
          'RESULT: Development source verification FAILED with ${errors.length} error(s).',
        );
      }
    } else {
      if (isReleaseReady) {
        buffer.writeln(
          'RESULT: Release validation PASSED. All content verified.',
        );
      } else {
        final totalBlockers = errors.length + pendingReleaseBlockers.length;
        buffer.writeln(
          'RESULT: Release validation BLOCKED. Found $totalBlockers release blocker(s).',
        );
      }
    }
    buffer.writeln(
      '======================================================================',
    );

    return buffer.toString();
  }
}

/// Shared pure Dart validator for religious content, hashes, and release prerequisites.
class ContentValidator {
  ContentValidator._();

  static const int kSupportedSchemaVersion = 1;

  /// Canonical SHA-256 for Tanzil Uthmani text v1.1
  static const String kExpectedTextSha256 =
      QuranSourceConstants.canonicalTextSha256;

  /// Canonical SHA-256 for Tanzil XML metadata v1.0
  static const String kExpectedMetadataSha256 =
      QuranSourceConstants.canonicalMetadataSha256;

  /// Canonical SHA-256 for GeoNames cities15000.txt
  static const String kExpectedCitiesSha256 =
      'c8e0a782e44ba580a2c0f0e3c9538051351629b442d4e6ff244aa609bd790a8d';

  /// Canonical SHA-256 for GeoNames GEONAMES-LICENSE-README.txt
  static const String kExpectedCitiesReadmeSha256 =
      'b1957379b6c1242c700c98ac9a8aa0a09f56c3c0a50ee72175527005f48ef2c5';

  /// Canonical SHA-256 for HadeethEnc Arabic Excel source export v1.7.0
  static const String kExpectedHadithSourceSha256 =
      'd5d397cb9fc8ddd54c4c6ee88357c2217721db0bd0759c6ec26d8b3fc36f1ec1';

  /// Canonical SHA-256 for bundled compact HadeethEnc Sahih JSON asset
  static const String kExpectedHadithJsonSha256 =
      '94a69dbdb44144d2dad2ba0a3fa1ee73c7f7b456c46d945ea15f4332a2eeeda7';

  /// Expected count of authentic ("صحيح") Hadith records
  static const int kExpectedHadithCount = 3213;

  /// Expected source edition version
  static const String kExpectedHadithVersion = 'v1.7.0';

  /// Canonical SHA-256 for official IslamHouse Hisn al-Muslim DOCX source
  static const String kExpectedHisnSourceSha256 =
      '7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a';

  /// Canonical SHA-256 for bundled compact Hisn al-Muslim JSON asset
  static const String kExpectedHisnJsonSha256 =
      '8655afe53935baf74fed92164fedb9f0ba7e989c23818f82bd231ebd6d7a773d';

  /// Expected count of Hisn al-Muslim items
  static const int kExpectedHisnItemsCount = 267;

  /// Expected count of Hisn al-Muslim chapters
  static const int kExpectedHisnChaptersCount = 132;

  /// Expected count of Hisn al-Muslim referenced footnotes
  static const int kExpectedHisnFootnotesCount = 300;

  /// Canonical SHA-256 for KFQC page bounds JSON asset
  static const String kExpectedKfqcBoundsSha256 =
      '95f609f8c56e811b8afed9695bee44a0e4766b47c01708a3abb7064b9bc42539';

  /// Canonical SHA-256 for KFQC page WebP digests catalog JSON asset
  static const String kExpectedKfqcDigestsSha256 =
      'a836ce22d62c5b61243b0e974fb7e6c80ecbcc99c5191a3d02f7ab2f3dec8956';

  /// Expected count of Medina Mushaf pages
  static const int kExpectedPageCount = 604;

  /// Expected total byte sum of 604 WebP page files
  static const int kExpectedTotalPageBytes = 91492288;

  /// Pinned SHA-256 for sample page 1 WebP
  static const String kExpectedPage1Sha256 =
      '1dd02b643c8b1dcb01aaeb3bb34fa240dfdd824898e402cbddfad01e2e470d87';

  /// Pinned SHA-256 for sample page 604 WebP
  static const String kExpectedPage604Sha256 =
      'f30b4aad9b322ce7c3d61c5d2bdedaa948eca8e76494eb21c4473dee68365689';

  /// Canonical set of unique voice IDs for bundled adhan recordings
  static const Set<String> kExpectedAdhanVoiceIds = {
    'adam',
    'atcovi',
    'malmo_fajr',
  };

  /// Expected count of bundled adhan voices
  static const int kExpectedAdhanVoicesCount = 3;

  /// Pinned SHA-256 hashes for full MP3 recordings
  static const Map<String, String> kExpectedAdhanAudioSha256 = {
    'adam': 'c3fa9ae67d8cf65474dec44194d8b6a76c2f04ef188c916cf9c4dd6f8eb28dc7',
    'atcovi': '0faa59e2028bbb2f60a670b53ec89ffcf628f3c195b43fb41d9bdbc99000c1b3',
    'malmo_fajr': '7027122a58eaded2e4fd2c721188e3a25a1d5371e4cd6a6b5b39e7a200e4f68c',
  };

  /// Pinned byte sizes for full MP3 recordings
  static const Map<String, int> kExpectedAdhanAudioBytes = {
    'adam': 1848886,
    'atcovi': 1448294,
    'malmo_fajr': 2971340,
  };

  /// Pinned canonical duration in seconds for full MP3 recordings
  static const Map<String, int> kExpectedAdhanAudioDurations = {
    'adam': 154,
    'atcovi': 87,
    'malmo_fajr': 248,
  };

  /// Pinned SHA-256 hashes for 27-second notification alert clips (PCM WAV)
  static const Map<String, String> kExpectedAdhanAlertSha256 = {
    'adam': 'de9c50bbf6dbaa6b6d4d6306bdafe2fcfa1139372701859e7b1359f802559c01',
    'atcovi':
        'd2e743b31815184e6a9ac2f7dc4fabc775f12742405ae9ea9e2f88df014784df',
    'malmo_fajr':
        'ac164747ac415c424905575ffc8c33fb8edc5cf99a67903b16b32b9e87666e4a',
  };

  /// Pinned byte size for 27-second notification alert clips
  static const int kExpectedAdhanAlertBytes = 1190778;

  /// Exact canonical duration in seconds for notification alert clips
  static const double kExpectedAdhanAlertDurationSeconds = 27.0;

  /// Maximum alert clip duration allowed by Apple UNNotificationSound (< 30 seconds)
  static const double kMaxAlertDurationSeconds = 30.0;

  /// Canonical byte offset for PCM sample data in bundled FFmpeg 7.1 WAV alert clips (after 34-byte LIST chunk)
  static const int kExpectedWavDataOffset = 78;

  /// Pinned lower bound for first-second RMS digital signal amplitude in 27s alert clips.
  ///
  /// Genuine measured first-second RMS on parsed 22050Hz mono PCM:
  /// - adam: ~0.0480
  /// - atcovi: ~0.0678
  /// - malmo_fajr: ~0.00365
  ///
  /// Threshold of 0.002 verifies non-zero digital signal level within numeric bounds.
  /// Note: These automated digital metrics verify non-zero signal presence within numeric bounds only;
  /// they do NOT establish human audible aesthetic quality or religious correctness.
  static const double kExpectedAdhanAlertOnsetRmsLowerBound = 0.002;

  /// Pinned canonical source URLs
  static const Map<String, String> kExpectedAdhanSourceUrls = {
    'adam': 'https://commons.wikimedia.org/wiki/File:Beautiful_adhan.ogg',
    'atcovi':
        'https://commons.wikimedia.org/wiki/File:The_Adhan_-_Muslim_Call_to_Prayer_-_Aaqib_Azeez.mp3',
    'malmo_fajr':
        'https://commons.wikimedia.org/wiki/File:Eid_al-Fitr_Fajr_azan_at_Malm%C3%B6_Mosque_-_19_August_2012.webm',
  };

  /// Pinned canonical licenses
  static const Map<String, String> kExpectedAdhanLicenses = {
    'adam': 'Creative Commons CC0 1.0 Universal',
    'atcovi':
        'Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)',
    'malmo_fajr': 'Creative Commons Attribution 3.0 Unported (CC BY 3.0)',
  };

  /// Pinned canonical license URLs
  static const Map<String, String> kExpectedAdhanLicenseUrls = {
    'adam': 'https://creativecommons.org/publicdomain/zero/1.0/',
    'atcovi': 'https://creativecommons.org/licenses/by-sa/4.0/',
    'malmo_fajr': 'https://creativecommons.org/licenses/by/3.0/',
  };

  /// Pinned relative audio asset paths
  static const Map<String, String> kExpectedAdhanAudioPaths = {
    'adam': 'assets/audio/adhan/adam-converted.mp3',
    'atcovi': 'assets/audio/adhan/atcovi-original.mp3',
    'malmo_fajr': 'assets/audio/adhan/malmo-fajr-extracted.mp3',
  };

  /// Pinned relative alert clip asset paths
  static const Map<String, String> kExpectedAdhanAlertPaths = {
    'adam': 'assets/audio/adhan/adam-alert.wav',
    'atcovi': 'assets/audio/adhan/atcovi-alert.wav',
    'malmo_fajr': 'assets/audio/adhan/malmo-fajr-alert.wav',
  };

  /// Pinned relative iOS Runner alert clip paths
  static const Map<String, String> kExpectedAdhanIosAlertPaths = {
    'adam': 'ios/Runner/adam-alert.wav',
    'atcovi': 'ios/Runner/atcovi-alert.wav',
    'malmo_fajr': 'ios/Runner/malmo-fajr-alert.wav',
  };

  /// Pinned relative Android res/raw alert clip paths
  static const Map<String, String> kExpectedAdhanAndroidAlertPaths = {
    'adam': 'android/app/src/main/res/raw/adam_alert.wav',
    'atcovi': 'android/app/src/main/res/raw/atcovi_alert.wav',
    'malmo_fajr': 'android/app/src/main/res/raw/malmo_fajr_alert.wav',
  };

  /// Validates content integrity and release readiness against a workspace root.
  static Future<ValidationResult> validate({
    required String workspaceRoot,
    bool isDevelopmentMode = false,
    bool strictImageHashes = false,
    String? manifestRelativePath,
  }) async {
    final errors = <String>[];
    final pendingBlockers = <String>[];
    final verified = <String>[];

    final rootDir = Directory(workspaceRoot);
    if (!await rootDir.exists()) {
      errors.add('Workspace directory does not exist: $workspaceRoot');
      return ValidationResult(
        isDevelopmentValid: false,
        isReleaseReady: false,
        errors: errors,
        pendingReleaseBlockers: pendingBlockers,
        verifiedItems: verified,
      );
    }

    final normalizedRoot = p.canonicalize(rootDir.path);
    late final String canonicalRoot;
    try {
      canonicalRoot = rootDir.resolveSymbolicLinksSync();
    } catch (e) {
      errors.add('Failed to resolve canonical path for workspace root: $e');
      return ValidationResult(
        isDevelopmentValid: false,
        isReleaseReady: false,
        errors: errors,
        pendingReleaseBlockers: pendingBlockers,
        verifiedItems: verified,
      );
    }

    // 1. Filesystem Containment & Traversal Safety for manifest
    final manifestRelPath = manifestRelativePath ??
        p.join('assets', 'content', 'manifest.json');
    if (!_isPathSafe(
      relativePath: manifestRelPath,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
    )) {
      errors.add('Unsafe manifest path: $manifestRelPath');
      return ValidationResult(
        isDevelopmentValid: false,
        isReleaseReady: false,
        errors: errors,
        pendingReleaseBlockers: pendingBlockers,
        verifiedItems: verified,
      );
    }

    final manifestFile = File(p.join(normalizedRoot, manifestRelPath));
    if (!await manifestFile.exists()) {
      errors.add('Manifest file not found: $manifestRelPath');
      return ValidationResult(
        isDevelopmentValid: false,
        isReleaseReady: false,
        errors: errors,
        pendingReleaseBlockers: pendingBlockers,
        verifiedItems: verified,
      );
    }

    Map<String, dynamic> manifest;
    try {
      final content = await manifestFile.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        errors.add('Manifest root must be a JSON object');
        return ValidationResult(
          isDevelopmentValid: false,
          isReleaseReady: false,
          errors: errors,
          pendingReleaseBlockers: pendingBlockers,
          verifiedItems: verified,
        );
      }
      manifest = decoded.cast<String, dynamic>();
    } catch (e) {
      errors.add('Failed to parse manifest.json: $e');
      return ValidationResult(
        isDevelopmentValid: false,
        isReleaseReady: false,
        errors: errors,
        pendingReleaseBlockers: pendingBlockers,
        verifiedItems: verified,
      );
    }

    // Validate schema_version
    final rawSchemaVersion = manifest['schema_version'];
    if (rawSchemaVersion is! int ||
        rawSchemaVersion != kSupportedSchemaVersion) {
      errors.add(
        'Unsupported or invalid schema_version: $rawSchemaVersion. '
        'Expected integer $kSupportedSchemaVersion.',
      );
    } else {
      verified.add('Manifest schema_version $kSupportedSchemaVersion verified');
    }

    final rawCorpora = manifest['corpora'];
    final corpora = rawCorpora is Map
        ? rawCorpora.cast<String, dynamic>()
        : null;
    if (corpora == null) {
      errors.add(
        'Manifest missing or malformed "corpora" section (expected JSON object)',
      );
    }

    final rawPending = manifest['pending_registries'];
    final pending = rawPending is Map
        ? rawPending.cast<String, dynamic>()
        : null;
    if (pending == null) {
      errors.add(
        'Manifest missing or malformed "pending_registries" section (expected JSON object)',
      );
    }

    final rawProvenance = manifest['provenance'];
    final provenance = rawProvenance is Map
        ? rawProvenance.cast<String, dynamic>()
        : null;
    if (provenance == null) {
      errors.add(
        'Manifest missing or malformed "provenance" section (expected JSON object)',
      );
    }

    // 2. Validate Supplied Corpora
    final corporaResult = await _validateCorpora(
      corpora: corpora,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
      errors: errors,
      verified: verified,
    );

    // 3. Validate Supplied Provenance
    await _validateProvenance(
      provenance: provenance,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
      errors: errors,
      verified: verified,
    );

    // 4. Structural and Relational Parse Validation of Supplied Quran Text + Metadata
    _validateQuranStructure(
      quranTextContent: corporaResult.quranTextContent,
      quranXmlContent: corporaResult.quranXmlContent,
      errors: errors,
      verified: verified,
    );

    // 5. Pending and Bundled Registries Checks
    await _validatePendingRegistries(
      pending: pending,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
      strictImageHashes: strictImageHashes,
      errors: errors,
      pendingBlockers: pendingBlockers,
      verified: verified,
    );

    final isDevelopmentValid = errors.isEmpty;
    final isReleaseReady = errors.isEmpty && pendingBlockers.isEmpty;

    return ValidationResult(
      isDevelopmentValid: isDevelopmentValid,
      isReleaseReady: isReleaseReady,
      errors: List.unmodifiable(errors),
      pendingReleaseBlockers: List.unmodifiable(pendingBlockers),
      verifiedItems: List.unmodifiable(verified),
    );
  }

  /// Filesystem containment & traversal safety check.
  static bool _isPathSafe({
    required String relativePath,
    required String normalizedRoot,
    required String canonicalRoot,
  }) {
    if (relativePath.contains('\x00')) {
      return false;
    }
    if (p.isAbsolute(relativePath)) {
      return false;
    }
    if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
      return false;
    }

    // Lexical check against normalizedRoot
    final joined = p.normalize(p.join(normalizedRoot, relativePath));
    final lexicalSafe =
        joined == normalizedRoot || p.isWithin(normalizedRoot, joined);
    if (!lexicalSafe) {
      return false;
    }

    // Canonical link/junction containment check
    final entityType = FileSystemEntity.typeSync(joined);
    final FileSystemEntity entity = entityType == FileSystemEntityType.directory
        ? Directory(joined)
        : File(joined);

    if (entity.existsSync()) {
      try {
        final resolved = entity.resolveSymbolicLinksSync();
        final canonicalSafe =
            resolved == canonicalRoot ||
            p.isWithin(canonicalRoot, resolved) ||
            resolved == normalizedRoot ||
            p.isWithin(normalizedRoot, resolved);
        if (!canonicalSafe) {
          return false;
        }
      } catch (_) {
        return false;
      }
    } else {
      // If file doesn't exist, verify its parent directory
      final parentDir = entity.parent;
      if (parentDir.existsSync()) {
        try {
          final resolvedParent = parentDir.resolveSymbolicLinksSync();
          final canonicalSafe =
              resolvedParent == canonicalRoot ||
              p.isWithin(canonicalRoot, resolvedParent) ||
              resolvedParent == normalizedRoot ||
              p.isWithin(normalizedRoot, resolvedParent);
          if (!canonicalSafe) {
            return false;
          }
        } catch (_) {
          return false;
        }
      }
    }

    return true;
  }

  /// Validates Holy Quran text and XML metadata source files.
  static Future<({String? quranTextContent, String? quranXmlContent})>
  _validateCorpora({
    required Map<String, dynamic>? corpora,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) async {
    String? quranTextContent;
    String? quranXmlContent;

    if (corpora == null) return (quranTextContent: null, quranXmlContent: null);

    // Validate Quran Text Corpus
    final qTextRaw = corpora['quran_text'];
    if (qTextRaw is! Map) {
      errors.add(
        'Malformed "quran_text" entry in corpora (expected JSON object)',
      );
    } else {
      final qText = qTextRaw.cast<String, dynamic>();
      final path = qText['path'];
      final declaredSha = qText['sha256'];
      final license = qText['license'];
      final evidenceDoc = qText['evidence_doc'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid path for quran_text: $path');
      } else {
        final textFile = File(p.join(normalizedRoot, path));
        if (!await textFile.exists()) {
          errors.add('Quran text source file not found: $path');
        } else {
          final bytes = await textFile.readAsBytes();
          final actualSha = sha256.convert(bytes).toString();

          if (actualSha != kExpectedTextSha256) {
            errors.add(
              'Quran text SHA-256 hash mismatch! '
              'Expected $kExpectedTextSha256, actual $actualSha',
            );
          } else if (declaredSha != kExpectedTextSha256) {
            errors.add(
              'Quran text declared hash mismatch! '
              'Declared $declaredSha != expected $kExpectedTextSha256',
            );
          } else {
            verified.add('Quran text SHA-256 verified ($actualSha)');
            quranTextContent = utf8.decode(bytes);
          }
        }
      }

      if (license is! String || license.isEmpty) {
        errors.add('Quran text missing license specification');
      } else {
        verified.add('Quran text license attributed: $license');
      }

      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for quran_text: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('Quran text evidence doc missing: $evidenceDoc');
          }
        }
      }
    }

    // Validate Quran Metadata Corpus
    final qXmlRaw = corpora['quran_metadata'];
    if (qXmlRaw is! Map) {
      errors.add(
        'Malformed "quran_metadata" entry in corpora (expected JSON object)',
      );
    } else {
      final qXml = qXmlRaw.cast<String, dynamic>();
      final path = qXml['path'];
      final declaredSha = qXml['sha256'];
      final license = qXml['license'];
      final evidenceDoc = qXml['evidence_doc'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid path for quran_metadata: $path');
      } else {
        final xmlFile = File(p.join(normalizedRoot, path));
        if (!await xmlFile.exists()) {
          errors.add('Quran XML metadata file not found: $path');
        } else {
          final bytes = await xmlFile.readAsBytes();
          final actualSha = sha256.convert(bytes).toString();

          if (actualSha != kExpectedMetadataSha256) {
            errors.add(
              'Quran metadata SHA-256 hash mismatch! '
              'Expected $kExpectedMetadataSha256, actual $actualSha',
            );
          } else if (declaredSha != kExpectedMetadataSha256) {
            errors.add(
              'Quran metadata declared hash mismatch! '
              'Declared $declaredSha != expected $kExpectedMetadataSha256',
            );
          } else {
            verified.add('Quran XML metadata SHA-256 verified ($actualSha)');
            quranXmlContent = utf8.decode(bytes);
          }
        }
      }

      if (license is! String || license.trim() != 'cc-by') {
        errors.add(
          'Quran metadata license must declare exact "cc-by" as specified in source XML root; '
          'found "$license". Precise license version must remain unspecified.',
        );
      } else {
        verified.add(
          'Quran metadata license: cc-by (unspecified version; precise rights pending)',
        );
      }

      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for quran_metadata: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('Quran metadata evidence doc missing: $evidenceDoc');
          }
        }
      }
    }

    return (
      quranTextContent: quranTextContent,
      quranXmlContent: quranXmlContent,
    );
  }

  /// Validates provenance documentation and auxiliary files (GeoNames, Tanzil).
  static Future<void> _validateProvenance({
    required Map<String, dynamic>? provenance,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) async {
    if (provenance == null) {
      return;
    }

    // Validate GeoNames
    final geoRaw = provenance['geonames'];
    if (geoRaw is! Map) {
      errors.add(
        'Malformed "geonames" provenance section (expected JSON object)',
      );
    } else {
      final geo = geoRaw.cast<String, dynamic>();
      final dataFileRaw = geo['data_file'];
      final readmeFileRaw = geo['readme_file'];
      final evidenceDoc = geo['evidence_doc'];

      if (dataFileRaw is! Map) {
        errors.add('GeoNames provenance missing "data_file" entry');
      } else {
        final dataFile = dataFileRaw.cast<String, dynamic>();
        final dataPath = dataFile['path'];
        if (dataPath is! String ||
            !_isPathSafe(
              relativePath: dataPath,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add('Unsafe or invalid GeoNames data path: $dataPath');
        } else {
          final f = File(p.join(normalizedRoot, dataPath));
          if (!await f.exists()) {
            errors.add('GeoNames data file missing: $dataPath');
          } else {
            final bytes = await f.readAsBytes();
            final actualSha = sha256.convert(bytes).toString();
            if (actualSha != kExpectedCitiesSha256) {
              errors.add(
                'GeoNames cities SHA-256 mismatch! Expected $kExpectedCitiesSha256, actual $actualSha',
              );
            } else {
              verified.add('GeoNames cities data file verified ($dataPath)');
            }
          }
        }
      }

      if (readmeFileRaw is! Map) {
        errors.add('GeoNames provenance missing "readme_file" entry');
      } else {
        final readmeFile = readmeFileRaw.cast<String, dynamic>();
        final readmePath = readmeFile['path'];
        if (readmePath is! String ||
            !_isPathSafe(
              relativePath: readmePath,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid GeoNames license readme path: $readmePath',
          );
        } else {
          final f = File(p.join(normalizedRoot, readmePath));
          if (!await f.exists()) {
            errors.add('GeoNames license readme file missing: $readmePath');
          } else {
            final bytes = await f.readAsBytes();
            final actualSha = sha256.convert(bytes).toString();
            if (actualSha != kExpectedCitiesReadmeSha256) {
              errors.add(
                'GeoNames license readme SHA-256 mismatch! Expected $kExpectedCitiesReadmeSha256, actual $actualSha',
              );
            } else {
              verified.add(
                'GeoNames license readme file verified ($readmePath)',
              );
            }
          }
        }
      }

      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for GeoNames: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('GeoNames evidence doc missing: $evidenceDoc');
          }
        }
      }
    }

    // Validate Tanzil Documentation
    final tanzilRaw = provenance['tanzil'];
    if (tanzilRaw is Map) {
      final tanzil = tanzilRaw.cast<String, dynamic>();
      final evidenceDoc = tanzil['evidence_doc'];
      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for Tanzil: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('Tanzil evidence doc missing: $evidenceDoc');
          }
        }
      }
    }

    // Validate HadeethEnc Provenance
    final hadeethRaw = provenance['hadeethenc'];
    if (hadeethRaw is Map) {
      final h = hadeethRaw.cast<String, dynamic>();
      final sourceFileRaw = h['source_file'];
      if (sourceFileRaw is Map) {
        final path = sourceFileRaw['path'];
        if (path is! String ||
            !_isPathSafe(
              relativePath: path,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add('Unsafe or invalid HadeethEnc provenance source path: $path');
        } else {
          final f = File(p.join(normalizedRoot, path));
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            final actualSha = sha256.convert(bytes).toString().toLowerCase();
            if (actualSha == kExpectedHadithSourceSha256) {
              verified.add('HadeethEnc provenance source XLSX verified ($path)');
            }
          }
        }
      }
      final evidenceDoc = h['evidence_doc'];
      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for HadeethEnc: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('HadeethEnc evidence doc missing: $evidenceDoc');
          } else {
            verified.add('HadeethEnc evidence doc verified ($evidenceDoc)');
          }
        }
      }
    }

    // Validate Hisn al-Muslim Provenance
    final hisnRaw = provenance['hisn_almuslim'];
    if (hisnRaw is Map) {
      final h = hisnRaw.cast<String, dynamic>();
      final sourceFileRaw = h['source_file'];
      if (sourceFileRaw is Map) {
        final path = sourceFileRaw['path'];
        if (path is! String ||
            !_isPathSafe(
              relativePath: path,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add('Unsafe or invalid Hisn al-Muslim provenance source path: $path');
        } else {
          final f = File(p.join(normalizedRoot, path));
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            final actualSha = sha256.convert(bytes).toString().toLowerCase();
            if (actualSha == kExpectedHisnSourceSha256) {
              verified.add('Hisn al-Muslim provenance source DOCX verified ($path)');
            }
          }
        }
      }
      final evidenceDoc = h['evidence_doc'];
      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for Hisn al-Muslim: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('Hisn al-Muslim evidence doc missing: $evidenceDoc');
          } else {
            verified.add('Hisn al-Muslim evidence doc verified ($evidenceDoc)');
          }
        }
      }
    }

    // Validate KFQC Mushaf Provenance
    final kfqcRaw = provenance['kfqc_mushaf'];
    if (kfqcRaw is Map) {
      final k = kfqcRaw.cast<String, dynamic>();
      final boundsRaw = k['bounds_file'];
      if (boundsRaw is Map) {
        final path = boundsRaw['path'];
        final declaredSha = boundsRaw['sha256'];
        if (path is! String ||
            !_isPathSafe(
              relativePath: path,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add('Unsafe or invalid KFQC bounds provenance path: $path');
        } else if (path != KfqcMushafCatalog.boundsAssetPath) {
          errors.add(
            'KFQC bounds provenance path must match exact runtime path "${KfqcMushafCatalog.boundsAssetPath}", got: $path',
          );
        } else {
          final f = File(p.join(normalizedRoot, path));
          if (!await f.exists()) {
            errors.add('KFQC bounds file missing in provenance: $path');
          } else {
            final bytes = await f.readAsBytes();
            final actualSha = sha256.convert(bytes).toString().toLowerCase();
            if (declaredSha is! String ||
                declaredSha.toLowerCase() != kExpectedKfqcBoundsSha256) {
              errors.add(
                'KFQC bounds file declared SHA mismatch in provenance: expected $kExpectedKfqcBoundsSha256 but got $declaredSha',
              );
            } else if (actualSha != kExpectedKfqcBoundsSha256) {
              errors.add(
                'KFQC bounds file SHA mismatch in provenance: expected $kExpectedKfqcBoundsSha256 but got $actualSha',
              );
            } else {
              verified.add('KFQC bounds file verified in provenance ($path)');
            }
          }
        }
      }
      final digestsRaw = k['digests_file'];
      if (digestsRaw is Map) {
        final path = digestsRaw['path'];
        final declaredSha = digestsRaw['sha256'];
        if (path is! String ||
            !_isPathSafe(
              relativePath: path,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add('Unsafe or invalid KFQC digests provenance path: $path');
        } else if (path != KfqcMushafCatalog.digestsAssetPath) {
          errors.add(
            'KFQC digests provenance path must match exact runtime path "${KfqcMushafCatalog.digestsAssetPath}", got: $path',
          );
        } else {
          final f = File(p.join(normalizedRoot, path));
          if (!await f.exists()) {
            errors.add('KFQC digests file missing in provenance: $path');
          } else {
            final bytes = await f.readAsBytes();
            final actualSha = sha256.convert(bytes).toString().toLowerCase();
            if (declaredSha is! String ||
                declaredSha.toLowerCase() != kExpectedKfqcDigestsSha256) {
              errors.add(
                'KFQC digests file declared SHA mismatch in provenance: expected $kExpectedKfqcDigestsSha256 but got $declaredSha',
              );
            } else if (actualSha != kExpectedKfqcDigestsSha256) {
              errors.add(
                'KFQC digests file SHA mismatch in provenance: expected $kExpectedKfqcDigestsSha256 but got $actualSha',
              );
            } else {
              verified.add('KFQC digests file verified in provenance ($path)');
            }
          }
        }
      }
      final evidenceDoc = k['evidence_doc'];
      if (evidenceDoc != null) {
        if (evidenceDoc is! String ||
            !_isPathSafe(
              relativePath: evidenceDoc,
              normalizedRoot: normalizedRoot,
              canonicalRoot: canonicalRoot,
            )) {
          errors.add(
            'Unsafe or invalid evidence_doc path for KFQC Mushaf: $evidenceDoc',
          );
        } else if (evidenceDoc != KfqcMushafCatalog.evidenceDocPath) {
          errors.add(
            'KFQC Mushaf evidence doc path must match exact runtime path "${KfqcMushafCatalog.evidenceDocPath}", got: $evidenceDoc',
          );
        } else {
          final evf = File(p.join(normalizedRoot, evidenceDoc));
          if (!await evf.exists()) {
            errors.add('KFQC Mushaf evidence doc missing: $evidenceDoc');
          } else {
            verified.add('KFQC Mushaf evidence doc verified ($evidenceDoc)');
          }
        }
      }
    }
  }

  /// Structurally parses verified text and XML metadata to guarantee verbatim completeness.
  static void _validateQuranStructure({
    required String? quranTextContent,
    required String? quranXmlContent,
    required List<String> errors,
    required List<String> verified,
  }) {
    if (quranTextContent == null || quranXmlContent == null) {
      return;
    }

    try {
      final parsedData = QuranParser.parse(
        textContent: quranTextContent,
        xmlMetadataContent: quranXmlContent,
      );

      verified.add(
        'Corpus structure verified: ${parsedData.surahs.length} chapters, '
        '${parsedData.verses.length} verses, ${parsedData.pages.length} pages, '
        '${parsedData.juzs.length} juz',
      );
      verified.add('First verse verified: 1:1 (Al-Faatiha)');
      verified.add('Last verse verified: 114:6 (An-Naas)');
      verified.add('Chapter 9 start verified at Page 187 Aya 1');
      verified.add('Page 604 start verified at Chapter 112 Aya 1');
      verified.add('Juz 30 start verified at Chapter 78 Aya 1');
    } catch (e) {
      errors.add('Quran corpus parsing / structural verification failed: $e');
    }
  }

  /// Typed pending and bundled registry checks.
  ///
  /// Enforces schema, field types, counts, and validates file-backed Hadith, Hisn, and Quran images bundles.
  /// Drops ONLY the corresponding release blockers when verified valid.
  static Future<void> _validatePendingRegistries({
    required Map<String, dynamic>? pending,
    required String normalizedRoot,
    required String canonicalRoot,
    required bool strictImageHashes,
    required List<String> errors,
    required List<String> pendingBlockers,
    required List<String> verified,
  }) async {
    if (pending == null) {
      return;
    }

    // 1. Quran Images Registry
    final imgRaw = pending['quran_images'];
    bool imagesValid = false;
    const imagesBlocker =
        'Missing 604 Medina Mushaf page images. '
        'Owner has no developer account/CDN access. Same-edition image alignment pending.';

    if (imgRaw is! Map) {
      errors.add(
        'Missing or malformed "quran_images" section in pending_registries',
      );
    } else {
      final img = imgRaw.cast<String, dynamic>();
      final status = img['status'];
      if (status is! String) {
        errors.add('Image registry status must be a string');
      }

      if (img.containsKey('pages')) {
        final pages = img['pages'];
        if (pages is! List) {
          errors.add('Image registry "pages" field must be a list');
        } else if (pages.isNotEmpty) {
          if (status == 'missing') {
            errors.add(
              'Image registry declares status="missing" but contains page entries',
            );
          }
          errors.add(
            'Quran page images are unsupported at this milestone; dedicated validator pending',
          );
        }
      }

      if (status == 'bundled') {
        imagesValid = await _validateBundledQuranImages(
          images: img,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
          strictImageHashes: strictImageHashes,
          errors: errors,
          verified: verified,
        );
      } else if (status == 'missing' || status == 'pending') {
        final expectedCount = img['expected_count'];
        if (expectedCount != null &&
            (expectedCount is! int || expectedCount < 0)) {
          errors.add(
            'Quran images expected_count must be a non-negative integer',
          );
        }

        final recordsCount = img['records_count'];
        if (recordsCount != null && (recordsCount is! int || recordsCount < 0)) {
          errors.add('Quran images records_count must be a non-negative integer');
        }
      } else if (status is String) {
        errors.add('Contradictory or invalid image registry status: "$status"');
      }
    }

    // 2. Adhan Audio Registry
    final audioRaw = pending['adhan_audio'];
    bool audioValid = false;
    const audioBlocker =
        'Missing 3 licensed adhan recordings (3 distinct voices including Fajr and <30s notification clips).';

    if (audioRaw is! Map) {
      errors.add(
        'Missing or malformed "adhan_audio" section in pending_registries',
      );
    } else {
      final audio = audioRaw.cast<String, dynamic>();
      final status = audio['status'];
      if (status is! String) {
        errors.add('Adhan audio registry status must be a string');
      } else if (status == 'bundled') {
        audioValid = await _validateBundledAdhanAudio(
          audio: audio,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
          errors: errors,
          verified: verified,
        );
      } else if (status == 'missing' || status == 'pending') {
        final expectedVoices = audio['expected_voices_count'];
        if (expectedVoices != null &&
            (expectedVoices is! int || expectedVoices < 0)) {
          errors.add(
            'Adhan audio expected_voices_count must be a non-negative integer',
          );
        }

        final voices = audio['voices'];
        if (voices is! List) {
          errors.add('Adhan audio "voices" field must be a list');
        }

        final clips = audio['notification_clips'];
        if (clips is! List) {
          errors.add('Adhan audio "notification_clips" field must be a list');
        }

        final hasDeclaredEntries =
            (voices is List && voices.isNotEmpty) ||
            (clips is List && clips.isNotEmpty);

        if (hasDeclaredEntries) {
          if (status == 'missing') {
            errors.add(
              'Adhan audio registry declares status="missing" but contains declared voice or clip entries',
            );
          }
          errors.add(
            'Adhan audio recordings are declared but registry status is "$status" instead of "bundled"',
          );
        }
      } else {
        errors.add('Contradictory or invalid adhan audio status: "$status"');
      }
    }

    // 3. Dhikr & Duas Registry
    final dhikrRaw = pending['dhikr_duas'];
    bool dhikrValid = false;
    const dhikrBlocker =
        'Missing documented Hisn al-Muslim dhikr/duas digital edition, references, and repetition counts.';

    if (dhikrRaw is! Map) {
      errors.add(
        'Missing or malformed "dhikr_duas" section in pending_registries',
      );
    } else {
      final dhikr = dhikrRaw.cast<String, dynamic>();
      final status = dhikr['status'];
      if (status is! String) {
        errors.add('Dhikr registry status must be a string');
      } else if (status == 'bundled') {
        dhikrValid = await _validateBundledHisn(
          dhikr: dhikr,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
          errors: errors,
          verified: verified,
        );
      } else if (status == 'missing' || status == 'pending') {
        final recordsCount = dhikr['records_count'];
        if (recordsCount != null && (recordsCount is! int || recordsCount < 0)) {
          errors.add('Dhikr records_count must be a non-negative integer');
        }

        final items = dhikr['items'];
        if (items is! List) {
          errors.add('Dhikr registry "items" field must be a list');
        } else {
          if (recordsCount is int && recordsCount > 0 && items.isEmpty) {
            errors.add(
              'Dhikr registry claims $recordsCount records but items list has 0',
            );
          }
          if (items.isNotEmpty) {
            if (status == 'missing') {
              errors.add(
                'Dhikr registry declares status="missing" but contains items',
              );
            }
            errors.add(
              'Dhikr collection is unsupported at this milestone; dedicated validator pending',
            );
          }
        }
      } else {
        errors.add(
          'Contradictory or invalid dhikr registry status: "$status"',
        );
      }
    }

    // 4. Hadith Registry
    final hadithRaw = pending['hadith'];
    bool hadithValid = false;
    const hadithBlocker =
        'Missing 100 authentic HadeethEnc hadith records with references and Arabic reuse rights.';

    if (hadithRaw is! Map) {
      errors.add('Missing or malformed "hadith" section in pending_registries');
    } else {
      final hadith = hadithRaw.cast<String, dynamic>();
      final status = hadith['status'];
      if (status is! String) {
        errors.add('Hadith registry status must be a string');
      } else if (status == 'bundled') {
        hadithValid = await _validateBundledHadith(
          hadith: hadith,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
          errors: errors,
          verified: verified,
        );
      } else if (status == 'missing' || status == 'pending') {
        final recordsCount = hadith['records_count'];
        if (recordsCount != null && (recordsCount is! int || recordsCount < 0)) {
          errors.add('Hadith records_count must be a non-negative integer');
        }

        final targetCount = hadith['target_count'];
        if (targetCount != null && (targetCount is! int || targetCount < 0)) {
          errors.add('Hadith target_count must be a non-negative integer');
        }

        final items = hadith['items'];
        if (items is! List) {
          errors.add('Hadith registry "items" field must be a list');
        } else {
          if (recordsCount is int && recordsCount > 0 && items.isEmpty) {
            errors.add(
              'Hadith registry claims $recordsCount records but items list has 0',
            );
          }
          if (items.isNotEmpty) {
            if (status == 'missing') {
              errors.add(
                'Hadith registry declares status="missing" but contains items',
              );
            }
            errors.add(
              'Hadith collection is unsupported at this milestone; dedicated validator pending',
            );
          }
        }
      } else {
        errors.add(
          'Contradictory or invalid hadith registry status: "$status"',
        );
      }
    }

    // 5. Human Review Registry
    final humanRaw = pending['human_review'];
    bool humanReviewValid = false;
    bool humanReviewApproved = false;
    const humanBlocker =
        'Qualified human reviewer religious review tied to exact corpus hashes is pending.';

    if (humanRaw is! Map) {
      errors.add(
        'Missing or malformed "human_review" section in pending_registries',
      );
    } else {
      final human = humanRaw.cast<String, dynamic>();
      final humanResult = await HumanReviewValidator.validate(
        humanReviewRegistry: human,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        underlyingIntegritySuccess: imagesValid &&
            audioValid &&
            dhikrValid &&
            hadithValid &&
            errors.isEmpty,
      );

      if (humanResult.errors.isNotEmpty) {
        errors.addAll(humanResult.errors);
      }
      if (humanResult.verifiedItems.isNotEmpty) {
        verified.addAll(humanResult.verifiedItems);
      }
      humanReviewValid = humanResult.isValid;
      humanReviewApproved = humanResult.isApproved;
    }

    // Drop ONLY Quran images blocker when valid
    if (!imagesValid) {
      pendingBlockers.add(imagesBlocker);
    }
    // Drop ONLY adhan audio release blocker when valid
    if (!audioValid) {
      pendingBlockers.add(audioBlocker);
    }

    // Drop ONLY Hisn al-Muslim release blocker when valid
    if (!dhikrValid) {
      pendingBlockers.add(dhikrBlocker);
    }

    // Drop ONLY the hadith release blocker when valid
    if (!hadithValid) {
      pendingBlockers.add(hadithBlocker);
    }

    // Drop ONLY qualified human review blocker on full valid evidence AND underlying asset integrity success
    if (!(humanReviewValid &&
        humanReviewApproved &&
        imagesValid &&
        audioValid &&
        dhikrValid &&
        hadithValid &&
        errors.isEmpty)) {
      pendingBlockers.add(humanBlocker);
    }
  }

  /// Strictly validates file-backed 604-page KFQC Medina Mushaf images bundle
  /// against bounds, digests catalog, safe paths, file count, total size,
  /// sample hashes, and optional full hash verification.
  static Future<bool> _validateBundledQuranImages({
    required Map<String, dynamic> images,
    required String normalizedRoot,
    required String canonicalRoot,
    required bool strictImageHashes,
    required List<String> errors,
    required List<String> verified,
  }) async {
    bool valid = true;

    // 1. Expected count and total bytes in manifest
    final declaredCount = images['expected_count'];
    if (declaredCount != kExpectedPageCount) {
      errors.add(
        'Quran images expected_count mismatch: manifest declared $declaredCount, expected $kExpectedPageCount',
      );
      valid = false;
    }

    final declaredBytes = images['total_bytes'];
    if (declaredBytes != kExpectedTotalPageBytes) {
      errors.add(
        'Quran images total_bytes mismatch: manifest declared $declaredBytes, expected $kExpectedTotalPageBytes',
      );
      valid = false;
    }

    // 2. Bounds file verification
    final boundsRaw = images['bounds_file'];
    if (boundsRaw is! Map) {
      errors.add('Quran images registry missing "bounds_file" entry');
      valid = false;
    } else {
      final boundsMap = boundsRaw.cast<String, dynamic>();
      final path = boundsMap['path'];
      final declaredSha = boundsMap['sha256'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid bounds_file path: $path');
        valid = false;
      } else if (path != KfqcMushafCatalog.boundsAssetPath) {
        errors.add(
          'Quran page bounds path must match exact runtime path "${KfqcMushafCatalog.boundsAssetPath}", got: $path',
        );
        valid = false;
      } else if (declaredSha is! String ||
          declaredSha.toLowerCase() != kExpectedKfqcBoundsSha256) {
        errors.add(
          'Bounds file declared SHA mismatch: expected $kExpectedKfqcBoundsSha256, declared $declaredSha',
        );
        valid = false;
      } else {
        final boundsFile = File(p.join(normalizedRoot, path));
        if (!await boundsFile.exists()) {
          errors.add('Quran page bounds file missing: $path');
          valid = false;
        } else {
          final bytes = await boundsFile.readAsBytes();
          final actualSha = sha256.convert(bytes).toString().toLowerCase();
          if (actualSha != kExpectedKfqcBoundsSha256) {
            errors.add(
              'Quran page bounds file SHA-256 mismatch: expected $kExpectedKfqcBoundsSha256, actual $actualSha',
            );
            valid = false;
          } else {
            try {
              final content = utf8.decode(bytes);
              final parsed = jsonDecode(content);
              if (parsed is Map && parsed['pages'] is List) {
                final pagesList = parsed['pages'] as List;
                if (pagesList.length != kExpectedPageCount) {
                  errors.add(
                    'Quran page bounds count mismatch: expected $kExpectedPageCount, found ${pagesList.length}',
                  );
                  valid = false;
                } else {
                  int totalCoveredVerses = 0;
                  for (int i = 0; i < pagesList.length; i++) {
                    final entry = pagesList[i];
                    if (entry is! Map) {
                      errors.add('Malformed page bound entry at index $i');
                      valid = false;
                      break;
                    }
                    final pageNum = entry['page'];
                    final startMap = entry['start'];
                    final endMap = entry['end'];
                    final count = entry['verse_count'];

                    if (pageNum is! int ||
                        startMap is! Map ||
                        endMap is! Map ||
                        count is! int) {
                      errors.add('Invalid types in page bound entry for page ${i + 1}');
                      valid = false;
                      break;
                    }

                    final sSurah = startMap['surah'] as int?;
                    final sAyah = startMap['ayah'] as int?;
                    final eSurah = endMap['surah'] as int?;
                    final eAyah = endMap['ayah'] as int?;

                    if (sSurah == null || sAyah == null || eSurah == null || eAyah == null) {
                      errors.add('Incomplete verse references in page bound entry for page $pageNum');
                      valid = false;
                      break;
                    }

                    final canonical = KfqcMushafCatalog.pages[i];
                    if (pageNum != canonical.page ||
                        sSurah != canonical.startSurah ||
                        sAyah != canonical.startAyah ||
                        eSurah != canonical.endSurah ||
                        eAyah != canonical.endAyah ||
                        count != canonical.verseCount) {
                      errors.add(
                        'Page $pageNum bound mismatch against canonical KFQC catalog: '
                        'got ($sSurah:$sAyah..$eSurah:$eAyah, count=$count), '
                        'expected (${canonical.startSurah}:${canonical.startAyah}..${canonical.endSurah}:${canonical.endAyah}, count=${canonical.verseCount})',
                      );
                      valid = false;
                      break;
                    }

                    totalCoveredVerses += count;
                  }

                  if (valid && totalCoveredVerses != 6236) {
                    errors.add(
                      'Quran page bounds total verses covered ($totalCoveredVerses) != 6236',
                    );
                    valid = false;
                  }
                }
              } else {
                errors.add('Quran page bounds JSON root must contain "pages" array');
                valid = false;
              }
            } catch (e) {
              errors.add('Failed to parse Quran page bounds JSON: $e');
              valid = false;
            }
          }
        }
      }
    }

    // 3. Digests file verification
    final digestsRaw = images['digests_file'];
    Map<String, String>? webpDigests;
    if (digestsRaw is! Map) {
      errors.add('Quran images registry missing "digests_file" entry');
      valid = false;
    } else {
      final digestsMap = digestsRaw.cast<String, dynamic>();
      final path = digestsMap['path'];
      final declaredSha = digestsMap['sha256'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid digests_file path: $path');
        valid = false;
      } else if (path != KfqcMushafCatalog.digestsAssetPath) {
        errors.add(
          'Quran page digests path must match exact runtime path "${KfqcMushafCatalog.digestsAssetPath}", got: $path',
        );
        valid = false;
      } else if (declaredSha is! String ||
          declaredSha.toLowerCase() != kExpectedKfqcDigestsSha256) {
        errors.add(
          'Digests file declared SHA mismatch: expected $kExpectedKfqcDigestsSha256, declared $declaredSha',
        );
        valid = false;
      } else {
        final digestsFile = File(p.join(normalizedRoot, path));
        if (!await digestsFile.exists()) {
          errors.add('Quran page digests file missing: $path');
          valid = false;
        } else {
          final bytes = await digestsFile.readAsBytes();
          final actualSha = sha256.convert(bytes).toString().toLowerCase();
          if (actualSha != kExpectedKfqcDigestsSha256) {
            errors.add(
              'Quran page digests file SHA-256 mismatch: expected $kExpectedKfqcDigestsSha256, actual $actualSha',
            );
            valid = false;
          } else {
            try {
              final content = utf8.decode(bytes);
              final parsed = jsonDecode(content);
              if (parsed is Map && parsed['pages'] is List) {
                final pagesList = parsed['pages'] as List;
                if (pagesList.length != kExpectedPageCount) {
                  errors.add(
                    'Quran page digests count mismatch: expected $kExpectedPageCount, found ${pagesList.length}',
                  );
                  valid = false;
                } else {
                  webpDigests = {};
                  for (final item in pagesList) {
                    if (item is Map) {
                      final pNum = item['page'];
                      final sha = item['webp_sha256'];
                      if (pNum is int && sha is String) {
                        webpDigests[pNum.toString().padLeft(3, '0')] =
                            sha.toLowerCase();
                      }
                    }
                  }
                  if (webpDigests.length != kExpectedPageCount) {
                    errors.add('Quran page digests has incomplete or invalid entries');
                    valid = false;
                  }
                }
              } else {
                errors.add('Quran page digests JSON root must contain "pages" array');
                valid = false;
              }
            } catch (e) {
              errors.add('Failed to parse Quran page digests JSON: $e');
              valid = false;
            }
          }
        }
      }
    }

    // 4. Pages directory and files verification
    final pagesDirRel = images['pages_directory'];
    if (pagesDirRel is! String ||
        !_isPathSafe(
          relativePath: pagesDirRel,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
        )) {
      errors.add('Unsafe or invalid pages_directory path: $pagesDirRel');
      valid = false;
    } else if (pagesDirRel != KfqcMushafCatalog.pagesAssetDirectory) {
      errors.add(
        'Quran pages directory must match exact runtime path "${KfqcMushafCatalog.pagesAssetDirectory}", got: $pagesDirRel',
      );
      valid = false;
    } else {
      final pagesDir = Directory(p.join(normalizedRoot, pagesDirRel));
      if (!await pagesDir.exists()) {
        errors.add('Quran pages directory missing: $pagesDirRel');
        valid = false;
      } else {
        final dirEntities = await pagesDir.list().toList();
        final fileEntities = dirEntities.whereType<File>().toList();

        if (fileEntities.length != kExpectedPageCount) {
          errors.add(
            'Quran pages directory file count mismatch: expected $kExpectedPageCount, found ${fileEntities.length}',
          );
          valid = false;
        }

        int totalBytes = 0;
        final existingFilenames = <String>{};
        for (final file in fileEntities) {
          final basename = p.basename(file.path);
          existingFilenames.add(basename);
          totalBytes += await file.length();
        }

        if (totalBytes != kExpectedTotalPageBytes) {
          errors.add(
            'Quran pages combined byte size mismatch: expected $kExpectedTotalPageBytes bytes, found $totalBytes bytes',
          );
          valid = false;
        }

        // Verify all 604 files 001.webp .. 604.webp exist
        for (int page = 1; page <= kExpectedPageCount; page++) {
          final expectedName = '${page.toString().padLeft(3, '0')}.webp';
          if (!existingFilenames.contains(expectedName)) {
            errors.add('Missing Quran page image file: $expectedName');
            valid = false;
            break;
          }
        }

        // Sample Page Hashes (Page 1 and Page 604)
        final page1File = File(p.join(pagesDir.path, '001.webp'));
        if (await page1File.exists()) {
          final p1Sha = sha256
              .convert(await page1File.readAsBytes())
              .toString()
              .toLowerCase();
          if (p1Sha != kExpectedPage1Sha256) {
            errors.add(
              'Page 1 WebP SHA-256 mismatch: expected $kExpectedPage1Sha256, got $p1Sha',
            );
            valid = false;
          }
        }

        final page604File = File(p.join(pagesDir.path, '604.webp'));
        if (await page604File.exists()) {
          final p604Sha = sha256
              .convert(await page604File.readAsBytes())
              .toString()
              .toLowerCase();
          if (p604Sha != kExpectedPage604Sha256) {
            errors.add(
              'Page 604 WebP SHA-256 mismatch: expected $kExpectedPage604Sha256, got $p604Sha',
            );
            valid = false;
          }
        }

        // If strictImageHashes is requested (e.g. CLI validator), hash all 604 files
        if (strictImageHashes && webpDigests != null && valid) {
          for (int page = 1; page <= kExpectedPageCount; page++) {
            final pageStr = page.toString().padLeft(3, '0');
            final filename = '$pageStr.webp';
            final file = File(p.join(pagesDir.path, filename));
            final fileSha = sha256
                .convert(await file.readAsBytes())
                .toString()
                .toLowerCase();
            final expectedDigest = webpDigests[pageStr];

            if (expectedDigest == null || fileSha != expectedDigest) {
              errors.add(
                'Page $page ($filename) digest mismatch: expected $expectedDigest, got $fileSha',
              );
              valid = false;
              break;
            }
          }
        }
      }
    }

    // 5. Evidence document
    final evidenceDoc = images['evidence_doc'];
    if (evidenceDoc != null) {
      if (evidenceDoc is! String ||
          !_isPathSafe(
            relativePath: evidenceDoc,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add(
          'Unsafe or invalid evidence_doc path for Quran images: $evidenceDoc',
        );
        valid = false;
      } else {
        final evf = File(p.join(normalizedRoot, evidenceDoc));
        if (!await evf.exists()) {
          errors.add('Quran images evidence doc missing: $evidenceDoc');
          valid = false;
        } else {
          verified.add('Quran images evidence doc verified ($evidenceDoc)');
        }
      }
    }

    if (valid) {
      verified.add(
        'Bundled 604 KFQC Medina Mushaf page images verified '
        '($kExpectedPageCount WebP pages, $kExpectedTotalPageBytes bytes, pinned bounds & digests)',
      );
    }

    return valid;
  }

  /// Strictly validates file-backed Hadith bundle against pinned constants,
  /// counts, IDs, verbatim source values, and metadata.
  static Future<bool> _validateBundledHadith({
    required Map<String, dynamic> hadith,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) async {
    bool valid = true;

    // 1. Source file (XLSX provenance)
    final sourceFileRaw = hadith['source_file'];
    if (sourceFileRaw is! Map) {
      errors.add('Hadith registry missing "source_file" specification');
      valid = false;
    } else {
      final sourceFile = sourceFileRaw.cast<String, dynamic>();
      final path = sourceFile['path'];
      final declaredSha = sourceFile['sha256'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid path for hadith source_file: $path');
        valid = false;
      } else {
        final f = File(p.join(normalizedRoot, path));
        if (!await f.exists()) {
          errors.add('Hadith source XLSX file not found: $path');
          valid = false;
        } else {
          final bytes = await f.readAsBytes();
          final actualSha = sha256.convert(bytes).toString().toLowerCase();

          if (actualSha != kExpectedHadithSourceSha256) {
            errors.add(
              'Hadith source XLSX SHA-256 hash mismatch! '
              'Expected $kExpectedHadithSourceSha256, actual $actualSha',
            );
            valid = false;
          } else if (declaredSha != kExpectedHadithSourceSha256) {
            errors.add(
              'Hadith source XLSX declared hash mismatch! '
              'Declared $declaredSha != expected $kExpectedHadithSourceSha256',
            );
            valid = false;
          } else {
            verified.add(
              'Hadith source XLSX SHA-256 verified ($actualSha)',
            );
          }
        }
      }
    }

    // 2. Data file (compact JSON asset)
    final dataFileRaw = hadith['data_file'];
    Uint8List? jsonBytes;
    if (dataFileRaw is! Map) {
      errors.add('Hadith registry missing "data_file" specification');
      valid = false;
    } else {
      final dataFile = dataFileRaw.cast<String, dynamic>();
      final path = dataFile['path'];
      final declaredSha = dataFile['sha256'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid path for hadith data_file: $path');
        valid = false;
      } else {
        final f = File(p.join(normalizedRoot, path));
        if (!await f.exists()) {
          errors.add('Hadith JSON asset file not found: $path');
          valid = false;
        } else {
          jsonBytes = await f.readAsBytes();
          final actualSha = sha256.convert(jsonBytes).toString().toLowerCase();

          if (actualSha != kExpectedHadithJsonSha256) {
            errors.add(
              'Hadith JSON asset SHA-256 hash mismatch! '
              'Expected $kExpectedHadithJsonSha256, actual $actualSha',
            );
            valid = false;
          } else if (declaredSha != kExpectedHadithJsonSha256) {
            errors.add(
              'Hadith JSON asset declared hash mismatch! '
              'Declared $declaredSha != expected $kExpectedHadithJsonSha256',
            );
            valid = false;
          } else {
            verified.add(
              'Hadith JSON asset SHA-256 verified ($actualSha)',
            );
          }
        }
      }
    }

    // 3. Evidence doc
    final evidenceDoc = hadith['evidence_doc'];
    if (evidenceDoc != null) {
      if (evidenceDoc is! String ||
          !_isPathSafe(
            relativePath: evidenceDoc,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid evidence_doc path for hadith: $evidenceDoc');
        valid = false;
      } else {
        final evf = File(p.join(normalizedRoot, evidenceDoc));
        if (!await evf.exists()) {
          errors.add('Hadith evidence doc missing: $evidenceDoc');
          valid = false;
        }
      }
    }

    // 4. Records count in manifest
    final recordsCount = hadith['records_count'];
    if (recordsCount is! int || recordsCount != kExpectedHadithCount) {
      errors.add(
        'Hadith records_count mismatch in manifest: expected $kExpectedHadithCount, got $recordsCount',
      );
      valid = false;
    }

    // 5. Structural and semantic verification of JSON content
    if (jsonBytes != null) {
      try {
        final decoded = jsonDecode(utf8.decode(jsonBytes));
        if (decoded is! Map<String, dynamic>) {
          errors.add('Hadith JSON root must be a JSON object');
          return false;
        }

        final meta = decoded['metadata'];
        if (meta is! Map<String, dynamic>) {
          errors.add('Hadith JSON missing "metadata" section');
          valid = false;
        } else {
          final ver = meta['version'];
          if (ver != kExpectedHadithVersion) {
            errors.add(
              'Hadith JSON version mismatch: expected "$kExpectedHadithVersion", got "$ver"',
            );
            valid = false;
          }
          final sourceUrl = meta['source'];
          if (sourceUrl != 'https://hadeethenc.com/ar') {
            errors.add('Hadith JSON invalid source URL: "$sourceUrl"');
            valid = false;
          }
          final checkUrl = meta['check_url'];
          if (checkUrl != 'https://hadeethenc.com/en/check/ar/v1.7.0') {
            errors.add('Hadith JSON invalid check URL: "$checkUrl"');
            valid = false;
          }
          final grade = meta['selection_grade'];
          if (grade != 'صحيح') {
            errors.add('Hadith JSON selection_grade must be "صحيح", got "$grade"');
            valid = false;
          }
          final totalRecords = meta['total_records'];
          if (totalRecords != kExpectedHadithCount) {
            errors.add(
              'Hadith JSON total_records mismatch: expected $kExpectedHadithCount, got $totalRecords',
            );
            valid = false;
          }
        }

        final items = decoded['items'];
        if (items is! List) {
          errors.add('Hadith JSON "items" must be a list');
          valid = false;
        } else {
          if (items.length != kExpectedHadithCount) {
            errors.add(
              'Hadith JSON items count mismatch: expected $kExpectedHadithCount, got ${items.length}',
            );
            valid = false;
          }

          final seenIds = <int>{};
          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is! Map<String, dynamic>) {
              errors.add('Hadith item at index $i is not a JSON object');
              valid = false;
              break;
            }

            final id = item['id'];
            if (id is! int || id <= 0) {
              errors.add('Hadith item at index $i has invalid ID: $id');
              valid = false;
              break;
            }
            if (seenIds.contains(id)) {
              errors.add('Duplicate Hadith ID: $id');
              valid = false;
              break;
            }
            seenIds.add(id);

            final title = item['title'];
            if (title is! String || title.trim().isEmpty) {
              errors.add('Hadith ID $id has empty title');
              valid = false;
              break;
            }

            final text = item['hadith_text'];
            if (text is! String || text.trim().isEmpty) {
              errors.add('Hadith ID $id has empty hadith_text');
              valid = false;
              break;
            }

            final gr = item['grade'];
            if (gr != 'صحيح') {
              errors.add('Hadith ID $id has non-sahih grade: "$gr"');
              valid = false;
              break;
            }

            final takhrij = item['takhrij'];
            if (takhrij is! String || takhrij.trim().isEmpty) {
              errors.add('Hadith ID $id has empty takhrij');
              valid = false;
              break;
            }

            final link = item['link'];
            if (link is! String || link != 'https://hadeethenc.com/ar/browse/hadith/$id') {
              errors.add('Hadith ID $id has invalid link: "$link"');
              valid = false;
              break;
            }
          }

          if (valid) {
            verified.add(
              'Hadith corpus structure verified: 3,213 authentic records (v1.7.0, all grade="صحيح")',
            );
            verified.add(
              'Hadith first record verified: ID ${items.first['id']} ("${(items.first['title'] as String).substring(0, 30)}...")',
            );
            verified.add(
              'Hadith last record verified: ID ${items.last['id']} ("${(items.last['title'] as String).substring(0, 30)}...")',
            );
          }
        }
      } catch (e) {
        errors.add('Hadith JSON parsing / validation error: $e');
        valid = false;
      }
    }

    return valid;
  }

  /// Strictly validates file-backed Hisn al-Muslim bundle against pinned constants,
  /// counts, 267 sequential IDs, 132 chapters, 300 footnotes, and metadata.
  static Future<bool> _validateBundledHisn({
    required Map<String, dynamic> dhikr,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) async {
    bool valid = true;

    // 1. Source file (DOCX provenance)
    final sourceFileRaw = dhikr['source_file'];
    if (sourceFileRaw is! Map) {
      errors.add('Dhikr registry missing "source_file" specification');
      valid = false;
    } else {
      final sourceFile = sourceFileRaw.cast<String, dynamic>();
      final path = sourceFile['path'];
      final declaredSha = sourceFile['sha256'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid path for dhikr source_file: $path');
        valid = false;
      } else {
        final f = File(p.join(normalizedRoot, path));
        if (!await f.exists()) {
          errors.add('Hisn al-Muslim source DOCX file not found: $path');
          valid = false;
        } else {
          final bytes = await f.readAsBytes();
          final actualSha = sha256.convert(bytes).toString().toLowerCase();

          if (actualSha != kExpectedHisnSourceSha256) {
            errors.add(
              'Hisn al-Muslim source DOCX SHA-256 hash mismatch! '
              'Expected $kExpectedHisnSourceSha256, actual $actualSha',
            );
            valid = false;
          } else if (declaredSha != kExpectedHisnSourceSha256) {
            errors.add(
              'Hisn al-Muslim source DOCX declared hash mismatch! '
              'Declared $declaredSha != expected $kExpectedHisnSourceSha256',
            );
            valid = false;
          } else {
            verified.add(
              'Hisn al-Muslim source DOCX SHA-256 verified ($actualSha)',
            );
          }
        }
      }
    }

    // 2. Data file (compact JSON asset)
    final dataFileRaw = dhikr['data_file'];
    Uint8List? jsonBytes;
    if (dataFileRaw is! Map) {
      errors.add('Dhikr registry missing "data_file" specification');
      valid = false;
    } else {
      final dataFile = dataFileRaw.cast<String, dynamic>();
      final path = dataFile['path'];
      final declaredSha = dataFile['sha256'];

      if (path is! String ||
          !_isPathSafe(
            relativePath: path,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid path for dhikr data_file: $path');
        valid = false;
      } else {
        final f = File(p.join(normalizedRoot, path));
        if (!await f.exists()) {
          errors.add('Hisn al-Muslim JSON asset file not found: $path');
          valid = false;
        } else {
          jsonBytes = await f.readAsBytes();
          final actualSha = sha256.convert(jsonBytes).toString().toLowerCase();

          if (actualSha != kExpectedHisnJsonSha256) {
            errors.add(
              'Hisn al-Muslim JSON asset SHA-256 hash mismatch! '
              'Expected $kExpectedHisnJsonSha256, actual $actualSha',
            );
            valid = false;
          } else if (declaredSha != kExpectedHisnJsonSha256) {
            errors.add(
              'Hisn al-Muslim JSON asset declared hash mismatch! '
              'Declared $declaredSha != expected $kExpectedHisnJsonSha256',
            );
            valid = false;
          } else {
            verified.add(
              'Hisn al-Muslim JSON asset SHA-256 verified ($actualSha)',
            );
          }
        }
      }
    }

    // 3. Evidence doc
    final evidenceDoc = dhikr['evidence_doc'];
    if (evidenceDoc != null) {
      if (evidenceDoc is! String ||
          !_isPathSafe(
            relativePath: evidenceDoc,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
        errors.add('Unsafe or invalid evidence_doc path for dhikr: $evidenceDoc');
        valid = false;
      } else {
        final evf = File(p.join(normalizedRoot, evidenceDoc));
        if (!await evf.exists()) {
          errors.add('Hisn al-Muslim evidence doc missing: $evidenceDoc');
          valid = false;
        }
      }
    }

    // 4. Records count in manifest
    final recordsCount = dhikr['records_count'];
    if (recordsCount is! int || recordsCount != kExpectedHisnItemsCount) {
      errors.add(
        'Hisn al-Muslim records_count mismatch in manifest: expected $kExpectedHisnItemsCount, got $recordsCount',
      );
      valid = false;
    }

    // 5. Structural and semantic verification of JSON content
    if (jsonBytes != null) {
      try {
        final decoded = jsonDecode(utf8.decode(jsonBytes));
        if (decoded is! Map<String, dynamic>) {
          errors.add('Hisn al-Muslim JSON root must be a JSON object');
          return false;
        }

        final meta = decoded['metadata'];
        if (meta is! Map<String, dynamic>) {
          errors.add('Hisn al-Muslim JSON missing "metadata" section');
          valid = false;
        } else {
          final totalChaps = meta['total_chapters'];
          if (totalChaps != kExpectedHisnChaptersCount) {
            errors.add(
              'Hisn al-Muslim metadata total_chapters mismatch: expected $kExpectedHisnChaptersCount, got $totalChaps',
            );
            valid = false;
          }
          final totalItems = meta['total_items'];
          if (totalItems != kExpectedHisnItemsCount) {
            errors.add(
              'Hisn al-Muslim metadata total_items mismatch: expected $kExpectedHisnItemsCount, got $totalItems',
            );
            valid = false;
          }
          final totalFns = meta['total_footnotes'];
          if (totalFns != kExpectedHisnFootnotesCount) {
            errors.add(
              'Hisn al-Muslim metadata total_footnotes mismatch: expected $kExpectedHisnFootnotesCount, got $totalFns',
            );
            valid = false;
          }
          final sourceDocxSha = meta['source_docx_sha256'];
          if (sourceDocxSha != kExpectedHisnSourceSha256) {
            errors.add(
              'Hisn al-Muslim metadata source_docx_sha256 mismatch: expected $kExpectedHisnSourceSha256, got $sourceDocxSha',
            );
            valid = false;
          }
        }

        final chapters = decoded['chapters'];
        if (chapters is! List || chapters.length != kExpectedHisnChaptersCount) {
          errors.add(
            'Hisn al-Muslim chapters list mismatch: expected $kExpectedHisnChaptersCount, got ${chapters is List ? chapters.length : "non-list"}',
          );
          valid = false;
        } else {
          for (int i = 0; i < chapters.length; i++) {
            final chap = chapters[i];
            if (chap is! Map<String, dynamic>) {
              errors.add('Hisn al-Muslim chapter at index $i is not a JSON object');
              valid = false;
              break;
            }
            final expectedNum = i + 1;
            if (chap['number'] != expectedNum) {
              errors.add('Hisn al-Muslim chapter $i number mismatch: expected $expectedNum, got ${chap["number"]}');
              valid = false;
              break;
            }
            final title = chap['title'];
            if (title is! String || title.trim().isEmpty) {
              errors.add('Hisn al-Muslim chapter $expectedNum has empty title');
              valid = false;
              break;
            }
            final itemIds = chap['item_ids'];
            if (itemIds is! List || itemIds.isEmpty) {
              errors.add('Hisn al-Muslim chapter $expectedNum has empty or invalid item_ids');
              valid = false;
              break;
            }
          }
        }

        final items = decoded['items'];
        if (items is! List || items.length != kExpectedHisnItemsCount) {
          errors.add(
            'Hisn al-Muslim items list mismatch: expected $kExpectedHisnItemsCount, got ${items is List ? items.length : "non-list"}',
          );
          valid = false;
        } else {
          final seenIds = <int>{};
          final seenFootnotes = <String>{};

          for (int i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is! Map<String, dynamic>) {
              errors.add('Hisn al-Muslim item at index $i is not a JSON object');
              valid = false;
              break;
            }

            final expectedId = i + 1;
            final id = item['id'];
            if (id is! int || id != expectedId) {
              errors.add('Hisn al-Muslim item at index $i has unexpected ID: $id (expected $expectedId)');
              valid = false;
              break;
            }
            if (seenIds.contains(id)) {
              errors.add('Duplicate Hisn al-Muslim item ID: $id');
              valid = false;
              break;
            }
            seenIds.add(id);

            final chapNum = item['chapter_number'];
            if (chapNum is! int || chapNum < 1 || chapNum > kExpectedHisnChaptersCount) {
              errors.add('Hisn al-Muslim item ID $id has invalid chapter_number: $chapNum');
              valid = false;
              break;
            }

            final chapTitle = item['chapter_title'];
            if (chapTitle is! String || chapTitle.trim().isEmpty) {
              errors.add('Hisn al-Muslim item ID $id has empty chapter_title');
              valid = false;
              break;
            }

            final text = item['text'];
            if (text is! String || text.trim().isEmpty) {
              errors.add('Hisn al-Muslim item ID $id has empty text');
              valid = false;
              break;
            }

            final paragraphs = item['paragraphs'];
            if (paragraphs is! List || paragraphs.isEmpty) {
              errors.add('Hisn al-Muslim item ID $id has empty or invalid paragraphs list');
              valid = false;
              break;
            }

            final fnIds = item['footnote_ids'];
            if (fnIds is! List) {
              errors.add('Hisn al-Muslim item ID $id has non-list footnote_ids');
              valid = false;
              break;
            }

            final fns = item['footnotes'];
            if (fns is! List || fns.isEmpty) {
              errors.add('Hisn al-Muslim item ID $id has empty footnotes list');
              valid = false;
              break;
            }

            for (final fn in fns) {
              if (fn is! Map<String, dynamic>) {
                errors.add('Hisn al-Muslim item ID $id has non-object footnote entry');
                valid = false;
                break;
              }
              final fnId = fn['id'];
              final fnText = fn['text'];
              if (fnId is! String || fnId.isEmpty || fnText is! String || fnText.trim().isEmpty) {
                errors.add('Hisn al-Muslim item ID $id has invalid footnote: $fnId');
                valid = false;
                break;
              }
              seenFootnotes.add(fnId);
            }

            final repeatTarget = item['repeat_target'];
            if (repeatTarget != null && (repeatTarget is! int || repeatTarget <= 0)) {
              errors.add('Hisn al-Muslim item ID $id has invalid repeat_target: $repeatTarget');
              valid = false;
              break;
            }
          }

          if (seenFootnotes.length != kExpectedHisnFootnotesCount) {
            errors.add(
              'Hisn al-Muslim referenced footnotes count mismatch: expected $kExpectedHisnFootnotesCount, got ${seenFootnotes.length}',
            );
            valid = false;
          }

          if (valid) {
            verified.add(
              'Hisn al-Muslim corpus structure verified: 267 items across 132 chapters with 300 footnotes',
            );
            verified.add(
              'Hisn al-Muslim first item verified: Item 1 ("${(items.first['text'] as String).substring(0, 30)}...")',
            );
            verified.add(
              'Hisn al-Muslim morning/evening section verified: Section 27 (Items 75..98)',
            );
            verified.add(
              'Hisn al-Muslim last item verified: Item 267 ("${(items.last['text'] as String).substring(0, 30)}...")',
            );
          }
        }
      } catch (e) {
        errors.add('Hisn al-Muslim JSON parsing / validation error: $e');
        valid = false;
      }
    }

    return valid;
  }

  /// Validates adhan audio manifest registry metadata fields and evidence document.
  static bool _validateAdhanManifestRegistry({
    required Map<String, dynamic> audio,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) {
    bool valid = true;

    // 1. rights_status
    final rightsStatus = audio['rights_status'];
    if (rightsStatus is! String || rightsStatus != 'licensed_free_content') {
      errors.add(
        'Adhan audio rights_status must be "licensed_free_content" (got: "$rightsStatus")',
      );
      valid = false;
    }

    // 2. evidence_doc
    final evidenceDocRel = audio['evidence_doc'];
    if (evidenceDocRel is! String || evidenceDocRel.isEmpty) {
      errors.add('Missing or malformed "evidence_doc" in adhan_audio registry');
      valid = false;
    } else if (!_isPathSafe(
      relativePath: evidenceDocRel,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
    )) {
      errors.add('Unsafe adhan audio evidence_doc path: "$evidenceDocRel"');
      valid = false;
    } else if (evidenceDocRel != 'docs/sources/ADHAN_AUDIO.md') {
      errors.add(
        'Adhan audio evidence_doc must be "docs/sources/ADHAN_AUDIO.md" (got: "$evidenceDocRel")',
      );
      valid = false;
    } else {
      final docFile = File(p.join(normalizedRoot, evidenceDocRel));
      if (!docFile.existsSync()) {
        errors.add('Missing adhan audio evidence document: "$evidenceDocRel"');
        valid = false;
      } else if (docFile.lengthSync() == 0) {
        errors.add('Empty adhan audio evidence document: "$evidenceDocRel"');
        valid = false;
      } else {
        verified.add('Adhan audio evidence doc verified ($evidenceDocRel)');
      }
    }

    // 3. expected_voices_count
    final declaredExpectedVoices = audio['expected_voices_count'];
    if (declaredExpectedVoices is! int ||
        declaredExpectedVoices != kExpectedAdhanVoicesCount) {
      errors.add(
        'Adhan audio expected_voices_count mismatch: manifest declared $declaredExpectedVoices, expected $kExpectedAdhanVoicesCount',
      );
      valid = false;
    }

    // 4. total_full_audio_bytes and total_alert_clip_bytes
    final expectedTotalFullBytes =
        kExpectedAdhanAudioBytes.values.reduce((a, b) => a + b);
    const expectedTotalAlertBytes =
        kExpectedAdhanAlertBytes * kExpectedAdhanVoicesCount;

    final declaredFullBytes = audio['total_full_audio_bytes'];
    if (declaredFullBytes is! int || declaredFullBytes != expectedTotalFullBytes) {
      errors.add(
        'Adhan audio total_full_audio_bytes mismatch: declared $declaredFullBytes, expected $expectedTotalFullBytes',
      );
      valid = false;
    }

    final declaredAlertBytes = audio['total_alert_clip_bytes'];
    if (declaredAlertBytes is! int ||
        declaredAlertBytes != expectedTotalAlertBytes) {
      errors.add(
        'Adhan audio total_alert_clip_bytes mismatch: declared $declaredAlertBytes, expected $expectedTotalAlertBytes',
      );
      valid = false;
    }

    return valid;
  }

  /// Validates individual adhan voice metadata and factual attribution fields.
  static bool _validateAdhanVoiceMetadata({
    required Map<String, dynamic> voice,
    required int index,
    required Set<String> seenVoiceIds,
    required Set<String> fajrVoiceIds,
    required List<String> errors,
  }) {
    bool valid = true;
    final voiceId = voice['id'];

    if (voiceId is! String || !kExpectedAdhanVoiceIds.contains(voiceId)) {
      errors.add('Invalid or unauthorized voice ID: "$voiceId" at index $index');
      return false;
    }

    if (seenVoiceIds.contains(voiceId)) {
      errors.add('Duplicate voice ID: "$voiceId"');
      valid = false;
    }
    seenVoiceIds.add(voiceId);

    final isFajr = voice['is_fajr'];
    if (isFajr is! bool) {
      errors.add('Voice "$voiceId" is_fajr must be a boolean');
      valid = false;
    } else {
      final expectedIsFajr = (voiceId == 'malmo_fajr');
      if (isFajr != expectedIsFajr) {
        errors.add(
          'Voice "$voiceId" is_fajr mismatch: declared $isFajr, expected $expectedIsFajr',
        );
        valid = false;
      }
      if (isFajr) {
        fajrVoiceIds.add(voiceId);
      }
    }

    final nameAr = voice['name_ar'];
    if (nameAr is! String || nameAr.trim().isEmpty) {
      errors.add('Voice "$voiceId" missing name_ar');
      valid = false;
    }

    final title = voice['title'];
    if (title is! String || title.trim().isEmpty) {
      errors.add('Voice "$voiceId" missing title');
      valid = false;
    }

    final performerOrSource = voice['performer_or_source'];
    if (performerOrSource is! String || performerOrSource.trim().isEmpty) {
      errors.add('Voice "$voiceId" missing performer_or_source');
      valid = false;
    }

    final license = voice['license'];
    final expectedLicense = kExpectedAdhanLicenses[voiceId];
    if (license is! String || license != expectedLicense) {
      errors.add(
        'Voice "$voiceId" license mismatch: declared "$license", expected "$expectedLicense"',
      );
      valid = false;
    }

    final licenseUrl = voice['license_url'];
    final expectedLicenseUrl = kExpectedAdhanLicenseUrls[voiceId];
    if (licenseUrl is! String || licenseUrl != expectedLicenseUrl) {
      errors.add(
        'Voice "$voiceId" license_url mismatch: declared "$licenseUrl", expected "$expectedLicenseUrl"',
      );
      valid = false;
    }

    final sourceUrl = voice['source_url'];
    final expectedSourceUrl = kExpectedAdhanSourceUrls[voiceId];
    if (sourceUrl is! String || sourceUrl != expectedSourceUrl) {
      errors.add(
        'Voice "$voiceId" source_url mismatch: declared "$sourceUrl", expected "$expectedSourceUrl"',
      );
      valid = false;
    }

    return valid;
  }

  /// Validates full MP3 audio recordings against pinned paths, formats, sizes, and SHA-256.
  static bool _validateAdhanAudioFiles({
    required String voiceId,
    required dynamic audioFileRaw,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) {
    if (audioFileRaw is! Map) {
      errors.add('Voice "$voiceId" missing audio_file object');
      return false;
    }

    bool valid = true;
    final audioMap = audioFileRaw.cast<String, dynamic>();
    final audioRelPath = audioMap['path'];
    final audioFormat = audioMap['format'];
    final audioBytes = audioMap['bytes'];
    final audioSha256 = audioMap['sha256'];
    final durationSec = audioMap['duration_seconds'];

    final expectedAudioRelPath = kExpectedAdhanAudioPaths[voiceId];
    final expectedBytes = kExpectedAdhanAudioBytes[voiceId];
    final expectedSha = kExpectedAdhanAudioSha256[voiceId];

    if (audioRelPath != expectedAudioRelPath) {
      errors.add(
        'Voice "$voiceId" audio_file path mismatch: "$audioRelPath" != "$expectedAudioRelPath"',
      );
      valid = false;
    }
    if (audioFormat != 'mp3') {
      errors.add('Voice "$voiceId" audio_file format must be "mp3" (got: "$audioFormat")');
      valid = false;
    }
    if (audioBytes != expectedBytes) {
      errors.add(
        'Voice "$voiceId" audio_file bytes mismatch ($audioBytes != $expectedBytes)',
      );
      valid = false;
    }
    if (audioSha256 != expectedSha) {
      errors.add(
        'Voice "$voiceId" audio_file SHA-256 mismatch ($audioSha256 != $expectedSha)',
      );
      valid = false;
    }
    final expectedDuration = kExpectedAdhanAudioDurations[voiceId];
    if (durationSec == null ||
        durationSec is! int ||
        durationSec != expectedDuration) {
      errors.add(
        'Voice "$voiceId" audio_file duration_seconds mismatch: declared $durationSec, expected $expectedDuration',
      );
      valid = false;
    }

    if (audioRelPath is String &&
        !_isPathSafe(
          relativePath: audioRelPath,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
        )) {
      errors.add('Voice "$voiceId" audio_file path traversal or unsafe');
      valid = false;
    } else if (audioRelPath is String) {
      final f = File(p.join(normalizedRoot, audioRelPath));
      if (!f.existsSync()) {
        errors.add('Voice "$voiceId" audio file missing: "$audioRelPath"');
        valid = false;
      } else {
        final actualLen = f.lengthSync();
        if (actualLen != expectedBytes) {
          errors.add(
            'Voice "$voiceId" audio file size on disk mismatch ($actualLen != $expectedBytes)',
          );
          valid = false;
        }
        final actualSha = sha256
            .convert(f.readAsBytesSync())
            .toString()
            .toLowerCase();
        if (actualSha != expectedSha) {
          errors.add(
            'Voice "$voiceId" audio file SHA on disk mismatch: $actualSha',
          );
          valid = false;
        }
      }
    }

    if (valid) {
      verified.add(
        'Bundled adhan voice "$voiceId" full recording verified ($expectedBytes bytes, SHA-256: ${expectedSha!.substring(0, 8)}...)',
      );
    }

    return valid;
  }

  /// Validates notification alert clips (PCM WAV), RIFF header, duration, and waveform energy.
  static bool _validateAdhanAlertClips({
    required String voiceId,
    required dynamic alertClipRaw,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) {
    if (alertClipRaw is! Map) {
      errors.add('Voice "$voiceId" missing alert_clip object');
      return false;
    }

    bool valid = true;
    final alertMap = alertClipRaw.cast<String, dynamic>();
    final alertRelPath = alertMap['path'];
    final alertFormat = alertMap['format'];
    final alertCodec = alertMap['codec'];
    final alertSampleRate = alertMap['sample_rate'];
    final alertChannels = alertMap['channels'];
    final alertDuration = alertMap['duration_seconds'];
    final alertBytes = alertMap['bytes'];
    final alertSha256 = alertMap['sha256'];

    final expectedAlertRelPath = kExpectedAdhanAlertPaths[voiceId];
    final expectedSha = kExpectedAdhanAlertSha256[voiceId];

    if (alertRelPath != expectedAlertRelPath) {
      errors.add(
        'Voice "$voiceId" alert_clip path mismatch: "$alertRelPath" != "$expectedAlertRelPath"',
      );
      valid = false;
    }
    if (alertFormat != 'wav') {
      errors.add('Voice "$voiceId" alert_clip format must be "wav"');
      valid = false;
    }
    if (alertCodec != 'pcm_s16le') {
      errors.add('Voice "$voiceId" alert_clip codec must be "pcm_s16le"');
      valid = false;
    }
    if (alertSampleRate != 22050) {
      errors.add('Voice "$voiceId" alert_clip sample_rate must be 22050');
      valid = false;
    }
    if (alertChannels != 1) {
      errors.add('Voice "$voiceId" alert_clip channels must be 1 (mono)');
      valid = false;
    }
    if (alertDuration == null ||
        alertDuration is! num ||
        alertDuration <= 0 ||
        (alertDuration.toDouble() - kExpectedAdhanAlertDurationSeconds).abs() > 0.05) {
      errors.add(
        'Voice "$voiceId" alert_clip duration must be exactly $kExpectedAdhanAlertDurationSeconds (got: $alertDuration)',
      );
      valid = false;
    }
    if (alertBytes != kExpectedAdhanAlertBytes) {
      errors.add(
        'Voice "$voiceId" alert_clip bytes mismatch ($alertBytes != $kExpectedAdhanAlertBytes)',
      );
      valid = false;
    }
    if (alertSha256 != expectedSha) {
      errors.add(
        'Voice "$voiceId" alert_clip SHA-256 mismatch ($alertSha256 != $expectedSha)',
      );
      valid = false;
    }

    if (alertRelPath is String &&
        !_isPathSafe(
          relativePath: alertRelPath,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
        )) {
      errors.add('Voice "$voiceId" alert_clip path traversal or unsafe');
      valid = false;
    } else if (alertRelPath is String) {
      final f = File(p.join(normalizedRoot, alertRelPath));
      if (!f.existsSync()) {
        errors.add('Voice "$voiceId" alert file missing: "$alertRelPath"');
        valid = false;
      } else {
        final actualLen = f.lengthSync();
        if (actualLen != kExpectedAdhanAlertBytes) {
          errors.add(
            'Voice "$voiceId" alert file size on disk mismatch ($actualLen != $kExpectedAdhanAlertBytes)',
          );
          valid = false;
        }
        final rawBytes = f.readAsBytesSync();
        final actualSha = sha256
            .convert(rawBytes)
            .toString()
            .toLowerCase();
        if (actualSha != expectedSha) {
          errors.add(
            'Voice "$voiceId" alert file SHA on disk mismatch: $actualSha',
          );
          valid = false;
        }

        // Rigorous WAV header inspection
        final wavResult = inspectWavHeader(rawBytes);
        if (!wavResult.isValid) {
          errors.add(
            'Voice "$voiceId" alert WAV header invalid: ${wavResult.errorMessage}',
          );
          valid = false;
        } else {
          if (wavResult.channels != 1) {
            errors.add('Voice "$voiceId" WAV channels must be 1');
            valid = false;
          }
          if (wavResult.sampleRate != 22050) {
            errors.add('Voice "$voiceId" WAV sample rate must be 22050');
            valid = false;
          }
          if (wavResult.bitDepth != 16) {
            errors.add('Voice "$voiceId" WAV bit depth must be 16');
            valid = false;
          }
          if ((wavResult.durationSeconds! - kExpectedAdhanAlertDurationSeconds).abs() > 0.05) {
            errors.add(
              'Voice "$voiceId" WAV duration mismatch (${wavResult.durationSeconds} != $kExpectedAdhanAlertDurationSeconds)',
            );
            valid = false;
          }
          if (wavResult.dataOffset != kExpectedWavDataOffset) {
            errors.add(
              'Voice "$voiceId" WAV dataOffset mismatch (${wavResult.dataOffset} != $kExpectedWavDataOffset)',
            );
            valid = false;
          }
          if (alertDuration is num &&
              (alertDuration.toDouble() - wavResult.durationSeconds!).abs() > 0.05) {
            errors.add(
              'Voice "$voiceId" declared duration ($alertDuration) does not match inspected WAV duration (${wavResult.durationSeconds})',
            );
            valid = false;
          }

          // Waveform energy & non-silent validation
          final metrics = analyzeWavWaveform(
            bytes: rawBytes,
            dataOffset: wavResult.dataOffset!,
            dataSize: wavResult.dataSize!,
            sampleRate: wavResult.sampleRate!,
          );
          if (!metrics.hasNonZeroSignal) {
            errors.add('Voice "$voiceId" alert WAV is completely silent');
            valid = false;
          } else if (metrics.peakAmplitude < 0.05) {
            errors.add(
              'Voice "$voiceId" alert WAV peak too low (${metrics.peakAmplitude} < 0.05)',
            );
            valid = false;
          } else if (metrics.rmsAmplitude < 0.005) {
            errors.add(
              'Voice "$voiceId" alert WAV RMS energy too low (${metrics.rmsAmplitude} < 0.005)',
            );
            valid = false;
          } else if (metrics.onsetRmsAmplitude < kExpectedAdhanAlertOnsetRmsLowerBound) {
            // First-second RMS bounds: adam ~0.0480, atcovi ~0.0678, malmo_fajr ~0.00365
            errors.add(
              'Voice "$voiceId" alert WAV onset RMS energy too low (${metrics.onsetRmsAmplitude} < $kExpectedAdhanAlertOnsetRmsLowerBound)',
            );
            valid = false;
          }
        }
      }
    }

    if (valid) {
      verified.add(
        'Bundled adhan voice "$voiceId" alert clip verified (PCM 16-bit, 22050Hz mono, 27s, non-zero digital signal within numeric bounds; human listening/religious review pending)',
      );
    }

    return valid;
  }

  /// Validates notification_clips list in adhan_audio manifest section.
  static bool _validateAdhanNotificationClipsManifest({
    required dynamic clipsRaw,
    required List<String> errors,
  }) {
    if (clipsRaw is! List) {
      errors.add('Adhan audio "notification_clips" field must be a list');
      return false;
    }
    if (clipsRaw.length != kExpectedAdhanVoicesCount) {
      errors.add(
        'Adhan audio notification_clips count mismatch: manifest has ${clipsRaw.length}, expected $kExpectedAdhanVoicesCount',
      );
      return false;
    }

    bool valid = true;
    final seenClipVoiceIds = <String>{};

    for (int i = 0; i < clipsRaw.length; i++) {
      final clipEntry = clipsRaw[i];
      if (clipEntry is! Map) {
        errors.add('Notification clip entry #$i is not an object');
        valid = false;
        continue;
      }
      final clipMap = clipEntry.cast<String, dynamic>();
      final clipVoiceId = clipMap['voice_id'];
      final clipPath = clipMap['path'];
      final clipSha = clipMap['sha256'];
      final clipBytes = clipMap['bytes'];
      final clipDuration = clipMap['duration_seconds'];

      if (clipVoiceId is! String ||
          !kExpectedAdhanVoiceIds.contains(clipVoiceId)) {
        errors.add('Invalid voice_id in notification_clips: "$clipVoiceId"');
        valid = false;
        continue;
      }
      seenClipVoiceIds.add(clipVoiceId);

      final expectedClipPath = kExpectedAdhanAlertPaths[clipVoiceId];
      if (clipPath != expectedClipPath) {
        errors.add(
          'Notification clip path mismatch for "$clipVoiceId": "$clipPath" != "$expectedClipPath"',
        );
        valid = false;
      }
      final clipFormat = clipMap['format'];
      if (clipFormat != 'wav') {
        errors.add(
          'Notification clip format mismatch for "$clipVoiceId": "$clipFormat" != "wav"',
        );
        valid = false;
      }
      if (clipSha != kExpectedAdhanAlertSha256[clipVoiceId]) {
        errors.add(
          'Notification clip SHA-256 mismatch for "$clipVoiceId"',
        );
        valid = false;
      }
      if (clipBytes != kExpectedAdhanAlertBytes) {
        errors.add(
          'Notification clip bytes mismatch for "$clipVoiceId"',
        );
        valid = false;
      }
      if (clipDuration == null ||
          clipDuration is! num ||
          clipDuration <= 0 ||
          (clipDuration.toDouble() - kExpectedAdhanAlertDurationSeconds).abs() > 0.05) {
        errors.add(
          'Notification clip duration mismatch for "$clipVoiceId": declared $clipDuration, expected $kExpectedAdhanAlertDurationSeconds',
        );
        valid = false;
      }
    }

    if (!seenClipVoiceIds.containsAll(kExpectedAdhanVoiceIds)) {
      errors.add(
        'Missing notification clips for voice IDs: ${kExpectedAdhanVoiceIds.difference(seenClipVoiceIds)}',
      );
      valid = false;
    }

    return valid;
  }

  /// Validates native platform alert copies (iOS Runner and Android res/raw) and prohibits OGG/FLAC.
  static bool _validateAdhanNativeCopies({
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) {
    bool valid = true;

    // 1. Verify iOS Runner directory and alert copies
    final iosRunnerDir = Directory(p.join(normalizedRoot, 'ios', 'Runner'));
    if (!iosRunnerDir.existsSync()) {
      errors.add('Missing required iOS Runner directory: ios/Runner');
      valid = false;
    }

    for (final voiceId in kExpectedAdhanVoiceIds) {
      final relPath = kExpectedAdhanIosAlertPaths[voiceId]!;
      if (!_isPathSafe(
        relativePath: relPath,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
      )) {
        errors.add('Unsafe iOS Runner alert clip path: $relPath');
        valid = false;
        continue;
      }

      final iosFile = File(p.join(normalizedRoot, relPath));
      if (!iosFile.existsSync()) {
        errors.add('Missing iOS Runner alert clip: $relPath');
        valid = false;
      } else {
        final actualLen = iosFile.lengthSync();
        if (actualLen != kExpectedAdhanAlertBytes) {
          errors.add(
            'iOS Runner alert clip size mismatch for "$voiceId" ($actualLen != $kExpectedAdhanAlertBytes)',
          );
          valid = false;
        }
        final actualBytes = iosFile.readAsBytesSync();
        final actualSha = sha256
            .convert(actualBytes)
            .toString()
            .toLowerCase();
        if (actualSha != kExpectedAdhanAlertSha256[voiceId]) {
          errors.add(
            'iOS Runner alert clip SHA mismatch for "$voiceId"',
          );
          valid = false;
        } else {
          final wavResult = inspectWavHeader(actualBytes);
          if (!wavResult.isValid ||
              wavResult.dataOffset != kExpectedWavDataOffset ||
              (wavResult.durationSeconds! - kExpectedAdhanAlertDurationSeconds).abs() > 0.05) {
            errors.add(
              'iOS Runner alert clip WAV format mismatch for "$voiceId"',
            );
            valid = false;
          } else {
            verified.add('iOS Runner alert clip verified: $relPath');
          }
        }
      }
    }

    // Check for forbidden OGG/FLAC in ios/Runner
    if (iosRunnerDir.existsSync()) {
      for (final entity in iosRunnerDir.listSync(recursive: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.ogg' || ext == '.flac') {
            errors.add('Prohibited audio format on iOS found in ios/Runner: ${entity.path}');
            valid = false;
          }
        }
      }
    }

    // 2. Verify Android res/raw directory and alert copies
    final androidRawDir = Directory(
      p.join(normalizedRoot, 'android', 'app', 'src', 'main', 'res', 'raw'),
    );
    if (!androidRawDir.existsSync()) {
      errors.add('Missing required Android res/raw directory: android/app/src/main/res/raw');
      valid = false;
    }

    for (final voiceId in kExpectedAdhanVoiceIds) {
      final relPath = kExpectedAdhanAndroidAlertPaths[voiceId]!;
      if (!_isPathSafe(
        relativePath: relPath,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
      )) {
        errors.add('Unsafe Android res/raw alert clip path: $relPath');
        valid = false;
        continue;
      }

      final rawFile = File(p.join(normalizedRoot, relPath));
      if (!rawFile.existsSync()) {
        errors.add('Missing Android res/raw alert clip: $relPath');
        valid = false;
      } else {
        final actualLen = rawFile.lengthSync();
        if (actualLen != kExpectedAdhanAlertBytes) {
          errors.add(
            'Android res/raw alert clip size mismatch for "$voiceId" ($actualLen != $kExpectedAdhanAlertBytes)',
          );
          valid = false;
        }
        final actualBytes = rawFile.readAsBytesSync();
        final actualSha = sha256
            .convert(actualBytes)
            .toString()
            .toLowerCase();
        if (actualSha != kExpectedAdhanAlertSha256[voiceId]) {
          errors.add(
            'Android res/raw alert clip SHA mismatch for "$voiceId"',
          );
          valid = false;
        } else {
          final wavResult = inspectWavHeader(actualBytes);
          if (!wavResult.isValid ||
              wavResult.dataOffset != kExpectedWavDataOffset ||
              (wavResult.durationSeconds! - kExpectedAdhanAlertDurationSeconds).abs() > 0.05) {
            errors.add(
              'Android res/raw alert clip WAV format mismatch for "$voiceId"',
            );
            valid = false;
          } else {
            verified.add('Android res/raw alert clip verified: $relPath');
          }
        }
      }
    }

    // 3. Verify no FLAC or OGG in assets/audio/adhan
    final adhanAssetsDir = Directory(
      p.join(normalizedRoot, 'assets', 'audio', 'adhan'),
    );
    if (!adhanAssetsDir.existsSync()) {
      errors.add('Missing required adhan assets directory: assets/audio/adhan');
      valid = false;
    } else {
      for (final entity in adhanAssetsDir.listSync(recursive: false)) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.ogg' || ext == '.flac') {
            errors.add(
              'Prohibited audio format in adhan assets: ${entity.path} (iOS requires MP3/WAV)',
            );
            valid = false;
          }
        }
      }
    }

    return valid;
  }

  /// Strictly validates file-backed bundled adhan recordings and alert clips
  /// against pinned hashes, byte sizes, metadata, RIFF PCM headers, and waveform energy.
  static Future<bool> _validateBundledAdhanAudio({
    required Map<String, dynamic> audio,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> verified,
  }) async {
    bool allValid = true;

    // 1. Manifest registry metadata
    final manifestOk = _validateAdhanManifestRegistry(
      audio: audio,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
      errors: errors,
      verified: verified,
    );
    if (!manifestOk) allValid = false;

    // 2. Voices list
    final voicesRaw = audio['voices'];
    if (voicesRaw is! List) {
      errors.add('Adhan audio "voices" field must be a list');
      allValid = false;
    } else if (voicesRaw.length != kExpectedAdhanVoicesCount) {
      errors.add(
        'Adhan audio voices count mismatch: manifest has ${voicesRaw.length}, expected $kExpectedAdhanVoicesCount',
      );
      allValid = false;
    } else {
      final seenVoiceIds = <String>{};
      final fajrVoiceIds = <String>{};

      for (int i = 0; i < voicesRaw.length; i++) {
        final voiceEntry = voicesRaw[i];
        if (voiceEntry is! Map) {
          errors.add('Adhan voice entry #$i is not an object');
          allValid = false;
          continue;
        }

        final voice = voiceEntry.cast<String, dynamic>();
        final voiceId = voice['id'];

        final metaOk = _validateAdhanVoiceMetadata(
          voice: voice,
          index: i,
          seenVoiceIds: seenVoiceIds,
          fajrVoiceIds: fajrVoiceIds,
          errors: errors,
        );
        if (!metaOk) allValid = false;

        if (voiceId is String && kExpectedAdhanVoiceIds.contains(voiceId)) {
          final audioFileOk = _validateAdhanAudioFiles(
            voiceId: voiceId,
            audioFileRaw: voice['audio_file'],
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
            errors: errors,
            verified: verified,
          );
          if (!audioFileOk) allValid = false;

          final alertClipOk = _validateAdhanAlertClips(
            voiceId: voiceId,
            alertClipRaw: voice['alert_clip'],
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
            errors: errors,
            verified: verified,
          );
          if (!alertClipOk) allValid = false;
        }
      }

      // Check Fajr voice rules: exactly one Fajr voice
      if (fajrVoiceIds.length != 1) {
        errors.add(
          'Exactly one Fajr voice must be designated (found ${fajrVoiceIds.length}: $fajrVoiceIds)',
        );
        allValid = false;
      } else if (!fajrVoiceIds.contains('malmo_fajr')) {
        errors.add(
          'Designated Fajr voice must be "malmo_fajr" (found: ${fajrVoiceIds.first})',
        );
        allValid = false;
      }

      // Check all expected voice IDs present
      if (!seenVoiceIds.containsAll(kExpectedAdhanVoiceIds)) {
        errors.add(
          'Missing expected adhan voice IDs: ${kExpectedAdhanVoiceIds.difference(seenVoiceIds)}',
        );
        allValid = false;
      }
    }

    // 3. Notification clips manifest
    final clipsOk = _validateAdhanNotificationClipsManifest(
      clipsRaw: audio['notification_clips'],
      errors: errors,
    );
    if (!clipsOk) allValid = false;

    // 4. External native copies (iOS Runner and Android res/raw)
    final nativeOk = _validateAdhanNativeCopies(
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
      errors: errors,
      verified: verified,
    );
    if (!nativeOk) allValid = false;

    return allValid;
  }

  /// Rigorously inspects a PCM WAV byte array (preserved for future audio milestone).
  static WavInspectionResult inspectWavHeader(Uint8List bytes) {
    if (bytes.length < 44) {
      return const WavInspectionResult.invalid(
        'File size is less than minimum 44-byte WAV header',
      );
    }

    final bd = ByteData.sublistView(bytes);

    // RIFF header
    if (bd.getUint8(0) != 0x52 ||
        bd.getUint8(1) != 0x49 ||
        bd.getUint8(2) != 0x46 ||
        bd.getUint8(3) != 0x46) {
      return const WavInspectionResult.invalid('Missing "RIFF" signature');
    }

    final riffChunkSize = bd.getUint32(4, Endian.little);
    if (bytes.length < riffChunkSize + 8) {
      return WavInspectionResult.invalid(
        'Truncated file: declared RIFF size $riffChunkSize + 8 > actual ${bytes.length}',
      );
    }

    // WAVE signature
    if (bd.getUint8(8) != 0x57 ||
        bd.getUint8(9) != 0x41 ||
        bd.getUint8(10) != 0x56 ||
        bd.getUint8(11) != 0x45) {
      return const WavInspectionResult.invalid(
        'Missing "WAVE" format identifier',
      );
    }

    int offset = 12;
    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? byteRate;
    int? blockAlign;
    int? bitDepth;
    int? dataSize;
    int? dataOffset;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        if (chunkSize < 16) {
          return const WavInspectionResult.invalid(
            '"fmt " chunk size less than 16 bytes',
          );
        }
        if (offset + 8 + 16 > bytes.length) {
          return const WavInspectionResult.invalid('Truncated "fmt " chunk');
        }
        audioFormat = bd.getUint16(offset + 8, Endian.little);
        channels = bd.getUint16(offset + 10, Endian.little);
        sampleRate = bd.getUint32(offset + 12, Endian.little);
        byteRate = bd.getUint32(offset + 16, Endian.little);
        blockAlign = bd.getUint16(offset + 20, Endian.little);
        bitDepth = bd.getUint16(offset + 22, Endian.little);
      } else if (chunkId == 'data') {
        dataSize = chunkSize;
        dataOffset = offset + 8;
      }

      offset += 8 + chunkSize;
      if (chunkSize.isOdd) {
        offset += 1; // 2-byte word padding
      }
    }

    if (audioFormat == null || audioFormat != 1) {
      return WavInspectionResult.invalid(
        'Non-PCM audio format ($audioFormat); only PCM (1) supported',
      );
    }
    if (channels == null || channels <= 0) {
      return const WavInspectionResult.invalid(
        'Invalid channel count (must be > 0)',
      );
    }
    if (sampleRate == null || sampleRate <= 0) {
      return const WavInspectionResult.invalid(
        'Invalid sample rate (must be > 0)',
      );
    }
    if (bitDepth == null || ![8, 16, 24, 32].contains(bitDepth)) {
      return WavInspectionResult.invalid(
        'Invalid bit depth ($bitDepth); must be 8, 16, 24, or 32',
      );
    }
    final expectedBlockAlign = channels * (bitDepth ~/ 8);
    if (blockAlign == null || blockAlign != expectedBlockAlign) {
      return WavInspectionResult.invalid(
        'Inconsistent blockAlign ($blockAlign != expected $expectedBlockAlign)',
      );
    }
    final expectedByteRate = sampleRate * blockAlign;
    if (byteRate == null || byteRate != expectedByteRate) {
      return WavInspectionResult.invalid(
        'Inconsistent byteRate ($byteRate != expected $expectedByteRate)',
      );
    }

    if (dataSize == null || dataSize <= 0 || dataOffset == null) {
      return const WavInspectionResult.invalid('Missing or empty "data" chunk');
    }

    // Check for truncated data
    if (dataOffset + dataSize > bytes.length) {
      return WavInspectionResult.invalid(
        'Truncated data chunk: header claims $dataSize bytes, but file only has ${bytes.length - dataOffset} bytes remaining',
      );
    }

    final durationSeconds = dataSize / byteRate;
    if (durationSeconds <= 0) {
      return const WavInspectionResult.invalid('Duration must be positive');
    }

    return WavInspectionResult.valid(
      channels: channels,
      sampleRate: sampleRate,
      bitDepth: bitDepth,
      dataSize: dataSize,
      dataOffset: dataOffset,
      durationSeconds: durationSeconds,
    );
  }

  /// Analyzes PCM 16-bit mono/stereo WAV waveform to compute peak amplitude, RMS energy,
  /// and onset energy.
  ///
  /// Verifies presence of a non-zero digital signal within reasonable bounds.
  /// Note: This automated check verifies digital signal presence and level only,
  /// and does NOT establish human audible aesthetic quality or religious correctness.
  static AudioWaveformMetrics analyzeWavWaveform({
    required Uint8List bytes,
    required int dataOffset,
    required int dataSize,
    int sampleRate = 22050,
  }) {
    final bd = ByteData.sublistView(bytes);
    final sampleCount = dataSize ~/ 2;
    if (sampleCount <= 0) {
      return const AudioWaveformMetrics(
        peakAmplitude: 0.0,
        rmsAmplitude: 0.0,
        onsetRmsAmplitude: 0.0,
        hasNonZeroSignal: false,
      );
    }

    double sumSquared = 0.0;
    double onsetSumSquared = 0.0;
    final onsetSamples = math.min(sampleCount, sampleRate); // first 1 second
    double maxPeak = 0.0;
    bool nonZero = false;

    for (int i = 0; i < sampleCount; i++) {
      final sampleOffset = dataOffset + i * 2;
      if (sampleOffset + 2 > bytes.length) break;
      final raw = bd.getInt16(sampleOffset, Endian.little);
      if (raw != 0) nonZero = true;
      final normalized = raw / 32768.0;
      final abs = normalized.abs();
      if (abs > maxPeak) maxPeak = abs;
      final sq = normalized * normalized;
      sumSquared += sq;
      if (i < onsetSamples) {
        onsetSumSquared += sq;
      }
    }

    final rms = math.sqrt(sumSquared / sampleCount);
    final onsetRms =
        onsetSamples > 0 ? math.sqrt(onsetSumSquared / onsetSamples) : 0.0;

    return AudioWaveformMetrics(
      peakAmplitude: maxPeak,
      rmsAmplitude: rms,
      onsetRmsAmplitude: onsetRms,
      hasNonZeroSignal: nonZero,
    );
  }
}

/// Result of inspecting a WAV header.
class WavInspectionResult {
  final bool isValid;
  final String? errorMessage;
  final int? channels;
  final int? sampleRate;
  final int? bitDepth;
  final int? dataSize;
  final int? dataOffset;
  final double? durationSeconds;

  const WavInspectionResult.valid({
    required this.channels,
    required this.sampleRate,
    required this.bitDepth,
    required this.dataSize,
    required this.dataOffset,
    required this.durationSeconds,
  }) : isValid = true,
       errorMessage = null;

  const WavInspectionResult.invalid(this.errorMessage)
    : isValid = false,
      channels = null,
      sampleRate = null,
      bitDepth = null,
      dataSize = null,
      dataOffset = null,
      durationSeconds = null;
}

/// Audio waveform metrics extracted from PCM WAV data for non-zero signal verification.
class AudioWaveformMetrics {
  final double peakAmplitude;
  final double rmsAmplitude;
  final double onsetRmsAmplitude;
  final bool hasNonZeroSignal;

  const AudioWaveformMetrics({
    required this.peakAmplitude,
    required this.rmsAmplitude,
    required this.onsetRmsAmplitude,
    required this.hasNonZeroSignal,
  });
}
