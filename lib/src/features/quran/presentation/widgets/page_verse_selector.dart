import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/sources/quran_asset_loader.dart';
import '../../domain/models/verse.dart';
import '../utils/quran_ui_utils.dart';

/// Selects a reference from the canonical image page without rendering verse text.
class PageVerseSelector extends ConsumerStatefulWidget {
  final List<Verse> verses;
  final Verse? initialVerse;
  final bool allowWholePage;
  final ValueChanged<Verse?> onChanged;

  const PageVerseSelector({
    super.key,
    required this.verses,
    this.initialVerse,
    this.allowWholePage = false,
    required this.onChanged,
  });

  @override
  ConsumerState<PageVerseSelector> createState() => _PageVerseSelectorState();
}

class _PageVerseSelectorState extends ConsumerState<PageVerseSelector> {
  late Verse _verse;
  late bool _wholePage;

  @override
  void initState() {
    super.initState();
    _verse = widget.verses.firstWhere(
      (v) => v.id == widget.initialVerse?.id,
      orElse: () => widget.verses.first,
    );
    _wholePage = widget.allowWholePage && widget.initialVerse == null;
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(quranRepositoryProvider).valueOrNull;
    final surahs = widget.verses.map((v) => v.surahNumber).toSet();
    final ayahs = widget.verses.where(
      (v) => v.surahNumber == _verse.surahNumber,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.allowWholePage)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('الصفحة كاملة'),
            value: _wholePage,
            onChanged: (value) {
              setState(() => _wholePage = value!);
              widget.onChanged(_wholePage ? null : _verse);
            },
          ),
        DropdownButtonFormField<int>(
          key: const ValueKey('page_verse_surah'),
          initialValue: _verse.surahNumber,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'السورة',
            border: OutlineInputBorder(),
          ),
          items: surahs
              .map(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    'سورة ${repository?.getSurah(s).name ?? QuranUiUtils.toArabicDigits(s)}',
                  ),
                ),
              )
              .toList(),
          onChanged: _wholePage
              ? null
              : (surah) {
                  setState(
                    () => _verse = widget.verses.firstWhere(
                      (v) => v.surahNumber == surah,
                    ),
                  );
                  widget.onChanged(_verse);
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('page_verse_ayah_${_verse.surahNumber}'),
          initialValue: _verse.id,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'رقم الآية',
            border: OutlineInputBorder(),
          ),
          items: ayahs
              .map(
                (v) => DropdownMenuItem(
                  value: v.id,
                  child: Text(
                    'الآية ${QuranUiUtils.toArabicDigits(v.verseNumber)}',
                  ),
                ),
              )
              .toList(),
          onChanged: _wholePage
              ? null
              : (id) {
                  setState(() => _verse = ayahs.firstWhere((v) => v.id == id));
                  widget.onChanged(_verse);
                },
        ),
      ],
    );
  }
}
