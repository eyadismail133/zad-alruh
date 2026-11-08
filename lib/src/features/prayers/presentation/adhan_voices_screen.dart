import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../prayer/data/online_adhan_store.dart';
import '../../prayer/domain/models/online_adhan.dart';
import '../../quran/presentation/utils/quran_ui_utils.dart';
import 'controllers/adhan_audio_controller.dart';

/// Choose the muezzin for prayer alarms. Recordings are downloaded once
/// (needs internet) and then play offline at prayer time.
class AdhanVoicesScreen extends ConsumerStatefulWidget {
  const AdhanVoicesScreen({super.key});

  @override
  ConsumerState<AdhanVoicesScreen> createState() => _AdhanVoicesScreenState();
}

class _AdhanVoicesScreenState extends ConsumerState<AdhanVoicesScreen> {
  final Map<String, double> _progress = {};
  late final AdhanAudioController _audio;
  bool _startedPreview = false;

  @override
  void initState() {
    super.initState();
    _audio = ref.read(adhanAudioControllerProvider.notifier);
  }

  @override
  void dispose() {
    if (_startedPreview) _audio.stop().catchError((_) {});
    super.dispose();
  }

  Future<void> _download(OnlineAdhan a) async {
    setState(() => _progress[a.id] = 0);
    try {
      await ref.read(onlineAdhanStoreProvider.notifier).download(
            a,
            onProgress: (p) {
              if (mounted) setState(() => _progress[a.id] = p);
            },
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر تحميل الأذان. تأكد من الاتصال بالإنترنت وحاول مرة أخرى.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _progress.remove(a.id));
    }
  }

  Future<void> _preview(OnlineAdhan a, bool downloaded) async {
    final audio = ref.read(adhanAudioControllerProvider);
    if (audio.activeVoiceId == 'online_${a.id}' &&
        (audio.isPlaying || audio.isLoading || audio.isBuffering)) {
      await _audio.stop();
      return;
    }
    var url = a.url;
    if (downloaded) {
      final f = await ref.read(onlineAdhanStoreProvider.notifier).fileFor(a);
      if (f != null) url = Uri.file(f.path).toString();
    }
    _startedPreview = true;
    await _audio.playAdhanPreview(
      voiceId: 'online_${a.id}',
      url: url,
      title: 'أذان ${a.nameAr}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(onlineAdhanStoreProvider);
    final audio = ref.watch(adhanAudioControllerProvider);
    final store = ref.read(onlineAdhanStoreProvider.notifier);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    String selectedName(String? id) {
      final a = OnlineAdhan.byId(id);
      if (a == null || !sel.downloaded.contains(a.id)) {
        return 'الصوت المدمج في التطبيق';
      }
      return '${a.nameAr} — ${a.noteAr}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المؤذنون')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.mosque_rounded),
                    title: const Text('أذان الصلوات'),
                    subtitle: Text(selectedName(sel.generalId)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.wb_twilight_rounded),
                    title: const Text('أذان الفجر'),
                    subtitle: Text(selectedName(sel.fajrId)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'حمّل صوت المؤذن مرة واحدة بالإنترنت، وبعدها هيشتغل وقت الصلاة من غير نت '
              '(في وضع "الأذان الكامل"). لو مسحت الملف، التطبيق يرجع للصوت المدمج تلقائيًا.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final a in OnlineAdhan.all) ...[
              _MuezzinCard(
                adhan: a,
                downloaded: sel.downloaded.contains(a.id),
                progress: _progress[a.id],
                isGeneral: sel.generalId == a.id,
                isFajr: sel.fajrId == a.id,
                isPlaying: audio.activeVoiceId == 'online_${a.id}' &&
                    (audio.isPlaying || audio.isLoading || audio.isBuffering),
                onDownload: () => _download(a),
                onPreview: () => _preview(a, sel.downloaded.contains(a.id)),
                onUseGeneral: () => store.selectGeneral(
                  sel.generalId == a.id ? null : a.id,
                ),
                onUseFajr: () => store.selectFajr(
                  sel.fajrId == a.id ? null : a.id,
                ),
                onDelete: () => store.delete(a),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
            Text(
              'المصدر: ${OnlineAdhan.sourceName} — ${OnlineAdhan.sourcePage}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuezzinCard extends StatelessWidget {
  final OnlineAdhan adhan;
  final bool downloaded;
  final double? progress;
  final bool isGeneral;
  final bool isFajr;
  final bool isPlaying;
  final VoidCallback onDownload;
  final VoidCallback onPreview;
  final VoidCallback onUseGeneral;
  final VoidCallback onUseFajr;
  final VoidCallback onDelete;

  const _MuezzinCard({
    required this.adhan,
    required this.downloaded,
    required this.progress,
    required this.isGeneral,
    required this.isFajr,
    required this.isPlaying,
    required this.onDownload,
    required this.onPreview,
    required this.onUseGeneral,
    required this.onUseFajr,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final downloading = progress != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: isPlaying ? 'إيقاف' : 'استماع',
                  icon: Icon(isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded),
                  onPressed: onPreview,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(adhan.nameAr, style: text.titleSmall),
                      Text(
                        downloaded ? '${adhan.noteAr} · محمّل ✓' : adhan.noteAr,
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (downloaded)
                  IconButton(
                    tooltip: 'حذف الملف',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (downloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: progress! > 0 ? progress : null),
                  const SizedBox(height: 4),
                  Text(
                    'جارٍ التحميل ${QuranUiUtils.toArabicDigits((progress! * 100).round())}٪',
                    style: text.bodySmall,
                  ),
                ],
              )
            else if (!downloaded)
              FilledButton.icon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('تحميل لاستخدامه وقت الصلاة'),
                onPressed: onDownload,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilterChip(
                    label: const Text('للصلوات'),
                    selected: isGeneral,
                    onSelected: (_) => onUseGeneral(),
                    selectedColor: scheme.primaryContainer,
                  ),
                  FilterChip(
                    label: const Text('للفجر'),
                    selected: isFajr,
                    onSelected: (_) => onUseFajr(),
                    selectedColor: scheme.primaryContainer,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
