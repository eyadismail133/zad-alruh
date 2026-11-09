import 'package:flutter/material.dart';

/// Zad Al-Ruh design tokens — "Calm Teal" (2026-11 v0.7 redesign): soft
/// neutral background, white cards with hairline borders, one calm teal
/// primary and a muted gold accent used sparingly.
///
/// Token NAMES are legacy (they are referenced ~1,300 times across screens);
/// their VALUES define the look. Change values here, never add inline colors
/// in widgets. See AGENTS.md §4.
class AppColors {
  // ---------------------------------------------------------------------------
  // Light theme — warm sand paper with deep emerald ink and brass accents.
  // ---------------------------------------------------------------------------
  static const Color creamBackground = Color(0xFFF4F5F1); // scaffold
  static const Color boardBackground = Color(0xFFEBEDE7); // grouped areas
  static const Color cardSurface = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE3E6DF);
  static const Color cardBorderSubtle = Color(0xFFEEF0EB);

  static const Color forestPrimary = Color(0xFF0F5E55); // primary / brand
  static const Color forestMedium = Color(0xFF187064);
  static const Color forestLight = Color(0xFF2B8A7B);
  static const Color forestSoftTint = Color(0xFFE4F1ED);

  static const Color goldAccent = Color(0xFFC9A35E); // brass
  static const Color goldMedium = Color(0xFFB68E47);
  static const Color goldDark = Color(0xFF8A6626);
  static const Color goldSoftTint = Color(0xFFFAF4E6);
  static const Color goldPill = Color(0xFFF1E5C6);

  static const Color textDark = Color(0xFF15211F);
  static const Color textBody = Color(0xFF243230);
  static const Color textMuted = Color(0xFF5E6D69);
  static const Color textSubtle = Color(0xFF7D8A86);

  // ---------------------------------------------------------------------------
  // Dark theme — night ink with luminous emerald and warm gold.
  // ---------------------------------------------------------------------------
  static const Color darkBackground = Color(0xFF0C1312);
  static const Color darkSurface = Color(0xFF141D1C);
  static const Color darkSurfaceHigh = Color(0xFF1B2725);
  static const Color darkCardBorder = Color(0xFF22302D);
  static const Color darkTextPrimary = Color(0xFFECF1EF);
  static const Color darkTextMuted = Color(0xFFA0B1AC);
  static const Color darkForestPrimary = Color(0xFF5CBFA8);
  static const Color darkGoldAccent = Color(0xFFE2C27E);

  // ---------------------------------------------------------------------------
  // Hero gradients (home hero, next-prayer card, reader header).
  // ---------------------------------------------------------------------------
  static const List<Color> heroGradientLight = [
    Color(0xFF0D564E),
    Color(0xFF12665B),
    Color(0xFF1C776A),
  ];
  static const List<Color> heroGradientDark = [
    Color(0xFF12302B),
    Color(0xFF163A35),
    Color(0xFF1C4640),
  ];

  /// Kaaba marker on the Qibla dial.
  static const Color kaabaBlack = Color(0xFF1B1B1B);

  // ---------------------------------------------------------------------------
  // Mushaf paper modes (see MushafPaperStyle).
  // ---------------------------------------------------------------------------
  static const Color mushafPaperWhite = Color(0xFFFFFFFF);
  static const Color mushafInkWhite = Color(0xFF000000);
  static const Color mushafPaperSepia = Color(0xFFF7EED8);
  static const Color mushafInkSepia = Color(0xFF1E140A);
  static const Color mushafPaperNight = Color(0xFF101A17);
  static const Color mushafInkNight = Color(0xFFE6E1D3);
  static const Color mushafReaderBackdropLight = Color(0xFFEDEDE6);
  static const Color mushafReaderBackdropDark = Color(0xFF070C0B);
}
