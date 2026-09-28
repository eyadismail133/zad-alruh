import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/models/hisn_item.dart';
import 'utils/hisn_text_formatter.dart';

/// Screen presenting the full detail of a single Dhikr / Dua from Hisn al-Muslim,
/// including verbatim text, chapter title, item number, explicit repetition targets,
/// all resolved scholarly footnotes, and IslamHouse provenance attribution.
class HisnDetailScreen extends StatelessWidget {
  final HisnItem item;

  const HisnDetailScreen({
    super.key,
    required this.item,
  });

  static const String islamHouseBookUrl = HisnTextFormatter.islamHouseBookUrl;

  Future<void> _copyDhikrText(BuildContext context) async {
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

  Future<void> _openSourceUrl(BuildContext context) async {
    try {
      final uri = Uri.parse(islamHouseBookUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        _showLaunchFallback(context);
      }
    } catch (_) {
      if (context.mounted) {
        _showLaunchFallback(context);
      }
    }
  }

  void _showLaunchFallback(BuildContext context) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        content: const Text('تعذر فتح الرابط في المتصفح الخارجي.'),
        action: SnackBarAction(
          label: 'نسخ الرابط',
          textColor: Colors.white,
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: islamHouseBookUrl));
          },
        ),
      ),
    );
  }

  String _formatRepeatLabel(int target) {
    if (target == 1) return 'مرة واحدة';
    if (target == 2) return 'مرتان';
    if (target >= 3 && target <= 10) return '$target مرات';
    return '$target مرة';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('ذكر #${item.number}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'نسخ نص الذكر والمراجع',
              onPressed: () => _copyDhikrText(context),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            children: [
              // 1. Header Card with Chapter & Item info
              Card(
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
                              'الباب ${item.chapterNumber}',
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
                              'رقم ${item.number} من ٢٦٧',
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
                      const SizedBox(height: 10),
                      Text(
                        item.chapterTitle,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textDark,
                          height: 1.4,
                        ),
                      ),
                      if (item.repeatTarget != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.amber.shade900.withAlpha(50)
                                : const Color(0xFFFFF9E6),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? Colors.amber.shade700
                                  : AppColors.goldAccent,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.repeat_rounded,
                                size: 18,
                                color: AppColors.goldAccent,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'التكرار الوارد في النص: ${_formatRepeatLabel(item.repeatTarget!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.darkGoldAccent
                                        : Colors.brown.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2. Verbatim Arabic Dhikr Text Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(
                        item.text,
                        textAlign: TextAlign.justify,
                        style: TextStyle(
                          fontSize: 19,
                          fontFamily: 'Amiri Quran',
                          height: 2.1,
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 3. Scholarly Footnotes & Citations Card
              if (item.footnotes.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.format_quote_rounded,
                              size: 20,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'التخريج وهوامش المصدر (${item.footnotes.length})',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.forestPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...item.footnotes.map((fn) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.forestPrimary,
                                  ),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    fn.text.trim(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                      color: isDark
                                          ? AppColors.darkTextMuted
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // 4. Provenance & Attribution Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.verified_outlined,
                            size: 18,
                            color: AppColors.forestPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'المصدر والأمانة العلمية',
                              style: TextStyle(
                                fontSize: 13,
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
                        'كتاب حصن المسلم من أذكار الكتاب والسنة\n'
                        'المؤلف: فضيلة الشيخ د. سعيد بن علي بن وهف القحطاني رحمه الله\n'
                        'النشر الرقمي: دار إسلام هاوس (IslamHouse.com) - مرفق 2019-05-02\n'
                        'نُقل النص والهوامش حرفياً دون تعديل أو توليد آلي.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.open_in_browser, size: 14),
                            label: const Text(
                              'صفحة الكتاب في إسلام هاوس',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: () => _openSourceUrl(context),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text(
                              'نسخ الرابط',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: () async {
                              await Clipboard.setData(
                                const ClipboardData(text: islamHouseBookUrl),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم نسخ رابط الكتاب بنجاح'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
