import 'package:flutter/material.dart';
import '../../domain/models/hisn_invocation_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/retryable_error_view.dart';
import '../../../progress/data/models/daily_source_confirmation.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';
import '../../domain/models/hisn_daily_catalog.dart';
import '../../domain/models/hisn_item.dart';
import '../controllers/hisn_provider.dart';
import '../hisn_detail_screen.dart';
import '../utils/hisn_text_formatter.dart';

/// Screen presenting all 8 authentic entries of Chapter 25 (items 66..73) from Hisn al-Muslim
/// for Post-Prayer Dhikr, with a single personal self-report confirmation checkbox.
///
/// Uses Item 66 as the Chapter 25 source anchor in SQLite storage without pretending all 8 entries are compulsory.
class PostPrayerDailyScreen extends ConsumerStatefulWidget {
  const PostPrayerDailyScreen({super.key});

  @override
  ConsumerState<PostPrayerDailyScreen> createState() =>
      _PostPrayerDailyScreenState();
}

class _PostPrayerDailyScreenState extends ConsumerState<PostPrayerDailyScreen> {
  bool _isSaving = false;
  final Set<int> _expandedFootnoteItemIds = <int>{};

  Future<void> _toggleConfirmation({
    required BuildContext context,
    required WidgetRef ref,
    required String bucket,
    required bool desiredBool,
  }) async {
    if (!mounted) return;
    final barrier = ref.read(resetBarrierProvider);
    if (barrier.isResetInProgress) return;
    final int capturedGen = barrier.currentGeneration;
    final key = DailySourceKey(
      dateBucket: bucket,
      taskKey: DailySourceTasks.postPrayer,
    );
    final notifier =
        ref.read(dailySourceConfirmationControllerProvider(key).notifier);

    setState(() {
      _isSaving = true;
    });

    try {
      // Store item 66 as the authoritative Chapter 25 reference anchor
      await notifier.setConfirmation(
        isCompleted: desiredBool,
        hisnItemId: HisnDailyCatalog.postPrayerItemIds.first, // 66
      );

      if (!mounted) return;

      final currentBarrier = ref.read(resetBarrierProvider);
      if (currentBarrier.isResetInProgress ||
          currentBarrier.currentGeneration != capturedGen) {
        return;
      }
    } catch (_) {
      if (!mounted) return;
      _showErrorSnackBar(
        notifier: notifier,
        capturedGen: capturedGen,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showErrorSnackBar({
    required DailySourceConfirmationController notifier,
    required int capturedGen,
  }) {
    if (!mounted || !context.mounted) return;
    final currentBarrier = ref.read(resetBarrierProvider);
    if (currentBarrier.isResetInProgress ||
        currentBarrier.currentGeneration != capturedGen) {
      return;
    }

    final errorMsg =
        notifier.saveErrorMessageArabic ?? 'تعذر حفظ أذكار بعد الصلاة.';
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        content: Text(errorMsg),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'إعادة المحاولة',
          textColor: Colors.white,
          onPressed: () async {
            if (!mounted || !context.mounted) return;
            final retryBarrier = ref.read(resetBarrierProvider);
            if (retryBarrier.isResetInProgress ||
                retryBarrier.currentGeneration != capturedGen) {
              return;
            }
            if (!notifier.hasSaveError) {
              return;
            }
            try {
              await notifier.retryFailedIntent();
            } catch (_) {
              if (mounted && context.mounted) {
                _showErrorSnackBar(
                  notifier: notifier,
                  capturedGen: capturedGen,
                );
              }
            }
          },
        ),
      ),
    );
  }

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

  String _formatRepeatLabel(HisnItem item) {
    final target = item.repeatTarget;
    if (target == null) return '';
    if (target == 1) return 'مرة واحدة';
    if (target == 2) return 'مرتان';
    if (target >= 3 && target <= 10) return '$target مرات';
    return '$target مرة';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final readiness = ref.watch(dateReadinessProvider);
    final isResetInProgress = ref.watch(isResetInProgressProvider);
    final hisnRepoAsync = ref.watch(hisnRepositoryProvider);

    ref.listen<bool>(isResetInProgressProvider, (prev, next) {
      if (next == true) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });
    ref.listen<ProgressMutationBarrier>(resetBarrierProvider, (prev, next) {
      if (prev != null && prev.currentGeneration != next.currentGeneration) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
    });

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('أذكار بعد الصلاة (الباب ٢٥)'),
        ),
        body: SafeArea(
          child: Builder(
            builder: (context) {
              if (readiness.isLoading || hisnRepoAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (readiness.hasError || !readiness.isReady || readiness.activeBucket == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: RetryableErrorView(
                      message: 'تعذر تحديد التاريخ والمنطقة الزمنية المعتمدة.',
                      onRetry: () => ref.refresh(preferencesControllerProvider),
                    ),
                  ),
                );
              }

              if (hisnRepoAsync.hasError || hisnRepoAsync.valueOrNull == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: RetryableErrorView(
                      message: 'تعذر تحميل كتاب حصن المسلم.',
                      onRetry: () => ref.refresh(hisnRepositoryProvider),
                    ),
                  ),
                );
              }

              final String dateBucket = readiness.activeBucket!;
              final repo = hisnRepoAsync.valueOrNull!;

              final sourceKey = DailySourceKey(
                dateBucket: dateBucket,
                taskKey: DailySourceTasks.postPrayer,
              );
              final confirmationAsync =
                  ref.watch(dailySourceConfirmationControllerProvider(sourceKey));

              if (confirmationAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (confirmationAsync.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: RetryableErrorView(
                      message: 'تعذر تحميل حالة أذكار بعد الصلاة.',
                      onRetry: () => ref.refresh(
                        dailySourceConfirmationControllerProvider(sourceKey),
                      ),
                    ),
                  ),
                );
              }

              final confirmation = confirmationAsync.requireValue;
              final bool isConfirmed = confirmation?.isCompleted ?? false;
              final isDisabled = _isSaving || isResetInProgress;

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // 1. Header Card with Date & Single Confirmation Checkbox
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isConfirmed
                            ? AppColors.forestPrimary
                            : (isDark ? AppColors.darkCardBorder : AppColors.cardBorder),
                        width: isConfirmed ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'تاريخ اليوم: ${formatDisplayDate(dateBucket)}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: isConfirmed
                                    ? (isDark ? Colors.green.withAlpha(40) : const Color(0xFFE8F5E9))
                                    : (isDark ? Colors.amber.withAlpha(30) : const Color(0xFFFFF8E1)),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isConfirmed ? 'مكتملة بحمد الله ✓' : 'لم تسجل بعد',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isConfirmed
                                      ? (isDark ? Colors.greenAccent : const Color(0xFF2E7D32))
                                      : (isDark ? AppColors.darkGoldAccent : AppColors.goldDark),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'الأذكار بعد السلام من الصلاة (٨ أذكار مأثورة)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'تتضمن الأذكار المشتركة والواردة في أحوال مختلفة؛ لا يشترط الإتيان بجميع الصيغ البديلة في كل صلاة.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Single explicit confirmation checkbox
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isConfirmed
                                ? (isDark ? AppColors.darkForestPrimary.withAlpha(40) : const Color(0xFFEFF5F0))
                                : (isDark ? AppColors.darkBackground : const Color(0xFFF7F9F7)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isConfirmed ? AppColors.forestPrimary : Colors.transparent,
                            ),
                          ),
                          child: InkWell(
                            onTap: isDisabled
                                ? null
                                : () {
                                    final capturedBucket = dateBucket;
                                    final bool desiredBool = !isConfirmed;
                                    _toggleConfirmation(
                                      context: context,
                                      ref: ref,
                                      bucket: capturedBucket,
                                      desiredBool: desiredBool,
                                    );
                                  },
                            child: Row(
                              children: [
                                SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: _isSaving
                                      ? const Center(
                                          child: SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 1.5),
                                          ),
                                        )
                                      : Checkbox(
                                          key: const Key('post_prayer_confirm_checkbox'),
                                          value: isConfirmed,
                                          activeColor: isDark
                                              ? AppColors.darkForestPrimary
                                              : AppColors.forestPrimary,
                                          onChanged: isDisabled
                                              ? null
                                              : (val) {
                                                  final capturedBucket = dateBucket;
                                                  final bool desiredBool = val ?? false;
                                                  _toggleConfirmation(
                                                    context: context,
                                                    ref: ref,
                                                    bucket: capturedBucket,
                                                    desiredBool: desiredBool,
                                                  );
                                                },
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'قرأت أذكار بعد الصلاة',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: isConfirmed
                                          ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                                          : (isDark ? AppColors.darkTextPrimary : AppColors.textDark),
                                    ),
                                  ),
                                ),
                                if (isConfirmed)
                                  Text(
                                    'مُسجل ✓ (اضغط للإلغاء)',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // 2. Personal Reading Disclaimer Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCardBorder : const Color(0xFFF3F6F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? AppColors.darkCardBorder : const Color(0xFFE0E8E1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            HisnDailyCatalog.personalTrackingExplanationArabic,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.4,
                              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 3. All 8 Items of Chapter 25 (66..73) with full texts and sources
                  ...HisnDailyCatalog.postPrayerItemIds.map((itemId) {
                    final item = repo.getById(itemId);
                    if (item == null) return const SizedBox.shrink();

                    final repeatLabel = _formatRepeatLabel(item);
                    final isFootnotesExpanded = _expandedFootnoteItemIds.contains(item.id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.darkCardBorder : AppColors.forestSoftTint,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${HisnInvocationCatalog.label(item.id)} #${item.number}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                                    ),
                                  ),
                                ),
                                if (repeatLabel.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.amber.shade900.withAlpha(50)
                                          : const Color(0xFFFFF9E6),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark ? Colors.amber.shade700 : AppColors.goldAccent,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.repeat_rounded, size: 13, color: AppColors.goldAccent),
                                        const SizedBox(width: 4),
                                        Text(
                                          repeatLabel,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? AppColors.darkGoldAccent : Colors.brown.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            SelectableText(
                              item.text,
                              textAlign: TextAlign.justify,
                              style: TextStyle(
                                fontSize: 16.5,
                                height: 1.9,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                              ),
                            ),

                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 8),

                            Row(
                              children: [
                                if (item.footnotes.isNotEmpty)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: Icon(
                                      isFootnotesExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      size: 16,
                                    ),
                                    label: Text(
                                      'التخريج (${item.footnotes.length})',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        if (isFootnotesExpanded) {
                                          _expandedFootnoteItemIds.remove(item.id);
                                        } else {
                                          _expandedFootnoteItemIds.add(item.id);
                                        }
                                      });
                                    },
                                  ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.open_in_new, size: 17),
                                  tooltip: 'عرض تفاصيل الذكر',
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
                                  icon: const Icon(Icons.copy_rounded, size: 17),
                                  tooltip: 'نسخ الذكر والمراجع',
                                  onPressed: () => _copyItemText(context, item),
                                ),
                              ],
                            ),

                            if (isFootnotesExpanded && item.footnotes.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkBackground : const Color(0xFFF9FAF9),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: item.footnotes
                                      .map((fn) => Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 3),
                                            child: Text(
                                              '• ${fn.text.trim()}',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                height: 1.45,
                                                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
