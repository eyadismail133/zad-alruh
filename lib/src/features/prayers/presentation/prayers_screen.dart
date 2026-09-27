import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../more/presentation/settings_screen.dart';
import '../../progress/presentation/controllers/progress_controller.dart';

class PrayersScreen extends ConsumerWidget {
  const PrayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقيت الصلاة'),
      ),
      body: SafeArea(
        child: prefsAsync.when(
          data: (prefs) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // City and Timezone Display
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
                      ),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المدينة المحددة',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${prefs.selectedCity} · ${prefs.selectedTimezone}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const SettingsScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('تغيير', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  EmptyStateView(
                    icon: Icons.access_time_filled,
                    statusTag: 'قيد الربط والتطوير',
                    title: 'حساب المواقيت قيد الربط الفلكي',
                    message:
                        'تطبيق زاد الروح يعتمد حسابات الأذان الفلكية الدقيقة دون إنترنت (Offline Prayer Calculator). لا يتم عرض مواعيد عشوائية أو أوقات وهمية قبل اكتمال ربط محرك الحسابات وجدولة الإشعارات التلقائية.',
                    action: OutlinedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      child: const Text('إعدادات الموقع والتنبيهات'),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => RetryableErrorView(
            message: err.toString(),
            onRetry: () => ref.read(preferencesControllerProvider.notifier).retry(),
          ),
        ),
      ),
    );
  }
}
