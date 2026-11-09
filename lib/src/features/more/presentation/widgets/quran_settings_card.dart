import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../quran/presentation/controllers/quran_reader_settings.dart';
import '../../../quran/presentation/widgets/mushaf_paper.dart';
import '../../../quran/presentation/widgets/reciter_picker.dart';

/// Mushaf reading and recitation preferences shown in the unified settings.
class QuranSettingsCard extends ConsumerWidget {
  const QuranSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paper = ref.watch(mushafPaperModeProvider);
    final keepOn = ref.watch(keepScreenOnProvider);
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Text('لون صفحة المصحف', style: text.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in MushafPaperMode.values)
                    ChoiceChip(
                      avatar: Icon(m.icon, size: 18),
                      label: Text(m.label),
                      selected: paper == m,
                      onSelected: (_) =>
                          ref.read(mushafPaperModeProvider.notifier).set(m),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              title: const Text('الشاشة تفضل منورة وأنا بقرأ'),
              value: keepOn,
              onChanged: (v) => ref.read(keepScreenOnProvider.notifier).set(v),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: ReciterPicker(),
            ),
          ],
        ),
      ),
    );
  }
}
