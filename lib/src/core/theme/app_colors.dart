import 'package:flutter/material.dart';

/// Zad Al-Ruh design tokens — "Night Emerald & Sand" (2026-11 redesign).
///
/// Token NAMES are legacy (they are referenced ~1,300 times across screens);
/// their VALUES define the look. Change values here, never add inline colors
/// in widgets. See AGENTS.md §4.
class AppColors {
  // ---------------------------------------------------------------------------
  // Light theme — warm sand paper with deep emerald ink and brass accents.
  // ---------------------------------------------------------------------------
  static const Color creamBackground = Color(0xFFF6F1E7); // scaffold
  static const Color boardBackground = Color(0xFFEEE6D6); // grouped areas
  static const Color cardSurface = Color(0xFFFFFCF7);
  static const Color cardBorder = Color(0xFFE6DCC8);
  static const Color cardBorderSubtle = Color(0xFFEDE5D5);

  static const Color forestPrimary = Color(0xFF0D4A43); // primary / brand
  static const Color forestMedium = Color(0xFF15665B);
  static const Color forestLight = Color(0xFF248072);
  static const Color forestSoftTint = Color(0xFFE2EEE9);

  static const Color goldAccent = Color(0xFFC9A05A); // brass
  static const Color goldMedium = Color(0xFFB88B3E);
  static const Color goldDark = Color(0xFF85601F);
  static const Color goldSoftTint = Color(0xFFFAF0DA);
  static const Color goldPill = Color(0xFFF3E2BB);

  static const Color textDark = Color(0xFF0E2D29);
  static const Color textBody = Color(0xFF1D2A27);
  static const Color textMuted = Color(0xFF5B6B66);
  static const Color textSubtle = Color(0xFF74827D);

  // ---------------------------------------------------------------------------
  // Dark theme — night ink with luminous emerald and warm gold.
  // ---------------------------------------------------------------------------
  static const Color darkBackground = Color(0xFF0A1412);
  static const Color darkSurface = Color(0xFF12201D);
  static const Color darkSurfaceHigh = Color(0xFF192B27);
  static const Color darkCardBorder = Color(0xFF223530);
  static const Color darkTextPrimary = Color(0xFFEBF2EE);
  static const Color darkTextMuted = Color(0xFF9CB1A9);
  static const Color darkForestPrimary = Color(0xFF4DB39C);
  static const Color darkGoldAccent = Color(0xFFE3BF76);

  // ---------------------------------------------------------------------------
  // Hero gradients (home hero, next-prayer card, reader header).
  // ---------------------------------------------------------------------------
  static const List<Color> heroGradientLight = [
    Color(0xFF0B3F39),
    Color(0xFF0F5248),
    Color(0xFF1A6A5C),
  ];
  static const List<Color> heroGradientDark = [
    Color(0xFF0E2622),
    Color(0xFF123530),
    Color(0xFF1A443C),
  ];

  // ---------------------------------------------------------------------------
  // Mushaf paper modes (see MushafPaperStyle).
  // ---------------------------------------------------------------------------
  static const Color mushafPaperWhite = Color(0xFFFFFFFF);
  static const Color mushafInkWhite = Color(0xFF000000);
  static const Color mushafPaperSepia = Color(0xFFF7EED8);
  static const Color mushafInkSepia = Color(0xFF1E140A);
  static const Color mushafPaperNight = Color(0xFF101A17);
  static const Color mushafInkNight = Color(0xFFE6E1D3);
  static const Color mushafReaderBackdropLight = Color(0xFFEDE5D3);
  static const Color mushafReaderBackdropDark = Color(0xFF070D0C);
}
