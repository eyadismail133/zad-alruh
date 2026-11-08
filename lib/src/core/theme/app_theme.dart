import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App-wide Material 3 theme (2026-11 redesign).
///
/// Typography split:
/// - [uiFont] (IBM Plex Sans Arabic): app bars, navigation, buttons, titles, labels.
/// - [fontFamily] (Noto Naskh Arabic): body text, adhkar, hadith, explanations.
/// - [quranFont] (Amiri Quran): Quranic text.
class AppTheme {
  static const String fontFamily = 'Noto Naskh Arabic';
  static const String uiFont = 'IBM Plex Sans Arabic';
  static const String quranFont = 'Amiri Quran';

  /// Used when [uiFont] lacks a glyph or is unavailable (e.g. widget tests
  /// that only load Naskh), so UI text never falls back to a square font.
  static const List<String> uiFontFallback = [fontFamily];

  static const double radiusSmall = 12;
  static const double radiusMedium = 18;
  static const double radiusLarge = 24;

  static ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: AppColors.forestPrimary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.forestSoftTint,
          onPrimaryContainer: AppColors.forestPrimary,
          secondary: AppColors.goldAccent,
          onSecondary: AppColors.textDark,
          secondaryContainer: AppColors.goldSoftTint,
          onSecondaryContainer: AppColors.goldDark,
          tertiary: AppColors.forestLight,
          surface: AppColors.cardSurface,
          onSurface: AppColors.textBody,
          onSurfaceVariant: AppColors.textMuted,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: AppColors.cardSurface,
          surfaceContainer: AppColors.creamBackground,
          surfaceContainerHigh: AppColors.boardBackground,
          surfaceContainerHighest: AppColors.cardBorderSubtle,
          outline: AppColors.cardBorder,
          outlineVariant: AppColors.cardBorderSubtle,
        ),
        scaffold: AppColors.creamBackground,
        surface: AppColors.cardSurface,
        border: AppColors.cardBorder,
        primary: AppColors.forestPrimary,
        accent: AppColors.goldDark,
        textStrong: AppColors.textDark,
        textBody: AppColors.textBody,
        textMuted: AppColors.textMuted,
        navIndicator: AppColors.forestSoftTint,
      );

  static ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: AppColors.darkForestPrimary,
          onPrimary: AppColors.darkBackground,
          primaryContainer: AppColors.darkSurfaceHigh,
          onPrimaryContainer: AppColors.darkForestPrimary,
          secondary: AppColors.darkGoldAccent,
          onSecondary: AppColors.darkBackground,
          secondaryContainer: AppColors.darkSurfaceHigh,
          onSecondaryContainer: AppColors.darkGoldAccent,
          tertiary: AppColors.darkForestPrimary,
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkTextPrimary,
          onSurfaceVariant: AppColors.darkTextMuted,
          surfaceContainerLowest: AppColors.darkBackground,
          surfaceContainerLow: AppColors.darkSurface,
          surfaceContainer: AppColors.darkSurface,
          surfaceContainerHigh: AppColors.darkSurfaceHigh,
          surfaceContainerHighest: AppColors.darkCardBorder,
          outline: AppColors.darkCardBorder,
          outlineVariant: AppColors.darkCardBorder,
        ),
        scaffold: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        border: AppColors.darkCardBorder,
        primary: AppColors.darkForestPrimary,
        accent: AppColors.darkGoldAccent,
        textStrong: AppColors.darkTextPrimary,
        textBody: AppColors.darkTextPrimary,
        textMuted: AppColors.darkTextMuted,
        navIndicator: AppColors.darkSurfaceHigh,
      );

  static TextTheme _textTheme(Color strong, Color body, Color muted) {
    TextStyle ui(double size, FontWeight weight, Color color, {double? height}) =>
        TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
        );
    TextStyle text(double size, Color color) => TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          color: color,
          height: 1.6,
        );
    return TextTheme(
      displayLarge: ui(48, FontWeight.w700, strong),
      displayMedium: ui(40, FontWeight.w700, strong),
      displaySmall: ui(34, FontWeight.w700, strong),
      headlineLarge: ui(28, FontWeight.w700, strong),
      headlineMedium: ui(24, FontWeight.w700, strong),
      headlineSmall: ui(21, FontWeight.w700, strong),
      titleLarge: ui(19, FontWeight.w700, strong),
      titleMedium: ui(16, FontWeight.w600, strong),
      titleSmall: ui(14, FontWeight.w600, strong),
      bodyLarge: text(16, body),
      bodyMedium: text(14, body),
      bodySmall: text(12, muted),
      labelLarge: ui(14, FontWeight.w500, strong),
      labelMedium: ui(12, FontWeight.w500, muted),
      labelSmall: ui(11, FontWeight.w500, muted),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color scaffold,
    required Color surface,
    required Color border,
    required Color primary,
    required Color accent,
    required Color textStrong,
    required Color textBody,
    required Color textMuted,
    required Color navIndicator,
  }) {
    final isDark = brightness == Brightness.dark;
    final onPrimary = scheme.onPrimary;
    final textTheme = _textTheme(textStrong, textBody, textMuted);

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusSmall + 2),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 13);
    const buttonText = TextStyle(
      fontFamily: uiFont,
      fontFamilyFallback: uiFontFallback,
      fontWeight: FontWeight.w600,
      fontSize: 14,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textStrong,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: true,
        iconTheme: IconThemeData(color: primary),
        actionsIconTheme: IconThemeData(color: primary),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: textStrong,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: textStrong,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 12.5,
          color: textMuted,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: navIndicator,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall + 2),
        ),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: uiFont,
            fontFamilyFallback: uiFontFallback,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? primary : textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? primary : textMuted,
            size: selected ? 26 : 24,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textMuted,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: border,
        labelStyle: const TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          textStyle: buttonText,
          shape: buttonShape,
          padding: buttonPadding,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          textStyle: buttonText,
          shape: buttonShape,
          padding: buttonPadding,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: border, width: 1.2),
          textStyle: buttonText,
          shape: buttonShape,
          padding: buttonPadding,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: buttonText,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border),
        labelStyle: TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: textStrong,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textStrong,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusLarge),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.darkSurfaceHigh : AppColors.textDark,
        contentTextStyle: const TextStyle(
          fontFamily: uiFont,
          fontFamilyFallback: uiFontFallback,
          fontSize: 13.5,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? onPrimary : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: border,
        circularTrackColor: border,
      ),
    );
  }
}
