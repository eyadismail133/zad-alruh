import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zad_alruh/src/core/content/content_validator.dart';
import 'package:zad_alruh/src/core/content/human_review_validator.dart';
import 'package:zad_alruh/src/features/quran/data/sources/kfqc_mushaf_catalog.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_source_verifier.dart';

void main() {
  final currentDir = Directory.current.path;

  group('HumanReviewValidator - Canonical Repository Pending State', () {
    test(
      'canonical untouched manifest stays pending without errors and blocks release',
      () async {
        final manifestFile = File(
          p.join(currentDir, 'assets', 'content', 'manifest.json'),
        );
        expect(manifestFile.existsSync(), isTrue);

        final manifest =
            jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
        final pending =
            manifest['pending_registries'] as Map<String, dynamic>;
        final humanReview = pending['human_review'] as Map<String, dynamic>;

        expect(humanReview['status'], 'pending');
        expect(humanReview['approved'], isFalse);
        expect(humanReview['reviewer_name'], isNull);
        expect(humanReview['evidence_path'], isNull);
        expect(humanReview['evidence_sha256'], isNull);
        expect(humanReview['reviewed_hashes'], isEmpty);

        final normalized = p.canonicalize(currentDir);
        final canonical = Directory(currentDir).resolveSymbolicLinksSync();

        final result = await HumanReviewValidator.validate(
          humanReviewRegistry: humanReview,
          normalizedRoot: normalized,
          canonicalRoot: canonical,
        );

        expect(result.isValid, isTrue);
        expect(result.isApproved, isFalse);
        expect(result.errors, isEmpty);
        expect(result.verifiedItems, contains(contains('pending')));
      },
    );

    test(
      'canonical ContentValidator development mode passes while release mode remains blocked',
      () async {
        final result = await ContentValidator.validate(
          workspaceRoot: currentDir,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isTrue);
        expect(result.errors, isEmpty);
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains(
              'Qualified human reviewer religious review tied to exact corpus hashes is pending.',
            ),
          ),
          isTrue,
        );

        final releaseResult = await ContentValidator.validate(
          workspaceRoot: currentDir,
          isDevelopmentMode: false,
        );

        expect(releaseResult.isReleaseReady, isFalse);
        expect(
          releaseResult.pendingReleaseBlockers.any(
            (b) => b.contains('Qualified human reviewer'),
          ),
          isTrue,
        );
      },
    );
  });

  group('HumanReviewValidator - Isolated Synthetic Unit Boundaries', () {
    late Directory tempDir;
    late String normalizedRoot;
    late String canonicalRoot;

    late String testPath1;
    late String testPath2;
    late String testPath3;
    late String sha1;
    late String sha2;
    late String sha3;
    late Map<String, String> syntheticCanonicalInventory;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'human_review_unit_test_',
      );
      normalizedRoot = p.canonicalize(tempDir.path);
      canonicalRoot = tempDir.resolveSymbolicLinksSync();

      testPath1 = p.join('assets', 'content', 'test1.txt');
      testPath2 = p.join('assets', 'content', 'test2.txt');
      testPath3 = p.join('assets', 'content', 'test3.txt');

      final f1 = File(p.join(normalizedRoot, testPath1));
      final f2 = File(p.join(normalizedRoot, testPath2));
      final f3 = File(p.join(normalizedRoot, testPath3));

      await f1.parent.create(recursive: true);

      final b1 = utf8.encode('Synthetic Holy Quran text fixture');
      final b2 = utf8.encode('Synthetic Prophetic Hadith text fixture');
      final b3 = utf8.encode('Synthetic Hisn al-Muslim prayer fixture');

      await f1.writeAsBytes(b1);
      await f2.writeAsBytes(b2);
      await f3.writeAsBytes(b3);

      sha1 = sha256.convert(b1).toString().toLowerCase();
      sha2 = sha256.convert(b2).toString().toLowerCase();
      sha3 = sha256.convert(b3).toString().toLowerCase();

      // Ensure paths use forward slashes for cross-platform manifest format
      final posix1 = testPath1.replaceAll('\\', '/');
      final posix2 = testPath2.replaceAll('\\', '/');
      final posix3 = testPath3.replaceAll('\\', '/');

      syntheticCanonicalInventory = {
        posix1: sha1,
        posix2: sha2,
        posix3: sha3,
      };
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    Map<String, dynamic> createValidReportData() {
      return <String, dynamic>{
        'schema_version': 1,
        'religious_approval': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications':
            'Senior Scholar in Quranic Sciences and Hadith Authentication, Al-Azhar University Graduate',
        'review_date': '2026-10-07',
        'scope':
            'Complete religious review of synthetic Quran, Hadith, and Hisn al-Muslim corpora',
        'review_method':
            'Letter-by-letter comparison and cryptographic digest verification',
        'coverage': '100% complete coverage of declared synthetic inventory',
        'concerns_and_limitations':
            'Valid only for offline bundled static files; external streaming endpoints excluded',
        'reviewed_hashes': Map<String, String>.from(
          syntheticCanonicalInventory,
        ),
      };
    }

    Future<({String reportRelPath, String reportSha256})> writeReportFile(
      Map<String, dynamic> data, {
      String relPath = 'docs/reviews/human_content_review.json',
      String? rawContentOverride,
    }) async {
      final file = File(p.join(normalizedRoot, relPath));
      await file.parent.create(recursive: true);

      final content = rawContentOverride ?? jsonEncode(data);
      final bytes = utf8.encode(content);
      await file.writeAsBytes(bytes);

      final digest = sha256.convert(bytes).toString().toLowerCase();
      return (reportRelPath: relPath, reportSha256: digest);
    }

    Map<String, dynamic> createValidManifestSection({
      required String reportRelPath,
      required String reportSha256,
      required Map<String, dynamic> reportData,
    }) {
      return <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': reportData['reviewer_name'],
        'reviewer_qualifications': reportData['reviewer_qualifications'],
        'review_date': reportData['review_date'],
        'evidence_path': reportRelPath,
        'evidence_sha256': reportSha256,
        'reviewed_hashes': Map<String, String>.from(
          reportData['reviewed_hashes'] as Map,
        ),
      };
    }

    test('valid synthetic human review report passes all checks', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
        verifyActualBytes: true,
      );

      expect(result.isValid, isTrue);
      expect(result.isApproved, isTrue);
      expect(result.errors, isEmpty);
      expect(result.reviewedItemCount, 3);
      expect(result.reviewerName, 'Sheikh Abdullah Al-Mansoor');
      expect(result.reviewDate, '2026-10-07');
      expect(result.verifiedItems.length, greaterThanOrEqualTo(3));
    });

    test('rejects report with religious_approval: false', () async {
      final reportData = createValidReportData();
      reportData['religious_approval'] = false;
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(result.isApproved, isFalse);
      expect(
        result.errors.any((e) => e.contains('religious_approval must be boolean true')),
        isTrue,
      );
    });

    test('rejects reviewer name mismatch between manifest and report', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );
      manifestSection['reviewer_name'] = 'Different Reviewer Name';

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Reviewer name mismatch')),
        isTrue,
      );
    });

    test('rejects reviewer qualifications mismatch', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );
      manifestSection['reviewer_qualifications'] =
          'Different scholar credentials';

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Reviewer qualifications mismatch'),
        ),
        isTrue,
      );
    });

    test('rejects review date mismatch', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );
      manifestSection['review_date'] = '2026-10-06';

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Review date mismatch')),
        isTrue,
      );
    });

    test('rejects invalid or impossible calendar dates', () async {
      expect(HumanReviewValidator.isValidCalendarDate('2026-10-07'), isTrue);
      expect(HumanReviewValidator.isValidCalendarDate('2026-02-28'), isTrue);
      // 2026 is not a leap year: Feb 29 must fail
      expect(HumanReviewValidator.isValidCalendarDate('2026-02-29'), isFalse);
      // 2024 was a leap year: Feb 29 must pass
      expect(HumanReviewValidator.isValidCalendarDate('2024-02-29'), isTrue);
      // April has 30 days: April 31 must fail
      expect(HumanReviewValidator.isValidCalendarDate('2026-04-31'), isFalse);
      // Month 13 must fail
      expect(HumanReviewValidator.isValidCalendarDate('2026-13-01'), isFalse);
      // Day 0 must fail
      expect(HumanReviewValidator.isValidCalendarDate('2026-01-00'), isFalse);
      // Non-date string must fail
      expect(HumanReviewValidator.isValidCalendarDate('not-a-date'), isFalse);
    });

    test('rejects placeholder reviewer information', () async {
      expect(HumanReviewValidator.isPlaceholder('TODO'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('TBD'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('N/A'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('placeholder'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('dummy'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('John Doe'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('Jane Doe'), isTrue);
      expect(HumanReviewValidator.isPlaceholder('...'), isTrue);
      expect(
        HumanReviewValidator.isPlaceholder('Sheikh Abdullah Al-Mansoor'),
        isFalse,
      );
    });

    test('rejects tampered evidence report SHA-256', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: 'f' * 64, // tampered digest
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('evidence SHA-256 mismatch')),
        isTrue,
      );
    });

    test('rejects tampered underlying asset bytes on disk', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      // Tamper test1.txt on disk
      final f1 = File(p.join(normalizedRoot, testPath1));
      await f1.writeAsString('Corrupt or tampered content');

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
        verifyActualBytes: true,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Underlying asset byte SHA-256 mismatch on disk'),
        ),
        isTrue,
      );
    });

    test('rejects missing inventory entries in report', () async {
      final reportData = createValidReportData();
      final hashes =
          reportData['reviewed_hashes'] as Map<String, String>;
      hashes.remove(testPath2.replaceAll('\\', '/')); // Remove test2
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Missing review hash claim for required religious asset'),
        ),
        isTrue,
      );
    });

    test('rejects extra unexpected inventory entry in report', () async {
      final reportData = createValidReportData();
      final hashes =
          reportData['reviewed_hashes'] as Map<String, String>;
      hashes['assets/content/extra.txt'] = 'a' * 64;
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Unexpected or extra review hash claim')),
        isTrue,
      );
    });

    test('detects and rejects duplicate JSON keys in report file', () async {
      // Craft JSON string with duplicate key
      const duplicateJson = '''
{
  "schema_version": 1,
  "religious_approval": true,
  "reviewer_name": "Sheikh Abdullah Al-Mansoor",
  "reviewer_name": "Duplicate Reviewer",
  "reviewer_qualifications": "Senior Scholar",
  "review_date": "2026-10-07",
  "scope": "All corpora",
  "review_method": "Inspection",
  "coverage": "Complete",
  "concerns_and_limitations": "None",
  "reviewed_hashes": {}
}
''';

      final dupKey =
          HumanReviewValidator.findDuplicateJsonKey(duplicateJson);
      expect(dupKey, 'reviewer_name');

      final report = await writeReportFile(
        {},
        rawContentOverride: duplicateJson,
      );

      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications': 'Senior Scholar',
        'review_date': '2026-10-07',
        'evidence_path': report.reportRelPath,
        'evidence_sha256': report.reportSha256,
        'reviewed_hashes': <String, String>{},
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Duplicate JSON key found in evidence report'),
        ),
        isTrue,
      );
    });

    test('rejects disallowed alias inventory list and requires canonical reviewed_hashes map', () async {
      final reportData = createValidReportData();
      reportData.remove('reviewed_hashes');
      final posix1 = testPath1.replaceAll('\\', '/');
      final posix2 = testPath2.replaceAll('\\', '/');
      final posix3 = testPath3.replaceAll('\\', '/');

      reportData['inventory'] = [
        {'path': posix1, 'sha256': sha1},
        {'path': posix2, 'sha256': sha2},
        {'path': posix3, 'sha256': sha3},
      ];

      final report = await writeReportFile(reportData);
      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': reportData['reviewer_name'],
        'reviewer_qualifications': reportData['reviewer_qualifications'],
        'review_date': reportData['review_date'],
        'evidence_path': report.reportRelPath,
        'evidence_sha256': report.reportSha256,
        'reviewed_hashes': Map<String, String>.from(
          syntheticCanonicalInventory,
        ),
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('disallowed alias "inventory"'),
        ),
        isTrue,
      );
    });

    test('detects and rejects duplicate paths in reviewed_hashes JSON map', () async {
      final posix1 = testPath1.replaceAll('\\', '/');
      final posix2 = testPath2.replaceAll('\\', '/');
      final posix3 = testPath3.replaceAll('\\', '/');

      final duplicateHashesJson = '''
{
  "schema_version": 1,
  "religious_approval": true,
  "reviewer_name": "Sheikh Abdullah Al-Mansoor",
  "reviewer_qualifications": "Senior Scholar in Quranic Sciences",
  "review_date": "2026-10-07",
  "scope": "All synthetic corpora",
  "review_method": "Letter-by-letter comparison",
  "coverage": "Complete synthetic coverage",
  "concerns_and_limitations": "Offline bundle only",
  "reviewed_hashes": {
    "$posix1": "$sha1",
    "$posix2": "$sha2",
    "$posix3": "$sha3",
    "$posix1": "$sha1"
  }
}
''';

      final dupKey =
          HumanReviewValidator.findDuplicateJsonKey(duplicateHashesJson);
      expect(dupKey, posix1);

      final report = await writeReportFile(
        {},
        rawContentOverride: duplicateHashesJson,
      );

      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications': 'Senior Scholar in Quranic Sciences',
        'review_date': '2026-10-07',
        'evidence_path': report.reportRelPath,
        'evidence_sha256': report.reportSha256,
        'reviewed_hashes': Map<String, String>.from(syntheticCanonicalInventory),
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Duplicate JSON key found in evidence report'),
        ),
        isTrue,
      );
    });

    test('rejects unsafe directory traversal in evidence_path', () async {
      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications': 'Senior Scholar',
        'review_date': '2026-10-07',
        'evidence_path': '../../outside_file.json',
        'evidence_sha256': 'a' * 64,
        'reviewed_hashes': <String, String>{},
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Unsafe or invalid evidence_path')),
        isTrue,
      );
    });

    test('rejects report file exceeding 1 MiB size bound', () async {
      final bigBuffer = StringBuffer();
      bigBuffer.write('{"junk": "');
      bigBuffer.write('x' * (1024 * 1024 + 10)); // Over 1 MiB
      bigBuffer.write('"}');

      final report = await writeReportFile(
        {},
        rawContentOverride: bigBuffer.toString(),
      );

      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications': 'Senior Scholar',
        'review_date': '2026-10-07',
        'evidence_path': report.reportRelPath,
        'evidence_sha256': report.reportSha256,
        'reviewed_hashes': <String, String>{},
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('exceeds 1 MiB bound')),
        isTrue,
      );
    });

    test('rejects report containing invalid UTF-8 bytes', () async {
      final file = File(
        p.join(normalizedRoot, 'docs', 'reviews', 'bad_utf8.json'),
      );
      await file.parent.create(recursive: true);
      final badBytes = [0xFF, 0xFE, 0x00, 0x01];
      await file.writeAsBytes(badBytes);

      final sha = sha256.convert(badBytes).toString().toLowerCase();

      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications': 'Senior Scholar',
        'review_date': '2026-10-07',
        'evidence_path': 'docs/reviews/bad_utf8.json',
        'evidence_sha256': sha,
        'reviewed_hashes': <String, String>{},
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('not valid UTF-8')),
        isTrue,
      );
    });

    test('rejects schema_version other than 1', () async {
      final reportData = createValidReportData();
      reportData['schema_version'] = 2; // Unsupported schema
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Unsupported schema_version')),
        isTrue,
      );
    });

    test('rejects manifest approved: true when evidence_path is missing', () async {
      final manifestSection = <String, dynamic>{
        'status': 'approved',
        'approved': true,
        'reviewer_name': 'Sheikh Abdullah Al-Mansoor',
        'reviewer_qualifications': 'Senior Scholar',
        'review_date': '2026-10-07',
        'evidence_path': null,
        'evidence_sha256': null,
        'reviewed_hashes': <String, String>{},
      };

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('evidence_path is missing')),
        isTrue,
      );
    });

    test('rejects non-string or empty/placeholder scope in report', () async {
      // Non-string type (int)
      var reportData = createValidReportData();
      reportData['scope'] = 12345;
      var report = await writeReportFile(reportData);
      var manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      var result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('scope" must be a string')), isTrue);

      // Placeholder
      reportData = createValidReportData();
      reportData['scope'] = 'TODO: add scope';
      report = await writeReportFile(reportData);
      manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('missing, empty, or placeholder scope')), isTrue);
    });

    test('rejects non-string or empty/placeholder review_method in report', () async {
      // Non-string type (List)
      var reportData = createValidReportData();
      reportData['review_method'] = ['manual_inspection'];
      var report = await writeReportFile(reportData);
      var manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      var result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('review_method" must be a string')), isTrue);

      // Placeholder
      reportData = createValidReportData();
      reportData['review_method'] = 'TBD';
      report = await writeReportFile(reportData);
      manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('missing, empty, or placeholder review_method')), isTrue);
    });

    test('rejects non-string or empty/placeholder coverage in report', () async {
      // Non-string type (Map)
      var reportData = createValidReportData();
      reportData['coverage'] = {'all': true};
      var report = await writeReportFile(reportData);
      var manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      var result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('coverage" must be a string')), isTrue);

      // Placeholder
      reportData = createValidReportData();
      reportData['coverage'] = 'N/A';
      report = await writeReportFile(reportData);
      manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('missing, empty, or placeholder coverage')), isTrue);
    });

    test('rejects non-string or empty/placeholder concerns_and_limitations in report', () async {
      // Non-string type (bool)
      var reportData = createValidReportData();
      reportData['concerns_and_limitations'] = false;
      var report = await writeReportFile(reportData);
      var manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      var result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('concerns_and_limitations" must be a string')), isTrue);

      // Placeholder
      reportData = createValidReportData();
      reportData['concerns_and_limitations'] = 'none';
      report = await writeReportFile(reportData);
      manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.contains('missing, empty, or placeholder concerns_and_limitations')), isTrue);
    });

    test('rejects simultaneous religious_approval: true and approved: false alias conflict', () async {
      final reportData = createValidReportData();
      reportData['approved'] = false; // Conflicting alias alongside religious_approval: true
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('disallowed alias "approved"')),
        isTrue,
      );
    });

    test('rejects disallowed aliases schemaVersion, reviewer_qualification, date, reviewMethod, concerns, limitations in report', () async {
      for (final aliasEntry in [
        ('schemaVersion', 1),
        ('reviewer_qualification', 'Scholar'),
        ('date', '2026-10-07'),
        ('reviewMethod', 'Method'),
        ('concerns', 'Limitations text'),
        ('limitations', 'Limitations text'),
      ]) {
        final reportData = createValidReportData();
        reportData[aliasEntry.$1] = aliasEntry.$2;
        final report = await writeReportFile(reportData);

        final manifestSection = createValidManifestSection(
          reportRelPath: report.reportRelPath,
          reportSha256: report.reportSha256,
          reportData: reportData,
        );

        final result = await HumanReviewValidator.validate(
          humanReviewRegistry: manifestSection,
          normalizedRoot: normalizedRoot,
          canonicalRoot: canonicalRoot,
          canonicalInventoryOverride: syntheticCanonicalInventory,
        );

        expect(result.isValid, isFalse);
        expect(
          result.errors.any((e) => e.contains('disallowed alias "${aliasEntry.$1}"')),
          isTrue,
        );
      }
    });

    test('rejects unrecognized extra fields in report', () async {
      final reportData = createValidReportData();
      reportData['extra_unrecognized_key'] = 'unexpected value';
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('unrecognized field: "extra_unrecognized_key"')),
        isTrue,
      );
    });

    test('rejects disallowed aliases or conflicting fields in manifest human_review section', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );
      manifestSection['religious_approval'] = false; // Conflicting alias in manifest

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('disallowed alias or conflicting field "religious_approval"'),
        ),
        isTrue,
      );
    });

    test('verifyActualBytes: false blocks approval and omits byte integrity verification message', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
        verifyActualBytes: false,
      );

      expect(result.isValid, isTrue);
      expect(result.isApproved, isFalse);
      expect(result.errors, isEmpty);
      expect(
        result.verifiedItems.any((v) => v.contains('bytes not verified')),
        isTrue,
      );
      expect(
        result.verifiedItems.any((v) => v.contains('Underlying asset byte integrity verified on disk')),
        isFalse,
      );
    });

    test('underlyingIntegritySuccess: false blocks approval and omits byte integrity verification message', () async {
      final reportData = createValidReportData();
      final report = await writeReportFile(reportData);

      final manifestSection = createValidManifestSection(
        reportRelPath: report.reportRelPath,
        reportSha256: report.reportSha256,
        reportData: reportData,
      );

      final result = await HumanReviewValidator.validate(
        humanReviewRegistry: manifestSection,
        normalizedRoot: normalizedRoot,
        canonicalRoot: canonicalRoot,
        canonicalInventoryOverride: syntheticCanonicalInventory,
        underlyingIntegritySuccess: false,
        verifyActualBytes: true,
      );

      expect(result.isValid, isTrue);
      expect(result.isApproved, isFalse);
      expect(result.errors, isEmpty);
      expect(
        result.verifiedItems.any((v) => v.contains('Underlying asset integrity gate pending or failed elsewhere')),
        isTrue,
      );
      expect(
        result.verifiedItems.any((v) => v.contains('Underlying asset byte integrity verified on disk')),
        isFalse,
      );
    });
  });

  group('HumanReviewValidator - Full Canonical Corpus Derivation', () {
    test(
      'buildCanonicalReligiousInventory produces exactly 624 religious artifacts',
      () {
        final inventory =
            HumanReviewValidator.buildCanonicalReligiousInventory(
          normalizedRoot: currentDir,
        );

        expect(inventory.length, HumanReviewValidator.kExpectedTotalReligiousItems);

        // Tanzil Quran text and metadata (2)
        expect(
          inventory['assets/content/quran/quran-uthmani.txt'],
          QuranSourceConstants.canonicalTextSha256,
        );
        expect(
          inventory['assets/content/quran/quran-data.xml'],
          QuranSourceConstants.canonicalMetadataSha256,
        );

        // HadeethEnc (2)
        expect(
          inventory['assets/content/hadith/hadeethenc-ar.xlsx'],
          ContentValidator.kExpectedHadithSourceSha256,
        );
        expect(
          inventory['assets/content/hadith/hadith-enc-sahih.json'],
          ContentValidator.kExpectedHadithJsonSha256,
        );

        // Hisn al-Muslim (2)
        expect(
          inventory['assets/content/hisn/hisn-muslim-source.docx'],
          ContentValidator.kExpectedHisnSourceSha256,
        );
        expect(
          inventory['assets/content/hisn/hisn-muslim.json'],
          ContentValidator.kExpectedHisnJsonSha256,
        );

        // Medina Mushaf page catalog (2)
        expect(
          inventory[KfqcMushafCatalog.boundsAssetPath],
          ContentValidator.kExpectedKfqcBoundsSha256,
        );
        expect(
          inventory[KfqcMushafCatalog.digestsAssetPath],
          ContentValidator.kExpectedKfqcDigestsSha256,
        );

        // 604 Medina Mushaf page images (604)
        for (int p = 1; p <= 604; p++) {
          final pagePath = KfqcMushafCatalog.pageAssetPath(p);
          expect(inventory.containsKey(pagePath), isTrue);
          expect(inventory[pagePath]!.length, 64);
        }

        // 3 Full adhan MP3s
        for (final voice in ContentValidator.kExpectedAdhanVoiceIds) {
          final audioPath = ContentValidator.kExpectedAdhanAudioPaths[voice]!;
          expect(
            inventory[audioPath],
            ContentValidator.kExpectedAdhanAudioSha256[voice],
          );
        }

        // 3 Alert WAVs in assets
        for (final voice in ContentValidator.kExpectedAdhanVoiceIds) {
          final alertPath = ContentValidator.kExpectedAdhanAlertPaths[voice]!;
          expect(
            inventory[alertPath],
            ContentValidator.kExpectedAdhanAlertSha256[voice],
          );
        }

        // 3 iOS Runner alert clips
        for (final voice in ContentValidator.kExpectedAdhanVoiceIds) {
          final iosPath = ContentValidator.kExpectedAdhanIosAlertPaths[voice]!;
          expect(
            inventory[iosPath],
            ContentValidator.kExpectedAdhanAlertSha256[voice],
          );
        }

        // 3 Android res/raw alert clips
        for (final voice in ContentValidator.kExpectedAdhanVoiceIds) {
          final androidPath =
              ContentValidator.kExpectedAdhanAndroidAlertPaths[voice]!;
          expect(
            inventory[androidPath],
            ContentValidator.kExpectedAdhanAlertSha256[voice],
          );
        }
      },
    );
  });

  group('ContentValidator - Real 624-Artifact Release Integration', () {
    test(
      'full release validation with synthetic test reviewer clears human review blocker against real corpus',
      () async {
        final realInventory =
            HumanReviewValidator.buildCanonicalReligiousInventory(
          normalizedRoot: currentDir,
        );
        expect(
          realInventory.length,
          HumanReviewValidator.kExpectedTotalReligiousItems,
        );

        // Unique temporary contained directory inside .local/
        final tempDirName =
            'test_ephemeral_integration_${DateTime.now().microsecondsSinceEpoch}';
        final tempDirPath = p.join(currentDir, '.local', tempDirName);
        final tempDir = Directory(tempDirPath);
        await tempDir.create(recursive: true);

        try {
          // 1. Synthetic test evidence report covering all 624 real items
          final reportData = <String, dynamic>{
            'schema_version': 1,
            'religious_approval': true,
            'reviewer_name': 'SYNTHETIC TEST (Automated Integration Only)',
            'reviewer_qualifications':
                'Synthetic automated test fixture credentials - not an actual human religious review',
            'review_date': '2026-10-07',
            'scope':
                'Complete synthetic integration review covering all 624 bundled religious artifacts on disk',
            'review_method':
                'Full automated cryptographic hash computation and disk byte verification',
            'coverage':
                '100% complete coverage of all 624 canonical religious files',
            'concerns_and_limitations':
                'Automated integration fixture evidence only; not a real scholar sign-off',
            'reviewed_hashes': Map<String, String>.from(realInventory),
          };

          final reportFile = File(
            p.join(tempDir.path, 'human_content_review_test.json'),
          );
          final reportBytes = utf8.encode(jsonEncode(reportData));
          await reportFile.writeAsBytes(reportBytes);
          final reportSha256 =
              sha256.convert(reportBytes).toString().toLowerCase();
          final reportRelPath = p
              .relative(reportFile.path, from: currentDir)
              .replaceAll('\\', '/');

          // 2. Ephemeral manifest derived from canonical manifest
          final canonicalManifestFile = File(
            p.join(currentDir, 'assets', 'content', 'manifest.json'),
          );
          expect(canonicalManifestFile.existsSync(), isTrue);

          final manifestMap =
              jsonDecode(await canonicalManifestFile.readAsString())
                  as Map<String, dynamic>;
          final pending =
              manifestMap['pending_registries'] as Map<String, dynamic>;

          pending['human_review'] = <String, dynamic>{
            'status': 'approved',
            'approved': true,
            'reviewer_name': reportData['reviewer_name'],
            'reviewer_qualifications': reportData['reviewer_qualifications'],
            'review_date': reportData['review_date'],
            'evidence_path': reportRelPath,
            'evidence_sha256': reportSha256,
            'reviewed_hashes': Map<String, String>.from(realInventory),
          };

          final testManifestFile = File(p.join(tempDir.path, 'manifest.json'));
          await testManifestFile.writeAsString(jsonEncode(manifestMap));
          final manifestRelPath = p
              .relative(testManifestFile.path, from: currentDir)
              .replaceAll('\\', '/');

          // 3. Run ContentValidator in release mode (isDevelopmentMode: false)
          final releaseResult = await ContentValidator.validate(
            workspaceRoot: currentDir,
            isDevelopmentMode: false,
            manifestRelativePath: manifestRelPath,
          );

          expect(
            releaseResult.isDevelopmentValid,
            isTrue,
            reason: releaseResult.toReport(),
          );
          expect(
            releaseResult.isReleaseReady,
            isTrue,
            reason: releaseResult.toReport(),
          );
          expect(
            releaseResult.errors,
            isEmpty,
            reason: releaseResult.toReport(),
          );
          expect(
            releaseResult.pendingReleaseBlockers.any(
              (b) => b.contains(HumanReviewValidator.kPendingBlockerMessage),
            ),
            isFalse,
          );
          expect(
            releaseResult.verifiedItems.any(
              (v) => v.contains(
                'Reviewer declaration fields matched: SYNTHETIC TEST',
              ),
            ),
            isTrue,
          );
          expect(
            releaseResult.verifiedItems.any(
              (v) => v.contains(
                'Underlying asset byte integrity verified on disk (624 assets)',
              ),
            ),
            isTrue,
          );

          // 4. Test tamper / partial inventory case: must block release
          final tamperedReportData = Map<String, dynamic>.from(reportData);
          final tamperedHashes = Map<String, String>.from(realInventory);
          tamperedHashes['assets/content/quran/quran-uthmani.txt'] = '0' * 64;
          tamperedReportData['reviewed_hashes'] = tamperedHashes;

          final tamperedReportFile = File(
            p.join(tempDir.path, 'tampered_report.json'),
          );
          final tamperedReportBytes =
              utf8.encode(jsonEncode(tamperedReportData));
          await tamperedReportFile.writeAsBytes(tamperedReportBytes);
          final tamperedReportSha = sha256
              .convert(tamperedReportBytes)
              .toString()
              .toLowerCase();
          final tamperedReportRel = p
              .relative(tamperedReportFile.path, from: currentDir)
              .replaceAll('\\', '/');

          final tamperedManifestMap =
              jsonDecode(await canonicalManifestFile.readAsString())
                  as Map<String, dynamic>;
          final tamperedPending =
              tamperedManifestMap['pending_registries']
                  as Map<String, dynamic>;
          tamperedPending['human_review'] = <String, dynamic>{
            'status': 'approved',
            'approved': true,
            'reviewer_name': reportData['reviewer_name'],
            'reviewer_qualifications': reportData['reviewer_qualifications'],
            'review_date': reportData['review_date'],
            'evidence_path': tamperedReportRel,
            'evidence_sha256': tamperedReportSha,
            'reviewed_hashes': Map<String, String>.from(tamperedHashes),
          };

          final tamperedManifestFile = File(
            p.join(tempDir.path, 'tampered_manifest.json'),
          );
          await tamperedManifestFile.writeAsString(
            jsonEncode(tamperedManifestMap),
          );
          final tamperedManifestRel = p
              .relative(tamperedManifestFile.path, from: currentDir)
              .replaceAll('\\', '/');

          final tamperedResult = await ContentValidator.validate(
            workspaceRoot: currentDir,
            isDevelopmentMode: false,
            manifestRelativePath: tamperedManifestRel,
          );

          expect(tamperedResult.isReleaseReady, isFalse);
          expect(
            tamperedResult.pendingReleaseBlockers.any(
              (b) => b.contains(HumanReviewValidator.kPendingBlockerMessage),
            ),
            isTrue,
          );
          expect(
            tamperedResult.errors.any(
              (e) =>
                  e.contains('assets/content/quran/quran-uthmani.txt') &&
                  (e.contains('mismatch') || e.contains('hash')),
            ),
            isTrue,
          );
        } finally {
          // Cleanup ephemeral directory
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }

          // Canonical manifest remains untouched and pending
          final canonicalManifestFile = File(
            p.join(currentDir, 'assets', 'content', 'manifest.json'),
          );
          final canonicalManifest =
              jsonDecode(await canonicalManifestFile.readAsString())
                  as Map<String, dynamic>;
          final pendingCanonical =
              canonicalManifest['pending_registries']
                  as Map<String, dynamic>;
          final humanCanonical =
              pendingCanonical['human_review'] as Map<String, dynamic>;
          expect(humanCanonical['status'], 'pending');
          expect(humanCanonical['approved'], isFalse);
        }
      },
    );
  });
}
