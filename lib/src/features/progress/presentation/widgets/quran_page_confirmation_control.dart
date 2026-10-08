import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../controllers/progress_controller.dart';

/// Compact control designed for insertion inside the horizontally scrolling Quran reader footer.
///
/// Uses finite intrinsic layout (no unbound Flexible/Expanded inside Row) with Wrap,
/// safe for horizontal scrolling parents and large accessibility text scales (textScale 2.0).
/// Captures original owning notifier and reset generation at first acceptance.
class QuranPageConfirmationControl extends ConsumerStatefulWidget {
  final int pageNumber;

  const QuranPageConfirmationControl({
    super.key,
    required this.pageNumber,
  });

  @override
  ConsumerState<QuranPageConfirmationControl> createState() =>
      _QuranPageConfirmationControlState();
}

class _QuranPageConfirmationControlState
    extends ConsumerState<QuranPageConfirmationControl> {
  bool _isSaving = false;

  Future<void> _performToggle({
    required BuildContext context,
    required WidgetRef ref,
    required int page,
    required String bucket,
    required bool desiredBool,
  }) async {
    if (!mounted) return;
    final barrier = ref.read(resetBarrierProvider);
    if (barrier.isResetInProgress) return;
    final int capturedGen = barrier.currentGeneration;
    final notifier =
        ref.read(dailyQuranPagesControllerProvider(bucket).notifier);

    setState(() {
      _isSaving = true;
    });

    try {
      if (desiredBool) {
        await notifier.confirmPage(page);
      } else {
        await notifier.undoPage(page);
      }

      if (!mounted) return;

      // Check generation after async repo write
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
    required DailyQuranPagesController notifier,
    required int capturedGen,
  }) {
    if (!mounted || !context.mounted) return;
    final currentBarrier = ref.read(resetBarrierProvider);
    if (currentBarrier.isResetInProgress ||
        currentBarrier.currentGeneration != capturedGen) {
      // Reset occurred; reject stale retry to avoid resurrecting state
      return;
    }

    final errorMsg =
        notifier.saveErrorMessageArabic ?? 'تعذر حفظ تأكيد قراءة الصفحة.';
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

  @override
  Widget build(BuildContext context) {
    if (widget.pageNumber < 1 || widget.pageNumber > 604) {
      return const SizedBox.shrink();
    }

    final readiness = ref.watch(dateReadinessProvider);
    final isResetInProgress = ref.watch(isResetInProgressProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

    if (!readiness.isReady || readiness.activeBucket == null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        child: readiness.isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              )
            : Text(
                'بانتظار تهيئة التاريخ...',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                ),
              ),
      );
    }

    final dateBucket = readiness.activeBucket!;
    final pagesAsync =
        ref.watch(dailyQuranPagesControllerProvider(dateBucket));
    final dailyAsync =
        ref.watch(dailyProgressControllerProvider(dateBucket));

    // Authoritative loading: do NOT assume false unconfirmed or 0 count
    if (pagesAsync.isLoading) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 8),
            Text(
              'جاري تحميل تأكيدات القراءة...',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Authoritative error: show stable Arabic error with read retry and disable writes
    if (pagesAsync.hasError) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'تعذر تحميل تأكيدات القراءة.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () => ref.refresh(
                  dailyQuranPagesControllerProvider(dateBucket)),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                visualDensity: VisualDensity.compact,
              ),
              child: const Text('إعادة المحاولة',
                  style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
    }

    final confirmedPages = pagesAsync.requireValue;
    final isConfirmed = confirmedPages.contains(widget.pageNumber);
    final confirmedCount = confirmedPages.length;

    final bool isDisabled = _isSaving || isResetInProgress;

    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          // Confirmation / Undo Action Button
          if (isConfirmed)
            OutlinedButton.icon(
              key: const Key('quran_page_undo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark
                    ? AppColors.darkGoldAccent
                    : AppColors.forestPrimary,
                side: BorderSide(
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestPrimary,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 34),
                visualDensity: VisualDensity.compact,
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    )
                  : const Icon(Icons.check_circle, size: 16),
              label: const Text(
                'مقروءة ✓ (تراجع)',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: isDisabled
                  ? null
                  : () {
                      final int targetPage = widget.pageNumber;
                      final String targetBucket = dateBucket;
                      const bool desiredBool = false;
                      _performToggle(
                        context: context,
                        ref: ref,
                        page: targetPage,
                        bucket: targetBucket,
                        desiredBool: desiredBool,
                      );
                    },
            )
          else
            ElevatedButton.icon(
              key: const Key('quran_page_confirm'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? AppColors.darkGoldAccent
                    : AppColors.forestPrimary,
                foregroundColor: isDark ? AppColors.textDark : Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(0, 34),
                visualDensity: VisualDensity.compact,
                elevation: 0,
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline, size: 16),
              label: const Text(
                'قرأت هذه الصفحة',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              onPressed: isDisabled
                  ? null
                  : () {
                      final int targetPage = widget.pageNumber;
                      final String targetBucket = dateBucket;
                      const bool desiredBool = true;
                      _performToggle(
                        context: context,
                        ref: ref,
                        page: targetPage,
                        bucket: targetBucket,
                        desiredBool: desiredBool,
                      );
                    },
            ),

          // Confirmed Count vs Daily Goal Indicator (authoritative, bounded intrinsic layout)
          if (dailyAsync.isLoading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$confirmedCount صفحة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                  ),
                ),
                const SizedBox(width: 6),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'جاري تحميل الورد...',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                ),
              ],
            )
          else if (dailyAsync.hasError)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$confirmedCount صفحة',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'تعذر تحميل الورد',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  key: const Key('quran_goal_retry'),
                  onPressed: () => ref.refresh(
                    dailyProgressControllerProvider(dateBucket),
                  ),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('إعادة المحاولة',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            )
          else ...[
            Builder(builder: (context) {
              final goalPages = dailyAsync.requireValue.quranGoalPages;
              final isGoalMet = confirmedCount >= goalPages;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$confirmedCount من $goalPages صفحة',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color:
                          isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                    ),
                  ),
                  if (isGoalMet) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.green.withAlpha(40)
                            : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'اكتمل الورد ✓',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.greenAccent
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ],
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}
