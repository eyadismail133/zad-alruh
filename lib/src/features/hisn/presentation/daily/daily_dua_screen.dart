import '../../domain/models/hisn_invocation_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/retryable_error_view.dart';
import '../../../progress/data/models/daily_source_confirmation.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';
import '../../domain/models/hisn_daily_catalog.dart';
import '../../domain/models/hisn_item.dart';
import '../../domain/repositories/hisn_repository.dart';
import '../controllers/hisn_provider.dart';
import '../hisn_detail_screen.dart';
import '../utils/hisn_text_formatter.dart';

/// Screen allowing the user to search and select any authentic Dhikr/Dua from Hisn al-Muslim
/// as their Daily Dua, persisting the selection uncompleted, and explicitly recording reading confirmation.
class DailyDuaScreen extends ConsumerStatefulWidget {
  const DailyDuaScreen({super.key});

  @override
  ConsumerState<DailyDuaScreen> createState() => _DailyDuaScreenState();
}

class _DailyDuaScreenState extends ConsumerState<DailyDuaScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSelectingNew = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _persistSelection({
    required BuildContext context,
    required WidgetRef ref,
    required String bucket,
    required int itemId,
    required bool isCompleted,
  }) async {
    if (!mounted) return;
    final barrier = ref.read(resetBarrierProvider);
    if (barrier.isResetInProgress) return;
    final int capturedGen = barrier.currentGeneration;
    final key = DailySourceKey(
      dateBucket: bucket,
      taskKey: DailySourceTasks.dailyDua,
    );
    final notifier = ref.read(
      dailySourceConfirmationControllerProvider(key).notifier,
    );

    setState(() {
      _isSaving = true;
    });

    try {
      await notifier.setConfirmation(
        isCompleted: isCompleted,
        hisnItemId: itemId,
      );

      if (!mounted) return;

      final currentBarrier = ref.read(resetBarrierProvider);
      if (currentBarrier.isResetInProgress ||
          currentBarrier.currentGeneration != capturedGen) {
        return;
      }
      setState(() {
        _isSelectingNew = false;
      });
    } catch (_) {
      if (!mounted) return;
      _showErrorSnackBar(notifier: notifier, capturedGen: capturedGen);
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

    final errorMsg = notifier.saveErrorMessageArabic ?? 'تعذر حفظ دعاء اليوم.';
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
            content: Text('تم نسخ نص الدعاء والمراجع بنجاح'),
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
          title: const Text('دعاء اليوم'),
          actions: [
            if (!_isSelectingNew)
              IconButton(
                key: const Key('change_daily_dua_button'),
                icon: const Icon(Icons.search),
                tooltip: 'اختيار أو تغيير الدعاء',
                onPressed: () {
                  setState(() {
                    _isSelectingNew = true;
                  });
                },
              ),
          ],
        ),
        body: SafeArea(
          child: Builder(
            builder: (context) {
              if (readiness.isLoading || hisnRepoAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (readiness.hasError ||
                  !readiness.isReady ||
                  readiness.activeBucket == null) {
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
                taskKey: DailySourceTasks.dailyDua,
              );
              final confirmationAsync = ref.watch(
                dailySourceConfirmationControllerProvider(sourceKey),
              );

              if (confirmationAsync.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (confirmationAsync.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: RetryableErrorView(
                      message: 'تعذر تحميل حالة دعاء اليوم.',
                      onRetry: () => ref.refresh(
                        dailySourceConfirmationControllerProvider(sourceKey),
                      ),
                    ),
                  ),
                );
              }

              final confirmation = confirmationAsync.requireValue;
              final int? chosenItemId = confirmation?.hisnItemId;
              final bool isConfirmed = confirmation?.isCompleted ?? false;
              final HisnItem? chosenItem = chosenItemId != null
                  ? repo.getById(chosenItemId)
                  : null;

              // If user is selecting new OR no item is chosen yet, render search & selection view
              if (_isSelectingNew ||
                  chosenItem == null ||
                  !HisnInvocationCatalog.contains(chosenItem.id)) {
                return _buildSelectionView(
                  context: context,
                  repo: repo,
                  dateBucket: dateBucket,
                  currentlyChosenId: chosenItemId,
                  isDark: isDark,
                  isResetInProgress: isResetInProgress,
                );
              }

              // Otherwise render the chosen item with explicit confirmation control
              return _buildChosenItemView(
                context: context,
                item: chosenItem,
                isConfirmed: isConfirmed,
                dateBucket: dateBucket,
                isResetInProgress: isResetInProgress,
                isDark: isDark,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildChosenItemView({
    required BuildContext context,
    required HisnItem item,
    required bool isConfirmed,
    required String dateBucket,
    required bool isResetInProgress,
    required bool isDark,
  }) {
    final isDisabled = _isSaving || isResetInProgress;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      children: [
        // 1. Status & Date Header
        Container(
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
                  Text(
                    'تاريخ اليوم: ${formatDisplayDate(dateBucket)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textMuted,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isConfirmed
                          ? (isDark
                                ? Colors.green.withAlpha(40)
                                : const Color(0xFFE8F5E9))
                          : (isDark
                                ? Colors.amber.withAlpha(30)
                                : const Color(0xFFFFF8E1)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isConfirmed ? 'مكتمل بحمد الله ✓' : 'بانتظار القراءة',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isConfirmed
                            ? (isDark
                                  ? Colors.greenAccent
                                  : const Color(0xFF2E7D32))
                            : (isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.goldDark),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'الدعاء المختار لهذا اليوم',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.contextLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestPrimary,
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
              color: isDark
                  ? AppColors.darkCardBorder
                  : const Color(0xFFE0E8E1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: isDark
                    ? AppColors.darkGoldAccent
                    : AppColors.forestPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  HisnDailyCatalog.personalTrackingExplanationArabic,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.4,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 3. Verbatim Chosen Item Card
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isConfirmed
                  ? (isDark
                        ? AppColors.darkForestPrimary
                        : AppColors.forestLight)
                  : (isDark ? AppColors.darkCardBorder : AppColors.cardBorder),
              width: isConfirmed ? 1.5 : 0.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                        '${HisnInvocationCatalog.label(item.id)} #${item.number}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.forestPrimary,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      key: const Key('change_daily_dua_inline_button'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.sync, size: 14),
                      label: const Text(
                        'تغيير الدعاء',
                        style: TextStyle(fontSize: 11),
                      ),
                      onPressed: () {
                        setState(() {
                          _isSelectingNew = true;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                SelectableText(
                  item.text,
                  textAlign: TextAlign.justify,
                  style: TextStyle(
                    fontSize: 17,
                    height: 2.0,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.textDark,
                  ),
                ),

                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 10),

                // Footnotes summary & detail/copy
                Row(
                  children: [
                    if (item.footnotes.isNotEmpty)
                      Expanded(
                        child: Text(
                          'التخريج: ${item.footnotes.first.text.trim()}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'عرض التفاصيل الكاملة',
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
                      tooltip: 'نسخ الدعاء والمراجع',
                      onPressed: () => _copyItemText(context, item),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Explicit Checkbox: قرأت هذا الدعاء (with undo)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isConfirmed
                        ? (isDark
                              ? AppColors.darkForestPrimary.withAlpha(40)
                              : const Color(0xFFEFF5F0))
                        : (isDark
                              ? AppColors.darkBackground
                              : const Color(0xFFF7F9F7)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isConfirmed
                          ? AppColors.forestPrimary
                          : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    onTap: isDisabled
                        ? null
                        : () {
                            final capturedBucket = dateBucket;
                            final capturedItemId = item.id;
                            final bool desiredBool = !isConfirmed;
                            _persistSelection(
                              context: context,
                              ref: ref,
                              bucket: capturedBucket,
                              itemId: capturedItemId,
                              isCompleted: desiredBool,
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
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                )
                              : Checkbox(
                                  key: const Key('daily_dua_confirm_checkbox'),
                                  value: isConfirmed,
                                  activeColor: isDark
                                      ? AppColors.darkForestPrimary
                                      : AppColors.forestPrimary,
                                  onChanged: isDisabled
                                      ? null
                                      : (val) {
                                          final capturedBucket = dateBucket;
                                          final capturedItemId = item.id;
                                          final bool desiredBool = val ?? false;
                                          _persistSelection(
                                            context: context,
                                            ref: ref,
                                            bucket: capturedBucket,
                                            itemId: capturedItemId,
                                            isCompleted: desiredBool,
                                          );
                                        },
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'قرأت هذا الدعاء',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: isConfirmed
                                  ? (isDark
                                        ? AppColors.darkGoldAccent
                                        : AppColors.forestPrimary)
                                  : (isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.textDark),
                            ),
                          ),
                        ),
                        if (isConfirmed)
                          Text(
                            'مُسجل ✓ (اضغط للإلغاء)',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionView({
    required BuildContext context,
    required HisnRepository repo,
    required String dateBucket,
    required int? currentlyChosenId,
    required bool isDark,
    required bool isResetInProgress,
  }) {
    final filteredItems = repo
        .search(_searchQuery)
        .where((item) => HisnInvocationCatalog.contains(item.id))
        .toList();
    final isLegacySelection =
        currentlyChosenId != null &&
        !HisnInvocationCatalog.contains(currentlyChosenId);

    return Column(
      children: [
        if (isLegacySelection)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'الاختيار السابق ذكر وليس من الأدعية المختارة. اختر دعاءً بديلاً؛ سجلك السابق محفوظ.',
              key: Key('legacy_daily_dua_notice'),
            ),
          ),
        // Search Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'اختر دعاء اليوم من الأدعية الموثقة',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  if (currentlyChosenId != null && !isLegacySelection)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isSelectingNew = false;
                        });
                      },
                      child: const Text(
                        'إلغاء التغيير',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'ابحث في الأدعية المختارة أو باسم الباب...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              ),
            ],
          ),
        ),

        // Filtered Results List
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'لم يتم العثور على أذكار تطابق "$_searchQuery".',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.textMuted,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  itemCount: filteredItems.length,
                  itemBuilder: (ctx, index) {
                    final item = filteredItems[index];
                    final isCurrentlySelected = item.id == currentlyChosenId;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    item.contextLabel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkGoldAccent
                                          : AppColors.forestPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${HisnInvocationCatalog.label(item.id)} #${item.number}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.7,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton.icon(
                                key: Key('select_dua_${item.id}'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCurrentlySelected
                                      ? Colors.grey.shade600
                                      : (isDark
                                            ? AppColors.darkGoldAccent
                                            : AppColors.forestPrimary),
                                  foregroundColor: isCurrentlySelected
                                      ? Colors.white
                                      : (isDark
                                            ? AppColors.textDark
                                            : Colors.white),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  elevation: 0,
                                ),
                                icon: Icon(
                                  isCurrentlySelected
                                      ? Icons.check
                                      : Icons.touch_app,
                                  size: 14,
                                ),
                                label: Text(
                                  isCurrentlySelected
                                      ? 'مختار حالياً'
                                      : 'اختيار كدعاء اليوم',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: (_isSaving || isResetInProgress)
                                    ? null
                                    : () {
                                        final capturedBucket = dateBucket;
                                        final capturedId = item.id;
                                        // Changing selection clears confirmation (isCompleted: false)
                                        _persistSelection(
                                          context: context,
                                          ref: ref,
                                          bucket: capturedBucket,
                                          itemId: capturedId,
                                          isCompleted: false,
                                        );
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
