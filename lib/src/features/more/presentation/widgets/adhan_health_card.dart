import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


/// "Test the adhan" + quick health checks (alarm volume, battery
/// optimisation) + the native log of recent alarm attempts.
class AdhanHealthCard extends StatefulWidget {
  const AdhanHealthCard({super.key});

  @override
  State<AdhanHealthCard> createState() => _AdhanHealthCardState();
}

class _AdhanHealthCardState extends State<AdhanHealthCard>
    with WidgetsBindingObserver {
  static const MethodChannel _channel =
      MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm');

  bool _available = false;
  bool _ignoringBattery = true;
  int _alarmVolume = 1;
  int _alarmVolumeMax = 1;
  List<Map<String, dynamic>> _log = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!Platform.isAndroid) return;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'getAdhanDiagnostics',
      );
      if (res == null || !mounted) return;
      final raw = jsonDecode(res['log'] as String? ?? '[]') as List<dynamic>;
      setState(() {
        _available = true;
        _ignoringBattery = res['ignoringBattery'] as bool? ?? true;
        _alarmVolume = res['alarmVolume'] as int? ?? 1;
        _alarmVolumeMax = res['alarmVolumeMax'] as int? ?? 1;
        _log = raw
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => e.cast<String, dynamic>())
            .toList()
            .reversed
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _test() async {
    final messenger = ScaffoldMessenger.of(context);
    var ok = false;
    try {
      ok = await _channel.invokeMethod<bool>(
            'scheduleTestAdhan',
            {'seconds': 30},
          ) ??
          false;
    } catch (_) {}
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(
          ok
              ? 'الأذان التجريبي هيشتغل بعد ٣٠ ثانية. اقفل الشاشة أو اطلع من التطبيق واستنى.'
              : 'تعذر جدولة التجربة.',
        ),
      ),
    );
    unawaited(Future<void>.delayed(const Duration(seconds: 45), _refresh));
  }

  String _describe(String m) {
    if (m.startsWith('playing')) return 'اشتغل الأذان ✓';
    if (m.contains('StartFullAdhan')) return 'وقت الصلاة: بدء تشغيل الأذان';
    if (m.contains('DeliverShortFallback')) return 'وقت الصلاة: اتبعت إشعار قصير بدل الأذان';
    if (m.contains('exact=false')) return 'التنبيه الدقيق مش مسموح';
    if (m.contains('dnd=true')) return 'الموبايل كان على "عدم الإزعاج"';
    if (m.contains('start_foreground')) return 'أندرويد منع تشغيل الأذان في الخلفية';
    if (m.contains('service_start_failed') || m.contains('service_launch_failed')) {
      return 'أندرويد منع تشغيل خدمة الأذان';
    }
    if (m.contains('audio_focus')) return 'تطبيق تاني ماسك الصوت';
    if (m.contains('prepare_failed')) return 'تعذر فتح ملف صوت الأذان';
    if (m.contains('completed_naturally')) return 'الأذان خلص';
    if (m.contains('stop_active_instance_requested') || m.contains('action_stop')) {
      return 'اتقفل يدويًا';
    }
    if (m.contains('suppressed')) return 'اتلغى بسبب الوضع الصامت/عدم الإزعاج';
    if (m.startsWith('test scheduled')) return 'تجربة: اتجدولت';
    if (m.startsWith('test alarm fired')) return 'تجربة: المنبه اشتغل';
    return m;
  }

  String _time(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.day}/${d.month} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lowVolume = _available && _alarmVolume == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('settings_test_adhan'),
          leading: const Icon(Icons.play_circle_outline_rounded),
          title: const Text('جرّب الأذان'),
          subtitle: const Text('يشتغل بعد ٣٠ ثانية بنفس طريقة وقت الصلاة'),
          trailing: IconButton.filledTonal(
            tooltip: 'تجربة الأذان',
            icon: const Icon(Icons.play_arrow_rounded),
            onPressed: _test,
          ),
        ),
        if (lowVolume)
          ListTile(
            leading: Icon(Icons.volume_mute_rounded, color: scheme.error),
            title: const Text('صوت المنبه على الصفر'),
            subtitle: const Text(
              'الأذان بيشتغل على صوت "المنبه". علّيه من أزرار الصوت أو إعدادات الصوت.',
            ),
          ),
        if (_available && !_ignoringBattery)
          ListTile(
            leading: Icon(Icons.battery_alert_outlined, color: scheme.error),
            title: const Text('توفير البطارية ممكن يوقف الأذان'),
            subtitle: const Text('اسمح للتطبيق يشتغل من غير قيود البطارية'),
            trailing: TextButton(
              onPressed: () async {
                try {
                  await _channel.invokeMethod<void>(
                    'requestIgnoreBatteryOptimizations',
                  );
                } catch (_) {}
              },
              child: const Text('السماح'),
            ),
          ),
        if (_log.isNotEmpty)
          ExpansionTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text('آخر محاولات الأذان'),
            subtitle: Text(
              _describe(_log.first['m'] as String? ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              for (final e in _log.take(12))
                ListTile(
                  dense: true,
                  title: Text(
                    _describe(e['m'] as String? ?? ''),
                    style: text.bodyMedium,
                  ),
                  subtitle: Text(
                    '${_time(e['t'] as int? ?? 0)} · ${e['m']}',
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('نسخ التقرير'),
                  onPressed: () {
                    final report = _log
                        .map((e) => '${_time(e['t'] as int? ?? 0)} ${e['e']} ${e['m']}')
                        .join('\n');
                    Clipboard.setData(ClipboardData(
                      text: 'vol=$_alarmVolume/$_alarmVolumeMax battery=$_ignoringBattery\n$report',
                    ));
                  },
                ),
              ),
            ],
          ),
      ],
    );
  }
}
