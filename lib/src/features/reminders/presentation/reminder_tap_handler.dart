import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../hisn/domain/models/hisn_daily_catalog.dart';
import '../../hisn/presentation/daily/daily_hisn_checklist_screen.dart';
import '../../more/presentation/duas_screen.dart';
import '../../quran/presentation/utils/quran_ui_utils.dart';
import '../data/reminder_service.dart';
import '../domain/reminder_settings.dart';

/// Opens the right screen for a tapped reminder payload.
void handleReminderPayload(String payload) {
  final nav = appNavigatorKey.currentState;
  if (nav == null) return;
  Widget? screen;
  if (payload.startsWith('dhikr:')) {
    final phrase = DhikrPhrase.byId(payload.substring(6)) ?? DhikrPhrase.all.first;
    screen = DhikrMomentScreen(phrase: phrase);
  } else if (payload == 'open:morning') {
    screen = const DailyHisnChecklistScreen(period: DhikrPeriod.morning);
  } else if (payload == 'open:evening') {
    screen = const DailyHisnChecklistScreen(period: DhikrPeriod.evening);
  } else if (payload == 'open:hisn') {
    screen = const DuasScreen();
  }
  if (screen != null) {
    nav.push(MaterialPageRoute<void>(builder: (_) => screen!));
  }
}

/// Full-screen dhikr card opened from a reminder: the phrase in large type
/// with a small tap counter.
class DhikrMomentScreen extends StatefulWidget {
  final DhikrPhrase phrase;
  const DhikrMomentScreen({super.key, required this.phrase});

  @override
  State<DhikrMomentScreen> createState() => _DhikrMomentScreenState();
}

class _DhikrMomentScreenState extends State<DhikrMomentScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? AppColors.heroGradientDark
                : AppColors.heroGradientLight,
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: AlignmentDirectional.topStart,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      widget.phrase.text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        color: Colors.white,
                        fontSize: 34,
                        height: 1.7,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _count++),
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withAlpha(30),
                          border: Border.all(
                            color: AppColors.goldAccent,
                            width: 3,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          QuranUiUtils.toArabicDigits(_count),
                          style: const TextStyle(
                            fontFamily: AppTheme.uiFont,
                            fontFamilyFallback: AppTheme.uiFontFallback,
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'اضغط للتسبيح',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
