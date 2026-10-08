import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/retryable_error_view.dart';
import '../../prayer/domain/models/adhan_voice.dart';
import '../../prayer/presentation/controllers/prayer_notification_controller.dart';
import '../../prayers/presentation/controllers/adhan_audio_controller.dart';
import '../../progress/presentation/controllers/progress_controller.dart';
import 'widgets/prayer_calculation_settings_section.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  /// Canonical legacy reference list preserved for API compatibility.
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

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
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

  void _showRejectedRetryNotice(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم إلغاء المحاولة السابقة لإعادة ضبط البيانات.'),
      ),
    );
  }

  Future<void> _updateDarkMode(BuildContext context, String mode) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setDarkMode(mode);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حفظ إعداد المظهر. يرجى إعادة المحاولة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                final curGen = ref
                    .read(progressRepositoryProvider)
                    .mutationBarrier
                    .currentGeneration;
                if (curGen != capturedGen) {
                  _showRejectedRetryNotice(context);
                  return;
                }
                _updateDarkMode(context, mode);
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateTextScale(BuildContext context, double scale) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setTextScale(scale);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حفظ حجم الخط. يرجى إعادة المحاولة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                final curGen = ref
                    .read(progressRepositoryProvider)
                    .mutationBarrier
                    .currentGeneration;
                if (curGen != capturedGen) {
                  _showRejectedRetryNotice(context);
                  return;
                }
                _updateTextScale(context, scale);
              },
            ),
          ),
        );
      }
    }
  }


  Future<void> _updateGeneralVoice(BuildContext context, String voiceId) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setGeneralAdhanVoice(voiceId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حفظ صوت الأذان العام. يرجى إعادة المحاولة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                final curGen = ref
                    .read(progressRepositoryProvider)
                    .mutationBarrier
                    .currentGeneration;
                if (curGen != capturedGen) {
                  _showRejectedRetryNotice(context);
                  return;
                }
                _updateGeneralVoice(context, voiceId);
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateFajrVoice(BuildContext context, String voiceId) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setFajrAdhanVoice(voiceId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حفظ صوت أذان الفجر. يرجى إعادة المحاولة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                final curGen = ref
                    .read(progressRepositoryProvider)
                    .mutationBarrier
                    .currentGeneration;
                if (curGen != capturedGen) {
                  _showRejectedRetryNotice(context);
                  return;
                }
                _updateFajrVoice(context, voiceId);
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _updateQuranGoal(BuildContext context, int goal) async {
    final repo = ref.read(progressRepositoryProvider);
    final int capturedGen = repo.mutationBarrier.currentGeneration;
    try {
      await ref.read(preferencesControllerProvider.notifier).setQuranGoal(goal);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade800,
            content: const Text('تعذر حفظ الهدف اليومي. يرجى إعادة المحاولة.'),
            action: SnackBarAction(
              label: 'إعادة المحاولة',
              textColor: Colors.white,
              onPressed: () {
                final curGen = ref
                    .read(progressRepositoryProvider)
                    .mutationBarrier
                    .currentGeneration;
                if (curGen != capturedGen) {
                  _showRejectedRetryNotice(context);
                  return;
                }
                _updateQuranGoal(context, goal);
              },
            ),
          ),
        );
      }
    }
  }

  void _showResetConfirmDialog(BuildContext context) {
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
                  // Direct invocation: core owns confirmed audio and native cancellation with synchronous fence
                  await ref.read(preferencesControllerProvider.notifier).resetAllState();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('تمت إعادة ضبط كافة البيانات بنجاح')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade800,
                        content: const Text('تعذر إعادة ضبط البيانات. يرجى إعادة المحاولة.'),
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

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getNotificationSubtitle(PrayerNotificationState notifState) {
    switch (notifState.status) {
      case PrayerNotificationStatus.activeExact:
        if (notifState.acceptedScheduledCount != null) {
          return 'مفعلة بتنبيهات دقيقة في موعد الأذان (${notifState.acceptedScheduledCount} موعد مجدول في النظام)';
        }
        return 'مفعلة بتنبيهات دقيقة في موعد الأذان (${notifState.plannedFutureEventsCount} موعد مخطط)';
      case PrayerNotificationStatus.activeInexact:
        return 'مفعلة بتوقيت تقريبي (إذن التنبيهات الدقيقة غير مفعل في إعدادات النظام)';
      case PrayerNotificationStatus.permissionDenied:
        return 'إذن إرسال الإشعارات غير مفعل في إعدادات نظام الجهاز';
      case PrayerNotificationStatus.recoveryRequired:
        return 'تتطلب التنبيهات إعادة التأكيد والتنظيف بعد عملية سابقة غير مكتملة';
      case PrayerNotificationStatus.polarDayUnresolved:
        return 'تعذر جدولة التنبيهات لتعذر حساب المواقيت الفلكية (يوم قطبي)';
      case PrayerNotificationStatus.partialFailure:
        return 'تم تحديث الخطة، ولكن تعذر اكتمال بعض التنبيهات في النظام';
      case PrayerNotificationStatus.updating:
        return 'جاري تحديث مواعيد التنبيهات في النظام...';
      case PrayerNotificationStatus.disabled:
        return 'التنبيهات متوقفة';
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(preferencesControllerProvider);
    final audioState = ref.watch(adhanAudioControllerProvider);
    final notifState = ref.watch(prayerNotificationStateProvider);
    final isResetInProgress = ref.watch(isResetInProgressProvider);
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
                if (isResetInProgress) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'جاري إعادة ضبط البيانات وتفريغ العمليات المعلقة...',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

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
                        onChanged: isResetInProgress
                            ? null
                            : (val) {
                                if (val != null) {
                                  _updateDarkMode(context, val);
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
                        onChanged: isResetInProgress
                            ? null
                            : (val) {
                                if (val != null) {
                                  _updateTextScale(context, val);
                                }
                              },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Location & Prayer Calculation Settings Section
                _buildSectionHeader('الموقع وحساب مواقيت الصلاة', isDark),
                PrayerCalculationSettingsSection(
                  prefs: prefs,
                  isDark: isDark,
                  disabled: isResetInProgress,
                ),

                const SizedBox(height: 16),

                // Notifications
                _buildSectionHeader('التنبيهات والأذان', isDark),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text(
                          'تنبيهات الأذان',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          _getNotificationSubtitle(notifState),
                          style: TextStyle(
                            fontSize: 11,
                            color: notifState.isRecoveryRequired
                                ? (isDark
                                    ? Colors.amber.shade300
                                    : Colors.amber.shade900)
                                : null,
                          ),
                        ),
                        value: prefs.notificationsEnabled,
                        onChanged: isResetInProgress
                            ? null
                            : (val) async {
                                await ref
                                    .read(prayerNotificationControllerProvider)
                                    .toggle(val);
                              },
                      ),
                      if (notifState.isRecoveryRequired) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                notifState.errorMessageAr ??
                                    'تتطلب التنبيهات إعادة التأكيد والتنظيف.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? Colors.amber.shade300
                                      : Colors.amber.shade900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: isResetInProgress ||
                                        notifState.status ==
                                            PrayerNotificationStatus.updating
                                    ? null
                                    : () async {
                                        await ref
                                            .read(
                                              prayerNotificationControllerProvider,
                                            )
                                            .recover();
                                      },
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('إعادة المحاولة والتنظيف'),
                              ),
                            ],
                          ),
                        ),
                      ] else if (notifState.status ==
                          PrayerNotificationStatus.permissionDenied) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 16,
                                color: isDark
                                    ? Colors.amber.shade300
                                    : Colors.amber.shade800,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'يرجى تفعيل إذن الإشعارات من إعدادات التطبيق في نظام الجهاز.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (notifState.status ==
                          PrayerNotificationStatus.activeInexact) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: isDark
                                        ? AppColors.darkGoldAccent
                                        : AppColors.forestPrimary,
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      'تنبيهات تقريبية. لتفعيل التنبيه الدقيق في الموعد تماماً، يمكن السماح بالتنبيهات الدقيقة في إعدادات النظام.',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: isResetInProgress
                                    ? null
                                    : () async {
                                        await ref
                                            .read(
                                              prayerNotificationControllerProvider,
                                            )
                                            .requestExactAlarmPermission();
                                      },
                                icon: const Icon(Icons.alarm_on, size: 16),
                                label: const Text('طلب إذن التنبيه الدقيق'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (notifState.isPartialCoverage &&
                          notifState.coverageExplanation != null &&
                          notifState.coverageExplanation!.isNotEmpty) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: isDark
                                    ? AppColors.darkGoldAccent
                                    : AppColors.forestPrimary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notifState.coverageExplanation!,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Adhan Voice Selection & Audio Preview Section
                _buildSectionHeader('أصوات الأذان وتجربة الاستماع', isDark),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (prefs.voiceRecoveryNotice) ...[
                        Container(
                          margin: const EdgeInsets.all(12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
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
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'تمت استعادة أصوات الأذان الافتراضية لعدم صلاحية الاختيار المحفوظ سابقاً.',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      // General Adhan Voice (adam or atcovi only)
                      _buildDropdownSetting<String>(
                        title: 'صوت أذان الصلوات العامة',
                        subtitle:
                            'للصلوات الأربع (الظهر، العصر، المغرب، العشاء). التسجيل مقتصر على الصيغ العامة منعاً لخلط ألفاظ أذان الفجر.',
                        value: prefs.generalAdhanVoice,
                        items: const [
                          DropdownMenuItem(
                            value: 'adam',
                            child: Text('أذان (تسجيل عام) · Adam-synagda (CC0)'),
                          ),
                          DropdownMenuItem(
                            value: 'atcovi',
                            child: Text('أذان (المصدر: Atcovi) · CC BY-SA 4.0'),
                          ),
                        ],
                        onChanged: isResetInProgress
                            ? null
                            : (val) {
                                if (val != null) {
                                  _updateGeneralVoice(context, val);
                                }
                              },
                      ),
                      const Divider(height: 1),

                      // Fajr Adhan Voice (adam, atcovi, or malmo_fajr)
                      _buildDropdownSetting<String>(
                        title: 'صوت أذان الفجر',
                        subtitle:
                            'مخصص لصلاة الفجر (الافتراضي: تسجيل المركز الإسلامي في مالمو)',
                        value: prefs.fajrAdhanVoice,
                        items: const [
                          DropdownMenuItem(
                            value: 'malmo_fajr',
                            child: Text(
                              'أذان الفجر - المركز الإسلامي في مالمو (CC BY 3.0) [افتراضي]',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'adam',
                            child: Text('أذان (تسجيل عام) · Adam-synagda (CC0)'),
                          ),
                          DropdownMenuItem(
                            value: 'atcovi',
                            child: Text('أذان (المصدر: Atcovi) · CC BY-SA 4.0'),
                          ),
                        ],
                        onChanged: isResetInProgress
                            ? null
                            : (val) {
                                if (val != null) {
                                  _updateFajrVoice(context, val);
                                }
                              },
                      ),
                      const Divider(height: 1),

                      // Audio Preview Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'معاينة التسجيلات المدمجة محلياً (بدون إنترنت)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkGoldAccent
                                    : AppColors.forestPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'استمع إلى التسجيلات الصوتية كاملة للتحقق من الصوت قبل الاعتماد. يتوقف التشغيل تلقائياً عند مغادرة الشاشة.',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      // Active Audio Player Banner (if playing or loading)
                      if (audioState.isPlaying || audioState.isLoading) ...[
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.teal.shade900.withAlpha(60)
                                : const Color(0xFFEFF5F0),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark
                                  ? AppColors.darkGoldAccent
                                  : AppColors.forestPrimary,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                audioState.isLoading
                                    ? Icons.hourglass_top_rounded
                                    : Icons.volume_up_rounded,
                                color: isDark
                                    ? AppColors.darkGoldAccent
                                    : AppColors.forestPrimary,
                                size: 24,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      AdhanVoice.findById(audioState.activeVoiceId ?? '')?.nameAr ??
                                          'جاري تشغيل التسجيل الصوتي...',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_formatDuration(audioState.position)} / ${_formatDuration(audioState.totalDuration)}',
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
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade700,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                icon: const Icon(Icons.stop_rounded, size: 18),
                                label: const Text(
                                  'إيقاف الاستماع',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                onPressed: () {
                                  _audioController.stop().catchError((_) {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Audio Error Banner
                      if (audioState.status == AdhanAudioStatus.error &&
                          audioState.errorMessage != null) ...[
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade700),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  audioState.errorMessage!,
                                  style: const TextStyle(fontSize: 11, color: Colors.red),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () {
                                  _audioController.stop().catchError((_) {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Three Voice Preview Tiles
                      ...AdhanVoice.allVoices.map((voice) {
                        final isThisActive = audioState.isVoiceActive(voice.id);
                        final isThisPlaying = audioState.isVoicePlaying(voice.id);

                        return ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  voice.nameAr,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (voice.isFajr)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.amber.shade900.withAlpha(50)
                                        : AppColors.goldSoftTint,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'مخصص للفجر',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? AppColors.darkGoldAccent
                                          : AppColors.goldDark,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            '${voice.title} · ${voice.license}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? AppColors.darkTextMuted : AppColors.textMuted,
                            ),
                          ),
                          trailing: isThisPlaying
                              ? IconButton(
                                  icon: const Icon(Icons.pause_circle_filled, size: 28),
                                  color: isDark ? AppColors.darkGoldAccent : AppColors.forestPrimary,
                                  tooltip: 'إيقاف مؤقت',
                                  onPressed: isResetInProgress
                                      ? null
                                      : () {
                                          _audioController.pause();
                                        },
                                )
                              : IconButton(
                                  icon: isThisActive && audioState.isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : Icon(
                                          Icons.play_circle_outline,
                                          size: 28,
                                          color: isResetInProgress
                                              ? Colors.grey
                                              : (isDark
                                                  ? AppColors.darkGoldAccent
                                                  : AppColors.forestPrimary),
                                        ),
                                  tooltip: 'استماع للتسجيل',
                                  onPressed: isResetInProgress
                                      ? null
                                      : () {
                                          _audioController.playVoice(voice);
                                        },
                                ),
                        );
                      }),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Quran Daily Goal Section
                _buildSectionHeader('أهداف القراءة والأوراد', isDark),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text(
                          'هدف الورد القرآني اليومي',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'المستهدف اليومي: ${prefs.quranDefaultGoal} صفحات يومياً',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: DropdownButton<int>(
                          value: prefs.quranDefaultGoal,
                          items: [1, 2, 4, 8, 10, 20].map((g) {
                            return DropdownMenuItem<int>(
                              value: g,
                              child: Text('$g صفحات'),
                            );
                          }).toList(),
                          onChanged: isResetInProgress
                              ? null
                              : (val) {
                                  if (val != null) {
                                    _updateQuranGoal(context, val);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Danger Zone / Reset All Data
                _buildSectionHeader('إدارة البيانات والخصوصية', isDark),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text(
                      'إعادة ضبط كافة البيانات المحلية',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    subtitle: const Text(
                      'حذف جميع السجلات والعلامات واسترجاع الحالة الابتدائية',
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: isResetInProgress
                        ? null
                        : () => _showResetConfirmDialog(context),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => RetryableErrorView(
            message: 'تعذر تحميل الإعدادات. يرجى إعادة المحاولة.',
            onRetry: () =>
                ref.read(preferencesControllerProvider.notifier).retry(),
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
    required ValueChanged<T?>? onChanged,
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
