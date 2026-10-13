import '../../domain/models/hisn_item.dart';
import '../../domain/models/hisn_invocation_catalog.dart';

/// Shared formatter for Hisn al-Muslim items to ensure uniform clipboard copying
/// and sharing across all Hisn screens (both chapter list and item detail views).
class HisnTextFormatter {
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
