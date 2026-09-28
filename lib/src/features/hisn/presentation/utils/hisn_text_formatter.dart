import '../../domain/models/hisn_item.dart';

/// Shared formatter for Hisn al-Muslim items to ensure uniform clipboard copying
/// and sharing across all Hisn screens (both chapter list and item detail views).
class HisnTextFormatter {
  static const String islamHouseBookUrl = 'https://islamhouse.com/ar/books/2522';

  /// Formats a complete [HisnItem] for copying to clipboard, preserving verbatim
  /// religious text, explicit repetition target (if present), citations/footnotes,
  /// and scholarly attribution to Dr. Saeed Al-Qahtani and IslamHouse.
  static String formatForClipboard(HisnItem item) {
    final buffer = StringBuffer();
    buffer.writeln('${item.chapterTitle} - ذكر #${item.number}');
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
    buffer.writeln(
      '\nالمصدر: كتاب حصن المسلم من أذكار الكتاب والسنة - د. سعيد بن علي بن وهف القحطاني',
    );
    buffer.writeln('دار إسلام هاوس: $islamHouseBookUrl');
    return buffer.toString().trimRight();
  }
}
