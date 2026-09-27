import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../progress/data/models/user_preferences.dart';
import '../../progress/presentation/controllers/progress_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<Map<String, String>> supportedCities = [
    {'name': 'القاهرة', 'tz': 'Africa/Cairo'},
    {'name': 'مكة المكرمة', 'tz': 'Asia/Riyadh'},
    {'name': 'المدينة المنورة', 'tz': 'Asia/Riyadh'},
    {'name': 'الرياض', 'tz': 'Asia/Riyadh'},
    {'name': 'دبي', 'tz': 'Asia/Dubai'},
    {'name': 'القدس الشريف', 'tz': 'Asia/Jerusalem'},
    {'name': 'إسطنبول', 'tz': 'Europe/Istanbul'},
    {'name': 'لندن', 'tz': 'Europe/London'},
  ];

  Future<void> _updateDarkMode(BuildContext context, WidgetRef ref, String mode) async {
    try {
      await ref.read(preferencesControllerProvider.notifier).setDarkMode(mode);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر حفظ إعداد المظهر: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _updateDarkMode(context, ref, mode),
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateTextScale(BuildContext context, WidgetRef ref, double scale) async {
    try {
      await ref.read(preferencesControllerProvider.notifier).setTextScale(scale);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر حفظ حجم الخط: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _updateTextScale(context, ref, scale),
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateCity(BuildContext context, WidgetRef ref, String city, String tz) async {
    try {
      await ref.read(preferencesControllerProvider.notifier).setCity(city, tz);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر حفظ المدينة والمنطقة الزمنية: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _updateCity(context, ref, city, tz),
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateQuranGoal(BuildContext context, WidgetRef ref, UserPreferences current, int goal) async {
    try {
      await ref.read(preferencesControllerProvider.notifier).updatePreferences(
            current.copyWith(quranDefaultGoal: goal),
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: Text('تعذر حفظ الهدف اليومي: $e'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () => _updateQuranGoal(context, ref, current, goal),
            ),
          ),
        );
      }
    }
  }

  void _showResetConfirmDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('تأكيد إعادة ضبط البيانات المحلية'),
          content: const Text(
            'سيؤدي هذا الإجراء إلى حذف كافة العلامات المرجعية، والمفضلة، وسجلات الأذكار، وتقدم القراءة، واستعادة الإعدادات الافتراضية. لا يمكن التراجع عن هذا الإجراء.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(preferencesControllerProvider.notifier).resetAllState();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت إعادة ضبط كافة البيانات بنجاح')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade800,
                        content: Text('فشل إعادة ضبط البيانات: $e'),
                      ),
                    );
                  }
                }
              },
              child: const Text('نعم، احذف البيانات'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(preferencesControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إعدادات التطبيق'),
      ),
      body: SafeArea(
        child: prefsAsync.when(
          data: (prefs) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // Appearance Section
                _buildSectionHeader('المظهر والقراءة', isDark),
                Card(
                  child: Column(
                    children: [
                      _buildDropdownSetting<String>(
                        title: 'وضع المظهر',
                        subtitle: prefs.darkMode == 'dark'
                            ? 'الوضع الداكن'
                            : prefs.darkMode == 'light'
                                ? 'الوضع الفاتح'
                                : 'تلقائي حسب نظام الجهاز',
                        value: prefs.darkMode,
                        items: const [
                          DropdownMenuItem(value: 'system', child: Text('تلقائي')),
                          DropdownMenuItem(value: 'light', child: Text('فاتح')),
                          DropdownMenuItem(value: 'dark', child: Text('داكن')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            _updateDarkMode(context, ref, val);
                          }
                        },
                      ),
                      const Divider(height: 1),
                      _buildDropdownSetting<double>(
                        title: 'حجم الخط في الواجهة',
                        subtitle: 'المقياس الحالي: ${prefs.textScale.toStringAsFixed(1)}x',
                        value: prefs.textScale,
                        items: const [
                          DropdownMenuItem(value: 0.9, child: Text('صغير (0.9x)')),
                          DropdownMenuItem(value: 1.0, child: Text('قياسي (1.0x)')),
                          DropdownMenuItem(value: 1.2, child: Text('متوسط (1.2x)')),
                          DropdownMenuItem(value: 1.4, child: Text('كبير (1.4x)')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            _updateTextScale(context, ref, val);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Location & Prayer Timezone
                _buildSectionHeader('الموقع ومواقيت الصلاة', isDark),
                Card(
                  child: Column(
                    children: [
                      _buildDropdownSetting<String>(
                        title: 'المدينة والمنطقة الزمنية',
                        subtitle: '${prefs.selectedCity} (${prefs.selectedTimezone})',
                        value: prefs.selectedCity,
                        items: supportedCities.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['name']!,
                            child: Text(c['name']!),
                          );
                        }).toList(),
                        onChanged: (city) {
                          if (city != null) {
                            final item = supportedCities.firstWhere((c) => c['name'] == city);
                            _updateCity(context, ref, city, item['tz']!);
                          }
                        },
                      ),
                      const Divider(height: 1),
                      const SwitchListTile(
                        title: Text('تنبيهات الأذان', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text('التنبيهات غير متوفرة حالياً لحين اكتمال مجدول الصلاة الفلكي', style: TextStyle(fontSize: 11)),
                        value: false,
                        onChanged: null,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Daily Quran Goal
                _buildSectionHeader('وِرد القرآن اليومي', isDark),
                Card(
                  child: _buildDropdownSetting<int>(
                    title: 'الهدف اليومي الافتراضي',
                    subtitle: '${prefs.quranDefaultGoal} صفحات يومياً',
                    value: prefs.quranDefaultGoal,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('صفحة واحدة')),
                      DropdownMenuItem(value: 2, child: Text('صفحتان')),
                      DropdownMenuItem(value: 4, child: Text('٤ صفحات')),
                      DropdownMenuItem(value: 8, child: Text('٨ صفحات')),
                      DropdownMenuItem(value: 10, child: Text('١٠ صفحات')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        _updateQuranGoal(context, ref, prefs, val);
                      }
                    },
                  ),
                ),

                const SizedBox(height: 24),

                // Danger Zone: Reset
                _buildSectionHeader('البيانات المحلية والخصوصية', isDark),
                Card(
                  color: isDark ? Colors.red.shade900.withAlpha(50) : const Color(0xFFFDE8E8),
                  child: ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text(
                      'إعادة ضبط البيانات المحلية',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    subtitle: const Text(
                      'حذف جميع السجلات والعلامات واسترجاع الحالة الابتدائية',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () => _showResetConfirmDialog(context, ref),
                  ),
                ),
                const SizedBox(height: 24),
              ],
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

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, right: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
        ),
      ),
    );
  }

  Widget _buildDropdownSetting<T>({
    required String title,
    required String subtitle,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
