import 'package:flutter/material.dart';
import 'package:hijri/hijri_calendar.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../quran/presentation/utils/quran_ui_utils.dart';

/// Arabic Hijri month names (Umm al-Qura order).
const List<String> kHijriMonthNamesAr = [
  'محرم',
  'صفر',
  'ربيع الأول',
  'ربيع الآخر',
  'جمادى الأولى',
  'جمادى الآخرة',
  'رجب',
  'شعبان',
  'رمضان',
  'شوال',
  'ذو القعدة',
  'ذو الحجة',
];

/// Formats today's Hijri date, applying the user's manual day adjustment.
/// Returns null when the date is outside the supported calendar range.
String? formatHijriToday(DateTime now, int dayAdjustment) {
  try {
    final h = HijriCalendar.fromDate(now.add(Duration(days: dayAdjustment)));
    // Typed as nullable so this compiles whether the package exposes
    // nullable or non-nullable fields.
    final int? hDay = h.hDay;
    final int? hMonth = h.hMonth;
    final int? hYear = h.hYear;
    if (hDay == null || hMonth == null || hYear == null) return null;
    if (hMonth < 1 || hMonth > 12) return null;
    final day = QuranUiUtils.toArabicDigits(hDay);
    final year = QuranUiUtils.toArabicDigits(hYear);
    return '$day ${kHijriMonthNamesAr[hMonth - 1]} $year هـ';
  } catch (_) {
    return null;
  }
}

String greetingFor(DateTime now) {
  final hour = now.hour;
  if (hour >= 4 && hour < 12) return 'صباح الخير';
  if (hour >= 12 && hour < 17) return 'طاب يومك';
  return 'مساء الخير';
}

/// Top header of the home screen: logo, greeting and Hijri date.
class HomeHeader extends StatelessWidget {
  final int hijriDayAdjustment;
  final DateTime? now;

  const HomeHeader({super.key, this.hijriDayAdjustment = 0, this.now});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = now ?? DateTime.now();
    final hijri = formatHijriToday(current, hijriDayAdjustment);

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceHigh : AppColors.forestSoftTint,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
            border: Border.all(
              color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
            ),
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
                greetingFor(current),
                style: TextStyle(
                  fontFamily: AppTheme.uiFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                ),
              ),
              Text(
                'زادُ الروح',
                style: TextStyle(
                  fontFamily: AppTheme.uiFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
        if (hijri != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceHigh
                    : AppColors.goldSoftTint,
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkCardBorder
                      : AppColors.goldPill,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.nightlight_round,
                    size: 14,
                    color:
                        isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hijri,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.uiFont,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
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
        ],
      ],
    );
  }
}

/// A row of round shortcut buttons (Quran, Prayers, Adhkar, Hadith).
class HomeQuickActions extends StatelessWidget {
  final List<HomeQuickAction> actions;

  const HomeQuickActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final action in actions)
          Expanded(child: _QuickActionButton(action: action)),
      ],
    );
  }
}

class HomeQuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const HomeQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class _QuickActionButton extends StatelessWidget {
  final HomeQuickAction action;

  const _QuickActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                    color:
                        isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
                  ),
                ),
                child: Icon(
                  action.icon,
                  size: 24,
                  color: isDark
                      ? AppColors.darkForestPrimary
                      : AppColors.forestPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTheme.uiFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
