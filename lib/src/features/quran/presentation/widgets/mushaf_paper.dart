import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/local_settings.dart';
import '../../../../core/theme/app_colors.dart';

/// How a Mushaf page image is painted.
///
/// The bundled page images are grayscale (ink ≈ #202020 on #FFFFFF). Instead of
/// editing the hash-verified assets, each mode remaps that grayscale range with
/// a color matrix: ink becomes [ink] and paper becomes [paper]. This makes the
/// text darker/crisper than the source and enables sepia and night reading
/// without touching the Quranic glyphs.
enum MushafPaperMode {
  /// Follows the app theme: [sepia] in light mode, [night] in dark mode.
  auto,
  white,
  sepia,
  night;

  String get label => switch (this) {
        MushafPaperMode.auto => 'تلقائي',
        MushafPaperMode.white => 'أبيض',
        MushafPaperMode.sepia => 'كريمي',
        MushafPaperMode.night => 'ليلي',
      };

  IconData get icon => switch (this) {
        MushafPaperMode.auto => Icons.brightness_auto_outlined,
        MushafPaperMode.white => Icons.light_mode_outlined,
        MushafPaperMode.sepia => Icons.auto_stories_outlined,
        MushafPaperMode.night => Icons.dark_mode_outlined,
      };

  MushafPaperMode resolve({required bool isDark}) {
    if (this != MushafPaperMode.auto) return this;
    return isDark ? MushafPaperMode.night : MushafPaperMode.sepia;
  }
}

/// Selected paper mode (shared by every reader page, persisted across launches).
final mushafPaperModeProvider =
    StateNotifierProvider<MushafPaperModeNotifier, MushafPaperMode>(
  (ref) => MushafPaperModeNotifier(),
);

class MushafPaperModeNotifier extends StateNotifier<MushafPaperMode> {
  static const _key = 'quran.paper_mode';

  MushafPaperModeNotifier() : super(_load());

  static MushafPaperMode _load() {
    final raw = LocalSettings.getString(_key);
    for (final m in MushafPaperMode.values) {
      if (m.name == raw) return m;
    }
    return MushafPaperMode.auto;
  }

  void set(MushafPaperMode mode) {
    state = mode;
    LocalSettings.setString(_key, mode.name);
  }
}

/// Whether reader chrome (app bar, toolbars) is hidden for full-screen reading.
final mushafImmersiveProvider = StateProvider<bool>((ref) => false);

class MushafPaperStyle {
  final Color paper;
  final Color ink;
  final Color backdrop;

  const MushafPaperStyle({
    required this.paper,
    required this.ink,
    required this.backdrop,
  });

  /// Darkest value present in the source page images (0x20).
  static const double sourceInkLevel = 32;

  factory MushafPaperStyle.of(MushafPaperMode mode, {required bool isDark}) {
    final backdrop = isDark
        ? AppColors.mushafReaderBackdropDark
        : AppColors.mushafReaderBackdropLight;
    switch (mode.resolve(isDark: isDark)) {
      case MushafPaperMode.white:
        return MushafPaperStyle(
          paper: AppColors.mushafPaperWhite,
          ink: AppColors.mushafInkWhite,
          backdrop: backdrop,
        );
      case MushafPaperMode.night:
        return MushafPaperStyle(
          paper: AppColors.mushafPaperNight,
          ink: AppColors.mushafInkNight,
          backdrop: AppColors.mushafReaderBackdropDark,
        );
      case MushafPaperMode.sepia:
      case MushafPaperMode.auto:
        return MushafPaperStyle(
          paper: AppColors.mushafPaperSepia,
          ink: AppColors.mushafInkSepia,
          backdrop: backdrop,
        );
    }
  }

  /// Maps source luminance L∈[sourceInkLevel, 255] linearly to ink→paper.
  ColorFilter get colorFilter {
    const span = 255.0 - sourceInkLevel;
    List<double> row(double inkChannel, double paperChannel) {
      final k = (paperChannel - inkChannel) / span;
      final offset = inkChannel - sourceInkLevel * k;
      // Source is grayscale: average R, G, B to read its luminance.
      return [k / 3, k / 3, k / 3, 0, offset];
    }

    double c(Color color, int shift) =>
        ((color.toARGB32() >> shift) & 0xFF).toDouble();

    return ColorFilter.matrix(<double>[
      ...row(c(ink, 16), c(paper, 16)),
      ...row(c(ink, 8), c(paper, 8)),
      ...row(c(ink, 0), c(paper, 0)),
      0, 0, 0, 1, 0,
    ]);
  }
}
