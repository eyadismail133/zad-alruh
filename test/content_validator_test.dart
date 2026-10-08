import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:zad_alruh/src/core/content/content_validator.dart';

/// Helper to generate minimal valid or intentional-invalid PCM WAV byte arrays for inspection tests.
Uint8List createDummyWavBytes({
  int sampleRate = 16000,
  int channels = 1,
  int bitDepth = 16,
  int dataBytesCount = 32000,
  int? headerClaimedDataSize,
  int? headerClaimedRiffSize,
  int audioFormat = 1,
}) {
  final blockAlign = channels * (bitDepth ~/ 8);
  final byteRate = sampleRate * blockAlign;
  final claimedData = headerClaimedDataSize ?? dataBytesCount;
  final riffPayloadSize =
      headerClaimedRiffSize ?? (4 + (8 + 16) + (8 + dataBytesCount));

  final builder = BytesBuilder();
  // 'RIFF'
  builder.add(utf8.encode('RIFF'));
  final bdRiff = ByteData(4)..setUint32(0, riffPayloadSize, Endian.little);
  builder.add(bdRiff.buffer.asUint8List());
  // 'WAVE'
  builder.add(utf8.encode('WAVE'));
  // 'fmt '
  builder.add(utf8.encode('fmt '));
  final bdFmtSize = ByteData(4)..setUint32(0, 16, Endian.little);
  builder.add(bdFmtSize.buffer.asUint8List());
  final bdFmt = ByteData(16);
  bdFmt.setUint16(0, audioFormat, Endian.little);
  bdFmt.setUint16(2, channels, Endian.little);
  bdFmt.setUint32(4, sampleRate, Endian.little);
  bdFmt.setUint32(8, byteRate, Endian.little);
  bdFmt.setUint16(12, blockAlign, Endian.little);
  bdFmt.setUint16(14, bitDepth, Endian.little);
  builder.add(bdFmt.buffer.asUint8List());
  // 'data'
  builder.add(utf8.encode('data'));
  final bdDataSize = ByteData(4)..setUint32(0, claimedData, Endian.little);
  builder.add(bdDataSize.buffer.asUint8List());
  builder.add(Uint8List(dataBytesCount));

  return builder.toBytes();
}

/// Creates a directory junction on Windows or symbolic link on non-Windows.
///
/// On Windows, junction creation is supported for standard users via PowerShell.
/// Fails the test on non-zero exit or invalid target (does not skip).
/// On non-Windows, if an unsupported OS permission error occurs, marks test skipped.
Future<void> _createDirectoryJunction({
  required String junctionPath,
  required String targetPath,
}) async {
  // Scoped literal target checks before creation
  final targetDir = Directory(targetPath);
  if (!await targetDir.exists()) {
    throw StateError(
      'Target directory does not exist for junction creation: $targetPath',
    );
  }

  if (Platform.isWindows) {
    // Single quotes with literal escaping ('' for ') and -ErrorAction Stop
    final escapedPath = junctionPath.replaceAll("'", "''");
    final escapedTarget = targetPath.replaceAll("'", "''");
    final script =
        "New-Item -ItemType Junction -Path '$escapedPath' -Target '$escapedTarget' -ErrorAction Stop";

    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);

    if (result.exitCode != 0) {
      throw StateError(
        'PowerShell directory junction creation failed (exit code ${result.exitCode}):\n'
        'STDOUT: ${result.stdout}\n'
        'STDERR: ${result.stderr}',
      );
    }
  } else {
    final link = Link(junctionPath);
    try {
      await link.create(targetPath);
    } on FileSystemException catch (e) {
      final osError = e.osError;
      if (osError != null &&
          (osError.errorCode == 1 ||
              osError.errorCode == 13 ||
              osError.errorCode == 38)) {
        markTestSkipped('Symlink creation unsupported: ${e.message}');
        return;
      }
      rethrow;
    }
  }

  // Verify actual link type and target immediately after creation
  final entityType = await FileSystemEntity.type(
    junctionPath,
    followLinks: false,
  );
  if (entityType != FileSystemEntityType.link) {
    throw StateError(
      'Created junction entity is not FileSystemEntityType.link: $entityType',
    );
  }
  final link = Link(junctionPath);
  final actualTarget = await link.target();
  if (p.normalize(actualTarget) != p.normalize(targetPath)) {
    throw StateError(
      'Created junction target mismatch: actual "$actualTarget" != expected "$targetPath"',
    );
  }
}

/// Safely unlinks a directory junction non-recursively using pure Dart Link.delete.
///
/// Verifies link type and expected target BEFORE unlinking.
/// Verifies point is absent after unlink and outside sentinel file remains
/// BEFORE any recursive cleanup of owned fixture paths.
/// Cleanup failure propagates immediately (never continues recursive cleanup through surviving junction).
Future<void> _safeUnlinkJunction({
  required String junctionPath,
  required String expectedTarget,
  required File sentinelFile,
}) async {
  final link = Link(junctionPath);

  // 1. Verify actual link type BEFORE unlink
  final entityType = await FileSystemEntity.type(
    junctionPath,
    followLinks: false,
  );
  if (entityType != FileSystemEntityType.link) {
    throw StateError(
      'Cannot safely unlink non-link entity at "$junctionPath" (type: $entityType)',
    );
  }

  // 2. Verify link target matches known expected target owned by this fixture
  final actualTarget = await link.target();
  if (p.normalize(actualTarget) != p.normalize(expectedTarget)) {
    throw StateError(
      'Refusing to unlink junction pointing to unexpected target: '
      'actual "$actualTarget" != expected "$expectedTarget"',
    );
  }

  // 3. Pure Dart Link.delete (non-recursive)
  await link.delete();

  // 4. Verify junction point is absent after unlink
  final postType = await FileSystemEntity.type(
    junctionPath,
    followLinks: false,
  );
  if (postType != FileSystemEntityType.notFound) {
    throw StateError(
      'Junction point still exists after unlink at "$junctionPath" (surviving type: $postType)',
    );
  }

  // 5. Verify outside sentinel file remains intact
  if (!await sentinelFile.exists()) {
    throw StateError(
      'Outside target sentinel file was damaged or missing after unlinking junction: ${sentinelFile.path}',
    );
  }
}

void main() {
  final currentDir = Directory.current.path;

  group('ContentValidator - Real Workspace Sources', () {
    test(
      'development source verification passes on bundled sources and lists all pending prerequisites',
      () async {
        final result = await ContentValidator.validate(
          workspaceRoot: currentDir,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isTrue);
        expect(result.errors, isEmpty);

        // Must list the 1 remaining pending release prerequisite (Hadith, Hisn, Quran images, and Adhan audio blockers resolved)
        expect(result.pendingReleaseBlockers.length, 1);
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('604 Medina Mushaf page images'),
          ),
          isFalse,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('3 licensed adhan recordings'),
          ),
          isFalse,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('Hisn al-Muslim'),
          ),
          isFalse,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('Qualified human reviewer'),
          ),
          isTrue,
        );
        expect(
          result.pendingReleaseBlockers.any((b) => b.contains('HadeethEnc')),
          isFalse,
        );

        // Verify report formatting
        final report = result.toReport(isDevelopment: true);
        expect(
          report,
          contains('RESULT: Development source-integrity verification PASSED.'),
        );
        expect(report, contains('NOTICE: This build is NOT release-ready'));
      },
    );

    test(
      'default release mode fails because release prerequisites are incomplete',
      () async {
        final result = await ContentValidator.validate(
          workspaceRoot: currentDir,
          isDevelopmentMode: false,
        );

        expect(result.isReleaseReady, isFalse);
        expect(result.pendingReleaseBlockers, isNotEmpty);

        final report = result.toReport(isDevelopment: false);
        expect(report, contains('RESULT: Release validation BLOCKED.'));
      },
    );
  });

  group('ContentValidator - Isolated Workspace Hardening & Security', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('validator_harden_test_');

      // Create content subdirectories
      final quranDir = Directory(
        p.join(tempDir.path, 'assets', 'content', 'quran'),
      );
      await quranDir.create(recursive: true);
      final citiesDir = Directory(
        p.join(tempDir.path, 'assets', 'content', 'cities'),
      );
      await citiesDir.create(recursive: true);
      final hadithDir = Directory(
        p.join(tempDir.path, 'assets', 'content', 'hadith'),
      );
      await hadithDir.create(recursive: true);
      final hisnDir = Directory(
        p.join(tempDir.path, 'assets', 'content', 'hisn'),
      );
      await hisnDir.create(recursive: true);
      final adhanAudioDir = Directory(
        p.join(tempDir.path, 'assets', 'audio', 'adhan'),
      );
      await adhanAudioDir.create(recursive: true);
      final iosRunnerDir = Directory(
        p.join(tempDir.path, 'ios', 'Runner'),
      );
      await iosRunnerDir.create(recursive: true);
      final androidRawDir = Directory(
        p.join(tempDir.path, 'android', 'app', 'src', 'main', 'res', 'raw'),
      );
      await androidRawDir.create(recursive: true);

      // Copy real bundled files into temp
      await File(
        'assets/content/manifest.json',
      ).copy(p.join(tempDir.path, 'assets', 'content', 'manifest.json'));
      await File('assets/content/quran/quran-uthmani.txt').copy(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'quran-uthmani.txt'),
      );
      await File('assets/content/quran/quran-data.xml').copy(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'quran-data.xml'),
      );
      await File('assets/content/cities/cities15000.txt').copy(
        p.join(tempDir.path, 'assets', 'content', 'cities', 'cities15000.txt'),
      );
      await File('assets/content/cities/GEONAMES-LICENSE-README.txt').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'cities',
          'GEONAMES-LICENSE-README.txt',
        ),
      );
      await File('assets/content/hadith/hadeethenc-ar.xlsx').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'hadith',
          'hadeethenc-ar.xlsx',
        ),
      );
      await File('assets/content/hadith/hadith-enc-sahih.json').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'hadith',
          'hadith-enc-sahih.json',
        ),
      );
      await File('assets/content/hisn/hisn-muslim-source.docx').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'hisn',
          'hisn-muslim-source.docx',
        ),
      );
      await File('assets/content/hisn/hisn-muslim.json').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'hisn',
          'hisn-muslim.json',
        ),
      );

      // Create docs subdirectories and copy referenced source documentation
      final docsSourcesDir = Directory(p.join(tempDir.path, 'docs', 'sources'));
      await docsSourcesDir.create(recursive: true);

      await File(
        'docs/sources/TANZIL.md',
      ).copy(p.join(tempDir.path, 'docs', 'sources', 'TANZIL.md'));
      await File(
        'docs/sources/GEONAMES.md',
      ).copy(p.join(tempDir.path, 'docs', 'sources', 'GEONAMES.md'));
      await File(
        'docs/sources/HADEETHENC.md',
      ).copy(p.join(tempDir.path, 'docs', 'sources', 'HADEETHENC.md'));
      await File(
        'docs/sources/HISN_ALMUSLIM.md',
      ).copy(p.join(tempDir.path, 'docs', 'sources', 'HISN_ALMUSLIM.md'));
      await File(
        'docs/sources/KFQC_MUSHAF.md',
      ).copy(p.join(tempDir.path, 'docs', 'sources', 'KFQC_MUSHAF.md'));
      await File(
        'docs/sources/ADHAN_AUDIO.md',
      ).copy(p.join(tempDir.path, 'docs', 'sources', 'ADHAN_AUDIO.md'));

      final adhanFiles = [
        'adam-converted.mp3',
        'atcovi-original.mp3',
        'malmo-fajr-extracted.mp3',
        'adam-alert.wav',
        'atcovi-alert.wav',
        'malmo-fajr-alert.wav',
      ];
      for (final f in adhanFiles) {
        await File('assets/audio/adhan/$f').copy(
          p.join(tempDir.path, 'assets', 'audio', 'adhan', f),
        );
      }

      final iosAlertFiles = [
        'adam-alert.wav',
        'atcovi-alert.wav',
        'malmo-fajr-alert.wav',
      ];
      for (final f in iosAlertFiles) {
        await File('ios/Runner/$f').copy(
          p.join(tempDir.path, 'ios', 'Runner', f),
        );
      }

      final androidAlertFiles = [
        'adam_alert.wav',
        'atcovi_alert.wav',
        'malmo_fajr_alert.wav',
      ];
      for (final f in androidAlertFiles) {
        await File('android/app/src/main/res/raw/$f').copy(
          p.join(tempDir.path, 'android', 'app', 'src', 'main', 'res', 'raw', f),
        );
      }

      await File('assets/content/quran/kfqc-page-bounds.json').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'quran',
          'kfqc-page-bounds.json',
        ),
      );
      await File('assets/content/quran/quran-pages-digests.json').copy(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'quran',
          'quran-pages-digests.json',
        ),
      );

      final targetPagesDir = Directory(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'pages'),
      );
      await targetPagesDir.create(recursive: true);
      if (Platform.isWindows) {
        await Process.run('robocopy', [
          p.join(Directory.current.path, 'assets', 'content', 'quran', 'pages'),
          targetPagesDir.path,
          '/e',
          '/njh',
          '/njs',
          '/ndl',
          '/nc',
          '/ns',
          '/nfl',
        ]);
      } else {
        final srcDir = Directory('assets/content/quran/pages');
        await for (final entity in srcDir.list()) {
          if (entity is File) {
            await entity.copy(
              p.join(targetPagesDir.path, p.basename(entity.path)),
            );
          }
        }
      }
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'isolated fixture baseline is completely valid in development mode with zero errors',
      () async {
        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.errors, isEmpty);
        expect(result.isDevelopmentValid, isTrue);
        expect(result.isReleaseReady, isFalse);
        expect(result.pendingReleaseBlockers.length, 1);
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('Qualified human reviewer'),
          ),
          isTrue,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('3 licensed adhan recordings'),
          ),
          isFalse,
        );
      },
    );

    // 1. Schema & Field Types
    test(
      'rejects unsupported schema_version integer with actionable error',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        json['schema_version'] = 2;
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('Unsupported or invalid schema_version: 2'),
          ),
          isTrue,
        );
      },
    );

    test(
      'rejects non-integer schema_version with actionable error without crashing',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        json['schema_version'] = '1';
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('Unsupported or invalid schema_version: 1'),
          ),
          isTrue,
        );
      },
    );

    test('rejects malformed non-object corpora section gracefully', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      json['corpora'] = 'not-a-map';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('missing or malformed "corpora" section'),
        ),
        isTrue,
      );
    });

    // 2. Traversal & Containment
    test(
      'rejects path traversal attempting to escape workspace root',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final corpora = json['corpora'] as Map<String, dynamic>;
        final quranText = corpora['quran_text'] as Map<String, dynamic>;
        quranText['path'] = '../../secret.txt';
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any((e) => e.contains('Unsafe or invalid path')),
          isTrue,
        );
      },
    );

    test('rejects path containing null byte', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final corpora = json['corpora'] as Map<String, dynamic>;
      final quranText = corpora['quran_text'] as Map<String, dynamic>;
      quranText['path'] = 'assets/content/quran/\x00secret.txt';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Unsafe or invalid path')),
        isTrue,
      );
    });

    test(
      'rejects manifest resolving outside workspace root via directory junction',
      () async {
        final outsideContentDir = await Directory.systemTemp.createTemp(
          'outside_content_dir_',
        );
        final outsideManifest = File(
          p.join(outsideContentDir.path, 'manifest.json'),
        );
        await outsideManifest.writeAsString(
          jsonEncode(<String, dynamic>{'schema_version': 1}),
        );
        final outsideSentinel = File(
          p.join(outsideContentDir.path, 'sentinel.txt'),
        );
        await outsideSentinel.writeAsString('sentinel-manifest\n');

        final contentDir = Directory(p.join(tempDir.path, 'assets', 'content'));
        final contentOrig = Directory(
          p.join(tempDir.path, 'assets', 'content_orig'),
        );
        await contentDir.rename(contentOrig.path);

        await _createDirectoryJunction(
          junctionPath: contentDir.path,
          targetPath: outsideContentDir.path,
        );

        if (!await Link(contentDir.path).exists()) {
          // Non-Windows skip occurred via markTestSkipped
          if (await contentOrig.exists()) {
            await contentOrig.rename(contentDir.path);
          }
          if (await outsideContentDir.exists()) {
            await outsideContentDir.delete(recursive: true);
          }
          return;
        }

        try {
          final result = await ContentValidator.validate(
            workspaceRoot: tempDir.path,
            isDevelopmentMode: true,
          );

          expect(result.isDevelopmentValid, isFalse);
          expect(
            result.errors.any((e) => e.contains('Unsafe manifest path')),
            isTrue,
          );
        } finally {
          await _safeUnlinkJunction(
            junctionPath: contentDir.path,
            expectedTarget: outsideContentDir.path,
            sentinelFile: outsideSentinel,
          );
          if (await contentOrig.exists()) {
            await contentOrig.rename(contentDir.path);
          }
          if (await outsideContentDir.exists()) {
            await outsideContentDir.delete(recursive: true);
          }
        }
      },
    );

    // 3. Hash & License Verification
    test('altered hash in source text copy is caught and rejected', () async {
      final textFile = File(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'quran-uthmani.txt'),
      );
      final original = await textFile.readAsString();
      await textFile.writeAsString('$original\n# extra corrupted line');

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Quran text SHA-256 hash mismatch'),
        ),
        isTrue,
      );
    });

    test('altered hash in XML metadata copy is caught and rejected', () async {
      final xmlFile = File(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'quran-data.xml'),
      );
      final original = await xmlFile.readAsString();
      await xmlFile.writeAsString('$original<!-- corrupted comment -->');

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Quran metadata SHA-256 hash mismatch'),
        ),
        isTrue,
      );
    });

    test('mismatched metadata license is caught and rejected', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final corpora = json['corpora'] as Map<String, dynamic>;
      final qXml = corpora['quran_metadata'] as Map<String, dynamic>;
      qXml['license'] =
          'CC-BY-4.0'; // Must declare exact root 'cc-by' with unspecified version
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.contains('Quran metadata license must declare exact "cc-by"'),
        ),
        isTrue,
      );
    });

    // 4. Image Registry Hardening
    test(
      'images registry rejects declared page entries as unsupported import',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final images = pending['quran_images'] as Map<String, dynamic>;
        images['pages'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'page_number': 1,
            'path': 'assets/content/quran/images/page_001.png',
            'sha256': 'a' * 64,
            'rights_evidence': 'evidence.txt',
          },
        ];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any((e) => e.contains('unsupported at this milestone')),
          isTrue,
        );
      },
    );

    test(
      'images registry rejects non-list pages field and non-string status',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final images = pending['quran_images'] as Map<String, dynamic>;
        images['pages'] = 'not-a-list';
        images['status'] = false;
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any((e) => e.contains('"pages" field must be a list')),
          isTrue,
        );
        expect(
          result.errors.any(
            (e) => e.contains('Image registry status must be a string'),
          ),
          isTrue,
        );
      },
    );

    // 5. Audio & WAV Inspection Hardening
    test('inspectWavHeader validates legitimate PCM WAV header', () {
      final wavBytes = createDummyWavBytes(
        sampleRate: 16000,
        channels: 1,
        bitDepth: 16,
        dataBytesCount: 32000, // 1.0 second duration
      );

      final res = ContentValidator.inspectWavHeader(wavBytes);
      expect(res.isValid, isTrue);
      expect(res.channels, 1);
      expect(res.sampleRate, 16000);
      expect(res.bitDepth, 16);
      expect(res.dataSize, 32000);
      expect(res.durationSeconds, 1.0);
    });

    test(
      'inspectWavHeader rejects truncated data chunk claiming data beyond file end',
      () {
        final truncatedWav = createDummyWavBytes(
          sampleRate: 16000,
          channels: 1,
          bitDepth: 16,
          dataBytesCount: 100,
          headerClaimedDataSize:
              10000, // Header claims 10000 bytes, but only 100 exist
        );

        final res = ContentValidator.inspectWavHeader(truncatedWav);
        expect(res.isValid, isFalse);
        expect(res.errorMessage, contains('Truncated data chunk'));
      },
    );

    test(
      'inspectWavHeader rejects truncated file claiming RIFF size beyond actual length',
      () {
        final truncatedRiff = createDummyWavBytes(
          sampleRate: 16000,
          channels: 1,
          bitDepth: 16,
          dataBytesCount: 100,
          headerClaimedRiffSize:
              10000, // Header claims 10000 bytes for RIFF, but file is small
        );

        final res = ContentValidator.inspectWavHeader(truncatedRiff);
        expect(res.isValid, isFalse);
        expect(
          res.errorMessage,
          contains('Truncated file: declared RIFF size'),
        );
      },
    );

    test(
      'inspectWavHeader rejects non-PCM format (e.g. IEEE float format 3)',
      () {
        final nonPcmWav = createDummyWavBytes(
          audioFormat: 3, // Non-PCM
          sampleRate: 16000,
          channels: 1,
          bitDepth: 16,
          dataBytesCount: 32000,
        );

        final res = ContentValidator.inspectWavHeader(nonPcmWav);
        expect(res.isValid, isFalse);
        expect(res.errorMessage, contains('Non-PCM audio format'));
      },
    );

    test(
      'audio registry with status missing rejects declared voices or clips',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final audio = pending['adhan_audio'] as Map<String, dynamic>;
        audio['status'] = 'missing';
        audio['voices'] = <Map<String, dynamic>>[
          <String, dynamic>{'id': 'voice_1', 'performer': 'Muaddhin A'},
        ];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('status="missing" but contains declared voice or clip entries'),
          ),
          isTrue,
        );
      },
    );

    test(
      'audio registry with status pending rejects declared voices or clips',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final audio = pending['adhan_audio'] as Map<String, dynamic>;
        audio['status'] = 'pending';
        audio['voices'] = <Map<String, dynamic>>[
          <String, dynamic>{'id': 'voice_1', 'performer': 'Muaddhin A'},
        ];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('registry status is "pending" instead of "bundled"'),
          ),
          isTrue,
        );
      },
    );

    test('audio registry rejects unknown or unauthorized voice ID', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final voices = (audio['voices'] as List).cast<Map<String, dynamic>>();
      voices[0]['id'] = 'unauthorized_voice';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Invalid or unauthorized voice ID')),
        isTrue,
      );
    });

    test('audio registry rejects duplicate voice ID', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final voices = (audio['voices'] as List).cast<Map<String, dynamic>>();
      voices[1]['id'] = 'adam'; // Duplicate 'adam'
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Duplicate voice ID')),
        isTrue,
      );
    });

    test('audio registry rejects invalid Fajr voice designation', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final voices = (audio['voices'] as List).cast<Map<String, dynamic>>();
      for (final v in voices) {
        if (v['id'] == 'malmo_fajr') v['is_fajr'] = false;
      }
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Exactly one Fajr voice must be designated')),
        isTrue,
      );
    });

    test('audio registry rejects tampered full MP3 recording bytes and hash', () async {
      final mp3File = File(
        p.join(tempDir.path, 'assets', 'audio', 'adhan', 'adam-converted.mp3'),
      );
      final original = await mp3File.readAsBytes();
      final tampered = Uint8List.fromList(original);
      tampered[100] = tampered[100] ^ 0xFF;
      await mp3File.writeAsBytes(tampered);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('audio file SHA on disk mismatch')),
        isTrue,
      );
    });

    test('audio registry rejects tampered alert WAV clip bytes and hash', () async {
      final wavFile = File(
        p.join(tempDir.path, 'assets', 'audio', 'adhan', 'adam-alert.wav'),
      );
      final original = await wavFile.readAsBytes();
      final tampered = Uint8List.fromList(original);
      tampered[1000] = tampered[1000] ^ 0xFF;
      await wavFile.writeAsBytes(tampered);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('alert file SHA on disk mismatch')),
        isTrue,
      );
    });

    test('audio registry rejects tampered native iOS Runner alert copy', () async {
      final iosWavFile = File(
        p.join(tempDir.path, 'ios', 'Runner', 'adam-alert.wav'),
      );
      final original = await iosWavFile.readAsBytes();
      final tampered = Uint8List.fromList(original);
      tampered[500] = tampered[500] ^ 0xFF;
      await iosWavFile.writeAsBytes(tampered);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('iOS Runner alert clip SHA mismatch')),
        isTrue,
      );
    });

    test('audio registry rejects tampered native Android raw alert copy', () async {
      final androidWavFile = File(
        p.join(tempDir.path, 'android', 'app', 'src', 'main', 'res', 'raw', 'adam_alert.wav'),
      );
      final original = await androidWavFile.readAsBytes();
      final tampered = Uint8List.fromList(original);
      tampered[500] = tampered[500] ^ 0xFF;
      await androidWavFile.writeAsBytes(tampered);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Android res/raw alert clip SHA mismatch')),
        isTrue,
      );
    });

    test('audio registry rejects prohibited OGG or FLAC file in ios/Runner', () async {
      final forbiddenFile = File(
        p.join(tempDir.path, 'ios', 'Runner', 'prohibited.ogg'),
      );
      await forbiddenFile.writeAsString('fake ogg audio content');

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Prohibited audio format on iOS')),
        isTrue,
      );
    });

    test('audio registry rejects mismatched canonical license or source URL', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final voices = (audio['voices'] as List).cast<Map<String, dynamic>>();
      voices[0]['source_url'] = 'https://tampered-source.org/fake.mp3';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('source_url mismatch')),
        isTrue,
      );
    });

    test('audio registry rejects missing or empty evidence doc', () async {
      final docFile = File(
        p.join(tempDir.path, 'docs', 'sources', 'ADHAN_AUDIO.md'),
      );
      await docFile.writeAsString(''); // Empty file

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Empty adhan audio evidence document')),
        isTrue,
      );
    });

    test('inspectWavHeader parses custom RIFF chunks with LIST metadata before data chunk', () {
      final bb = BytesBuilder();
      bb.add(ascii.encode('RIFF'));
      final riffSizeBd = ByteData(4)..setUint32(0, 100, Endian.little);
      bb.add(riffSizeBd.buffer.asUint8List());
      bb.add(ascii.encode('WAVE'));

      // 'fmt ' chunk (16 bytes payload)
      bb.add(ascii.encode('fmt '));
      final fmtSizeBd = ByteData(4)..setUint32(0, 16, Endian.little);
      bb.add(fmtSizeBd.buffer.asUint8List());
      final fmtBd = ByteData(16);
      fmtBd.setUint16(0, 1, Endian.little); // PCM
      fmtBd.setUint16(2, 1, Endian.little); // Mono
      fmtBd.setUint32(4, 22050, Endian.little); // Sample rate
      fmtBd.setUint32(8, 44100, Endian.little); // Byte rate
      fmtBd.setUint16(12, 2, Endian.little); // Block align
      fmtBd.setUint16(14, 16, Endian.little); // 16-bit
      bb.add(fmtBd.buffer.asUint8List());

      // 'LIST' chunk before 'data' (4 bytes payload: 'INFO')
      bb.add(ascii.encode('LIST'));
      final listSizeBd = ByteData(4)..setUint32(0, 4, Endian.little);
      bb.add(listSizeBd.buffer.asUint8List());
      bb.add(ascii.encode('INFO'));

      // 'data' chunk (8 bytes header + 40 bytes payload)
      bb.add(ascii.encode('data'));
      final dataSizeBd = ByteData(4)..setUint32(0, 40, Endian.little);
      bb.add(dataSizeBd.buffer.asUint8List());
      bb.add(Uint8List(40)); // 40 bytes of zero data

      final bytes = bb.takeBytes();
      ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);

      final res = ContentValidator.inspectWavHeader(bytes);
      expect(res.isValid, isTrue);
      expect(res.dataOffset, equals(56));
      expect(res.dataSize, equals(40));
      expect(res.channels, equals(1));
      expect(res.sampleRate, equals(22050));
      expect(res.bitDepth, equals(16));
    });

    test('analyzeWavWaveform calculates accurate peak, RMS and flags silence vs signal', () {
      // 1. All zero samples -> silent
      final silentBytes = Uint8List(100);
      final silentMetrics = ContentValidator.analyzeWavWaveform(
        bytes: silentBytes,
        dataOffset: 0,
        dataSize: 100,
        sampleRate: 22050,
      );
      expect(silentMetrics.hasNonZeroSignal, isFalse);
      expect(silentMetrics.peakAmplitude, equals(0.0));
      expect(silentMetrics.rmsAmplitude, equals(0.0));

      // 2. Constant 50% amplitude (16384 out of 32768)
      final activeBytes = Uint8List(200);
      final activeBd = ByteData.sublistView(activeBytes);
      for (int i = 0; i < 100; i++) {
        activeBd.setInt16(i * 2, 16384, Endian.little);
      }
      final activeMetrics = ContentValidator.analyzeWavWaveform(
        bytes: activeBytes,
        dataOffset: 0,
        dataSize: 200,
        sampleRate: 22050,
      );
      expect(activeMetrics.hasNonZeroSignal, isTrue);
      expect(activeMetrics.peakAmplitude, closeTo(0.5, 0.001));
      expect(activeMetrics.rmsAmplitude, closeTo(0.5, 0.001));
      expect(activeMetrics.onsetRmsAmplitude, closeTo(0.5, 0.001));
    });

    test('audio registry rejects non-list voices or clips field', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      audio['voices'] = 'invalid-voices';
      audio['notification_clips'] = 'invalid-clips';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('"voices" field must be a list')),
        isTrue,
      );
      expect(
        result.errors.any(
          (e) => e.contains('"notification_clips" field must be a list'),
        ),
        isTrue,
      );
    });

    test('audio registry rejects missing whole ios/Runner directory', () async {
      final iosDir = Directory(p.join(tempDir.path, 'ios', 'Runner'));
      await iosDir.delete(recursive: true);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Missing required iOS Runner directory: ios/Runner'),
        ),
        isTrue,
      );
      expect(
        result.errors.any(
          (e) => e.contains('Missing iOS Runner alert clip'),
        ),
        isTrue,
      );
    });

    test('audio registry rejects missing whole android res/raw directory', () async {
      final rawDir = Directory(
        p.join(tempDir.path, 'android', 'app', 'src', 'main', 'res', 'raw'),
      );
      await rawDir.delete(recursive: true);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains(
            'Missing required Android res/raw directory: android/app/src/main/res/raw',
          ),
        ),
        isTrue,
      );
      expect(
        result.errors.any(
          (e) => e.contains('Missing Android res/raw alert clip'),
        ),
        isTrue,
      );
    });

    test('audio registry rejects missing whole assets/audio/adhan directory', () async {
      final adhanDir = Directory(p.join(tempDir.path, 'assets', 'audio', 'adhan'));
      await adhanDir.delete(recursive: true);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains(
            'Missing required adhan assets directory: assets/audio/adhan',
          ),
        ),
        isTrue,
      );
    });

    test('audio registry rejects missing individual iOS Runner alert clip', () async {
      final f = File(p.join(tempDir.path, 'ios', 'Runner', 'malmo-fajr-alert.wav'));
      await f.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Missing iOS Runner alert clip: ios/Runner/malmo-fajr-alert.wav'),
        ),
        isTrue,
      );
    });

    test('audio registry rejects missing individual Android res/raw alert clip', () async {
      final f = File(
        p.join(tempDir.path, 'android', 'app', 'src', 'main', 'res', 'raw', 'malmo_fajr_alert.wav'),
      );
      await f.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Missing Android res/raw alert clip: android/app/src/main/res/raw/malmo_fajr_alert.wav'),
        ),
        isTrue,
      );
    });

    test('audio registry rejects missing individual adhan full MP3 file', () async {
      final f = File(p.join(tempDir.path, 'assets', 'audio', 'adhan', 'adam-converted.mp3'));
      await f.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Voice "adam" audio file missing')),
        isTrue,
      );
    });

    test('audio registry rejects missing individual adhan alert WAV file', () async {
      final f = File(p.join(tempDir.path, 'assets', 'audio', 'adhan', 'adam-alert.wav'));
      await f.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Voice "adam" alert file missing')),
        isTrue,
      );
    });

    test(
      'audio registry rejects invalid voice alert_clip duration across zero, negative, 1, 30, and 31',
      () async {
        for (final invalidDuration in [0, -5, 1, 30.0, 31.0]) {
          final manifestFile = File(
            p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
          );
          final json =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final pending = json['pending_registries'] as Map<String, dynamic>;
          final audio = pending['adhan_audio'] as Map<String, dynamic>;
          final voices =
              (audio['voices'] as List).cast<Map<String, dynamic>>();
          voices[0]['alert_clip']['duration_seconds'] = invalidDuration;
          await manifestFile.writeAsString(jsonEncode(json));

          final result = await ContentValidator.validate(
            workspaceRoot: tempDir.path,
            isDevelopmentMode: true,
          );

          expect(
            result.isDevelopmentValid,
            isFalse,
            reason: 'Failed to reject voice alert duration: $invalidDuration',
          );
          expect(
            result.errors.any(
              (e) =>
                  e.contains('alert_clip duration must be exactly 27.0') ||
                  e.contains('does not match inspected WAV duration'),
            ),
            isTrue,
            reason:
                'Expected duration error for voice alert duration: $invalidDuration',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('audio registry rejects invalid voice alert_clip format (e.g. ogg)', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final voices =
          (audio['voices'] as List).cast<Map<String, dynamic>>();
      voices[0]['alert_clip']['format'] = 'ogg';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('alert_clip format must be "wav"')),
        isTrue,
      );
    });

    test(
      'audio registry rejects invalid notification_clips duration across zero, negative, 1, 30, and 31',
      () async {
        for (final invalidDuration in [0, -5, 1, 30.0, 31.0]) {
          final manifestFile = File(
            p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
          );
          final json =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final pending = json['pending_registries'] as Map<String, dynamic>;
          final audio = pending['adhan_audio'] as Map<String, dynamic>;
          final clips =
              (audio['notification_clips'] as List).cast<Map<String, dynamic>>();
          clips[0]['duration_seconds'] = invalidDuration;
          await manifestFile.writeAsString(jsonEncode(json));

          final result = await ContentValidator.validate(
            workspaceRoot: tempDir.path,
            isDevelopmentMode: true,
          );

          expect(
            result.isDevelopmentValid,
            isFalse,
            reason: 'Failed to reject notification clip duration: $invalidDuration',
          );
          expect(
            result.errors.any(
              (e) => e.contains('Notification clip duration mismatch'),
            ),
            isTrue,
            reason:
                'Expected duration error for notification clip duration: $invalidDuration',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('audio registry rejects invalid notification_clips format (e.g. ogg)', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final clips =
          (audio['notification_clips'] as List).cast<Map<String, dynamic>>();
      clips[0]['format'] = 'ogg';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Notification clip format mismatch'),
        ),
        isTrue,
      );
    });

    test(
      'audio registry rejects invalid audio_file duration across zero, negative, and mismatched values',
      () async {
        for (final invalidDuration in [0, -10, 100]) {
          final manifestFile = File(
            p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
          );
          final json =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final pending = json['pending_registries'] as Map<String, dynamic>;
          final audio = pending['adhan_audio'] as Map<String, dynamic>;
          final voices =
              (audio['voices'] as List).cast<Map<String, dynamic>>();
          voices[0]['audio_file']['duration_seconds'] = invalidDuration;
          await manifestFile.writeAsString(jsonEncode(json));

          final result = await ContentValidator.validate(
            workspaceRoot: tempDir.path,
            isDevelopmentMode: true,
          );

          expect(
            result.isDevelopmentValid,
            isFalse,
            reason: 'Failed to reject audio duration: $invalidDuration',
          );
          expect(
            result.errors.any(
              (e) => e.contains('audio_file duration_seconds mismatch'),
            ),
            isTrue,
            reason:
                'Expected duration error for audio duration: $invalidDuration',
          );
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('audio registry rejects invalid audio_file format (e.g. wav instead of mp3)', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final audio = pending['adhan_audio'] as Map<String, dynamic>;
      final voices =
          (audio['voices'] as List).cast<Map<String, dynamic>>();
      voices[0]['audio_file']['format'] = 'wav';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('audio_file format must be "mp3"')),
        isTrue,
      );
    });

    test('analyzeWavWaveform detects onset RMS energy below threshold on dead onset', () {
      final pcmData = Uint8List(22050 * 2 * 2); // 2 seconds of 22050Hz 16-bit
      final bd = ByteData.sublistView(pcmData);
      // First second (22050 samples) is silent (0)
      // Second second has non-zero signal (amplitude 16384 out of 32768)
      for (int i = 22050; i < 44100; i++) {
        bd.setInt16(i * 2, 16384, Endian.little);
      }
      final metrics = ContentValidator.analyzeWavWaveform(
        bytes: pcmData,
        dataOffset: 0,
        dataSize: pcmData.length,
        sampleRate: 22050,
      );
      expect(metrics.hasNonZeroSignal, isTrue);
      expect(metrics.onsetRmsAmplitude, equals(0.0));
      expect(
        metrics.onsetRmsAmplitude < ContentValidator.kExpectedAdhanAlertOnsetRmsLowerBound,
        isTrue,
      );
      expect(metrics.rmsAmplitude, greaterThan(0.2));
    });

    test('audio registry rejects alert WAV with dead or silent onset energy', () async {
      final wavFile = File(
        p.join(tempDir.path, 'assets', 'audio', 'adhan', 'adam-alert.wav'),
      );
      final original = await wavFile.readAsBytes();
      final tampered = Uint8List.fromList(original);
      // Clear first 22050 samples (44100 bytes) after dataOffset 78 to 0 (silent onset)
      for (int i = 0; i < 44100; i++) {
        tampered[78 + i] = 0;
      }
      await wavFile.writeAsBytes(tampered);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('onset RMS energy too low')),
        isTrue,
      );
    });

    // 6. Dhikr & Hadith Registries Hardening
    test(
      'dhikr registry with status missing rejects count-only integer with empty items list',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final dhikr = pending['dhikr_duas'] as Map<String, dynamic>;
        dhikr['status'] = 'missing';
        dhikr['records_count'] = 45; // Claims 45 records but items is empty
        dhikr['items'] = <Map<String, dynamic>>[];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('claims 45 records but items list has 0'),
          ),
          isTrue,
        );
      },
    );

    test(
      'dhikr registry with status missing rejects non-empty items as unsupported import',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final dhikr = pending['dhikr_duas'] as Map<String, dynamic>;
        dhikr['status'] = 'missing';
        dhikr['items'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'dhikr_1',
            'text': 'سُبْحَانَ اللَّهِ',
            'reference': 'Sahih Muslim',
            'repetition_count': 33,
          },
        ];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) =>
                e.contains('declares status="missing" but contains items') ||
                e.contains('Dhikr collection is unsupported at this milestone'),
          ),
          isTrue,
        );
      },
    );

    test('dhikr registry with status missing rejects non-list items field', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final dhikr = pending['dhikr_duas'] as Map<String, dynamic>;
      dhikr['status'] = 'missing';
      dhikr['items'] = 'not-a-list';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Dhikr registry "items" field must be a list'),
        ),
        isTrue,
      );
    });

    test(
      'hadith registry with status missing rejects count-only integer with empty items list',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final hadith = pending['hadith'] as Map<String, dynamic>;
        hadith['status'] = 'missing';
        hadith['records_count'] = 100; // Claims 100 records but items is empty
        hadith['items'] = <Map<String, dynamic>>[];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('claims 100 records but items list has 0'),
          ),
          isTrue,
        );
      },
    );

    test(
      'hadith registry with status missing rejects non-empty items as unsupported import',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final hadith = pending['hadith'] as Map<String, dynamic>;
        hadith['status'] = 'missing';
        hadith['items'] = <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'hadith_1',
            'text': 'إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ',
            'reference': 'Sahih Bukhari 1',
          },
        ];
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) =>
                e.contains('declares status="missing" but contains items') ||
                e.contains('Hadith collection is unsupported at this milestone'),
          ),
          isTrue,
        );
      },
    );

    test('hadith registry with status missing rejects non-list items field', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final hadith = pending['hadith'] as Map<String, dynamic>;
      hadith['status'] = 'missing';
      hadith['items'] = 'not-a-list';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Hadith registry "items" field must be a list'),
        ),
        isTrue,
      );
    });

    test('rejects negative records_count in pending registries', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final dhikr = pending['dhikr_duas'] as Map<String, dynamic>;
      dhikr['status'] = 'missing';
      dhikr['records_count'] = -5;
      final hadith = pending['hadith'] as Map<String, dynamic>;
      hadith['status'] = 'missing';
      hadith['records_count'] = -10;
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.contains('Dhikr records_count must be a non-negative integer'),
        ),
        isTrue,
      );
      expect(
        result.errors.any(
          (e) =>
              e.contains('Hadith records_count must be a non-negative integer'),
        ),
        isTrue,
      );
    });

    test('hadith registry rejects altered SHA-256 for source XLSX copy', () async {
      final xlsxFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hadith', 'hadeethenc-ar.xlsx'),
      );
      final original = await xlsxFile.readAsBytes();
      final corrupted = Uint8List.fromList(original);
      corrupted[corrupted.length - 1] ^= 0xFF;
      await xlsxFile.writeAsBytes(corrupted);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hadith source XLSX SHA-256 hash mismatch')),
        isTrue,
      );
    });

    test('hadith registry rejects altered SHA-256 for JSON asset copy', () async {
      final jsonFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hadith', 'hadith-enc-sahih.json'),
      );
      final text = await jsonFile.readAsString();
      await jsonFile.writeAsString('$text ');

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hadith JSON asset SHA-256 hash mismatch')),
        isTrue,
      );
    });

    test('hadith registry rejects missing source XLSX file', () async {
      final xlsxFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hadith', 'hadeethenc-ar.xlsx'),
      );
      await xlsxFile.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hadith source XLSX file not found')),
        isTrue,
      );
    });

    test('hadith registry rejects missing JSON asset file', () async {
      final jsonFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hadith', 'hadith-enc-sahih.json'),
      );
      await jsonFile.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hadith JSON asset file not found')),
        isTrue,
      );
    });

    test('hadith registry rejects manifest declared count mismatch', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final hadith = pending['hadith'] as Map<String, dynamic>;
      hadith['records_count'] = 100;
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hadith records_count mismatch in manifest')),
        isTrue,
      );
    });

    test('hadith registry rejects path traversal in source_file', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final hadith = pending['hadith'] as Map<String, dynamic>;
      hadith['source_file']['path'] = '../../hadeethenc.xlsx';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Unsafe or invalid path for hadith source_file')),
        isTrue,
      );
    });

    test('hisn registry rejects altered SHA-256 for source DOCX copy', () async {
      final docxFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hisn', 'hisn-muslim-source.docx'),
      );
      final original = await docxFile.readAsBytes();
      final corrupted = Uint8List.fromList(original);
      corrupted[corrupted.length - 1] ^= 0xFF;
      await docxFile.writeAsBytes(corrupted);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hisn al-Muslim source DOCX SHA-256 hash mismatch')),
        isTrue,
      );
    });

    test('hisn registry rejects altered SHA-256 for JSON asset copy', () async {
      final jsonFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hisn', 'hisn-muslim.json'),
      );
      final text = await jsonFile.readAsString();
      await jsonFile.writeAsString('$text ');

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hisn al-Muslim JSON asset SHA-256 hash mismatch')),
        isTrue,
      );
    });

    test('hisn registry rejects missing source DOCX file', () async {
      final docxFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hisn', 'hisn-muslim-source.docx'),
      );
      await docxFile.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hisn al-Muslim source DOCX file not found')),
        isTrue,
      );
    });

    test('hisn registry rejects missing JSON asset file', () async {
      final jsonFile = File(
        p.join(tempDir.path, 'assets', 'content', 'hisn', 'hisn-muslim.json'),
      );
      await jsonFile.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hisn al-Muslim JSON asset file not found')),
        isTrue,
      );
    });

    test('hisn registry rejects manifest declared count mismatch', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final dhikr = pending['dhikr_duas'] as Map<String, dynamic>;
      dhikr['records_count'] = 100;
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Hisn al-Muslim records_count mismatch in manifest')),
        isTrue,
      );
    });

    test('hisn registry rejects path traversal in source_file', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final dhikr = pending['dhikr_duas'] as Map<String, dynamic>;
      dhikr['source_file']['path'] = '../../hisn.docx';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('Unsafe or invalid path for dhikr source_file')),
        isTrue,
      );
    });

    // 7. Human Review Hardening
    test('human review rejects approved: true without valid evidence', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final humanReview = pending['human_review'] as Map<String, dynamic>;
      humanReview['approved'] = true;
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.contains('evidence_path is missing') ||
              e.contains('Contradictory human review status'),
        ),
        isTrue,
      );
    });

    test(
      'human review rejects declared evidence or reviewer without complete valid evidence',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final pending = json['pending_registries'] as Map<String, dynamic>;
        final humanReview = pending['human_review'] as Map<String, dynamic>;
        humanReview['approved'] = false;
        humanReview['evidence_path'] =
            'assets/content/unsupported_evidence.txt';
        humanReview['evidence_sha256'] = 'a' * 64;
        humanReview['reviewer_name'] = 'External Reviewer';
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains(
              'Human review declared evidence or reviewer claims while status is "pending"',
            ),
          ),
          isTrue,
        );
        expect(
          result.errors.any(
            (e) => e.contains('Human review evidence file not found'),
          ),
          isTrue,
        );
      },
    );

    test('human review rejects non-boolean approved field', () async {
      final manifestFile = File(
        p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
      );
      final json =
          jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      final pending = json['pending_registries'] as Map<String, dynamic>;
      final humanReview = pending['human_review'] as Map<String, dynamic>;
      humanReview['approved'] = 'yes';
      await manifestFile.writeAsString(jsonEncode(json));

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.contains('Human review "approved" field must be a boolean'),
        ),
        isTrue,
      );
    });

    // 8. Containment and Release Readiness Hardening
    test(
      'rejects provenance evidence_doc attempting to escape workspace root',
      () async {
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        final provenance = json['provenance'] as Map<String, dynamic>;
        final tanzil = provenance['tanzil'] as Map<String, dynamic>;
        tanzil['evidence_doc'] = '../../secret_notes.md';
        await manifestFile.writeAsString(jsonEncode(json));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any(
            (e) => e.contains('Unsafe or invalid evidence_doc path for Tanzil'),
          ),
          isTrue,
        );
      },
    );

    test(
      'directory junction escaping workspace root is caught and rejected',
      () async {
        final outsideDir = await Directory.systemTemp.createTemp(
          'outside_evidence_dir_',
        );
        final outsideFile = File(p.join(outsideDir.path, 'outside.md'));
        await outsideFile.writeAsString('# Escaped Evidence Document\n');

        final linkTarget = p.join(
          tempDir.path,
          'assets',
          'content',
          'junction_outside',
        );

        await _createDirectoryJunction(
          junctionPath: linkTarget,
          targetPath: outsideDir.path,
        );

        if (!await Link(linkTarget).exists()) {
          // Non-Windows symlink was skipped by markTestSkipped
          if (await outsideDir.exists()) {
            await outsideDir.delete(recursive: true);
          }
          return;
        }

        try {
          final manifestFile = File(
            p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
          );
          final json =
              jsonDecode(await manifestFile.readAsString())
                  as Map<String, dynamic>;
          final provenance = json['provenance'] as Map<String, dynamic>;
          final tanzil = provenance['tanzil'] as Map<String, dynamic>;
          tanzil['evidence_doc'] = 'assets/content/junction_outside/outside.md';
          await manifestFile.writeAsString(jsonEncode(json));

          final result = await ContentValidator.validate(
            workspaceRoot: tempDir.path,
            isDevelopmentMode: true,
          );

          expect(result.isDevelopmentValid, isFalse);
          expect(
            result.errors.any(
              (e) => e.contains('Unsafe or invalid evidence_doc path'),
            ),
            isTrue,
          );
        } finally {
          await _safeUnlinkJunction(
            junctionPath: linkTarget,
            expectedTarget: outsideDir.path,
            sentinelFile: outsideFile,
          );
          if (await outsideDir.exists()) {
            await outsideDir.delete(recursive: true);
          }
        }
      },
    );

    test(
      'development validation passes for valid canonical workspace, but release mode retains remaining 1 release blocker',
      () async {
        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: false,
        );

        // Development validity is true (supplied sources and pending schemas are clean)
        expect(result.isDevelopmentValid, isTrue);
        expect(result.errors, isEmpty);

        // Release mode MUST fail because 1 unacquired category remains pending (human reviewer)
        expect(result.isReleaseReady, isFalse);
        expect(result.pendingReleaseBlockers.length, 1);
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('604 Medina Mushaf page images'),
          ),
          isFalse,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('3 licensed adhan recordings'),
          ),
          isFalse,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('Hisn al-Muslim'),
          ),
          isFalse,
        );
        expect(
          result.pendingReleaseBlockers.any(
            (b) => b.contains('Qualified human reviewer'),
          ),
          isTrue,
        );
        expect(
          result.pendingReleaseBlockers.any((b) => b.contains('HadeethEnc')),
          isFalse,
        );
      },
    );

    test('rejects missing Quran page image file in pages directory', () async {
      final page121 = File(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'pages', '121.webp'),
      );
      await page121.delete();

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.contains('Missing Quran page image file: 121.webp') ||
              e.contains('file count mismatch'),
        ),
        isTrue,
      );
    });

    test('rejects tampered or corrupt page bounds file', () async {
      final boundsFile = File(
        p.join(
          tempDir.path,
          'assets',
          'content',
          'quran',
          'kfqc-page-bounds.json',
        ),
      );
      await boundsFile.writeAsString('{"pages": []}');

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any((e) => e.contains('SHA-256 mismatch')),
        isTrue,
      );
    });

    test('rejects tampered sample page WebP hash', () async {
      final page1File = File(
        p.join(tempDir.path, 'assets', 'content', 'quran', 'pages', '001.webp'),
      );
      await page1File.writeAsBytes([0x00, 0x01, 0x02, 0x03]);

      final result = await ContentValidator.validate(
        workspaceRoot: tempDir.path,
        isDevelopmentMode: true,
      );

      expect(result.isDevelopmentValid, isFalse);
      expect(
        result.errors.any(
          (e) =>
              e.contains('Page 1 WebP SHA-256 mismatch') ||
              e.contains('byte size mismatch'),
        ),
        isTrue,
      );
    });

    test(
      'rejects modified manifest pointing to valid files elsewhere while deleting packaged paths',
      () async {
        // Copy valid bounds file to an alternate path
        final altDir = Directory(
          p.join(tempDir.path, 'assets', 'content', 'alternate'),
        );
        await altDir.create(recursive: true);
        final altBounds = File(p.join(altDir.path, 'alt-bounds.json'));
        final packagedBounds = File(
          p.join(
            tempDir.path,
            'assets',
            'content',
            'quran',
            'kfqc-page-bounds.json',
          ),
        );
        await packagedBounds.copy(altBounds.path);

        // Delete the packaged bounds file at runtime path
        await packagedBounds.delete();

        // Point manifest to the alternate valid file
        final manifestFile = File(
          p.join(tempDir.path, 'assets', 'content', 'manifest.json'),
        );
        final manifestJson =
            jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        final pending =
            manifestJson['pending_registries'] as Map<String, dynamic>;
        final quranImages = pending['quran_images'] as Map<String, dynamic>;
        final boundsMap = quranImages['bounds_file'] as Map<String, dynamic>;
        boundsMap['path'] = 'assets/content/alternate/alt-bounds.json';

        final provenance = manifestJson['provenance'] as Map<String, dynamic>;
        final kfqc = provenance['kfqc_mushaf'] as Map<String, dynamic>;
        final provBounds = kfqc['bounds_file'] as Map<String, dynamic>;
        provBounds['path'] = 'assets/content/alternate/alt-bounds.json';

        await manifestFile.writeAsString(jsonEncode(manifestJson));

        final result = await ContentValidator.validate(
          workspaceRoot: tempDir.path,
          isDevelopmentMode: true,
        );

        expect(result.isDevelopmentValid, isFalse);
        expect(
          result.errors.any((e) => e.contains('must match exact runtime path')),
          isTrue,
        );
      },
    );
  });
}
