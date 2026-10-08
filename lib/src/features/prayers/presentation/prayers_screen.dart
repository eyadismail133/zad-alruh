import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../more/presentation/settings_screen.dart';
import '../../prayer/domain/models/adhan_voice.dart';
import '../../prayer/domain/models/prayer_event.dart';
import '../../prayer/presentation/controllers/prayer_notification_controller.dart';
import '../../progress/data/models/user_preferences.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import 'controllers/adhan_audio_controller.dart';
import 'controllers/prayers_controller.dart';
import 'widgets/city_search_picker_dialog.dart';

class PrayersScreen extends ConsumerStatefulWidget {
  const PrayersScreen({super.key});

  @override
  ConsumerState<PrayersScreen> createState() => _PrayersScreenState();
}

class _PrayersScreenState extends ConsumerState<PrayersScreen> {
  late AdhanAudioController _audioController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _audioController = ref.read(adhanAudioControllerProvider.notifier);
  }

  @override
  void dispose() {
    _audioController.stop().catchError((_) {});
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final prayerStateAsync = ref.watch(prayerTimesControllerProvider);
    final prefs = ref.watch(preferencesControllerProvider).valueOrNull;
    final audioState = ref.watch(adhanAudioControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقيت الصلاة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.volume_up_outlined),
            tooltip: 'أصوات الأذان وتجربة الاستماع',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
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
                      cityId: null,
                    ),
                    const SizedBox(height: 24),
                    EmptyStateView(
                      icon: Icons.location_off_outlined,
                      statusTag: 'مدينة غير محددة',
                      title: 'المدينة المحددة غير مطابقة لقاعدة البيانات',
                      message:
                          'المدينة المحددة «${state.unsupportedCity}» بمنطقتها الزمنية «${state.unsupportedTimezone}» غير متطابقة مع قاعدة بيانات المدن المعتمدة. يرجى اختيار مدينة من قاعدة البيانات.',
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
                        onPressed: () async {
                          final picked = await CitySearchPickerDialog.show(context);
                          if (picked != null && context.mounted) {
                            await ref
                                .read(preferencesControllerProvider.notifier)
                                .setSelectedCity(picked);
                          }
                        },
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text(
                          'اختيار مدينة من قاعدة البيانات',
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
                    cityId: city.id,
                  ),

                  const SizedBox(height: 8),

                  // Calculation Method Banner
                  _buildCalculationMethodCard(
                    context: context,
                    state: state,
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

                  // Adhan Audio Voice & Preview Info Card
                  _buildAdhanAudioCard(
                    context: context,
                    generalVoiceId: prefs?.generalAdhanVoice ?? 'adam',
                    fajrVoiceId: prefs?.fajrAdhanVoice ?? 'malmo_fajr',
                    audioState: audioState,
                    isDark: isDark,
                    preferences: prefs,
                  ),

                  const SizedBox(height: 16),

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
    int? cityId,
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
                onPressed: () async {
                  final picked = await CitySearchPickerDialog.show(
                    context,
                    currentCityId: cityId,
                  );
                  if (picked != null && context.mounted) {
                    try {
                      await ref
                          .read(preferencesControllerProvider.notifier)
                          .setSelectedCity(picked);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: Colors.red.shade800,
                            content: const Text(
                              'تعذر حفظ المدينة المختارة. يرجى إعادة المحاولة.',
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.search, size: 15),
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

  Widget _buildCalculationMethodCard({
    required BuildContext context,
    required PrayerState state,
    required bool isDark,
  }) {
    final effective = state.effectiveSettings;
    final methodName = state.calculationMethodArabicName;
    final isCustomOverride = effective != null &&
        effective.settings.calculationMethod !=
            effective.city.defaultCalculationMethod;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface.withAlpha(120)
            : AppColors.forestSoftTint.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.tune,
            size: 16,
            color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$methodName${isCustomOverride ? " (تخصيص يدوي)" : " (افتراضي المدينة)"}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextMuted : AppColors.forestMedium,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsScreen(),
                ),
              );
            },
            child: Text(
              'ضبط',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color:
                    isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
              ),
            ),
          ),
        ],
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
              Builder(
                builder: (context) {
                  final notifState = ref.watch(prayerNotificationStateProvider);
                  final IconData notifIcon;
                  final Color notifColor;
                  final String notifText;

                  switch (notifState.status) {
                    case PrayerNotificationStatus.activeExact:
                      notifIcon = Icons.notifications_active_outlined;
                      notifColor = Colors.white;
                      final countText = notifState.acceptedScheduledCount != null
                          ? '${notifState.acceptedScheduledCount} موعد مجدول'
                          : '${notifState.plannedFutureEventsCount} موعد مخطط';
                      notifText =
                          'تنبيه الأذان الدقيق مفعّل ($countText)';
                      break;
                    case PrayerNotificationStatus.activeInexact:
                      notifIcon = Icons.notifications_outlined;
                      notifColor = isDark
                          ? AppColors.darkGoldAccent
                          : AppColors.goldAccent;
                      final countText = notifState.acceptedScheduledCount != null
                          ? ' (${notifState.acceptedScheduledCount} موعد تقريبي)'
                          : '';
                      notifText = 'تنبيه الأذان مفعّل بتوقيت تقريبي$countText';
                      break;
                    case PrayerNotificationStatus.recoveryRequired:
                      notifIcon = Icons.warning_amber_rounded;
                      notifColor = Colors.amber.shade300;
                      notifText = 'تنبيهات الأذان تتطلب التأكيد في الإعدادات';
                      break;
                    case PrayerNotificationStatus.permissionDenied:
                      notifIcon = Icons.notifications_paused_outlined;
                      notifColor = Colors.white70;
                      notifText = 'إذن الإشعارات متوقف في النظام';
                      break;
                    default:
                      notifIcon = Icons.notifications_off_outlined;
                      notifColor = Colors.white70;
                      notifText = 'التنبيهات التلقائية غير مفعّلة حالياً';
                      break;
                  }

                  return ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: heroConstraints.maxWidth),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            notifIcon,
                            size: 12,
                            color: notifColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              notifText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 10,
                                color: notifColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
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

  Widget _buildAdhanAudioCard({
    required BuildContext context,
    required String generalVoiceId,
    required String fajrVoiceId,
    required AdhanAudioState audioState,
    required bool isDark,
    UserPreferences? preferences,
  }) {
    final generalVoice = AdhanVoice.findById(generalVoiceId) ?? AdhanVoice.adam;
    final fajrVoice = AdhanVoice.findById(fajrVoiceId) ?? AdhanVoice.malmoFajr;

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
            children: [
              Icon(
                Icons.volume_up_outlined,
                size: 18,
                color:
                    isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تسجيلات الأذان المتوفرة',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color:
                        isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                  ),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.tune, size: 14),
                label: const Text(
                  'تغيير الأصوات',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (preferences?.voiceRecoveryNotice == true) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber.shade900.withAlpha(50)
                    : const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : Colors.amber.shade700,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: isDark
                        ? AppColors.darkGoldAccent
                        : Colors.amber.shade800,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'تمت استعادة أصوات الأذان الافتراضية لعدم صلاحية الاختيار المحفوظ سابقاً.',
                      style: TextStyle(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Text(
            '• الصلوات العامة: ${generalVoice.nameAr} (${generalVoice.title})',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '• أذان الفجر: ${fajrVoice.nameAr} (${fajrVoice.title})',
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
            ),
          ),
          if (audioState.status == AdhanAudioStatus.error &&
              audioState.errorMessage != null) ...[
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.shade900.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade700),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      audioState.errorMessage!,
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 14),
                    onPressed: () => _audioController.stop().catchError((_) {}),
                  ),
                ],
              ),
            ),
          ],
          if (audioState.isPlaying || audioState.isLoading) ...[
            const Divider(height: 16),
            Row(
              children: [
                Icon(
                  audioState.isLoading
                      ? Icons.hourglass_top_rounded
                      : Icons.graphic_eq_rounded,
                  size: 18,
                  color: isDark
                      ? AppColors.darkGoldAccent
                      : AppColors.forestPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'جاري الاستماع: ${AdhanVoice.findById(audioState.activeVoiceId ?? '')?.nameAr ?? ''} (${_formatDuration(audioState.position)} / ${_formatDuration(audioState.totalDuration)})',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.textDark,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                     backgroundColor: Colors.red.shade700,
                     foregroundColor: Colors.white,
                     padding:
                         const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('إيقاف', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    _audioController.stop().catchError((_) {});
                  },
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text(
                    'معاينة أذان الصلوات العامة',
                    style: TextStyle(fontSize: 10.5),
                  ),
                  onPressed: () {
                    _audioController.playVoice(generalVoice);
                  },
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text(
                    'معاينة أذان الفجر',
                    style: TextStyle(fontSize: 10.5),
                  ),
                  onPressed: () {
                    _audioController.playVoice(fajrVoice);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
