import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../quran/presentation/utils/quran_ui_utils.dart';
import '../data/reminder_service.dart';
import '../domain/reminder_settings.dart';

/// Settings for offline reminders: periodic dhikr phrases and fixed adhkar
/// times. All reminders are scheduled locally and need no internet.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with WidgetsBindingObserver {
  late ReminderSettings _s;
  bool _overlayAllowed = true;

  @override
  void initState() {
    super.initState();
    _s = ReminderService.instance.settings;
    WidgetsBinding.instance.addObserver(this);
    _checkOverlay();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system permission screen.
    if (state == AppLifecycleState.resumed) {
      _checkOverlay();
      ReminderService.instance.reschedule(_s);
    }
  }

  Future<void> _checkOverlay() async {
    final ok = await ReminderService.instance.canShowOverlay();
    if (mounted) setState(() => _overlayAllowed = ok);
  }

  Future<void> _update(ReminderSettings next) async {
    final turningOn = !_s.anyEnabled && next.anyEnabled;
    setState(() => _s = next);
    if (turningOn) {
      final ok = await ReminderService.instance.requestPermission();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'لازم تسمح للتطبيق بالإشعارات من إعدادات الموبايل عشان التذكيرات تظهر.',
            ),
          ),
        );
      }
    }
    await ReminderService.instance.save(next);
  }

  String _hour(int h) {
    final hh = h % 24;
    final suffix = hh < 12 ? 'ص' : 'م';
    final display = hh % 12 == 0 ? 12 : hh % 12;
    return '${QuranUiUtils.toArabicDigits(display)} $suffix';
  }

  String _interval(int m) {
    if (m < 60) return 'كل ${QuranUiUtils.toArabicDigits(m)} دقيقة';
    final h = m ~/ 60;
    if (h == 1) return 'كل ساعة';
    if (h == 2) return 'كل ساعتين';
    return 'كل ${QuranUiUtils.toArabicDigits(h)} ساعات';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('التذكيرات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              'تذكيرات بتشتغل من غير إنترنت وحتى لو التطبيق مقفول.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 12),

            // ---------------- Periodic dhikr ----------------
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SwitchListTile(
                      key: const ValueKey('reminders_dhikr_switch'),
                      secondary: const Icon(Icons.notifications_active_outlined),
                      title: const Text('ذكّرني بذكر الله'),
                      subtitle: Text(_interval(_s.intervalMinutes)),
                      value: _s.dhikrEnabled,
                      onChanged: (v) => _update(_s.copyWith(dhikrEnabled: v)),
                    ),
                    if (_s.dhikrEnabled) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('كل قد إيه؟', style: text.titleSmall),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final m in ReminderSettings.intervalOptions)
                              ChoiceChip(
                                label: Text(_interval(m)),
                                selected: _s.intervalMinutes == m,
                                onSelected: (_) =>
                                    _update(_s.copyWith(intervalMinutes: m)),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          'من ${_hour(_s.startHour)} إلى ${_hour(_s.endHour)}',
                          style: text.titleSmall,
                        ),
                      ),
                      RangeSlider(
                        values: RangeValues(
                          _s.startHour.toDouble(),
                          _s.endHour.toDouble(),
                        ),
                        min: 0,
                        max: 24,
                        divisions: 24,
                        labels: RangeLabels(
                          _hour(_s.startHour),
                          _hour(_s.endHour),
                        ),
                        onChanged: (r) {
                          final start = r.start.round();
                          final end = r.end.round();
                          if (end - start < 1) return;
                          setState(() => _s = _s.copyWith(
                                startHour: start,
                                endHour: end,
                              ));
                        },
                        onChangeEnd: (_) => _update(_s),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text('الأذكار اللي تظهر', style: text.titleSmall),
                      ),
                      for (final p in DhikrPhrase.all)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            p.text,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 15,
                            ),
                          ),
                          value: _s.phraseIds.contains(p.id),
                          onChanged: (v) {
                            final ids = [..._s.phraseIds];
                            if (v == true) {
                              if (!ids.contains(p.id)) ids.add(p.id);
                            } else {
                              if (ids.length <= 1) return;
                              ids.remove(p.id);
                            }
                            _update(_s.copyWith(phraseIds: ids));
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ---------------- Display style ----------------
            Text('طريقة الظهور', style: text.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StyleOption(
                    key: const ValueKey('reminders_style_overlay'),
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'بطاقة لطيفة',
                    subtitle: 'تظهر على الشاشة وتختفي لوحدها',
                    selected: _s.useOverlay,
                    onTap: () => _update(_s.copyWith(displayStyle: 'overlay')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StyleOption(
                    key: const ValueKey('reminders_style_notification'),
                    icon: Icons.notifications_none_rounded,
                    title: 'إشعار عادي',
                    subtitle: 'في شريط الإشعارات',
                    selected: !_s.useOverlay,
                    onTap: () =>
                        _update(_s.copyWith(displayStyle: 'notification')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_s.useOverlay)
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_overlayAllowed) ...[
                        Text(
                          'عشان البطاقة تظهر فوق أي تطبيق، اسمح لـ "زاد الروح" بالظهور فوق التطبيقات الأخرى. '
                          'لحد ما تسمح، التذكير هيوصلك كإشعار عادي.',
                          style: text.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          icon: const Icon(Icons.verified_user_outlined, size: 18),
                          label: const Text('السماح بالظهور على الشاشة'),
                          onPressed: () async {
                            await ReminderService.instance
                                .requestOverlayPermission();
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text('مكانها في الشاشة', style: text.titleSmall),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'top',
                            icon: Icon(Icons.vertical_align_top_rounded),
                            label: Text('فوق'),
                          ),
                          ButtonSegment(
                            value: 'center',
                            icon: Icon(Icons.vertical_align_center_rounded),
                            label: Text('النص'),
                          ),
                          ButtonSegment(
                            value: 'bottom',
                            icon: Icon(Icons.vertical_align_bottom_rounded),
                            label: Text('تحت'),
                          ),
                        ],
                        selected: {_s.overlayPosition},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) =>
                            _update(_s.copyWith(overlayPosition: v.first)),
                      ),
                      const SizedBox(height: 14),
                      Text('تفضل ظاهرة قد إيه', style: text.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final sec in const [5, 8, 15, 30])
                            ChoiceChip(
                              label: Text(
                                '${QuranUiUtils.toArabicDigits(sec)} ثانية',
                              ),
                              selected: _s.overlaySeconds == sec,
                              onSelected: (_) =>
                                  _update(_s.copyWith(overlaySeconds: sec)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: SwitchListTile(
                  key: const ValueKey('reminders_popup_switch'),
                  secondary: const Icon(Icons.open_in_full_rounded),
                  title: const Text('إشعار منبثق بصوت خفيف'),
                  subtitle: const Text('لو قفلتها هيظهر بهدوء في شريط الإشعارات'),
                  value: _s.popUp,
                  onChanged: (v) => _update(_s.copyWith(popUp: v)),
                ),
              ),
            const SizedBox(height: 12),

            // ---------------- Fixed reminders ----------------
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.wb_sunny_outlined),
                    title: const Text('أذكار الصباح'),
                    subtitle: Text(_hour(7)),
                    value: _s.morningAdhkar,
                    onChanged: (v) => _update(_s.copyWith(morningAdhkar: v)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.nights_stay_outlined),
                    title: const Text('أذكار المساء'),
                    subtitle: Text(_hour(17)),
                    value: _s.eveningAdhkar,
                    onChanged: (v) => _update(_s.copyWith(eveningAdhkar: v)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.menu_book_outlined),
                    title: const Text('وِرد القرآن اليومي'),
                    subtitle: Text(_hour(20)),
                    value: _s.dailyWird,
                    onChanged: (v) => _update(_s.copyWith(dailyWird: v)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.bedtime_outlined),
                    title: const Text('أذكار النوم'),
                    subtitle: const Text('١٠:٣٠ م'),
                    value: _s.sleepAdhkar,
                    onChanged: (v) => _update(_s.copyWith(sleepAdhkar: v)),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.event_available_outlined),
                    title: const Text('سورة الكهف يوم الجمعة'),
                    subtitle: Text('الجمعة ${_hour(10)}'),
                    value: _s.fridayKahf,
                    onChanged: (v) => _update(_s.copyWith(fridayKahf: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: Icon(Icons.play_arrow_rounded, color: scheme.primary),
              label: const Text('جرّب تذكير دلوقتي'),
              onPressed: () async {
                if (_s.useOverlay) {
                  final shown =
                      await ReminderService.instance.previewOverlay(_s);
                  if (shown) return;
                }
                await ReminderService.instance.requestPermission();
                await ReminderService.instance.showTest(_s);
              },
            ),
            const SizedBox(height: 12),
            Text(
              'ملاحظة: بعض الموبايلات (شاومي، أوبو، ريلمي…) بتوقف التذكيرات لتوفير البطارية. '
              'لو التذكيرات مش بتظهر، خلّي "زاد الروح" بدون قيود في إعدادات البطارية.',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StyleOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _StyleOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: selected ? scheme.primaryContainer : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.6 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(height: 8),
              Text(title, style: text.titleSmall),
              const SizedBox(height: 2),
              Text(subtitle, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
