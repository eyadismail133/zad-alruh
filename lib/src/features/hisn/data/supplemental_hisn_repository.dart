import '../../hadith/domain/models/hadith_item.dart';
import '../../hadith/domain/repositories/hadith_repository.dart';
import '../../quran/domain/utils/arabic_normalizer.dart';
import '../domain/models/hisn_chapter.dart';
import '../domain/models/hisn_invocation_catalog.dart';
import '../domain/models/hisn_item.dart';
import '../domain/models/hisn_metadata.dart';
import '../domain/repositories/hisn_repository.dart';

/// Supplements browsing without changing the canonical book or its counts.
class SupplementalHisnRepository extends HisnRepository {
  final HisnRepository hisn;
  @override
  final List<HisnItem> supplementalItems;

  SupplementalHisnRepository({
    required this.hisn,
    required HadithRepository hadiths,
  }) : supplementalItems = List.unmodifiable([
         for (final sourceId in {
           ...HisnInvocationCatalog.supplementalDuaHadithIds,
           ...HisnInvocationCatalog.supplementalDhikrHadithIds,
         })
           _fromHadith(
             hadiths.getById(sourceId) ??
                 (throw StateError(
                   'Missing supplemental source hadith $sourceId',
                 )),
           ),
       ]);

  static HisnItem _fromHadith(HadithItem source) => HisnItem(
    id: HisnInvocationCatalog.supplementalIdOffset + source.id,
    number: source.id,
    chapterNumber: 0,
    chapterTitle: source.title,
    text: source.hadithText,
    paragraphs: [source.hadithText],
    footnoteIds: ['hadeethenc:${source.id}'],
    footnotes: [
      HisnFootnote(
        id: 'hadeethenc:${source.id}',
        text: '${source.grade} — ${source.takhrij}\nHadeethEnc: ${source.link}',
      ),
    ],
    sourceHadithId: source.id,
    sourceUrl: source.link,
  );

  @override
  List<HisnItem> get allItems => hisn.allItems;
  @override
  List<HisnChapter> get allChapters => hisn.allChapters;
  @override
  HisnMetadata get metadata => hisn.metadata;
  @override
  HisnChapter? getChapter(int chapterNumber) => hisn.getChapter(chapterNumber);
  @override
  List<HisnItem> getItemsByChapter(int chapterNumber) =>
      hisn.getItemsByChapter(chapterNumber);

  @override
  HisnItem? getById(int id) {
    for (final entry in supplementalItems) {
      if (entry.id == id) return entry;
    }
    return hisn.getById(id);
  }

  @override
  List<HisnItem> search(String query) {
    final normalized = ArabicNormalizer.normalize(query.trim());
    final sourceId = ArabicNormalizer.parseArabicInt(query.trim());
    return [
      ...hisn.search(query),
      for (final entry in supplementalItems)
        if (normalized.isEmpty ||
            entry.number == sourceId ||
            entry.id == sourceId ||
            ArabicNormalizer.normalize(
              '${entry.chapterTitle} ${entry.text} ${entry.footnotes.first.text}',
            ).contains(normalized))
          entry,
    ];
  }
}
