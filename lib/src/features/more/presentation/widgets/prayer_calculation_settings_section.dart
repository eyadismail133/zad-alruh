import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../prayer/domain/models/prayer_settings.dart';
import '../../../prayer/domain/models/selected_city.dart';
import '../../../prayers/presentation/controllers/prayers_controller.dart';
import '../../../prayers/presentation/widgets/city_search_picker_dialog.dart';
import '../../../progress/data/models/user_preferences.dart';
import '../../../progress/presentation/controllers/progress_controller.dart';

/// Comprehensive settings section for prayer calculation methods, policies, and minute offsets.
///
/// Features:
/// - Offline global city selector covering 34,149 GeoNames entries.
/// - City-default method with retention indication when manual override is active.
/// - Explicit "Reset to city default" button for calculation method override.
/// - Shafi and Hanafi Asr madhabs.
/// - High-latitude rules (middle of night, seventh of night, twilight angle).
/// - Polar day resolution (unresolved safe default vs nearest latitude / Aqrab Al-Balad).
/// - Umm Al-Qura Ramadan +30 min policy (evening of Ramadan, civil day, disabled).
/// - Hijri adjustment (±2 days).
/// - Manual minute offsets (±120 min) for all six events.
/// - Strict client-side boundary validation before persistence.
/// - Responsive down to 320x480 and textScale 2.0.
class PrayerCalculationSettingsSection extends ConsumerWidget {
  final UserPreferences prefs;
  final bool isDark;
  final bool disabled;

  const PrayerCalculationSettingsSection({
    super.key,
    required this.prefs,
    required this.isDark,
    this.disabled = false,
  });

  String _getMethodName(CalculationMethod method) {
    return getCalculationMethodArabicName(method);
  }

  void _showError(BuildContext context, String message, {VoidCallback? onRetry}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        content: Text(message),
        action: onRetry != null
            ? SnackBarAction(
                label: 'إعادة المحاولة',
                textColor: Colors.white,
                onPressed: onRetry,
              )
            : null,
      ),
    );
  }

  Future<void> _handleCitySelection(
    BuildContext context,
    WidgetRef ref,
    SelectedCity city,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setSelectedCity(city);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ المدينة المختارة. يرجى إعادة المحاولة.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleCitySelection(context, ref, city);
          }
        },
      );
    }
  }

  Future<void> _handleMethodOverrideChange(
    BuildContext context,
    WidgetRef ref,
    CalculationMethod? method,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .setCalculationMethodOverride(method);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ طريقة الحساب. يرجى إعادة المحاولة.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleMethodOverrideChange(context, ref, method);
          }
        },
      );
    }
  }

  Future<void> _handleMadhabChange(
    BuildContext context,
    WidgetRef ref,
    Madhab madhab,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setAsrMadhab(madhab);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ مذهب صلاة العصر.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleMadhabChange(context, ref, madhab);
          }
        },
      );
    }
  }

  Future<void> _handleHighLatitudeRuleChange(
    BuildContext context,
    WidgetRef ref,
    HighLatitudeRule rule,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setHighLatitudeRule(rule);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ قاعدة خطوط العرض العليا.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleHighLatitudeRuleChange(context, ref, rule);
          }
        },
      );
    }
  }

  Future<void> _handlePolarResolutionChange(
    BuildContext context,
    WidgetRef ref,
    PolarDayResolution resolution,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setPolarResolution(resolution);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ معالجة المناطق القطبية.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handlePolarResolutionChange(context, ref, resolution);
          }
        },
      );
    }
  }

  Future<void> _handleRamadanPolicyChange(
    BuildContext context,
    WidgetRef ref,
    UmmAlQuraRamadanPolicy policy,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setRamadanPolicy(policy);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ سياسة رمضان لأم القرى.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleRamadanPolicyChange(context, ref, policy);
          }
        },
      );
    }
  }

  Future<void> _handleHijriAdjustmentChange(
    BuildContext context,
    WidgetRef ref,
    int days,
  ) async {
    if (days < -2 || days > 2) return;
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setHijriDayAdjustment(days);
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ تعديل التقويم الهجري.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleHijriAdjustmentChange(context, ref, days);
          }
        },
      );
    }
  }

  Future<void> _handleOffsetChange(
    BuildContext context,
    WidgetRef ref, {
    int? fajr,
    int? sunrise,
    int? dhuhr,
    int? asr,
    int? maghrib,
    int? isha,
  }) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setPrayerOffsets(
            fajr: fajr,
            sunrise: sunrise,
            dhuhr: dhuhr,
            asr: asr,
            maghrib: maghrib,
            isha: isha,
          );
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر حفظ فروق مواقيت الصلاة.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleOffsetChange(
              context,
              ref,
              fajr: fajr,
              sunrise: sunrise,
              dhuhr: dhuhr,
              asr: asr,
              maghrib: maghrib,
              isha: isha,
            );
          }
        },
      );
    }
  }

  Future<void> _handleResetAllPrayerSettings(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref
          .read(preferencesControllerProvider.notifier)
          .resetPrayerSettingsToDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت استعادة إعدادات الحساب الافتراضية بنجاح.'),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'تعذر استعادة إعدادات الحساب الافتراضية.',
        onRetry: () {
          final curGen = ref.read(progressRepositoryProvider).mutationBarrier.currentGeneration;
          if (curGen == capturedGen) {
            _handleResetAllPrayerSettings(context, ref);
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveSnapshotAsync = ref.watch(effectivePrayerSettingsProvider);
    final SelectedCity? selectedCity = effectiveSnapshotAsync.valueOrNull?.city;
    final bool hasRecoveryNotice = prefs.prayerSettingsRecoveryNotice;
    final bool hasCityError = effectiveSnapshotAsync.hasError;

    final cityDefaultMethod = selectedCity?.defaultCalculationMethod ??
        CalculationMethod.egyptian;
    final isOverridden = prefs.calculationMethodOverride != null;

    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Corruption or Recovery Alert Banner
            if (hasRecoveryNotice) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'تم رصد بعض الإعدادات غير الصالحة واستعادتها إلى القيم الآمنة تلقائياً دون تعديل باقي بياناتك.',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Unresolved City Alert
            if (hasCityError) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade900.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade700),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_off, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'المدينة المحددة (${prefs.selectedCity}) غير مطابقة لقاعدة البيانات.',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? AppColors.darkForestPrimary
                            : AppColors.forestPrimary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () async {
                        final picked = await CitySearchPickerDialog.show(
                          context,
                          currentCityId: prefs.selectedCityId,
                        );
                        if (picked != null && context.mounted) {
                          await _handleCitySelection(context, ref, picked);
                        }
                      },
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('اختيار مدينة صالحة من قاعدة البيانات'),
                    ),
                  ],
                ),
              ),
            ],

            // 1. City Selection Card
            _buildSettingCard(
              title: 'المدينة والمنطقة الزمنية',
              subtitle: 'اختر مدينتك من بين ٣٤,١٤٩ مدينة لحساب دقيق للمواقيت بدون إنترنت',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkForestPrimary.withAlpha(40)
                        : AppColors.forestSoftTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.location_city,
                    color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                  ),
                ),
                title: Text(
                  selectedCity != null
                      ? (selectedCity.arabicName != null
                          ? '${selectedCity.arabicName} (${selectedCity.name})'
                          : selectedCity.name)
                      : prefs.selectedCity,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  selectedCity != null
                      ? '${selectedCity.countryCode} · ${selectedCity.timezone} · المعرف: ${selectedCity.id}'
                      : prefs.selectedTimezone,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                  ),
                ),
                trailing: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? AppColors.darkForestPrimary
                        : AppColors.forestPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final picked = await CitySearchPickerDialog.show(
                      context,
                      currentCityId: prefs.selectedCityId,
                    );
                    if (picked != null && context.mounted) {
                      await _handleCitySelection(context, ref, picked);
                    }
                  },
                  icon: const Icon(Icons.search, size: 14),
                  label: const Text('تغيير', style: TextStyle(fontSize: 11)),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 2. Calculation Method & Override Retention
            _buildSettingCard(
              title: 'طريقة الحساب الفلكي',
              subtitle: 'اختر طريقة الحساب المعتمدة أو اعتمد الطريقة الافتراضية للمدينة',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<CalculationMethod?>(
                    key: ValueKey('method_override_${prefs.calculationMethodOverride?.name}'),
                    initialValue: prefs.calculationMethodOverride,
                    isExpanded: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? AppColors.darkSurface : Colors.grey.shade50,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    items: [
                      DropdownMenuItem<CalculationMethod?>(
                        value: null,
                        child: Text(
                          'افتراضي المدينة: ${_getMethodName(cityDefaultMethod)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ...PrayerSettings.supportedMethods.map((method) {
                        return DropdownMenuItem<CalculationMethod?>(
                          value: method,
                          child: Text(
                            _getMethodName(method),
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) => _handleMethodOverrideChange(context, ref, val),
                  ),
                  if (isOverridden) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber.withAlpha(30)
                            : AppColors.goldSoftTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.lock_clock,
                            size: 16,
                            color: isDark ? AppColors.darkGoldAccent : AppColors.goldDark,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'تم تفعيل تخصيص يدوي: سيبقى ثابتاً حتى لو تغيرت المدينة ما لم تقم بإلغائه.',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _handleMethodOverrideChange(context, ref, null),
                            child: const Text('استعادة الافتراضي', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 3. Asr Madhab & High-Latitude Rules
            _buildSettingCard(
              title: 'مذهب العصر وخطوط العرض العليا',
              subtitle: 'تحديد وقت صلاة العصر وقواعد احتساب الشفق في المناطق الشمالية',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Madhab>(
                          key: ValueKey('asr_madhab_${prefs.asrMadhab.name}'),
                          initialValue: prefs.asrMadhab,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'مذهب صلاة العصر',
                            labelStyle: const TextStyle(fontSize: 11),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: Madhab.shafi,
                              child: Text('الجمهور (الشافعي/المالكي/الحنبلي)', style: TextStyle(fontSize: 11)),
                            ),
                            DropdownMenuItem(
                              value: Madhab.hanafi,
                              child: Text('الحنفي (ظل المثلين)', style: TextStyle(fontSize: 11)),
                            ),
                          ],
                          onChanged: (val) {
                            if (val != null) _handleMadhabChange(context, ref, val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<HighLatitudeRule>(
                    key: ValueKey('high_latitude_${prefs.highLatitudeRule.name}'),
                    initialValue: prefs.highLatitudeRule,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'قاعدة خطوط العرض العليا',
                      labelStyle: const TextStyle(fontSize: 11),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: HighLatitudeRule.middle_of_the_night,
                        child: Text('منتصف الليل (Middle of the Night)', style: TextStyle(fontSize: 11)),
                      ),
                      DropdownMenuItem(
                        value: HighLatitudeRule.seventh_of_the_night,
                        child: Text('سُبع الليل (Seventh of the Night)', style: TextStyle(fontSize: 11)),
                      ),
                      DropdownMenuItem(
                        value: HighLatitudeRule.twilight_angle,
                        child: Text('زاوية الشفق (Twilight Angle)', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) _handleHighLatitudeRuleChange(context, ref, val);
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<PolarDayResolution>(
                    key: ValueKey('polar_res_${prefs.polarResolution.name}'),
                    initialValue: prefs.polarResolution,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'المناطق القطبية (غياب الشمس أو شروق مستمر)',
                      labelStyle: const TextStyle(fontSize: 11),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PolarDayResolution.unresolved,
                        child: Text('غير محدد صراحة (الوضع الآمن)', style: TextStyle(fontSize: 11)),
                      ),
                      DropdownMenuItem(
                        value: PolarDayResolution.nearestLatitude,
                        child: Text('أقرب خط عرض صالح (أقرب البلاد)', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) _handlePolarResolutionChange(context, ref, val);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 4. Ramadan Policy & Hijri Adjustment
            _buildSettingCard(
              title: 'سياسة أم القرى لرمضان وتعديل التقويم',
              subtitle: 'إضافة ٣٠ دقيقة لصلاة العشاء في رمضان وتعديل الرؤية المحلية للأشهر',
              child: Column(
                children: [
                  DropdownButtonFormField<UmmAlQuraRamadanPolicy>(
                    key: ValueKey('ramadan_policy_${prefs.ramadanPolicy.name}'),
                    initialValue: prefs.ramadanPolicy,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'سياسة إضافة ٣٠ دقيقة للعشاء برمضان',
                      labelStyle: const TextStyle(fontSize: 11),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: UmmAlQuraRamadanPolicy.eveningOfRamadan,
                        child: Text('المساء الشرعي (ليلة ١ رمضان حتى ليلة العيد)', style: TextStyle(fontSize: 11)),
                      ),
                      DropdownMenuItem(
                        value: UmmAlQuraRamadanPolicy.civilDay,
                        child: Text('اليوم المدني لرمضان (حسب التقويم)', style: TextStyle(fontSize: 11)),
                      ),
                      DropdownMenuItem(
                        value: UmmAlQuraRamadanPolicy.disabled,
                        child: Text('معطل (٩٠ دقيقة دائماً)', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) _handleRamadanPolicyChange(context, ref, val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'تعديل التقويم الهجري:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: prefs.hijriDayAdjustment > -2
                            ? () => _handleHijriAdjustmentChange(
                                  context,
                                  ref,
                                  prefs.hijriDayAdjustment - 1,
                                )
                            : null,
                      ),
                      Text(
                        '${prefs.hijriDayAdjustment > 0 ? "+" : ""}${prefs.hijriDayAdjustment} يوم',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: prefs.hijriDayAdjustment < 2
                            ? () => _handleHijriAdjustmentChange(
                                  context,
                                  ref,
                                  prefs.hijriDayAdjustment + 1,
                                )
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 5. Manual Offsets (±120 min)
            _buildSettingCard(
              title: 'فروق التوقيت اليدوية (بالدقائق)',
              subtitle: 'تعديل أوقات الصلوات يدوياً بدقة (بين -١٢٠ و +١٢٠ دقيقة)',
              child: Column(
                children: [
                  _buildOffsetRow(
                    context,
                    ref,
                    title: 'الفجر',
                    value: prefs.fajrOffset,
                    onChange: (v) => _handleOffsetChange(context, ref, fajr: v),
                  ),
                  _buildOffsetRow(
                    context,
                    ref,
                    title: 'الشروق',
                    value: prefs.sunriseOffset,
                    onChange: (v) => _handleOffsetChange(context, ref, sunrise: v),
                  ),
                  _buildOffsetRow(
                    context,
                    ref,
                    title: 'الظهر',
                    value: prefs.dhuhrOffset,
                    onChange: (v) => _handleOffsetChange(context, ref, dhuhr: v),
                  ),
                  _buildOffsetRow(
                    context,
                    ref,
                    title: 'العصر',
                    value: prefs.asrOffset,
                    onChange: (v) => _handleOffsetChange(context, ref, asr: v),
                  ),
                  _buildOffsetRow(
                    context,
                    ref,
                    title: 'المغرب',
                    value: prefs.maghribOffset,
                    onChange: (v) => _handleOffsetChange(context, ref, maghrib: v),
                  ),
                  _buildOffsetRow(
                    context,
                    ref,
                    title: 'العشاء',
                    value: prefs.ishaOffset,
                    onChange: (v) => _handleOffsetChange(context, ref, isha: v),
                  ),
                  if (prefs.fajrOffset != 0 ||
                      prefs.sunriseOffset != 0 ||
                      prefs.dhuhrOffset != 0 ||
                      prefs.asrOffset != 0 ||
                      prefs.maghribOffset != 0 ||
                      prefs.ishaOffset != 0) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                        icon: const Icon(Icons.restart_alt, size: 14),
                        label: const Text('تصفير كافة الفروق', style: TextStyle(fontSize: 11)),
                        onPressed: () => _handleOffsetChange(
                          context,
                          ref,
                          fajr: 0,
                          sunrise: 0,
                          dhuhr: 0,
                          asr: 0,
                          maghrib: 0,
                          isha: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Reset Prayer Settings Button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                side: BorderSide(
                  color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _handleResetAllPrayerSettings(context, ref),
              icon: const Icon(Icons.restore, size: 16),
              label: const Text(
                'استعادة إعدادات الحساب الافتراضية',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkCardBorder : AppColors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildOffsetRow(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required int value,
    required ValueChanged<int> onChange,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 16),
                onPressed: value > -120 ? () => onChange(value - 1) : null,
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${value > 0 ? "+" : ""}$value د',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: value != 0
                        ? (isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary)
                        : null,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 16),
                onPressed: value < 120 ? () => onChange(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
