import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:zad_alruh/src/core/content/content_validator.dart';

/// CLI executable for Zad Alruh content validation.
///
/// Usage:
///   dart run tool/validate_content.dart                # Default: Strict Release Mode (exits nonzero if blockers exist)
///   dart run tool/validate_content.dart --development  # Development Mode: Verifies supplied sources only
Future<void> main(List<String> args) async {
  final isDevelopment = args.contains('--development') || args.contains('-d');

  // Locate workspace root
  String workspaceRoot = Directory.current.path;
  if (!await File(
    p.join(workspaceRoot, 'assets', 'content', 'manifest.json'),
  ).exists()) {
    // Attempt parent directory in case script is run from within tool/
    final parent = p.dirname(workspaceRoot);
    if (await File(
      p.join(parent, 'assets', 'content', 'manifest.json'),
    ).exists()) {
      workspaceRoot = parent;
    }
  }

  final result = await ContentValidator.validate(
    workspaceRoot: workspaceRoot,
    isDevelopmentMode: isDevelopment,
    strictImageHashes: true,
  );

  stdout.write(result.toReport(isDevelopment: isDevelopment));

  if (isDevelopment) {
    if (result.isDevelopmentValid) {
      exit(0);
    } else {
      exit(1);
    }
  } else {
    // Default Release Mode: strictly requires full release readiness
    if (result.isReleaseReady) {
      exit(0);
    } else {
      exit(1);
    }
  }
}
