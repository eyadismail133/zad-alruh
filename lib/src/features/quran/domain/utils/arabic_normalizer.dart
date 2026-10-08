/// Utility for Arabic text normalization for search purposes.
///
/// This does NOT alter or mutate original Quranic text. It only produces
/// normalized search keys so that searches succeed regardless of whether
/// queries or source text contain diacritics, tatweel, or alef variants.
class ArabicNormalizer {
  ArabicNormalizer._();

  // Regex matching Arabic Tashkeel/diacritics, dagger alefs, and Quranic signs
  static final RegExp _diacriticsRegex = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED]',
  );

  // Regex matching Tatweel (Kashida)
  static final RegExp _tatweelRegex = RegExp(r'\u0640');

  // Regex matching Alef variants: أ (0623), إ (0625), آ (0622), ٱ (0671)
  static final RegExp _alefVariantsRegex = RegExp(
    r'[\u0622\u0623\u0625\u0671]',
  );

  // Regex matching multiple whitespaces
  static final RegExp _whitespaceRegex = RegExp(r'\s+');

  /// Normalizes Arabic text by:
  /// 1. Removing diacritics (Harakat, Tashkeel, Dagger Alef, Quranic signs)
  /// 2. Removing Tatweel / Kashida
  /// 3. Normalizing Alef variants (أ, إ, آ, ٱ) to bare Alef (ا)
  /// 4. Collapsing redundant whitespaces and trimming.
  static String normalize(String text) {
    if (text.isEmpty) return '';

    return text
        .replaceAll(_tatweelRegex, '')
        .replaceAll(_diacriticsRegex, '')
        .replaceAll(_alefVariantsRegex, '\u0627')
        .replaceAll(_whitespaceRegex, ' ')
        .trim();
  }

  /// Converts Arabic-Indic (٠-٩) and Eastern Arabic / Persian (۰-۹) digits to ASCII digits (0-9).
  static String normalizeDigits(String text) {
    if (text.isEmpty) return '';
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      // Arabic-Indic digits ٠-٩ (U+0660 - U+0669)
      if (code >= 0x0660 && code <= 0x0669) {
        buffer.writeCharCode(0x0030 + (code - 0x0660));
      }
      // Eastern Arabic-Indic / Persian digits ۰-۹ (U+06F0 - U+06F9)
      else if (code >= 0x06F0 && code <= 0x06F9) {
        buffer.writeCharCode(0x0030 + (code - 0x06F0));
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  /// Parses an integer string, converting any Arabic-Indic or Eastern Arabic digits to standard digits.
  static int? parseArabicInt(String text) {
    final ascii = normalizeDigits(text.trim());
    return int.tryParse(ascii);
  }
}
