import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../hisn/domain/models/hisn_daily_catalog.dart';
import '../../hisn/presentation/daily/daily_dua_screen.dart';
import '../../hisn/presentation/daily/daily_hisn_checklist_screen.dart';
import '../../hisn/presentation/daily/post_prayer_daily_screen.dart';
import '../../more/presentation/duas_screen.dart';
import '../../more/presentation/favorites_screen.dart';
import '../../more/presentation/hadith_screen.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import '../../reminders/presentation/reminders_screen.dart';
import 'dhikr_screen.dart';

/// "الأذكار" tab: one organized place for daily adhkar, the tasbih counter,
/// and the supplication / hadith libraries.
class AdhkarHubScreen extends ConsumerWidget {
  const AdhkarHubScreen({super.key});

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = ref.watch(activeDateBucketProvider);
    final daily = ref.watch(dailyProgressControllerProvider(today)).valueOrNull;
    final hour = DateTime.now().hour;
    final morningFirst = hour >= 3 && hour < 15;

    final morning = _DailyCardData(
      key: const ValueKey('adhkar_hub_morning'),
      icon: Icons.wb_sunny_rounded,
      title: 'أذكار الصباح',
      subtitle: '٢٢ ذكراً',
      done: daily?.morningDhikrCompleted ?? false,
      onTap: () => _push(
        context,
        const DailyHisnChecklistScreen(period: DhikrPeriod.morning),
      ),
    );
    final evening = _DailyCardData(
      key: const ValueKey('adhkar_hub_evening'),
      icon: Icons.nights_stay_rounded,
      title: 'أذكار المساء',
      subtitle: '٢٠ ذكراً',
      done: daily?.eveningDhikrCompleted ?? false,
      onTap: () => _push(
        context,
        const DailyHisnChecklistScreen(period: DhikrPeriod.evening),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('الأذكار والأدعية')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _SectionTitle('أذكار اليوم'),
            Row(
              children: [
                Expanded(child: _DailyCard(data: morningFirst ? morning : evening)),
                const SizedBox(width: 12),
                Expanded(child: _DailyCard(data: morningFirst ? evening : morning)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DailyCard(
                    data: _DailyCardData(
                      key: const ValueKey('adhkar_hub_post_prayer'),
                      icon: Icons.handshake_outlined,
                      title: 'بعد الصلاة',
                      subtitle: 'أذكار ختام الصلاة',
                      done: daily?.postPrayerDhikrCompleted ?? false,
                      onTap: () => _push(context, const PostPrayerDailyScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DailyCard(
                    data: _DailyCardData(
                      key: const ValueKey('adhkar_hub_daily_dua'),
                      icon: Icons.volunteer_activism_outlined,
                      title: 'دعاء اليوم',
                      subtitle: 'من حصن المسلم',
                      done: daily?.dailyDuaCompleted ?? false,
                      onTap: () => _push(context, const DailyDuaScreen()),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tasbih counter banner
            _TasbihBanner(
              isDark: isDark,
              onTap: () => _push(context, const DhikrScreen()),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                key: const ValueKey('adhkar_hub_reminders'),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('تذكيرات الذكر'),
                subtitle: const Text(
                  'سبحان الله، الله أكبر… تظهر على الشاشة بدون إنترنت',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => _push(context, const RemindersScreen()),
              ),
            ),
            const SizedBox(height: 20),

            const _SectionTitle('المكتبة'),
            Card(
              child: Column(
                children: [
                  _LibraryTile(
                    icon: Icons.shield_moon_outlined,
                    title: 'حصن المسلم',
                    subtitle: 'كل الأبواب: النوم، السفر، الطعام، الكرب…',
                    onTap: () => _push(context, const DuasScreen()),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _LibraryTile(
                    icon: Icons.format_quote_rounded,
                    title: 'الأحاديث النبوية',
                    subtitle: 'أحاديث صحيحة مع الشرح والفوائد',
                    onTap: () => _push(context, const HadithScreen()),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _LibraryTile(
                    icon: Icons.favorite_border_rounded,
                    title: 'المفضلة',
                    subtitle: 'الأذكار والأدعية والعلامات المحفوظة',
                    onTap: () => _push(context, const FavoritesScreen()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _DailyCardData {
  final Key key;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool done;
  final VoidCallback onTap;

  const _DailyCardData({
    required this.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.onTap,
  });
}

class _DailyCard extends StatelessWidget {
  final _DailyCardData data;
  const _DailyCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? AppColors.darkForestPrimary : AppColors.forestPrimary;
    final gold = isDark ? AppColors.darkGoldAccent : AppColors.goldDark;

    return Material(
      key: data.key,
      color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: data.done
              ? accent.withAlpha(140)
              : (isDark ? AppColors.darkCardBorder : AppColors.cardBorder),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: data.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkSurfaceHigh
                          : AppColors.goldSoftTint,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(data.icon, size: 20, color: gold),
                  ),
                  const Spacer(),
                  if (data.done)
                    Icon(Icons.check_circle_rounded, size: 20, color: accent),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                data.done ? 'تم اليوم ✓' : data.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TasbihBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _TasbihBanner({required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const ValueKey('adhkar_hub_tasbih'),
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? AppColors.heroGradientDark
                : AppColors.heroGradientLight,
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(28),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.radio_button_checked_rounded,
                    color: AppColors.goldAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'المسبحة الإلكترونية',
                        style: TextStyle(
                          fontFamily: AppTheme.uiFont,
                          fontFamilyFallback: AppTheme.uiFontFallback,
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'عدّاد تسبيح بأهداف ٣٣ و١٠٠ مع حفظ الجلسات',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_left_rounded, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LibraryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
    );
  }
}
