import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/models/hadith_item.dart';
import '../domain/repositories/hadith_repository.dart';
import 'controllers/hadith_provider.dart';

class HadithDetailScreen extends ConsumerStatefulWidget {
  final HadithItem hadith;
  final HadithRepository? repository;

  const HadithDetailScreen({super.key, required this.hadith, this.repository});

  @override
  ConsumerState<HadithDetailScreen> createState() => _HadithDetailScreenState();
}

class _HadithDetailScreenState extends ConsumerState<HadithDetailScreen> {
  late HadithItem hadith = widget.hadith;

  void _showHadith(HadithItem next) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() => hadith = next);
  }

  Future<void> _copyLink(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: hadith.link));
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم نسخ رابط الحديث بنجاح: ${hadith.link}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر نسخ الرابط إلى الحافظة.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _openUrl(BuildContext context) async {
    try {
      final uri = Uri.parse(hadith.link);
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
          onPressed: () => _copyLink(context),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final repository =
        widget.repository ?? ref.watch(hadithRepositoryProvider).valueOrNull;
    final ordered = repository?.allHadiths ?? const <HadithItem>[];
    final index = ordered.indexWhere((entry) => entry.id == hadith.id);
    final previous = index > 0 ? ordered[index - 1] : null;
    final next = index >= 0 && index + 1 < ordered.length
        ? ordered[index + 1]
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('حديث #${hadith.id}'),
          actions: [
            IconButton(
              tooltip: 'الحديث السابق',
              icon: const Icon(Icons.navigate_before),
              onPressed: previous == null ? null : () => _showHadith(previous),
            ),
            IconButton(
              tooltip: 'الحديث التالي',
              icon: const Icon(Icons.navigate_next),
              onPressed: next == null ? null : () => _showHadith(next),
            ),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'نسخ رابط الحديث',
              onPressed: () => _copyLink(context),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            key: ValueKey(hadith.id),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Header Card with Title, ID and Grade
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
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.darkCardBorder
                                  : AppColors.forestSoftTint,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'رقم #${hadith.id}',
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
                              horizontal: 12,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.teal.shade900.withAlpha(50)
                                  : AppColors.forestSoftTint,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isDark
                                    ? Colors.teal.shade700
                                    : AppColors.forestLight,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 14,
                                  color: isDark
                                      ? Colors.tealAccent.shade100
                                      : AppColors.forestPrimary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hadith.grade,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.tealAccent.shade100
                                        : AppColors.forestPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hadith.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          height: 1.5,
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

              // 2. Full Hadith Text Card
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.format_quote_rounded,
                            size: 20,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'نص الحديث النبوي الشريف',
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
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF161E1A)
                              : const Color(0xFFF9FAF6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : const Color(0xFFD8E2DA),
                          ),
                        ),
                        child: SelectableText(
                          hadith.hadithText,
                          style: TextStyle(
                            fontSize: 17,
                            height: 2.1,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textDark,
                          ),
                          textAlign: TextAlign.justify,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 3. Takhrij Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.menu_book_rounded,
                            size: 18,
                            color: AppColors.forestPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'التخريج والمصدر',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        hadith.takhrij,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Explanation Section (Optional)
              if (hadith.explanation.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 18,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'شرح الحديث',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          hadith.explanation,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.8,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 5. Word Meanings Section (Optional)
              if (hadith.wordMeanings.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.spellcheck_rounded,
                              size: 18,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'معاني المفردات',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          hadith.wordMeanings,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.7,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 6. Benefits Section (Optional)
              if (hadith.benefits.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.star_outline_rounded,
                              size: 18,
                              color: AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'الفوائد المستنبطة',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SelectableText(
                          hadith.benefits,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.7,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // 7. Provenance & Attribution Footer Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: AppColors.forestPrimary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'المصدر والتوثيق',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'المصدر: موسوعة الأحاديث النبوية (HadeethEnc.com)\nالإصدار: v1.7.0 (2025-11-12)\nرابط الحديث: ${hadith.link}',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.open_in_browser, size: 14),
                            label: const Text(
                              'فتح في المتصفح',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: () => _openUrl(context),
                          ),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text(
                              'نسخ الرابط',
                              style: TextStyle(fontSize: 11),
                            ),
                            onPressed: () => _copyLink(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'تنبيه: لا يدّعي التطبيق اعتماداً أو تحقيقاً علمياً مستقلاً، والنصوص مأخوذة كما هي من موسوعة HadeethEnc.',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.5,
                          color: isDark
                              ? AppColors.darkTextMuted
                              : AppColors.textSubtle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
