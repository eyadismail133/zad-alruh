import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../more/presentation/settings_screen.dart';
import '../../prayer/domain/models/prayer_event.dart';
import 'controllers/prayers_controller.dart';

class PrayersScreen extends ConsumerWidget {
  const PrayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerStateAsync = ref.watch(prayerTimesControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقيت الصلاة'),
      ),
      body: SafeArea(
        child: prayerStateAsync.when(
          data: (state) {
            if (state.isUnsupported) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCityCard(
                      context: context,
                      cityName: state.unsupportedCity ?? 'غير محدد',
                      timezone: state.unsupportedTimezone ?? 'غير محدد',
                      isDark: isDark,
                    ),
                    const SizedBox(height: 24),
                    EmptyStateView(
                      icon: Icons.location_off_outlined,
                      statusTag: 'مدينة غير مدعومة',
                      title: 'المدينة المحددة غير مدعومة حالياً',
                      message:
                          'المدينة المحددة «${state.unsupportedCity}» بمنطقتها الزمنية «${state.unsupportedTimezone}» غير متطابقة مع المدن الثماني المعتمدة حالياً في حساب المواقيت الفلكية الدقيقة. يرجى اختيار إحدى المدن المدعومة من شاشة الإعدادات.',
                      action: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark
                              ? AppColors.darkForestPrimary
                              : AppColors.forestPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text(
                          'فتح الإعدادات لاختيار مدينة مدعومة',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final city = state.city!;
            final prayerDay = state.prayerDay;
            final isUnresolved = state.isUnresolved;
            final isEstimated = state.isEstimated;
            final nextPrayer = state.nextPrayer;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // City and Timezone Header
                  _buildCityCard(
                    context: context,
                    cityName: city.arabicName ?? city.name,
                    timezone: city.timezone,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 14),

                  // High-Latitude Estimation Notice Banner
                  if (isEstimated && !isUnresolved) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.withAlpha(40)
                            : AppColors.goldSoftTint,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.goldDark,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.goldDark,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'مواقيت تقديرية (قواعد خطوط العرض العليا)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? AppColors.darkGoldAccent
                                        : AppColors.goldDark,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  state.estimationReason ??
                                      'تم تطبيق قواعد التقدير لشفق الفجر والعشاء.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    height: 1.4,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.textBody,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Unresolved Polar Day Notice (No invented numbers)
                  if (isUnresolved) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.withAlpha(40)
                            : AppColors.goldSoftTint,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? AppColors.darkGoldAccent
                              : AppColors.goldDark,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 36,
                            color: isDark
                                ? AppColors.darkGoldAccent
                                : AppColors.goldDark,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'مواقيت غير محددة فلكياً لهذا اليوم',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.unresolvedReason ??
                                'تعذر تحديد المواقيت الفلكية لتعذر غياب أو شروق الشمس في هذا التاريخ والمنطقة الجغرافية (يوم قطبي). عملاً بالأمانة الدينية، لا يتم اختراع أوقات وهمية.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.5,
                              color: isDark
                                  ? AppColors.darkTextMuted
                                  : AppColors.textBody,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ] else ...[
                    // Next Prayer Hero Card
                    _buildNextPrayerHero(
                      context: context,
                      state: state,
                      timezone: city.timezone,
                      isDark: isDark,
                    ),

                    const SizedBox(height: 16),

                    // Daily Prayers List (5 Prayers + Sunrise)
                    if (prayerDay != null)
                      _buildPrayerTimesCard(
                        prayerDay: prayerDay,
                        nextPrayer: nextPrayer,
                        timezone: city.timezone,
                        isDark: isDark,
                      ),

                    const SizedBox(height: 16),
                  ],

                  // Context & Meta Details Card
                  _buildContextDetailsCard(
                    state: state,
                    timezone: city.timezone,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (_, __) => RetryableErrorView(
            message:
                'تعذر تحميل مواقيت الصلاة. يرجى التحقق من إعدادات المدينة أو إعادة المحاولة.',
            onRetry: () =>
                ref.read(prayerTimesControllerProvider.notifier).retry(),
          ),
        ),
      ),
    );
  }

  Widget _buildCityCard({
    required BuildContext context,
    required String cityName,
    required String timezone,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 320;
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isNarrow ? constraints.maxWidth : constraints.maxWidth - 90,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 20,
                      color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'المدينة المحددة',
                            style: TextStyle(
                              fontSize: 10,
                              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$cityName · $timezone',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.tune, size: 15),
                label: const Text(
                  'تغيير',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNextPrayerHero({
    required BuildContext context,
    required PrayerState state,
    required String timezone,
    required bool isDark,
  }) {
    final nextPrayer = state.nextPrayer;
    final prayerName = nextPrayer?.type.arabicName ?? 'المواقيت';
    final timeFormatted = nextPrayer != null
        ? formatPrayerTime(nextPrayer, timezone)
        : '--:--';
    final countdown = state.countdownString;

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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, heroConstraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: heroConstraints.maxWidth),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(30),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 13,
                            color: isDark ? AppColors.darkGoldAccent : AppColors.goldAccent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'الصلاة القادمة · $prayerName',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkGoldAccent : AppColors.goldAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    timeFormatted,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  countdown,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'متبقي على أذان $prayerName',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: heroConstraints.maxWidth),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_off_outlined,
                        size: 12,
                        color: Colors.white70,
                      ),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'التنبيهات التلقائية غير مفعّلة حالياً',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPrayerTimesCard({
    required dynamic prayerDay,
    required PrayerEvent? nextPrayer,
    required String timezone,
    required bool isDark,
  }) {
    final rows = [
      (PrayerType.fajr, prayerDay.fajr as PrayerEvent?, Icons.nightlight_round),
      (PrayerType.sunrise, prayerDay.sunrise as PrayerEvent?, Icons.wb_sunny_outlined),
      (PrayerType.dhuhr, prayerDay.dhuhr as PrayerEvent?, Icons.wb_sunny),
      (PrayerType.asr, prayerDay.asr as PrayerEvent?, Icons.filter_drama_outlined),
      (PrayerType.maghrib, prayerDay.maghrib as PrayerEvent?, Icons.wb_twilight),
      (PrayerType.isha, prayerDay.isha as PrayerEvent?, Icons.bedtime_outlined),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _buildPrayerRow(
              type: rows[i].$1,
              event: rows[i].$2,
              icon: rows[i].$3,
              isNext: rows[i].$2 != null &&
                  nextPrayer != null &&
                  rows[i].$2!.utcDateTime.isAtSameMomentAs(nextPrayer.utcDateTime),
              timezone: timezone,
              isDark: isDark,
            ),
            if (i < rows.length - 1)
              Divider(
                height: 1,
                thickness: 0.7,
                color: isDark ? AppColors.darkCardBorder : const Color(0xFFEDF0ED),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrayerRow({
    required PrayerType type,
    required PrayerEvent? event,
    required IconData icon,
    required bool isNext,
    required String timezone,
    required bool isDark,
  }) {
    final isSunrise = type == PrayerType.sunrise;
    final timeStr = event != null ? formatPrayerTime(event, timezone) : '--:--';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isNext
            ? (isDark
                ? AppColors.darkForestPrimary.withAlpha(45)
                : AppColors.forestSoftTint)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isNext
            ? Border.all(
                color: isDark
                    ? AppColors.darkForestPrimary.withAlpha(80)
                    : const Color(0xFFD7E7D9),
                width: 1,
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 16,
                      color: isNext
                          ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                          : (isSunrise
                              ? (isDark ? Colors.amber.shade300 : AppColors.goldDark)
                              : (isDark ? AppColors.darkTextMuted : AppColors.textMuted)),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        type.arabicName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isNext ? FontWeight.bold : FontWeight.w500,
                          color: isNext
                              ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                              : (isDark ? AppColors.darkTextPrimary : AppColors.textDark),
                        ),
                      ),
                    ),
                  ],
                ),
                if (isSunrise)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.amber.withAlpha(40) : AppColors.goldSoftTint,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'شروق الشمس',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
                      ),
                    ),
                  ),
                if (isNext)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkGoldAccent.withAlpha(40)
                          : AppColors.goldPill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'الصلاة القادمة',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isNext
                  ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                  : (isDark ? AppColors.darkTextPrimary : AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextDetailsCard({
    required PrayerState state,
    required String timezone,
    required bool isDark,
  }) {
    final y = state.civilDate.year;
    final m = state.civilDate.month.toString().padLeft(2, '0');
    final d = state.civilDate.day.toString().padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.all(14),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'التاريخ المدني المعتمد في المدينة: $y-$m-$d',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.public_outlined,
                size: 14,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'المنطقة الزمنية: $timezone',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.tune_outlined,
                size: 14,
                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'طريقة الحساب: ${state.calculationMethodArabicName} (افتراضي المدينة)',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          Text(
            'حساب فلكي دقيق بدون إنترنت. قد تختلف الأوقات بدقائق يسيرة عن الجداول المحلية لبعض المساجد. المراجعة الفقهية المستقلة قيد الاستكمال.',
            style: TextStyle(
              fontSize: 10,
              height: 1.5,
              color: isDark ? AppColors.darkTextMuted : AppColors.textSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
