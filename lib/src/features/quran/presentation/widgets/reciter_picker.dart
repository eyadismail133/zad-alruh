import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/quran_reciter.dart';
import '../controllers/quran_reader_settings.dart';

/// Dropdown to choose the reciter used for full-surah streaming.
class ReciterPicker extends ConsumerWidget {
  const ReciterPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedReciterProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'القارئ: الشيخ ${selected.nameAr}',
          style: const TextStyle(
            fontFamily: AppTheme.uiFont,
            fontFamilyFallback: AppTheme.uiFontFallback,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: const ValueKey('quran_reciter_dropdown'),
          initialValue: selected.id,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.record_voice_over_outlined,
                size: 18, color: scheme.primary),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
          ),
          items: [
            for (final r in QuranReciter.all)
              DropdownMenuItem<String>(
                value: r.id,
                child: Text(
                  r.nameAr,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
          ],
          onChanged: (id) {
            if (id != null) {
              ref.read(selectedReciterIdProvider.notifier).set(id);
            }
          },
        ),
      ],
    );
  }
}
