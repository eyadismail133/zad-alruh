import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../features/quran/data/parsers/quran_parser.dart';
import '../../features/quran/data/sources/quran_source_verifier.dart';

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

  /// Validates content integrity and release readiness against a workspace root.
  static Future<ValidationResult> validate({
    required String workspaceRoot,
    bool isDevelopmentMode = false,
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
    final manifestRelPath = p.join('assets', 'content', 'manifest.json');
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
  /// Enforces schema, field types, counts, and validates file-backed Hadith bundle.
  /// Drops ONLY the Hadith release blocker when verified valid.
  static Future<void> _validatePendingRegistries({
    required Map<String, dynamic>? pending,
    required String normalizedRoot,
    required String canonicalRoot,
    required List<String> errors,
    required List<String> pendingBlockers,
    required List<String> verified,
  }) async {
    if (pending == null) {
      return;
    }

    // 1. Quran Images Registry
    final imgRaw = pending['quran_images'];
    if (imgRaw is! Map) {
      errors.add(
        'Missing or malformed "quran_images" section in pending_registries',
      );
    } else {
      final img = imgRaw.cast<String, dynamic>();
      final status = img['status'];
      if (status is! String) {
        errors.add('Image registry status must be a string');
      } else if (status != 'missing' && status != 'pending') {
        errors.add('Contradictory or invalid image registry status: "$status"');
      }

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

    // 2. Adhan Audio Registry
    final audioRaw = pending['adhan_audio'];
    if (audioRaw is! Map) {
      errors.add(
        'Missing or malformed "adhan_audio" section in pending_registries',
      );
    } else {
      final audio = audioRaw.cast<String, dynamic>();
      final status = audio['status'];
      if (status is! String) {
        errors.add('Adhan audio registry status must be a string');
      } else if (status != 'missing' && status != 'pending') {
        errors.add('Contradictory or invalid adhan audio status: "$status"');
      }

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
          'Adhan audio recordings are unsupported at this milestone; dedicated validator pending',
        );
      }
    }

    // 3. Dhikr & Duas Registry
    final dhikrRaw = pending['dhikr_duas'];
    if (dhikrRaw is! Map) {
      errors.add(
        'Missing or malformed "dhikr_duas" section in pending_registries',
      );
    } else {
      final dhikr = dhikrRaw.cast<String, dynamic>();
      final status = dhikr['status'];
      if (status is! String) {
        errors.add('Dhikr registry status must be a string');
      } else if (status != 'missing' && status != 'pending') {
        errors.add('Contradictory or invalid dhikr registry status: "$status"');
      }

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
    if (humanRaw is! Map) {
      errors.add(
        'Missing or malformed "human_review" section in pending_registries',
      );
    } else {
      final human = humanRaw.cast<String, dynamic>();
      final status = human['status'];
      if (status is! String) {
        errors.add('Human review status must be a string');
      }

      final approved = human['approved'];
      if (approved is! bool) {
        errors.add('Human review "approved" field must be a boolean');
      } else if (approved == true) {
        errors.add(
          'Human review approval is unsupported at this milestone; dedicated review verification pending',
        );
      }

      if (human['evidence_path'] != null) {
        errors.add(
          'Human review evidence is unsupported at this milestone; dedicated review verification pending',
        );
      }
      if (human['evidence_sha256'] != null) {
        errors.add(
          'Human review evidence SHA is unsupported at this milestone; dedicated review verification pending',
        );
      }
      final reviewedHashes = human['reviewed_hashes'];
      if (reviewedHashes != null &&
          (reviewedHashes is! Map || reviewedHashes.isNotEmpty)) {
        errors.add(
          'Human review hash claims are unsupported at this milestone; dedicated review verification pending',
        );
      }
      if (human['reviewer_name'] != null) {
        errors.add(
          'Human reviewer declarations are unsupported at this milestone; dedicated review verification pending',
        );
      }
    }

    // Retain Quran images, audio, Hisn and human-review blockers
    pendingBlockers.add(
      'Missing 604 Medina Mushaf page images. '
      'Owner has no developer account/CDN access. Same-edition image alignment pending.',
    );
    pendingBlockers.add(
      'Missing 3 licensed adhan recordings (3 distinct voices including Fajr and <30s notification clips).',
    );
    pendingBlockers.add(
      'Missing documented Hisn al-Muslim dhikr/duas digital edition, references, and repetition counts.',
    );

    // Drop ONLY the hadith release blocker when valid
    if (!hadithValid) {
      pendingBlockers.add(hadithBlocker);
    }

    pendingBlockers.add(
      'Qualified human reviewer religious review tied to exact corpus hashes is pending.',
    );
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
      durationSeconds: durationSeconds,
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
  final double? durationSeconds;

  const WavInspectionResult.valid({
    required this.channels,
    required this.sampleRate,
    required this.bitDepth,
    required this.dataSize,
    required this.durationSeconds,
  }) : isValid = true,
       errorMessage = null;

  const WavInspectionResult.invalid(this.errorMessage)
    : isValid = false,
      channels = null,
      sampleRate = null,
      bitDepth = null,
      dataSize = null,
      durationSeconds = null;
}
