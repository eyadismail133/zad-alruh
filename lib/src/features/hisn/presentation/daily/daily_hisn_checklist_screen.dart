import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/retryable_error_view.dart';
import '../../../progress/data/models/hisn_daily_item_progress.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';
import '../../domain/models/hisn_daily_catalog.dart';
import '../../domain/models/hisn_item.dart';
import '../../domain/repositories/hisn_repository.dart';
import '../controllers/hisn_provider.dart';
import '../hisn_detail_screen.dart';
import '../utils/hisn_text_formatter.dart';

/// Screen presenting the authoritative source-based daily Dhikr checklist
/// for either Morning (exact 22 items) or Evening (exact 20 items),
/// along with the optional shared daily 100-times item (Item 96).
class DailyHisnChecklistScreen extends ConsumerStatefulWidget {
  final DhikrPeriod period;

  const DailyHisnChecklistScreen({
    super.key,
    required this.period,
  });

  @override
  ConsumerState<DailyHisnChecklistScreen> createState() =>
      _DailyHisnChecklistScreenState();
}

class _DailyHisnChecklistScreenState
    extends ConsumerState<DailyHisnChecklistScreen> {
  final Set<int> _savingItemIds = <int>{};
  final Set<int> _expandedFootnoteItemIds = <int>{};

  Future<void> _toggleItemProgress({
    required BuildContext context,
    required WidgetRef ref,
    required String bucket,
    required DhikrPeriod period,
    required int itemId,
    required bool desiredBool,
  }) async {
    if (!mounted) return;
    final barrier = ref.read(resetBarrierProvider);
    if (barrier.isResetInProgress) return;
    final int capturedGen = barrier.currentGeneration;
    final key = HisnItemProgressKey(dateBucket: bucket, period: period);
    final notifier =
        ref.read(hisnDailyItemProgressControllerProvider(key).notifier);

    setState(() {
      _savingItemIds.add(itemId);
    });

    try {
      await notifier.setItemProgress(
        itemId: itemId,
        isCompleted: desiredBool,
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
          _savingItemIds.remove(itemId);
        });
      }
    }
  }

  void _showErrorSnackBar({
    required HisnDailyItemProgressController notifier,
    required int capturedGen,
  }) {
    if (!mounted || !context.mounted) return;
    final currentBarrier = ref.read(resetBarrierProvider);
    if (currentBarrier.isResetInProgress ||
        currentBarrier.currentGeneration != capturedGen) {
      return;
    }

    final errorMsg =
        notifier.saveErrorMessageArabic ?? 'تعذر حفظ قراءة الذكر.';
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
    if (item.id == HisnDailyCatalog.item92Id) {
      return '١٠ مرات أو مرة واحدة عند الكسل (حسب الرواية)';
    }
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

    final String screenTitle = widget.period == DhikrPeriod.morning
        ? 'أذكار الصباح (٢٢ ذكراً)'
        : 'أذكار المساء (٢٠ ذكراً)';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(screenTitle),
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
                      message: 'تعذر تحميل كتاب حصن المسلم الموثق.',
                      onRetry: () => ref.refresh(hisnRepositoryProvider),
                    ),
                  ),
                );
              }

              final String dateBucket = readiness.activeBucket!;
              final repo = hisnRepoAsync.valueOrNull!;

              final periodKey = HisnItemProgressKey(
                dateBucket: dateBucket,
                period: widget.period,
              );
              final periodProgressAsync =
                  ref.watch(hisnDailyItemProgressControllerProvider(periodKey));

              final sharedKey = HisnItemProgressKey(
                dateBucket: dateBucket,
                period: DhikrPeriod.shared100,
              );
              final sharedProgressAsync =
                  ref.watch(hisnDailyItemProgressControllerProvider(sharedKey));

              if (periodProgressAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (periodProgressAsync.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: RetryableErrorView(
                      message: 'تعذر تحميل حالة أذكار اليوم.',
                      onRetry: () => ref.refresh(
                        hisnDailyItemProgressControllerProvider(periodKey),
                      ),
                    ),
                  ),
                );
              }

              final completedPeriodItemIds = periodProgressAsync.requireValue
                  .where((p) => p.isCompleted)
                  .map((p) => p.itemId)
                  .toSet();

              final itemIds = HisnDailyCatalog.getItemIdsForPeriod(widget.period);
              final totalCount = widget.period == DhikrPeriod.morning
                  ? HisnDailyCatalog.morningTotalCount
                  : HisnDailyCatalog.eveningTotalCount;
              final completedCount = completedPeriodItemIds.length;
              final isAllCompleted = completedCount >= totalCount;

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // 1. Header Progress & Date Card
                  _buildHeaderCard(
                    dateBucket: dateBucket,
                    completedCount: completedCount,
                    totalCount: totalCount,
                    isAllCompleted: isAllCompleted,
                    isDark: isDark,
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

                  // 3. Exact Sourced Items (22 morning or 20 evening)
                  ...itemIds.map((itemId) {
                    final item = repo.getById(itemId);
                    if (item == null) return const SizedBox.shrink();

                    final isItemCompleted = completedPeriodItemIds.contains(itemId);
                    final isSaving = _savingItemIds.contains(itemId);
                    final isDisabled = isSaving || isResetInProgress;

                    return _buildChecklistItemCard(
                      context: context,
                      item: item,
                      isCompleted: isItemCompleted,
                      isDisabled: isDisabled,
                      isSaving: isSaving,
                      dateBucket: dateBucket,
                      period: widget.period,
                      isDark: isDark,
                    );
                  }),

                  const SizedBox(height: 16),

                  // 4. Optional Shared Daily 100 Item (Item 96)
                  _buildShared100Card(
                    context: context,
                    repo: repo,
                    dateBucket: dateBucket,
                    sharedProgressAsync: sharedProgressAsync,
                    isResetInProgress: isResetInProgress,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard({
    required String dateBucket,
    required int completedCount,
    required int totalCount,
    required bool isAllCompleted,
    required bool isDark,
  }) {
    final double ratio = totalCount > 0 ? (completedCount / totalCount).clamp(0.0, 1.0) : 0.0;
    final int percentage = (ratio * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'تاريخ اليوم: ${formatDisplayDate(dateBucket)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isAllCompleted) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.green.withAlpha(40) : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'مكتملة ✓',
                    style: TextStyle(
                      color: isDark ? Colors.greenAccent : const Color(0xFF2E7D32),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$completedCount من $totalCount ذكراً مكتملاً ($percentage٪)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: isDark ? AppColors.darkCardBorder : const Color(0xFFD9DFCC),
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark ? AppColors.darkForestPrimary : AppColors.forestPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistItemCard({
    required BuildContext context,
    required HisnItem item,
    required bool isCompleted,
    required bool isDisabled,
    required bool isSaving,
    required String dateBucket,
    required DhikrPeriod period,
    required bool isDark,
  }) {
    final repeatLabel = _formatRepeatLabel(item);
    final eveningNote = widget.period == DhikrPeriod.evening
        ? HisnDailyCatalog.eveningAlternativeNotes[item.id]
        : null;

    final isFootnotesExpanded = _expandedFootnoteItemIds.contains(item.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCompleted
              ? (isDark ? AppColors.darkForestPrimary : AppColors.forestLight)
              : (isDark ? AppColors.darkCardBorder : AppColors.cardBorder),
          width: isCompleted ? 1.5 : 0.8,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Row: Item Number & Repetition
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCardBorder : AppColors.forestSoftTint,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ذكر #${item.number}',
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
                        Flexible(
                          child: Text(
                            repeatLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkGoldAccent : Colors.brown.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Verbatim Text (Preserving Item 75 preface and all paragraphs)
            SelectableText(
              item.text,
              textAlign: TextAlign.justify,
              style: TextStyle(
                fontFamily: 'Amiri Quran',
                fontSize: 16.5,
                height: 1.9,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
              ),
            ),

            // Evening Verbatim Source Footnote Banner (77, 78, 80, 81, 89, 90)
            if (eveningNote != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2E2412) : const Color(0xFFFFFBEA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700.withAlpha(120)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.brightness_3, size: 14, color: AppColors.goldAccent),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'صيغة المساء الواردة في هامش المصدر:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkGoldAccent : Colors.brown.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ...item.footnotes
                        .where((fn) => eveningNote.footnoteIds.contains(fn.id))
                        .map((fn) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                fn.text.trim(),
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.45,
                                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF4A3800),
                                ),
                              ),
                            )),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Footnotes expand toggle & Detail & Copy Actions
            Row(
              children: [
                if (item.footnotes.isNotEmpty)
                  TextButton.icon(
                    key: Key('hisn_checklist_footnotes_toggle_${item.id}'),
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

            const SizedBox(height: 8),

            // Explicit Checkbox: قرأت هذا الذكر (with Undo)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCompleted
                    ? (isDark ? AppColors.darkForestPrimary.withAlpha(35) : const Color(0xFFEFF5F0))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: isDisabled
                    ? null
                    : () {
                        final capturedId = item.id;
                        final capturedPeriod = period;
                        final capturedBucket = dateBucket;
                        final bool desiredBool = !isCompleted;
                        _toggleItemProgress(
                          context: context,
                          ref: ref,
                          bucket: capturedBucket,
                          period: capturedPeriod,
                          itemId: capturedId,
                          desiredBool: desiredBool,
                        );
                      },
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: isSaving
                          ? const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              ),
                            )
                          : Checkbox(
                              key: Key('hisn_checklist_checkbox_${item.id}'),
                              value: isCompleted,
                              activeColor: isDark
                                  ? AppColors.darkForestPrimary
                                  : AppColors.forestPrimary,
                              onChanged: isDisabled
                                  ? null
                                  : (val) {
                                      final capturedId = item.id;
                                      final capturedPeriod = period;
                                      final capturedBucket = dateBucket;
                                      final bool desiredBool = val ?? false;
                                      _toggleItemProgress(
                                        context: context,
                                        ref: ref,
                                        bucket: capturedBucket,
                                        period: capturedPeriod,
                                        itemId: capturedId,
                                        desiredBool: desiredBool,
                                      );
                                    },
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'قرأت هذا الذكر',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                              : (isDark ? AppColors.darkTextPrimary : AppColors.textDark),
                        ),
                      ),
                    ),
                    if (isCompleted)
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
    );
  }

  Widget _buildShared100Card({
    required BuildContext context,
    required HisnRepository repo,
    required String dateBucket,
    required AsyncValue<List<HisnDailyItemProgress>> sharedProgressAsync,
    required bool isResetInProgress,
    required bool isDark,
  }) {
    final item = repo.getById(HisnDailyCatalog.sharedDaily100ItemId);
    if (item == null) return const SizedBox.shrink();

    final isSharedLoading = sharedProgressAsync.isLoading;
    final isSharedError = sharedProgressAsync.hasError;
    final isCompleted = (sharedProgressAsync.valueOrNull ?? <HisnDailyItemProgress>[])
        .any((p) => p.itemId == HisnDailyCatalog.sharedDaily100ItemId && p.isCompleted);

    final isSaving = _savingItemIds.contains(item.id);
    final isDisabled = isSaving || isResetInProgress || isSharedLoading || isSharedError;

    return Card(
      color: isDark ? const Color(0xFF1B2B20) : const Color(0xFFF1F7F2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isCompleted
              ? AppColors.forestPrimary
              : (isDark ? AppColors.darkCardBorder : AppColors.cardBorder),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, size: 18, color: AppColors.goldAccent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'ذكر الاستغفار اليومي (١٠٠ مرة) - اختياري',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.amber.shade900.withAlpha(50) : const Color(0xFFFFF9E6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.goldAccent),
                      ),
                      child: const Text(
                        '١٠٠ مرة',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.goldAccent),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 6),
            Text(
              'مستقل عن نسبة إكمال الصباح (٢٢) والمساء (٢٠)، ويُسجل مرة واحدة في اليوم ويظهر في كلا الوردين.',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 10),
            SelectableText(
              item.text,
              textAlign: TextAlign.justify,
              style: TextStyle(
                fontFamily: 'Amiri Quran',
                fontSize: 16.5,
                height: 1.9,
                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isCompleted
                    ? (isDark ? AppColors.darkForestPrimary.withAlpha(35) : const Color(0xFFE4EDE5))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: InkWell(
                onTap: isDisabled
                    ? null
                    : () {
                        final capturedId = item.id;
                        final capturedBucket = dateBucket;
                        final bool desiredBool = !isCompleted;
                        _toggleItemProgress(
                          context: context,
                          ref: ref,
                          bucket: capturedBucket,
                          period: DhikrPeriod.shared100,
                          itemId: capturedId,
                          desiredBool: desiredBool,
                        );
                      },
                child: Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: isSaving || isSharedLoading
                          ? const Center(
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              ),
                            )
                          : Checkbox(
                              key: const Key('hisn_checklist_checkbox_96'),
                              value: isCompleted,
                              activeColor: isDark ? AppColors.darkForestPrimary : AppColors.forestPrimary,
                              onChanged: isDisabled
                                  ? null
                                  : (val) {
                                      final capturedId = item.id;
                                      final capturedBucket = dateBucket;
                                      final bool desiredBool = val ?? false;
                                      _toggleItemProgress(
                                        context: context,
                                        ref: ref,
                                        bucket: capturedBucket,
                                        period: DhikrPeriod.shared100,
                                        itemId: capturedId,
                                        desiredBool: desiredBool,
                                      );
                                    },
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'قرأت هذا الذكر (١٠٠ مرة)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                              : (isDark ? AppColors.darkTextPrimary : AppColors.textDark),
                        ),
                      ),
                    ),
                    if (isSharedError)
                      Text(
                        'تعذر تحميل الحالة (معطل)',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red.shade700,
                        ),
                      )
                    else if (isCompleted)
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
    );
  }
}
