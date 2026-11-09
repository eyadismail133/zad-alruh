import '../../domain/models/hisn_item.dart';
import '../../domain/models/hisn_invocation_catalog.dart';

/// Shared formatter for Hisn al-Muslim items to ensure uniform clipboard copying
/// and sharing across all Hisn screens (both chapter list and item detail views).
class HisnTextFormatter {
  /// Display-only cleanup of the book's typesetting artefacts. The stored
  /// source text is never changed (copy/share still use it verbatim):
  /// - empty footnote markers "()" and the "(( … ))" quote brackets
  /// - item numbering such as "77-(3) "
  /// - the basmala ornament glyphs "ﭑ ﭒ ﭓ" → written basmala
  /// - Quran quotes "{ … }" → ﴿ … ﴾
  /// - hard line breaks from the printed layout
  static String clean(String raw) {
    const basmala = 'بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ';
    var t = raw.replaceAll('ﭑ ﭒ ﭓ', basmala);
    t = t.replaceAll(RegExp(r'\(\s*\)'), '');
    t = t.replaceAll('((', '').replaceAll('))', '');
    t = t.replaceAllMapped(
      RegExp(r'(^|\n)[ \t]*\d+[ \t]*-[ \t]*(\(\d+\)[ \t]*)?'),
      (m) => m.group(1) ?? '',
    );
    t = t.replaceAll('{', '﴿').replaceAll('}', '﴾');
    t = t.replaceAll(RegExp(r'\*\s*'), ' ۝ ');
    const para = '\u0000';
    t = t.replaceAll(RegExp(r'\n[ \t]*\n'), para);
    t = t.replaceAll(RegExp(r'[ \t]*\n[ \t]*'), ' ');
    t = t.replaceAll(para, '\n\n');
    t = t.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    t = t.replaceAllMapped(RegExp(r'[ \t]+([،.:؛])'), (m) => m.group(1)!);
    return t.trim();
  }

  static const String islamHouseBookUrl =
      'https://islamhouse.com/ar/books/2522';

  /// Formats a complete [HisnItem] for copying to clipboard, preserving verbatim
  /// religious text, explicit repetition target (if present), citations/footnotes,
  /// and scholarly attribution to Dr. Saeed Al-Qahtani and IslamHouse.
  static String formatForClipboard(HisnItem item) {
    final buffer = StringBuffer();
    buffer.writeln(
      '${item.chapterTitle} - ${HisnInvocationCatalog.label(item.id)} #${item.number}',
    );
    buffer.writeln(item.text);
    if (item.repeatTarget != null) {
      buffer.writeln('عدد التكرار: ${item.repeatTarget} مرات');
    }
    if (item.footnotes.isNotEmpty) {
      buffer.writeln('\nالتخريج والمراجع:');
      for (final fn in item.footnotes) {
        buffer.writeln(fn.text);
      }
    }
    if (item.sourceHadithId != null) {
      buffer.writeln(
        '\nالمصدر: موسوعة الأحاديث النبوية HadeethEnc — ${item.sourceUrl}',
      );
      return buffer.toString().trimRight();
    }
    buffer.writeln(
      '\nالمصدر: كتاب حصن المسلم من أذكار الكتاب والسنة - د. سعيد بن علي بن وهف القحطاني',
    );
    buffer.writeln('دار إسلام هاوس: $islamHouseBookUrl');
    return buffer.toString().trimRight();
  }
}
