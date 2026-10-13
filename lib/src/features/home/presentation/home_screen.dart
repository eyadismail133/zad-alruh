import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../hisn/domain/models/hisn_daily_catalog.dart';
import '../../hisn/presentation/daily/daily_dua_screen.dart';
import '../../hisn/presentation/daily/daily_hisn_checklist_screen.dart';
import '../../hisn/presentation/daily/post_prayer_daily_screen.dart';
import '../../more/presentation/settings_screen.dart';
import '../../prayer/domain/models/prayer_day.dart';
import '../../prayer/domain/models/prayer_event.dart';
import '../../prayers/presentation/controllers/prayers_controller.dart';
import '../../progress/data/models/daily_progress.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../../quran/presentation/controllers/quran_navigation_controller.dart';
import '../../quran/presentation/quran_reader_screen.dart';

class HomeScreen extends ConsumerWidget {
  final void Function(int tabIndex)? onNavigateTab;

  const HomeScreen({super.key, this.onNavigateTab});

  void _navigateToQuranReader(BuildContext context, WidgetRef ref, int page) {
    ref.read(quranNavigationProvider.notifier).openReader(page);
    if (onNavigateTab != null) {
      onNavigateTab!(1);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QuranReaderScreen(initialPage: page),
        ),
      );
    }
  }

  void _showQuranGoalDialog(
    BuildContext context,
    WidgetRef ref,
    int currentGoal,
  ) {
    int selectedGoal = currentGoal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('تحديد هدف القراءة اليومي'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'اختر عدد الصفحات المستهدف قراءتها يومياً (١ إلى ٦٠٤ صفحات):',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: selectedGoal > 1
                            ? () => setDialogState(() => selectedGoal--)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCardBorder
                              : AppColors.forestSoftTint,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary,
                          ),
                        ),
                        child: Text(
                          '$selectedGoal ${selectedGoal == 1
                              ? 'صفحة'
                              : selectedGoal == 2
                              ? 'صفحتان'
                              : selectedGoal <= 10
                              ? 'صفحات'
                              : 'صفحة'}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: selectedGoal < 604
                            ? () => setDialogState(() => selectedGoal++)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [2, 4, 8, 10, 20].map((quick) {
                      return ChoiceChip(
                        label: Text('$quick'),
                        selected: selectedGoal == quick,
                        onSelected: (selected) {
                          if (selected) {
                            setDialogState(() => selectedGoal = quick);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(preferencesControllerProvider.notifier)
                          .setQuranGoal(selectedGoal);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red.shade800,
                            content: const Text('تعذر حفظ هدف القراءة.'),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('حفظ الهدف'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingAsync = ref.watch(readingProgressControllerProvider);
    final readiness = ref.watch(dateReadinessProvider);
    final today = readiness.isReady
        ? readiness.activeBucket!
        : ref.watch(activeDateBucketProvider);
    final dailyAsync = ref.watch(dailyProgressControllerProvider(today));
    final prayerStateAsync = ref.watch(prayerTimesControllerProvider);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Greeting
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : AppColors.forestSoftTint,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/branding/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.auto_stories,
                              color: AppColors.forestPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'زادُ الروح',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                              Text(
                                'خلّي يومك أقرب للسكينة',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.darkTextMuted
                                      : AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.amber.withAlpha(40)
                          : AppColors.goldPill,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          size: 13,
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.goldDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'نور يومي',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.goldDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Hero Reading Card
              readingAsync.when(
                data: (reading) {
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1B4E3B), const Color(0xFF123528)]
                            : [AppColors.forestPrimary, AppColors.forestMedium],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'وِردك اليومي',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkGoldAccent
                                    : AppColors.goldAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              Icons.auto_awesome,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : Colors.white70,
                              size: 16,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'كل آية نور في يومك',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'آخر صفحة مسجلة: صفحة ${reading.resumePage} من ٦٠٤',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.goldSoftTint,
                            foregroundColor: AppColors.textDark,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          onPressed: () {
                            _navigateToQuranReader(
                              context,
                              ref,
                              reading.resumePage,
                            );
                          },
                          child: const Text(
                            'كمّل وِردك  ←',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                loading: () => Container(
                  height: 140,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'جاري تحميل الوِرد...',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
                error: (err, _) => RetryableErrorView(
                  message: 'تعذر تحميل موضع القراءة السابق.',
                  onRetry: () => ref
                      .read(readingProgressControllerProvider.notifier)
                      .retry(),
                ),
              ),

              const SizedBox(height: 14),

              // Daily 5-Task Card (Truthful Source-Based Progress)
              Builder(
                builder: (context) {
                  if (readiness.isLoading) {
                    return Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (readiness.hasError) {
                    return RetryableErrorView(
                      message: 'تعذر تهيئة التاريخ والمنطقة الزمنية المعتمدة.',
                      onRetry: () => ref.refresh(preferencesControllerProvider),
                    );
                  }

                  return dailyAsync.when(
                    data: (daily) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : AppColors.cardBorder,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'إنجازك اليوم (${formatDisplayDate(today)})',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDark
                                              ? AppColors.darkTextMuted
                                              : AppColors.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'القرآن والأذكار اليومية',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isDark
                                              ? AppColors.darkTextPrimary
                                              : AppColors.textDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Completion Ring / Badge
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? AppColors.darkGoldAccent
                                          : AppColors.goldAccent,
                                      width: 3.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${daily.completionPercentage}٪',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? AppColors.darkGoldAccent
                                            : AppColors.forestPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Meter Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: daily.completionRatio,
                                minHeight: 6,
                                backgroundColor: isDark
                                    ? AppColors.darkCardBorder
                                    : const Color(0xFFD9DFCC),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDark
                                      ? AppColors.darkForestPrimary
                                      : AppColors.forestLight,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${daily.completedTasksCount} من ٥ خطوات يومية مكتملة',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.textSubtle,
                              ),
                            ),
                            const Divider(height: 18),

                            // 5 Working Routes Task Rows
                            // Task 1: Quran Reading
                            _buildQuranTaskRow(
                              daily: daily,
                              readingPage:
                                  readingAsync.valueOrNull?.resumePage ?? 1,
                              isDark: isDark,
                              context: context,
                              ref: ref,
                            ),

                            // Task 2: Morning Dhikr (22 items)
                            _buildMorningDhikrTaskRow(
                              daily: daily,
                              isDark: isDark,
                              context: context,
                            ),

                            // Task 3: Evening Dhikr (20 items)
                            _buildEveningDhikrTaskRow(
                              daily: daily,
                              isDark: isDark,
                              context: context,
                            ),

                            // Task 4: Post-Prayer Dhikr (Chapter 25)
                            _buildPostPrayerTaskRow(
                              daily: daily,
                              isDark: isDark,
                              context: context,
                            ),

                            // Task 5: Daily Dua (Hisn al-Muslim)
                            _buildDailyDuaTaskRow(
                              daily: daily,
                              isDark: isDark,
                              context: context,
                            ),
                          ],
                        ),
                      );
                    },
                    loading: () => Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => RetryableErrorView(
                      message: 'تعذر تحميل التقدم اليومي.',
                      onRetry: () => ref
                          .read(dailyProgressControllerProvider(today).notifier)
                          .retry(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 14),

              // Next Prayer Card (Real offline calculations from shared provider)
              prayerStateAsync.when(
                data: (state) {
                  if (state.isUnsupported) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkCardBorder
                              : AppColors.cardBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(
                                'مواقيت الصلاة',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.textDark,
                                ),
                              ),
                              Text(
                                state.unsupportedCity ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.forestMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'المدينة المحددة غير مدعومة حالياً في حساب المواقيت. اضغط لفتح الإعدادات واختيار مدينة معتمدة.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute<void>(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.tune, size: 14),
                              label: const Text(
                                'الإعدادات',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (state.isUnresolved) {
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkCardBorder
                              : AppColors.cardBorder,
                        ),
                      ),
                      child: InkWell(
                        onTap: () => onNavigateTab?.call(2),
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'مواقيت الصلاة',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'تعذر حساب المواقيت فلكياً لهذا اليوم (يوم قطبي). اضغط لعرض التفاصيل.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.4,
                                color: isDark
                                    ? AppColors.darkTextMuted
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final city = state.city;
                  final next = state.nextPrayer;
                  final timeString = next != null && city != null
                      ? formatPrayerTime(next, city.timezone)
                      : '--:--';
                  final countdown = state.countdownString;

                  return Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? AppColors.darkCardBorder
                            : AppColors.cardBorder,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => onNavigateTab?.call(2),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  'الصلاة القادمة',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.textDark,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 13,
                                      color: isDark
                                          ? AppColors.darkGoldAccent
                                          : AppColors.forestMedium,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      city?.arabicName ?? city?.name ?? '',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark
                                            ? AppColors.darkGoldAccent
                                            : AppColors.forestMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            // Next prayer callout
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isDark
                                      ? [
                                          const Color(0xFF1B4E3B),
                                          const Color(0xFF123528),
                                        ]
                                      : [
                                          const Color(0xFFFFF5DF),
                                          const Color(0xFFE7F1E6),
                                        ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${next?.type.arabicName ?? ''} · بعد $countdown',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? AppColors.darkTextMuted
                                                : AppColors.textMuted,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          timeString,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: isDark
                                                ? AppColors.darkGoldAccent
                                                : const Color(0xFF875E22),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'عرض الكل',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? AppColors.darkGoldAccent
                                              : AppColors.forestPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        size: 11,
                                        color: isDark
                                            ? AppColors.darkGoldAccent
                                            : AppColors.forestPrimary,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (state.prayerDay != null &&
                                !state.prayerDay!.isUnresolved) ...[
                              const SizedBox(height: 10),
                              _buildPrayersSummaryRow(
                                prayerDay: state.prayerDay!,
                                nextPrayer: next,
                                timezone: city?.timezone ?? 'Africa/Cairo',
                                isDark: isDark,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
                loading: () => Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkSurface
                        : AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    'تعذر حساب مواقيت الصلاة. يرجى التحقق من إعدادات المدينة أو إعادة المحاولة.',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Quick Actions
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => onNavigateTab?.call(3), // Dhikr Tab
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.goldSoftTint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : const Color(0xFFF0DFBB),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wb_sunny_outlined,
                              size: 15,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.goldDark,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'أذكار اليوم',
                                softWrap: true,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkGoldAccent
                                      : AppColors.goldDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => onNavigateTab?.call(4), // More Tab
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkSurface
                              : AppColors.forestSoftTint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkCardBorder
                                : const Color(0xFFD7E7D9),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 15,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.forestPrimary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'الأدعية والمزيد',
                                softWrap: true,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkTextPrimary
                                      : AppColors.forestPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuranTaskRow({
    required DailyProgress daily,
    required int readingPage,
    required bool isDark,
    required BuildContext context,
    required WidgetRef ref,
  }) {
    return InkWell(
      key: const Key('home_task_quran'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => _navigateToQuranReader(context, ref, readingPage),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Icon(
              daily.quranCompleted
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 20,
              color: daily.quranCompleted
                  ? (isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestPrimary)
                  : (isDark ? AppColors.darkTextMuted : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'وِرد القرآن (${daily.quranPagesRead} من ${daily.quranGoalPages} صفحات)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                      decoration: daily.quranCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    daily.quranCompleted
                        ? 'مكتمل بحمد الله'
                        : 'اضغط للمتابعة والقراءة في المصحف',
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
            IconButton(
              key: const Key('home_task_quran_goal_button'),
              icon: const Icon(Icons.tune, size: 16),
              tooltip: 'تعديل الهدف اليومي',
              visualDensity: VisualDensity.compact,
              onPressed: () =>
                  _showQuranGoalDialog(context, ref, daily.quranGoalPages),
            ),
            const Icon(Icons.chevron_left, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMorningDhikrTaskRow({
    required DailyProgress daily,
    required bool isDark,
    required BuildContext context,
  }) {
    return InkWell(
      key: const Key('home_task_morning_dhikr'),
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                const DailyHisnChecklistScreen(period: DhikrPeriod.morning),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Icon(
              daily.morningDhikrCompleted
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 20,
              color: daily.morningDhikrCompleted
                  ? (isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestPrimary)
                  : (isDark ? AppColors.darkTextMuted : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أذكار الصباح (${daily.morningCompletedCount} من ${HisnDailyCatalog.morningTotalCount} ذكراً)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                      decoration: daily.morningDhikrCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    daily.morningDhikrCompleted
                        ? 'مكتملة بحمد الله'
                        : 'اضغط لفتح قائمة أذكار الصباح الموثقة',
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
            const Icon(Icons.chevron_left, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildEveningDhikrTaskRow({
    required DailyProgress daily,
    required bool isDark,
    required BuildContext context,
  }) {
    return InkWell(
      key: const Key('home_task_evening_dhikr'),
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                const DailyHisnChecklistScreen(period: DhikrPeriod.evening),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Icon(
              daily.eveningDhikrCompleted
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 20,
              color: daily.eveningDhikrCompleted
                  ? (isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestPrimary)
                  : (isDark ? AppColors.darkTextMuted : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أذكار المساء (${daily.eveningCompletedCount} من ${HisnDailyCatalog.eveningTotalCount} ذكراً)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                      decoration: daily.eveningDhikrCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    daily.eveningDhikrCompleted
                        ? 'مكتملة بحمد الله'
                        : 'اضغط لفتح قائمة أذكار المساء الموثقة',
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
            const Icon(Icons.chevron_left, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPostPrayerTaskRow({
    required DailyProgress daily,
    required bool isDark,
    required BuildContext context,
  }) {
    return InkWell(
      key: const Key('home_task_post_prayer'),
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const PostPrayerDailyScreen(),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Icon(
              daily.postPrayerDhikrCompleted
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
              size: 20,
              color: daily.postPrayerDhikrCompleted
                  ? (isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestPrimary)
                  : (isDark ? AppColors.darkTextMuted : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'أذكار بعد الصلاة (الباب ٢٥)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                      decoration: daily.postPrayerDhikrCompleted
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    daily.postPrayerDhikrCompleted
                        ? 'مسجلة بحمد الله'
                        : 'اضغط لفتح أذكار بعد الصلاة من حصن المسلم',
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
            const Icon(Icons.chevron_left, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyDuaTaskRow({
    required DailyProgress daily,
    required bool isDark,
    required BuildContext context,
  }) {
    final hasChosen = daily.dailyDuaItemId != null;
    final isDone = daily.dailyDuaCompleted;

    return InkWell(
      key: const Key('home_task_daily_dua'),
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const DailyDuaScreen()),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: isDone
                  ? (isDark
                        ? AppColors.darkGoldAccent
                        : AppColors.forestPrimary)
                  : (isDark ? AppColors.darkTextMuted : AppColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'دعاء اليوم',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    hasChosen
                        ? (isDone
                              ? 'ذكر #${daily.dailyDuaItemId} (مكتمل بحمد الله)'
                              : 'ذكر #${daily.dailyDuaItemId} (بانتظار القراءة)')
                        : 'اضغط لاختيار وقراءة دعاء من الأدعية الموثقة',
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
            const Icon(Icons.chevron_left, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayersSummaryRow({
    required PrayerDay prayerDay,
    required PrayerEvent? nextPrayer,
    required String timezone,
    required bool isDark,
  }) {
    final prayers = [
      (PrayerType.fajr, prayerDay.fajr),
      (PrayerType.dhuhr, prayerDay.dhuhr),
      (PrayerType.asr, prayerDay.asr),
      (PrayerType.maghrib, prayerDay.maghrib),
      (PrayerType.isha, prayerDay.isha),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : const Color(0xFFE5EBE6),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final textScale = MediaQuery.textScalerOf(context).scale(1.0);
          final estimatedItemWidth = 68.0 * textScale;
          final totalNeeded = estimatedItemWidth * prayers.length;
          final shouldWrap =
              constraints.maxWidth < totalNeeded || textScale > 1.15;

          Widget buildItem((PrayerType, PrayerEvent?) p) {
            final isNext =
                p.$2 != null &&
                nextPrayer != null &&
                p.$2!.utcDateTime.isAtSameMomentAs(nextPrayer.utcDateTime);
            final time = p.$2 != null
                ? formatPrayerTime(p.$2!, timezone, use12Hour: false)
                : '--:--';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: isNext
                    ? (isDark
                          ? AppColors.darkForestPrimary.withAlpha(50)
                          : const Color(0xFFE7F0E8))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.$1.arabicName,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                      color: isNext
                          ? (isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary)
                          : (isDark
                                ? AppColors.darkTextMuted
                                : AppColors.textMuted),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isNext
                          ? (isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.forestPrimary)
                          : (isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textDark),
                    ),
                  ),
                ],
              ),
            );
          }

          if (shouldWrap) {
            return SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceAround,
                runAlignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: prayers.map(buildItem).toList(),
              ),
            );
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: prayers.map(buildItem).toList(),
          );
        },
      ),
    );
  }
}
