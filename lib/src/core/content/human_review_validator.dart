import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../../features/quran/data/sources/kfqc_mushaf_catalog.dart';
import '../../features/quran/data/sources/quran_source_verifier.dart';
import 'content_validator.dart';

/// Strongly-typed result of qualified human content-review verification.
class HumanReviewValidationResult {
  /// Whether the review validation completed without integrity or format errors.
  final bool isValid;

  /// Whether the qualified reviewer explicitly approved the religious content.
  final bool isApproved;

  /// Critical blocking errors (e.g. hash mismatch, unsafe path, missing reviewer).
  final List<String> errors;

  /// Checklist items and metadata successfully verified.
  final List<String> verifiedItems;

  /// Reviewer full name, if declared.
  final String? reviewerName;

  /// Reviewer religious and academic qualifications, if declared.
  final String? reviewerQualifications;

  /// Review calendar date in ISO YYYY-MM-DD format, if declared.
  final String? reviewDate;

  /// Relative path to the evidence report JSON file, if declared.
  final String? evidencePath;

  /// Cryptographic SHA-256 digest of the evidence report file, if declared.
  final String? evidenceSha256;

  /// Total count of reviewed items in verified inventory.
  final int reviewedItemCount;

  const HumanReviewValidationResult({
    required this.isValid,
    required this.isApproved,
    required this.errors,
    required this.verifiedItems,
    this.reviewerName,
    this.reviewerQualifications,
    this.reviewDate,
    this.evidencePath,
    this.evidenceSha256,
    this.reviewedItemCount = 0,
  });
}

enum _ContainerType { object, array }

class _JsonScope {
  final _ContainerType type;
  final Set<String> keys = <String>{};
  bool expectingKey = false;
  _JsonScope(this.type) {
    expectingKey = (type == _ContainerType.object);
  }
}

/// Pure Dart verifier for hash-bound qualified human religious content review evidence.
///
/// Ensures all bundled religious assets (Quran text, Quran XML metadata,
/// 604 Medina Mushaf page images and bounds, HadeethEnc Hadiths, Hisn al-Muslim
/// duas, and 3 adhan audio voices across full MP3, alert WAV, and native platform copies)
/// are backed by a hash-bound declaration and schema-compliant human review report
/// signed off with non-placeholder qualifications, exact calendar date, and exact
/// cryptographic inventory matching disk bytes.
///
/// IMPORTANT LIMITATION NOTICE:
/// Automated software tools verify cryptographic hashes, file containment,
/// schema structure, and calendar validity. The machine CANNOT authenticate
/// real-world human identity, academic/religious qualifications, reviewer
/// honesty, or theological truth. Religious authority and scholarly review
/// remain fundamentally human and institutional responsibilities.
class HumanReviewValidator {
  HumanReviewValidator._();

  /// Supported evidence report schema version.
  static const int kSupportedSchemaVersion = 1;

  /// Bounded maximum size for human review evidence report file (1 MiB).
  static const int kMaxReportSizeBytes = 1024 * 1024;

  /// Total count of canonical religious content items requiring human review sign-off.
  static const int kExpectedTotalReligiousItems = 624;

  /// Release blocker message emitted when human review is pending or incomplete.
  static const String kPendingBlockerMessage =
      'Qualified human reviewer religious review tied to exact corpus hashes is pending.';

  static final List<RegExp> _placeholderPatterns = <RegExp>[
    RegExp(r'^\s*todo\b', caseSensitive: false),
    RegExp(r'^\s*tbd\b', caseSensitive: false),
    RegExp(r'^\s*n/?a\b', caseSensitive: false),
    RegExp(r'^\s*placeholder\b', caseSensitive: false),
    RegExp(r'^\s*dummy\b', caseSensitive: false),
    RegExp(r'^\s*test\b', caseSensitive: false),
    RegExp(r'^\s*sample\b', caseSensitive: false),
    RegExp(r'^\s*unknown\b', caseSensitive: false),
    RegExp(r'^\s*none\b', caseSensitive: false),
    RegExp(r'^\s*null\b', caseSensitive: false),
    RegExp(r'^\s*john\s+doe\b', caseSensitive: false),
    RegExp(r'^\s*jane\s+doe\b', caseSensitive: false),
    RegExp(r'^[.\-_*?#@!\s]+$'),
  ];

  /// Detects blank, trivial, or obvious placeholder text.
  static bool isPlaceholder(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length < 3) return true;
    for (final pattern in _placeholderPatterns) {
      if (pattern.hasMatch(trimmed)) return true;
    }
    return false;
  }

  /// Strictly verifies that the date string represents a valid Gregorian calendar date
  /// in YYYY-MM-DD format (accounting for months, varying days, and leap years).
  static bool isValidCalendarDate(String dateStr) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateStr);
    if (match == null) return false;

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final day = int.tryParse(match.group(3)!);

    if (year == null || month == null || day == null) return false;
    if (year < 1970 || year > 2100) return false;
    if (month < 1 || month > 12) return false;

    int maxDays;
    switch (month) {
      case 1:
      case 3:
      case 5:
      case 7:
      case 8:
      case 10:
      case 12:
        maxDays = 31;
        break;
      case 4:
      case 6:
      case 9:
      case 11:
        maxDays = 30;
        break;
      case 2:
        final isLeap =
            (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
        maxDays = isLeap ? 29 : 28;
        break;
      default:
        return false;
    }

    return day >= 1 && day <= maxDays;
  }

  /// Scans raw JSON text to detect duplicate keys in objects without silent overwrite.
  /// Returns the first duplicate key name found, or null if all keys are unique.
  static String? findDuplicateJsonKey(String jsonText) {
    final stack = <_JsonScope>[];
    int i = 0;
    final len = jsonText.length;

    while (i < len) {
      final c = jsonText[i];

      // Skip whitespace
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
        continue;
      }

      if (c == '{') {
        stack.add(_JsonScope(_ContainerType.object));
        i++;
        continue;
      }

      if (c == '}') {
        if (stack.isNotEmpty && stack.last.type == _ContainerType.object) {
          stack.removeLast();
          if (stack.isNotEmpty && stack.last.type == _ContainerType.object) {
            stack.last.expectingKey = false;
          }
        }
        i++;
        continue;
      }

      if (c == '[') {
        stack.add(_JsonScope(_ContainerType.array));
        i++;
        continue;
      }

      if (c == ']') {
        if (stack.isNotEmpty && stack.last.type == _ContainerType.array) {
          stack.removeLast();
          if (stack.isNotEmpty && stack.last.type == _ContainerType.object) {
            stack.last.expectingKey = false;
          }
        }
        i++;
        continue;
      }

      if (c == ':') {
        i++;
        continue;
      }

      if (c == ',') {
        if (stack.isNotEmpty && stack.last.type == _ContainerType.object) {
          stack.last.expectingKey = true;
        }
        i++;
        continue;
      }

      if (c == '"') {
        final start = i;
        i++; // skip opening quote
        bool escaped = false;
        while (i < len) {
          final sc = jsonText[i];
          if (escaped) {
            escaped = false;
            i++;
          } else if (sc == '\\') {
            escaped = true;
            i++;
          } else if (sc == '"') {
            i++; // skip closing quote
            break;
          } else {
            i++;
          }
        }

        final rawString = jsonText.substring(start, i);
        String decodedString;
        try {
          decodedString = jsonDecode(rawString) as String;
        } catch (_) {
          decodedString = rawString.length >= 2
              ? rawString.substring(1, rawString.length - 1)
              : rawString;
        }

        if (stack.isNotEmpty &&
            stack.last.type == _ContainerType.object &&
            stack.last.expectingKey) {
          if (stack.last.keys.contains(decodedString)) {
            return decodedString;
          }
          stack.last.keys.add(decodedString);
          stack.last.expectingKey = false;
        }
        continue;
      }

      // Skip non-string tokens (numbers, booleans, null)
      while (i < len) {
        final nc = jsonText[i];
        if (nc == ' ' ||
            nc == '\t' ||
            nc == '\n' ||
            nc == '\r' ||
            nc == ',' ||
            nc == '}' ||
            nc == ']' ||
            nc == ':') {
          break;
        }
        i++;
      }
      if (stack.isNotEmpty && stack.last.type == _ContainerType.object) {
        stack.last.expectingKey = false;
      }
    }

    return null;
  }

  /// Strictly checks filesystem containment and traversal safety.
  static bool isPathSafe({
    required String relativePath,
    required String normalizedRoot,
    required String canonicalRoot,
  }) {
    if (relativePath.contains('\x00')) return false;
    if (p.isAbsolute(relativePath)) return false;
    if (relativePath.startsWith('/') || relativePath.startsWith('\\')) {
      return false;
    }
    if (RegExp(r'^[a-zA-Z]:').hasMatch(relativePath)) return false;
    if (relativePath.startsWith(r'\\')) return false;

    final joined = p.normalize(p.join(normalizedRoot, relativePath));
    final lexicalSafe =
        joined == normalizedRoot || p.isWithin(normalizedRoot, joined);
    if (!lexicalSafe) return false;

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
        if (!canonicalSafe) return false;
      } catch (_) {
        return false;
      }
    } else {
      final parentDir = entity.parent;
      if (parentDir.existsSync()) {
        try {
          final resolvedParent = parentDir.resolveSymbolicLinksSync();
          final canonicalSafe =
              resolvedParent == canonicalRoot ||
              p.isWithin(canonicalRoot, resolvedParent) ||
              resolvedParent == normalizedRoot ||
              p.isWithin(normalizedRoot, resolvedParent);
          if (!canonicalSafe) return false;
        } catch (_) {
          return false;
        }
      }
    }

    return true;
  }

  /// Derives the exact, complete canonical religious content inventory
  /// (relative path -> lowercase 64-hex SHA-256 hash).
  ///
  /// Includes:
  /// - Tanzil Uthmani Quran text + Tanzil Quran metadata XML (2)
  /// - HadeethEnc source XLSX + shipped compact JSON (2)
  /// - Hisn al-Muslim source DOCX + shipped compact JSON (2)
  /// - Medina Mushaf bounds JSON + WebP page digests JSON (2)
  /// - 604 Medina Mushaf page WebP image files (604)
  /// - 3 full adhan audio recordings (MP3) (3)
  /// - 3 adhan notification alert clips (WAV) in assets (3)
  /// - 3 iOS Runner native notification alert copies (WAV) (3)
  /// - 3 Android res/raw native notification alert copies (WAV) (3)
  /// Total: exactly 624 religious content artifacts.
  static Map<String, String> buildCanonicalReligiousInventory({
    String? normalizedRoot,
    Map<String, String>? webpDigests,
  }) {
    final inventory = <String, String>{};

    // 1. Holy Quran text and metadata
    inventory['assets/content/quran/quran-uthmani.txt'] =
        QuranSourceConstants.canonicalTextSha256;
    inventory['assets/content/quran/quran-data.xml'] =
        QuranSourceConstants.canonicalMetadataSha256;

    // 2. Hadith collection (HadeethEnc source XLSX + shipped JSON)
    inventory['assets/content/hadith/hadeethenc-ar.xlsx'] =
        ContentValidator.kExpectedHadithSourceSha256;
    inventory['assets/content/hadith/hadith-enc-sahih.json'] =
        ContentValidator.kExpectedHadithJsonSha256;

    // 3. Dhikr and Duas (Hisn al-Muslim source DOCX + shipped JSON)
    inventory['assets/content/hisn/hisn-muslim-source.docx'] =
        ContentValidator.kExpectedHisnSourceSha256;
    inventory['assets/content/hisn/hisn-muslim.json'] =
        ContentValidator.kExpectedHisnJsonSha256;

    // 4. Medina Mushaf page catalog
    inventory[KfqcMushafCatalog.boundsAssetPath] =
        ContentValidator.kExpectedKfqcBoundsSha256;
    inventory[KfqcMushafCatalog.digestsAssetPath] =
        ContentValidator.kExpectedKfqcDigestsSha256;

    // 5. 604 KFQC Medina Mushaf page WebP images
    if (webpDigests != null) {
      for (int pNum = 1; pNum <= KfqcMushafCatalog.expectedPageCount; pNum++) {
        final padded = pNum.toString().padLeft(3, '0');
        final path = KfqcMushafCatalog.pageAssetPath(pNum);
        final sha = webpDigests[padded] ?? webpDigests[path];
        if (sha != null) {
          inventory[path] = sha.toLowerCase();
        }
      }
    } else if (normalizedRoot != null) {
      final digestsFile = File(
        p.join(normalizedRoot, KfqcMushafCatalog.digestsAssetPath),
      );
      if (digestsFile.existsSync()) {
        try {
          final content = digestsFile.readAsStringSync();
          final parsed = jsonDecode(content);
          if (parsed is Map && parsed['pages'] is List) {
            final pagesList = parsed['pages'] as List<dynamic>;
            for (final item in pagesList) {
              if (item is Map) {
                final pNum = item['page'] as int?;
                final sha = item['webp_sha256'] as String?;
                if (pNum != null && sha != null) {
                  inventory[KfqcMushafCatalog.pageAssetPath(pNum)] =
                      sha.toLowerCase();
                }
              }
            }
          }
        } catch (_) {}
      }
    }

    // 6. Three full adhan recordings (MP3)
    for (final voiceId in ContentValidator.kExpectedAdhanVoiceIds) {
      inventory[ContentValidator.kExpectedAdhanAudioPaths[voiceId]!] =
          ContentValidator.kExpectedAdhanAudioSha256[voiceId]!;
    }

    // 7. Three alert WAV notification clips in assets
    for (final voiceId in ContentValidator.kExpectedAdhanVoiceIds) {
      inventory[ContentValidator.kExpectedAdhanAlertPaths[voiceId]!] =
          ContentValidator.kExpectedAdhanAlertSha256[voiceId]!;
    }

    // 8. Platform native copies (iOS Runner and Android res/raw)
    for (final voiceId in ContentValidator.kExpectedAdhanVoiceIds) {
      inventory[ContentValidator.kExpectedAdhanIosAlertPaths[voiceId]!] =
          ContentValidator.kExpectedAdhanAlertSha256[voiceId]!;
      inventory[ContentValidator.kExpectedAdhanAndroidAlertPaths[voiceId]!] =
          ContentValidator.kExpectedAdhanAlertSha256[voiceId]!;
    }

    return Map<String, String>.unmodifiable(inventory);
  }

  /// Strictly validates human review declarations, report evidence, inventory, and disk bytes.
  static Future<HumanReviewValidationResult> validate({
    required Map<String, dynamic> humanReviewRegistry,
    required String normalizedRoot,
    required String canonicalRoot,
    bool underlyingIntegritySuccess = true,
    Map<String, String>? canonicalInventoryOverride,
    bool verifyActualBytes = true,
  }) async {
    final errors = <String>[];
    final verified = <String>[];

    // 1. Validate manifest status and approved fields
    const disallowedManifestAliases = <String, String>{
      'religious_approval': 'approved',
      'inventory': 'reviewed_hashes',
      'schema_version': 'manifest level schema_version',
      'schemaVersion': 'manifest level schema_version',
      'reviewer_qualification': 'reviewer_qualifications',
      'date': 'review_date',
    };

    for (final entry in disallowedManifestAliases.entries) {
      if (humanReviewRegistry.containsKey(entry.key)) {
        errors.add(
          'Manifest human_review section contains disallowed alias or conflicting field "${entry.key}"; use canonical "${entry.value}"',
        );
      }
    }

    final status = humanReviewRegistry['status'];
    if (status is! String) {
      errors.add('Human review status must be a string');
    }

    final approved = humanReviewRegistry['approved'];
    if (approved is! bool) {
      errors.add('Human review "approved" field must be a boolean');
    }

    final evidencePath = humanReviewRegistry['evidence_path'];
    final evidenceSha256 = humanReviewRegistry['evidence_sha256'];
    final reviewerName = humanReviewRegistry['reviewer_name'];
    final reviewerQualifications =
        humanReviewRegistry['reviewer_qualifications'];
    final reviewDate = humanReviewRegistry['review_date'];
    final reviewedHashesRaw = humanReviewRegistry['reviewed_hashes'];

    final hasEvidenceClaims = evidencePath != null ||
        evidenceSha256 != null ||
        reviewerName != null ||
        reviewerQualifications != null ||
        reviewDate != null ||
        (reviewedHashesRaw is Map && reviewedHashesRaw.isNotEmpty);

    // Canonical pending branch: approved: false and clean status
    if (approved == false) {
      if (status != 'pending') {
        errors.add(
          'Contradictory human review status: status is "$status" but approved is false',
        );
      }

      if (hasEvidenceClaims) {
        errors.add(
          'Human review declared evidence or reviewer claims while status is "pending" and approved is false; '
          'approval and evidence must be complete and consistent',
        );
        if (evidencePath != null && evidencePath is String) {
          final file = File(p.join(normalizedRoot, evidencePath));
          if (!file.existsSync()) {
            errors.add('Human review evidence file not found: "$evidencePath"');
          }
        }
      }

      return HumanReviewValidationResult(
        isValid: errors.isEmpty,
        isApproved: false,
        errors: errors,
        verifiedItems: errors.isEmpty
            ? const <String>[
                'Human content review status: pending (release blocker active)',
              ]
            : verified,
      );
    }

    // Approved branch (approved == true): requires full valid evidence
    if (status != 'approved') {
      errors.add(
        'Contradictory human review status: approved is true but status is "$status" (expected "approved")',
      );
    }

    if (reviewerName == null ||
        reviewerName is! String ||
        reviewerName.trim().isEmpty) {
      errors.add('Human review approved is true but reviewer_name is missing');
    } else if (isPlaceholder(reviewerName)) {
      errors.add(
        'Human review reviewer_name contains placeholder text: "$reviewerName"',
      );
    }

    if (reviewerQualifications == null ||
        reviewerQualifications is! String ||
        reviewerQualifications.trim().isEmpty) {
      errors.add(
        'Human review approved is true but reviewer_qualifications is missing',
      );
    } else if (isPlaceholder(reviewerQualifications)) {
      errors.add(
        'Human review reviewer_qualifications contains placeholder text: "$reviewerQualifications"',
      );
    }

    if (reviewDate == null ||
        reviewDate is! String ||
        reviewDate.trim().isEmpty) {
      errors.add('Human review approved is true but review_date is missing');
    } else if (!isValidCalendarDate(reviewDate)) {
      errors.add(
        'Human review review_date is invalid or not a real calendar date (expected YYYY-MM-DD): "$reviewDate"',
      );
    }

    if (evidencePath == null ||
        evidencePath is! String ||
        evidencePath.trim().isEmpty) {
      errors.add('Human review approved is true but evidence_path is missing');
    }

    if (evidenceSha256 == null ||
        evidenceSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(evidenceSha256.toLowerCase())) {
      errors.add(
        'Human review evidence_sha256 must be a 64-character lowercase hexadecimal SHA-256 string',
      );
    }

    if (reviewedHashesRaw == null || reviewedHashesRaw is! Map) {
      errors.add(
        'Human review reviewed_hashes must be a JSON object mapping relative paths to SHA-256 digests',
      );
    }

    if (errors.isNotEmpty || evidencePath == null || evidencePath is! String) {
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    // 2. Safe path and containment check on evidence file
    if (!isPathSafe(
      relativePath: evidencePath,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
    )) {
      errors.add('Unsafe or invalid evidence_path: "$evidencePath"');
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    final evidenceFile = File(p.join(normalizedRoot, evidencePath));
    if (!evidenceFile.existsSync()) {
      errors.add('Human review evidence file not found: "$evidencePath"');
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    final fileSize = evidenceFile.lengthSync();
    if (fileSize == 0) {
      errors.add('Human review evidence file is empty: "$evidencePath"');
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }
    if (fileSize > kMaxReportSizeBytes) {
      errors.add(
        'Human review evidence file exceeds 1 MiB bound ($fileSize > $kMaxReportSizeBytes bytes)',
      );
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    // 3. Evidence file SHA-256 integrity
    final fileBytes = evidenceFile.readAsBytesSync();
    final actualReportSha =
        sha256.convert(fileBytes).toString().toLowerCase();
    if (actualReportSha != (evidenceSha256 as String).toLowerCase()) {
      errors.add(
        'Human review evidence SHA-256 mismatch: manifest declared $evidenceSha256, actual file SHA-256 is $actualReportSha',
      );
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    // 4. Decode UTF-8 and check duplicate JSON keys
    late final String reportText;
    try {
      reportText = utf8.decode(fileBytes);
    } catch (e) {
      errors.add('Human review evidence file is not valid UTF-8: $e');
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    final duplicateKey = findDuplicateJsonKey(reportText);
    if (duplicateKey != null) {
      errors.add(
        'Duplicate JSON key found in evidence report: "$duplicateKey"',
      );
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    // 5. Parse JSON
    late final Map<String, dynamic> report;
    try {
      final decoded = jsonDecode(reportText);
      if (decoded is! Map) {
        errors.add('Human review evidence report root must be a JSON object');
        return HumanReviewValidationResult(
          isValid: false,
          isApproved: false,
          errors: errors,
          verifiedItems: verified,
        );
      }
      report = decoded.cast<String, dynamic>();
    } catch (e) {
      errors.add('Failed to parse human review evidence JSON: $e');
      return HumanReviewValidationResult(
        isValid: false,
        isApproved: false,
        errors: errors,
        verifiedItems: verified,
      );
    }

    // Reject ambiguous, disallowed alias, or unrecognized fields in evidence report
    const allowedReportKeys = <String>{
      'schema_version',
      'religious_approval',
      'reviewer_name',
      'reviewer_qualifications',
      'review_date',
      'scope',
      'review_method',
      'coverage',
      'concerns_and_limitations',
      'reviewed_hashes',
    };

    const disallowedReportAliases = <String, String>{
      'approved': 'religious_approval',
      'inventory': 'reviewed_hashes',
      'schemaVersion': 'schema_version',
      'reviewer_qualification': 'reviewer_qualifications',
      'date': 'review_date',
      'reviewMethod': 'review_method',
      'concerns': 'concerns_and_limitations',
      'limitations': 'concerns_and_limitations',
    };

    for (final key in report.keys) {
      if (!allowedReportKeys.contains(key)) {
        if (disallowedReportAliases.containsKey(key)) {
          errors.add(
            'Human review report contains disallowed alias "$key"; use canonical "${disallowedReportAliases[key]}"',
          );
        } else {
          errors.add(
            'Human review report contains unrecognized field: "$key"',
          );
        }
      }
    }

    // 6. Validate report schema version
    final schemaVersion = report['schema_version'];
    if (schemaVersion == null) {
      errors.add('Human review report missing required "schema_version" field');
    } else if (schemaVersion is! int || schemaVersion != kSupportedSchemaVersion) {
      errors.add(
        'Unsupported schema_version in human review report '
        '(expected integer $kSupportedSchemaVersion, got $schemaVersion)',
      );
    }

    // 7. Validate explicit religious approval
    final repApproval = report['religious_approval'];
    if (repApproval == null) {
      errors.add(
        'Human review report missing required "religious_approval" field',
      );
    } else if (repApproval is! bool) {
      errors.add('Human review report "religious_approval" must be a boolean');
    } else if (repApproval != true) {
      errors.add(
        'Human review report does not contain explicit religious approval '
        '(religious_approval must be boolean true)',
      );
    }

    // 8. Validate reviewer name, qualifications, review date match
    final repName = report['reviewer_name'];
    if (repName == null) {
      errors.add('Human review report missing required "reviewer_name" field');
    } else if (repName is! String) {
      errors.add('Human review report "reviewer_name" must be a string');
    } else if (repName.trim().isEmpty || repName.length > 500 || isPlaceholder(repName)) {
      errors.add(
        'Human review report contains invalid, empty, or placeholder reviewer_name: "$repName"',
      );
    } else if (repName != reviewerName) {
      errors.add(
        'Reviewer name mismatch: manifest declared "$reviewerName", report declared "$repName"',
      );
    }

    final repQual = report['reviewer_qualifications'];
    if (repQual == null) {
      errors.add(
        'Human review report missing required "reviewer_qualifications" field',
      );
    } else if (repQual is! String) {
      errors.add('Human review report "reviewer_qualifications" must be a string');
    } else if (repQual.trim().isEmpty || repQual.length > 2000 || isPlaceholder(repQual)) {
      errors.add(
        'Human review report contains invalid, empty, or placeholder reviewer_qualifications: "$repQual"',
      );
    } else if (repQual != reviewerQualifications) {
      errors.add(
        'Reviewer qualifications mismatch: manifest declared "$reviewerQualifications", report declared "$repQual"',
      );
    }

    final repDate = report['review_date'];
    if (repDate == null) {
      errors.add('Human review report missing required "review_date" field');
    } else if (repDate is! String) {
      errors.add('Human review report "review_date" must be a string');
    } else if (!isValidCalendarDate(repDate)) {
      errors.add(
        'Human review report review_date is invalid or not a real calendar date (expected YYYY-MM-DD): "$repDate"',
      );
    } else if (repDate != reviewDate) {
      errors.add(
        'Review date mismatch: manifest declared "$reviewDate", report declared "$repDate"',
      );
    }

    // 9. Scope, review method, coverage, concerns/limitations
    final scope = report['scope'];
    if (scope == null) {
      errors.add('Human review report missing required "scope" field');
    } else if (scope is! String) {
      errors.add('Human review report "scope" must be a string');
    } else if (scope.trim().isEmpty || scope.length > 2000 || isPlaceholder(scope)) {
      errors.add('Human review report missing, empty, or placeholder scope');
    }

    final reviewMethod = report['review_method'];
    if (reviewMethod == null) {
      errors.add('Human review report missing required "review_method" field');
    } else if (reviewMethod is! String) {
      errors.add('Human review report "review_method" must be a string');
    } else if (reviewMethod.trim().isEmpty || reviewMethod.length > 2000 || isPlaceholder(reviewMethod)) {
      errors.add('Human review report missing, empty, or placeholder review_method');
    }

    final coverage = report['coverage'];
    if (coverage == null) {
      errors.add('Human review report missing required "coverage" field');
    } else if (coverage is! String) {
      errors.add('Human review report "coverage" must be a string');
    } else if (coverage.trim().isEmpty || coverage.length > 2000 || isPlaceholder(coverage)) {
      errors.add('Human review report missing, empty, or placeholder coverage');
    }

    final limitations = report['concerns_and_limitations'];
    if (limitations == null) {
      errors.add(
        'Human review report missing required "concerns_and_limitations" field',
      );
    } else if (limitations is! String) {
      errors.add('Human review report "concerns_and_limitations" must be a string');
    } else if (limitations.trim().isEmpty || limitations.length > 4000 || isPlaceholder(limitations)) {
      errors.add(
        'Human review report missing, empty, or placeholder concerns_and_limitations',
      );
    }

    // 10. Extract report inventory (canonical "reviewed_hashes" map ONLY)
    final reportInventory = <String, String>{};
    final repReviewedHashes = report['reviewed_hashes'];

    if (repReviewedHashes == null) {
      errors.add('Human review report missing required "reviewed_hashes" map');
    } else if (repReviewedHashes is! Map) {
      errors.add(
        'Human review report "reviewed_hashes" must be a JSON object mapping relative paths to SHA-256 digests',
      );
    } else {
      for (final entry in repReviewedHashes.entries) {
        final k = entry.key;
        final v = entry.value;
        if (k is! String ||
            v is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(v.toLowerCase())) {
          errors.add(
            'Invalid entry in report reviewed_hashes: path must be string and hash must be 64-hex SHA-256 digest',
          );
        } else {
          reportInventory[k] = v.toLowerCase();
        }
      }
    }

    // 11. Compare report inventory against manifest reviewed_hashes
    final manifestInventory = <String, String>{};
    for (final entry in (reviewedHashesRaw as Map).entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is String && v is String) {
        manifestInventory[k] = v.toLowerCase();
      }
    }

    if (manifestInventory.length != reportInventory.length) {
      errors.add(
        'Item count mismatch between manifest reviewed_hashes (${manifestInventory.length}) and report inventory (${reportInventory.length})',
      );
    } else {
      for (final entry in reportInventory.entries) {
        final mSha = manifestInventory[entry.key];
        if (mSha == null) {
          errors.add(
            'Manifest reviewed_hashes is missing path present in report: "${entry.key}"',
          );
        } else if (mSha != entry.value) {
          errors.add(
            'Hash claim mismatch for "${entry.key}": manifest has $mSha, report has ${entry.value}',
          );
        }
      }
    }

    // 12. Compare inventory against Required Canonical Inventory
    final canonicalInventory = canonicalInventoryOverride ??
        buildCanonicalReligiousInventory(normalizedRoot: normalizedRoot);

    if (canonicalInventory.length != reportInventory.length) {
      errors.add(
        'Human review inventory count mismatch: required ${canonicalInventory.length} canonical items, report covers ${reportInventory.length}',
      );
    }

    for (final entry in canonicalInventory.entries) {
      final claimedSha = reportInventory[entry.key];
      if (claimedSha == null) {
        errors.add(
          'Missing review hash claim for required religious asset: "${entry.key}"',
        );
      } else if (claimedSha != entry.value.toLowerCase()) {
        errors.add(
          'Review hash mismatch for "${entry.key}": claimed $claimedSha, expected canonical ${entry.value}',
        );
      }
    }

    for (final claimedPath in reportInventory.keys) {
      if (!canonicalInventory.containsKey(claimedPath)) {
        errors.add(
          'Unexpected or extra review hash claim in evidence: "$claimedPath"',
        );
      }
    }

    // 13. Verify actual disk bytes of underlying assets
    bool diskLoopCompleted = false;
    if (verifyActualBytes) {
      if (errors.isEmpty) {
        for (final entry in canonicalInventory.entries) {
          final relPath = entry.key;
          final expectedSha = entry.value.toLowerCase();

          if (!isPathSafe(
            relativePath: relPath,
            normalizedRoot: normalizedRoot,
            canonicalRoot: canonicalRoot,
          )) {
            errors.add('Unsafe underlying asset path: "$relPath"');
            continue;
          }

          final assetFile = File(p.join(normalizedRoot, relPath));
          if (!assetFile.existsSync()) {
            errors.add(
              'Underlying religious asset missing on disk: "$relPath"',
            );
            continue;
          }

          final actualBytes = assetFile.readAsBytesSync();
          final actualSha =
              sha256.convert(actualBytes).toString().toLowerCase();
          if (actualSha != expectedSha) {
            errors.add(
              'Underlying asset byte SHA-256 mismatch on disk for "$relPath": expected $expectedSha, actual $actualSha',
            );
          }
        }
        if (errors.isEmpty) {
          diskLoopCompleted = true;
        }
      }
    } else {
      verified.add(
        'Underlying asset byte verification skipped (approval gate blocked: bytes not verified)',
      );
    }

    // 14. Gate on underlying asset integrity success AND actual disk loop completion
    bool isApproved = false;
    if (errors.isEmpty) {
      if (!verifyActualBytes) {
        isApproved = false;
      } else if (!underlyingIntegritySuccess) {
        isApproved = false;
        verified.add(
          'Underlying asset integrity gate pending or failed elsewhere (approval blocked)',
        );
      } else if (diskLoopCompleted) {
        isApproved = true;
      }
    }

    if (errors.isEmpty) {
      verified.add('Human review report schema_version 1 verified');
      verified.add(
        'Reviewer declaration fields matched: $reviewerName ($reviewerQualifications, reviewed on $reviewDate)',
      );
      verified.add(
        'Human review inventory verified: ${reportInventory.length} required religious assets matched',
      );
      if (diskLoopCompleted && underlyingIntegritySuccess) {
        verified.add(
          'Underlying asset byte integrity verified on disk (${canonicalInventory.length} assets)',
        );
      }
    }

    return HumanReviewValidationResult(
      isValid: errors.isEmpty,
      isApproved: isApproved,
      errors: errors,
      verifiedItems: verified,
      reviewerName: reviewerName as String?,
      reviewerQualifications: reviewerQualifications as String?,
      reviewDate: reviewDate as String?,
      evidencePath: evidencePath,
      evidenceSha256: actualReportSha,
      reviewedItemCount: reportInventory.length,
    );
  }
}
