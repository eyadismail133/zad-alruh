import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/models/hisn_chapter.dart';
import '../domain/models/hisn_item.dart';
import '../domain/repositories/hisn_repository.dart';
import 'hisn_detail_screen.dart';
import 'utils/hisn_text_formatter.dart';

/// Screen displaying all items belonging to a specific chapter of Hisn al-Muslim.
class HisnChapterScreen extends StatelessWidget {
  final HisnChapter chapter;
  final HisnRepository repository;

  const HisnChapterScreen({
    super.key,
    required this.chapter,
    required this.repository,
  });

  Future<void> _copyItemText(BuildContext context, HisnItem item) async {
    try {
      final formatted = HisnTextFormatter.formatForClipboard(item);
      await Clipboard.setData(ClipboardData(text: formatted));
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم نسخ نص الذكر والمراجع بنجاح'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر نسخ النص إلى الحافظة.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatRepeatLabel(int target) {
    if (target == 1) return 'مرة واحدة';
    if (target == 2) return 'مرتان';
    if (target >= 3 && target <= 10) return '$target مرات';
    return '$target مرة';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = repository.getItemsByChapter(chapter.number);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(chapter.title),
        ),
        body: SafeArea(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                // Chapter Header Card
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCardBorder
                                    : AppColors.forestSoftTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'الباب ${chapter.number} من ١٣٢',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.forestPrimary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCardBorder
                                    : AppColors.forestSoftTint,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${items.length} ${items.length == 1 ? 'ذكر' : 'أذكار'}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.forestPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          chapter.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final item = items[index - 1];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Item Header with Number & Repeat Target
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkCardBorder
                                  : AppColors.forestSoftTint,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'ذكر #${item.number}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkGoldAccent
                                    : AppColors.forestPrimary,
                              ),
                            ),
                          ),
                          if (item.repeatTarget != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.amber.shade900.withAlpha(50)
                                    : const Color(0xFFFFF9E6),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.amber.shade700
                                      : AppColors.goldAccent,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.repeat_rounded,
                                    size: 13,
                                    color: AppColors.goldAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatRepeatLabel(item.repeatTarget!),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkGoldAccent
                                          : Colors.brown.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Verbatim Text
                      SelectableText(
                        item.text,
                        textAlign: TextAlign.justify,
                        style: TextStyle(
                          fontSize: 17,
                          fontFamily: 'Amiri Quran',
                          height: 2.0,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textDark,
                        ),
                      ),

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // Actions & Detail button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.format_quote_rounded, size: 16),
                            label: Text(
                              'التخريج (${item.footnotes.length})',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => HisnDetailScreen(item: item),
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'نسخ الذكر والمراجع',
                            onPressed: () => _copyItemText(context, item),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
