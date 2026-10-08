import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:zad_alruh/src/core/content/human_review_validator.dart';

/// Read-only CLI tool to export the exact 624-item canonical religious content inventory to STDOUT.
///
/// Validates disk digests and filesystem containment for all 624 canonical
/// religious content files before emitting the inventory JSON to standard output.
///
/// Strictly read-only: does not accept file output options or modify any workspace files.
///
/// Usage:
///   dart run tool/export_human_review_inventory.dart
Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    stderr.writeln(
      'Error: export_human_review_inventory is strictly read-only and emits to STDOUT only. '
      'Arguments (including --output) are prohibited to prevent accidental file overwrites. '
      'Usage: dart run tool/export_human_review_inventory.dart',
    );
    exit(1);
  }

  // Locate workspace root
  String workspaceRoot = Directory.current.path;
  if (!await File(
    p.join(workspaceRoot, 'assets', 'content', 'manifest.json'),
  ).exists()) {
    final parent = p.dirname(workspaceRoot);
    if (await File(
      p.join(parent, 'assets', 'content', 'manifest.json'),
    ).exists()) {
      workspaceRoot = parent;
    }
  }

  final normalizedRoot = p.canonicalize(workspaceRoot);
  final rootDir = Directory(workspaceRoot);
  late final String canonicalRoot;
  try {
    canonicalRoot = rootDir.resolveSymbolicLinksSync();
  } catch (e) {
    stderr.writeln('Error resolving canonical workspace root: $e');
    exit(1);
  }

  final inventory = HumanReviewValidator.buildCanonicalReligiousInventory(
    normalizedRoot: normalizedRoot,
  );

  if (inventory.length != HumanReviewValidator.kExpectedTotalReligiousItems) {
    stderr.writeln(
      'Integrity Error: Inventory derivation yielded ${inventory.length} items, '
      'expected ${HumanReviewValidator.kExpectedTotalReligiousItems}',
    );
    exit(1);
  }

  // Validate containment and actual disk bytes for all 624 items
  final errors = <String>[];
  for (final entry in inventory.entries) {
    final relPath = entry.key;
    final expectedSha = entry.value.toLowerCase();

    if (!HumanReviewValidator.isPathSafe(
      relativePath: relPath,
      normalizedRoot: normalizedRoot,
      canonicalRoot: canonicalRoot,
    )) {
      errors.add('Unsafe path in inventory: "$relPath"');
      continue;
    }

    final file = File(p.join(normalizedRoot, relPath));
    if (!file.existsSync()) {
      errors.add('Missing religious content file on disk: "$relPath"');
      continue;
    }

    final actualSha =
        sha256.convert(file.readAsBytesSync()).toString().toLowerCase();
    if (actualSha != expectedSha) {
      errors.add(
        'Digest mismatch on disk for "$relPath": expected $expectedSha, got $actualSha',
      );
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln(
      'Canonical inventory disk validation failed with ${errors.length} error(s):',
    );
    for (final err in errors) {
      stderr.writeln('  [ERROR] $err');
    }
    exit(1);
  }

  final jsonOutput =
      const JsonEncoder.withIndent('  ').convert(inventory);

  stdout.writeln(jsonOutput);
  exit(0);
}
