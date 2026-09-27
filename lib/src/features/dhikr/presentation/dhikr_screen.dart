import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/data/models/dhikr_session.dart';
import '../../progress/presentation/controllers/progress_controller.dart';

class DhikrScreen extends ConsumerStatefulWidget {
  const DhikrScreen({super.key});

  @override
  ConsumerState<DhikrScreen> createState() => _DhikrScreenState();
}

class _DhikrScreenState extends ConsumerState<DhikrScreen> {
  int _selectedTarget = 33;
  String? _localActiveSessionId;

  void _showTargetPickerDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        int tempTarget = _selectedTarget;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('اختيار هدف التسبيح الشخصي'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('٣٣ تسبيحة'),
                    trailing: tempTarget == 33 ? const Icon(Icons.check, color: AppColors.forestPrimary) : null,
                    onTap: () => setDialogState(() => tempTarget = 33),
                  ),
                  ListTile(
                    title: const Text('١٠٠ تسبيحة'),
                    trailing: tempTarget == 100 ? const Icon(Icons.check, color: AppColors.forestPrimary) : null,
                    onTap: () => setDialogState(() => tempTarget = 100),
                  ),
                  ListTile(
                    title: const Text('١٠ تسبيحات'),
                    trailing: tempTarget == 10 ? const Icon(Icons.check, color: AppColors.forestPrimary) : null,
                    onTap: () => setDialogState(() => tempTarget = 10),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedTarget = tempTarget;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('تأكيد'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _startNewSession(String dateBucket) async {
    final newId = generateSessionId(prefix: 'session');
    try {
      await ref.read(dhikrSessionsControllerProvider(dateBucket).notifier).startSession(
            sessionId: newId,
            dhikrId: 'personal_tasbeeh',
            category: 'عام',
            targetCount: _selectedTarget,
          );
      if (mounted) {
        setState(() {
          _localActiveSessionId = newId;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر بدء الجلسة: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _startNewSession(dateBucket),
            ),
          ),
        );
      }
    }
  }

  Future<void> _activateSession(String sessionId) async {
    try {
      await ref.read(preferencesControllerProvider.notifier).setActiveDhikrSessionId(sessionId);
      if (mounted) {
        setState(() {
          _localActiveSessionId = sessionId;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر تفعيل الجلسة: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _activateSession(sessionId),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(activeDateBucketProvider);
    final sessionsAsync = ref.watch(dhikrSessionsControllerProvider(today));
    final unfinishedAsync = ref.watch(unfinishedDhikrSessionsProvider);
    final prefs = ref.watch(preferencesControllerProvider).valueOrNull;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveActiveId = _localActiveSessionId ?? prefs?.activeDhikrSessionId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('التسبيح والذكر'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'تغيير الهدف',
            onPressed: _showTargetPickerDialog,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'جلسة جديدة',
            onPressed: () => _startNewSession(today),
          ),
        ],
      ),
      body: SafeArea(
        child: sessionsAsync.when(
          data: (sessions) {
            DhikrSession? activeSession;
            if (effectiveActiveId != null) {
              final found = sessions.where((s) => s.sessionId == effectiveActiveId);
              if (found.isNotEmpty) {
                activeSession = found.first;
              } else {
                final unfin = unfinishedAsync.valueOrNull?.where((s) => s.sessionId == effectiveActiveId);
                if (unfin != null && unfin.isNotEmpty) {
                  activeSession = unfin.first;
                }
              }
            }
            activeSession ??= sessions.isNotEmpty ? sessions.first : null;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Active Interactive Dhikr Counter Card
                  if (activeSession != null)
                    _buildActiveCounter(activeSession, isDark)
                  else
                    _buildStartNewSessionCard(isDark, today),

                  const SizedBox(height: 16),

                  // Resumable Unfinished Historical Sessions Section
                  unfinishedAsync.when(
                    data: (unfinished) {
                      final nonActiveUnfinished = unfinished.where((s) => s.sessionId != activeSession?.sessionId).toList();
                      if (nonActiveUnfinished.isEmpty) return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'جلسات سابقة غير مكتملة (قابلة للمتابعة)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${nonActiveUnfinished.length} جلسة',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...nonActiveUnfinished.map((s) {
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.history, color: AppColors.goldAccent, size: 20),
                                title: Text(
                                  'جلسة تاريخ ${formatDisplayDate(s.dateBucket)} (${s.currentCount}/${s.targetCount})',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                subtitle: Text(
                                  'المتبقي: ${s.remainingCount} تسبيحة',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: TextButton(
                                  child: const Text('متابعة', style: TextStyle(fontSize: 11)),
                                  onPressed: () => _activateSession(s.sessionId),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 14),
                        ],
                      );
                    },
                    loading: () => const SizedBox.shrink(),
                    error: (err, _) => Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'تعذر تحميل الجلسات السابقة غير المكتملة',
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref.invalidate(unfinishedDhikrSessionsProvider),
                            child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Session History for Today
                  if (sessions.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'جلسات اليوم المحفوظة',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${sessions.length} جلسة',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...sessions.map((s) {
                      final isSelected = s.sessionId == activeSession?.sessionId;
                      return Card(
                        color: isSelected
                            ? (isDark ? AppColors.darkCardBorder : AppColors.forestSoftTint)
                            : (isDark ? AppColors.darkSurface : AppColors.cardSurface),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            s.isCompleted
                                ? 'جلسة مكتملة (${s.currentCount}/${s.targetCount})'
                                : 'جلسة قيد التقدم (${s.currentCount}/${s.targetCount})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: isSelected ? AppColors.forestPrimary : null,
                            ),
                          ),
                          subtitle: Text('الهدف: ${s.targetCount} تسبيحة', style: const TextStyle(fontSize: 10)),
                          trailing: s.isCompleted
                              ? const Icon(Icons.check_circle, color: AppColors.forestLight, size: 20)
                              : const Icon(Icons.timelapse, color: AppColors.goldAccent, size: 20),
                          onTap: () => _activateSession(s.sessionId),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],

                  // Honest Empty State Notice for Dhikr Corpus
                  const EmptyStateView(
                    icon: Icons.auto_awesome,
                    statusTag: 'قيد التدقيق والترخيص المعتمد',
                    title: 'متون الأذكار المأثورة قيد التدقيق',
                    message:
                        'عداد التسبيح وحفظ الجلسات يعمل محلياً في قاعدة البيانات بشكل كامل ودائم. متون أذكار الصباح والمساء المعتمدة من كتاب حصن المسلم ستُدرج بنصوصها الموثقة وترجماتها بعد استكمال التدقيق والترخيص.',
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => RetryableErrorView(
            message: err.toString(),
            onRetry: () => ref.read(dhikrSessionsControllerProvider(today).notifier).retry(),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveCounter(DhikrSession session, bool isDark) {
    final today = ref.watch(activeDateBucketProvider);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'الهدف المختار: ${session.targetCount} تسبيحة',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                ),
              ),
              if (session.isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'مكتملة ✓',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          // Large Tap Button for Atomic SQLite Increments
          InkWell(
            onTap: session.isCompleted
                ? null
                : () async {
                    try {
                      await ref
                          .read(dhikrSessionsControllerProvider(session.dateBucket).notifier)
                          .incrementSession(session.sessionId);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تعذر تسجيل التسبيحة: $e'),
                        ),
                      );
                    }
                  },
            borderRadius: BorderRadius.circular(60),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: session.isCompleted
                      ? [Colors.grey.shade400, Colors.grey.shade500]
                      : [AppColors.forestPrimary, AppColors.forestMedium],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.forestPrimary.withAlpha(50),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${session.currentCount}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            session.isCompleted ? 'تم إكمال التسبيح بنجاح' : 'المتبقي: ${session.remainingCount}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _startNewSession(today),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('بدء جلسة جديدة (مع حفظ السابقة)'),
          ),
        ],
      ),
    );
  }

  Widget _buildStartNewSessionCard(bool isDark, String dateBucket) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.touch_app, size: 40, color: AppColors.forestPrimary),
          const SizedBox(height: 12),
          const Text(
            'ابدأ جلسة ذكر جديدة',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'الجلسات تُحفظ تلقائياً في قاعدة البيانات المحلية وتحافظ على سجل الأيام السابقة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _startNewSession(dateBucket),
            child: Text('بدء جلسة تسبيح ($_selectedTarget)'),
          ),
        ],
      ),
    );
  }
}
