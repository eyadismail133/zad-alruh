/// UI Utilities for Quran numbers, page jumping, and digit formatting.
class QuranUiUtils {
  QuranUiUtils._();

  /// Normalizes Arabic-Indic and ASCII digits from user input,
  /// validates range 1..604, and returns the parsed integer or null.
  ///
  /// Important: Only user-input digits for page navigation are normalized.
  /// Verbatim Quranic Uthmani text is NEVER normalized for rendering.
  static int? normalizeAndParsePageNumber(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final buffer = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      final codeUnit = trimmed.codeUnitAt(i);
      // Arabic-Indic digits: ٠ (0x0660) to ٩ (0x0669)
      if (codeUnit >= 0x0660 && codeUnit <= 0x0669) {
        buffer.write(codeUnit - 0x0660);
      }
      // Extended Arabic-Indic digits: ۰ (0x06F0) to ۹ (0x06F9)
      else if (codeUnit >= 0x06F0 && codeUnit <= 0x06F9) {
        buffer.write(codeUnit - 0x06F0);
      }
      // ASCII digits: '0' (0x0030) to '9' (0x0039)
      else if (codeUnit >= 0x0030 && codeUnit <= 0x0039) {
        buffer.writeCharCode(codeUnit);
      } else {
        // Any other non-digit character (letters, spaces, punctuation) is invalid
        return null;
      }
    }

    final parsed = int.tryParse(buffer.toString());
    if (parsed == null || parsed < 1 || parsed > 604) {
      return null;
    }
    return parsed;
  }

  /// Converts an integer into Arabic-Indic digits (٠..٩) for UI display.
  static String toArabicDigits(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    final s = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      final digit = int.tryParse(c);
      if (digit != null) {
        buffer.write(arabicDigits[digit]);
      } else {
        buffer.write(c);
      }
    }
    return buffer.toString();
  }
}
