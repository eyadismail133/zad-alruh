import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_alruh/src/features/hisn/data/hisn_repository_impl.dart';
import 'package:zad_alruh/src/features/hisn/domain/repositories/hisn_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List realJsonBytes;
  late HisnRepository realRepository;

  setUpAll(() async {
    final file = File('assets/content/hisn/hisn-muslim.json');
    expect(await file.exists(), isTrue, reason: 'Hisn JSON asset must exist');
    realJsonBytes = await file.readAsBytes();
    realRepository = HisnRepositoryImpl.fromBytes(realJsonBytes);
  });

  group('Hisn al-Muslim Corpus Integrity & Metadata', () {
    test('bundled JSON parses exactly 267 items across 132 chapters with 300 footnotes', () {
      expect(realRepository.count, 267);
      expect(realRepository.chaptersCount, 132);
      expect(realRepository.allItems.length, 267);
      expect(realRepository.allChapters.length, 132);

      final meta = realRepository.metadata;
      expect(meta.totalChapters, 132);
      expect(meta.totalItems, 267);
      expect(meta.totalFootnotes, 300);
      expect(meta.author, contains('سعيد بن علي بن وهف القحطاني'));
      expect(meta.source, 'https://islamhouse.com/ar/books/2522');
      expect(meta.sourceEn, 'https://islamhouse.com/en/books/2522');
      expect(meta.language, 'العربية');
      expect(meta.edition, contains('كتاب حصن المسلم word'));
      expect(
        meta.sourceDocxSha256,
        '7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a',
      );
    });

    test('all 132 chapters are numbered sequentially 1..132 with non-empty titles', () {
      for (int i = 0; i < realRepository.allChapters.length; i++) {
        final chapter = realRepository.allChapters[i];
        expect(chapter.number, i + 1);
        expect(chapter.title.trim().isNotEmpty, isTrue);
        expect(chapter.itemsCount, chapter.itemIds.length);
        expect(chapter.itemsCount > 0, isTrue);
      }
    });

    test('all 267 items are numbered sequentially 1..267 with non-empty essential fields', () {
      int totalFootnotes = 0;
      for (int i = 0; i < realRepository.allItems.length; i++) {
        final item = realRepository.allItems[i];
        expect(item.id, i + 1);
        expect(item.number, i + 1);
        expect(item.chapterNumber >= 1 && item.chapterNumber <= 132, isTrue);
        expect(item.chapterTitle.trim().isNotEmpty, isTrue);
        expect(item.text.trim().isNotEmpty, isTrue);
        expect(item.paragraphs.isNotEmpty, isTrue);
        expect(item.footnotes.isNotEmpty, isTrue, reason: 'Item ${item.id} must have footnotes');
        totalFootnotes += item.footnotes.length;
      }
      expect(totalFootnotes, 300);
    });
  });

  group('Sample Earliest, Morning/Evening, and Final Entries', () {
    test('item 1 (earliest) matches verbatim source text and footnote 16', () {
      final item1 = realRepository.getById(1);
      expect(item1, isNotNull);
      expect(item1!.number, 1);
      expect(item1.chapterNumber, 1);
      expect(item1.chapterTitle, 'أَذْكَارُ الاسْـــتِيقَاظِ مِنَ النَّـــومِ');
      expect(item1.text, contains('الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا'));
      expect(item1.repeatTarget, isNull);
      expect(item1.footnotes.length, 1);
      expect(item1.footnotes.first.id, '16');
      expect(item1.footnotes.first.text, contains('البخاري مع الفتح'));
      expect(item1.footnotes.first.text, contains('6314'));
      expect(item1.footnotes.first.text, contains('مسلم'));
    });

    test('morning and evening section (Chapter 27, items 75..98) integrity', () {
      final chapter27 = realRepository.getChapter(27);
      expect(chapter27, isNotNull);
      expect(chapter27!.title, 'أَذْكَارُ الصَّـــبَاحِ وَالْمَسَــــاءِ');
      expect(chapter27.itemsCount, 24);
      expect(chapter27.itemIds.first, 75);
      expect(chapter27.itemIds.last, 98);

      final items27 = realRepository.getItemsByChapter(27);
      expect(items27.length, 24);

      // Item 75 has introductory preamble as first paragraph and footnote 101
      final item75 = realRepository.getById(75);
      expect(item75, isNotNull);
      expect(item75!.paragraphs.length, 2);
      expect(item75.paragraphs.first, contains('الْحَمْدُ لِلَّهِ وَحْدَهُ'));
      expect(item75.text, contains('الْحَمْدُ لِلَّهِ وَحْدَهُ'));
      expect(item75.text, contains('أَعُوذُ بِاللَّهِ مِنَ الشَّيطَانِ الرَّجِيمِ'));
      expect(item75.text, contains('اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ الْحَيُّ الْقَيُّومُ'));
      expect(item75.footnotes.first.id, '101');
      expect(item75.footnotes.first.text, contains('أبو داود'));

      // Item 76 has 3 repetitions explicitly stated
      final item76 = realRepository.getById(76);
      expect(item76, isNotNull);
      expect(item76!.repeatTarget, 3);
      expect(item76.text, contains('قُلْ هُوَ اللَّهُ أَحَدٌ'));
      expect(item76.text, contains('ثلاثَ مرَّاتٍ'));

      // Item 80 has 4 repetitions explicitly stated
      final item80 = realRepository.getById(80);
      expect(item80, isNotNull);
      expect(item80!.repeatTarget, 4);

      // Item 83 has 7 repetitions explicitly stated
      final item83 = realRepository.getById(83);
      expect(item83, isNotNull);
      expect(item83!.repeatTarget, 7);

      // Item 91 has 100 repetitions explicitly stated
      final item91 = realRepository.getById(91);
      expect(item91, isNotNull);
      expect(item91!.repeatTarget, 100);

      // Item 92 offers alternative options (10 or 1 upon laziness); badge is null while source text is preserved
      final item92 = realRepository.getById(92);
      expect(item92, isNotNull);
      expect(item92!.repeatTarget, isNull);
      expect(item92.text, contains('عشرَ مرَّات'));
      expect(item92.text, contains('مرَّةً واحدةً عندَ الكَسَلِ'));
    });

    test('post-prayer adhkar section (Chapter 25, items 66..73) integrity', () {
      final chapter25 = realRepository.getChapter(25);
      expect(chapter25, isNotNull);
      expect(chapter25!.title, 'الأَذْكَارُ بَعْــدَ السَّــلاَمِ مِنَ الصَّــلاَةِ');
      expect(chapter25.itemsCount, 8);
      expect(chapter25.itemIds.first, 66);
      expect(chapter25.itemIds.last, 73);

      // Item 66: only initial phrase أستغفر الله is repeated 3x; entire entry badge is null
      final item66 = realRepository.getById(66);
      expect(item66, isNotNull);
      expect(item66!.repeatTarget, isNull);
      expect(item66.text, contains('أَسْتَغْفِرُ اللَّهَ (ثَلاَثَاً)'));
      expect(item66.text, contains('اللَّهُمَّ أَنْتَ السَّلاَمُ'));

      // Item 69: multi-part tasbih (33/33/33 + 1 tahlil); entire entry badge is null
      final item69 = realRepository.getById(69);
      expect(item69, isNotNull);
      expect(item69!.repeatTarget, isNull);
      expect(item69.text, contains('ثلاثاً وثلاثين'));

      // Item 72: single dhikr formula repeated 10 times after Maghrib & Fajr; badge is 10
      final item72 = realRepository.getById(72);
      expect(item72, isNotNull);
      expect(item72!.repeatTarget, 10);
    });

    test('item 267 (final) matches verbatim source text, 2 paragraphs, and footnote 315', () {
      final item267 = realRepository.getById(267);
      expect(item267, isNotNull);
      expect(item267!.number, 267);
      expect(item267.chapterNumber, 132);
      expect(item267.chapterTitle, 'مِنْ أَنْوَاعِ الْخَيْرِ وَالآدَابِ الْجَامِعَةِ');
      expect(item267.paragraphs.length, 2);
      expect(item267.footnotes.length, 1);
      expect(item267.footnotes[0].id, '315');
      expect(item267.footnotes[0].text, contains('البخاري مع الفتح'));
      expect(item267.footnotes[0].text, contains('5623'));
      expect(item267.footnotes[0].text, contains('2012'));
      expect(item267.text, contains('إِذَا كَانَ جُنْحُ اللَّيْلِ'));
      expect(item267.text, contains('وَصَلَّى اللَّهُ وَسَلَّمَ وَبَارَكَ عَلَى نَبِيِّنَا مُحَمَّدٍ'));
    });
  });

  group('Continuation Paragraphs Verification', () {
    test('multi-paragraph items preserve all continuation text and footnotes', () {
      // Item 19: دعاء الذهاب إلى المسجد
      final item19 = realRepository.getById(19)!;
      expect(item19.paragraphs.length, 2);
      expect(item19.footnotes.length, 4);
      expect(item19.footnoteIds, ['34', '35', '36', '37']);
      expect(item19.text, contains('اللَّهُمَّ اجْعَلْ فِي قَلْبِي نُوراً'));
      expect(item19.text, contains('وَهَبْ لِي نُوراً عَلَى نُورٍ'));

      // Item 74: دعاء صلاة الاستخارة
      final item74 = realRepository.getById(74)!;
      expect(item74.paragraphs.length, 2);
      expect(item74.text, contains('فَلْيَرْكَعْ رَكْعَتَيْنِ'));
      expect(item74.text, contains('اللَّهُمَّ إِنِّي أَسْتَخِيرُكَ بِعِلْمِكَ'));

      // Item 114: ما يفعل من رأى الرؤيا أو الحلم (multi-step action across 4 paragraphs; badge is null)
      final item114 = realRepository.getById(114)!;
      expect(item114.paragraphs.length, 4);
      expect(item114.repeatTarget, isNull);
      expect(item114.footnotes.length, 4);

      // Item 133: دعاء من أصابه وسوسة في الإيمان
      final item133 = realRepository.getById(133)!;
      expect(item133.paragraphs.length, 2);

      // Item 160: الدعاء للفرط في الصلاة عليه
      final item160 = realRepository.getById(160)!;
      expect(item160.paragraphs.length, 2);

      // Item 162: دعاء التعزية
      final item162 = realRepository.getById(162)!;
      expect(item162.paragraphs.length, 2);
    });
  });

  group('Explicit Repetition Target Rule Verification & Ambiguous Cases', () {
    test('reviewed whitelist contains exactly 17 unambiguous items and 250 null items', () {
      final targetCounts = <int, int>{};
      int nullCount = 0;

      for (final item in realRepository.allItems) {
        if (item.repeatTarget != null) {
          targetCounts[item.repeatTarget!] = (targetCounts[item.repeatTarget!] ?? 0) + 1;
        } else {
          nullCount++;
        }
      }

      // Exactly 17 items qualify for a single overall repetition badge
      expect(targetCounts.values.reduce((a, b) => a + b), 17);
      expect(nullCount, 250);

      // Exact count distribution
      expect(targetCounts[3], 9);     // Items 33, 41, 76, 82, 86, 87, 94, 97, 130
      expect(targetCounts[4], 1);     // Item 80
      expect(targetCounts[7], 2);     // Items 83, 148
      expect(targetCounts[10], 2);    // Items 72, 98
      expect(targetCounts[100], 3);   // Items 91, 93, 96
      expect(targetCounts.containsKey(33), isFalse); // Item 69 & 106 are compound/multi-part
    });

    test('straightforward positive items have exact expected counter badge targets', () {
      // Item 33: دعاء الركوع (سبحان ربي العظيم 3 مرات)
      final item33 = realRepository.getById(33)!;
      expect(item33.repeatTarget, 3);
      expect(item33.text, contains('سُبْحانَ رَبِّيَ الْعَظِيمِ'));

      // Item 41: دعاء السجود (سبحان ربي الأعلى 3 مرات)
      final item41 = realRepository.getById(41)!;
      expect(item41.repeatTarget, 3);
      expect(item41.text, contains('سُبْحَانَ رَبِّيَ الأَعْلَى'));

      // Item 72: بعد صلاة المغرب والصبح (10 مرات)
      final item72 = realRepository.getById(72)!;
      expect(item72.repeatTarget, 10);

      // Item 76: المعوذات (3 مرات)
      final item76 = realRepository.getById(76)!;
      expect(item76.repeatTarget, 3);

      // Item 80: اللهم إني أصبحت أشهدك (4 مرات)
      final item80 = realRepository.getById(80)!;
      expect(item80.repeatTarget, 4);

      // Item 83: حسبي الله لا إله إلا هو (7 مرات)
      final item83 = realRepository.getById(83)!;
      expect(item83.repeatTarget, 7);

      // Item 91: سبحان الله وبحمده (100 مرة)
      final item91 = realRepository.getById(91)!;
      expect(item91.repeatTarget, 100);

      // Item 148: الدعاء للمريض (7 مرات)
      final item148 = realRepository.getById(148)!;
      expect(item148.repeatTarget, 7);
      expect(item148.text, contains('أَسْأَلُ اللَّهَ الْعَظيمَ رَبَّ الْعَرْشِ الْعَظِيمِ أَنْ يَشْفيَكَ'));
    });

    test('ambiguous, multi-part, action, and narrative entries have null badge while preserving source text', () {
      // Item 66: Partial repetition (Astaghfirullah 3x, dua continues)
      final item66 = realRepository.getById(66)!;
      expect(item66.repeatTarget, isNull);
      expect(item66.text, contains('أَسْتَغْفِرُ اللَّهَ (ثَلاَثَاً)'));

      // Item 67: Partial repetition (only initial formula marked [ثلاثاً])
      final item67 = realRepository.getById(67)!;
      expect(item67.repeatTarget, isNull);
      expect(item67.text, contains('[ثلاثاً]'));

      // Item 69: Multi-part (33x Tasbih, 33x Tahmid, 33x Takbir, 1x Tahlil)
      final item69 = realRepository.getById(69)!;
      expect(item69.repeatTarget, isNull);
      expect(item69.text, contains('ثلاثاً وثلاثين'));

      // Item 92: Alternative options (10 or 1 upon laziness)
      final item92 = realRepository.getById(92)!;
      expect(item92.repeatTarget, isNull);
      expect(item92.text, contains('عشرَ مرَّات'));
      expect(item92.text, contains('مرَّةً واحدةً عندَ الكَسَلِ'));

      // Item 99: Narrative action sequence (cupping hands, blowing, wiping 3x)
      final item99 = realRepository.getById(99)!;
      expect(item99.repeatTarget, isNull);
      expect(item99.text, contains('يفعلُ ذلك ثلاثَ مرَّاتٍ'));

      // Item 102: Count in footnote is for dusting the bed, not the dua
      final item102 = realRepository.getById(102)!;
      expect(item102.repeatTarget, isNull);
      expect(item102.footnotes.first.text, contains('ثلاث مرات'));

      // Item 106: Compound counts (33 Tasbih, 33 Tahmid, 34 Takbir)
      final item106 = realRepository.getById(106)!;
      expect(item106.repeatTarget, isNull);
      expect(item106.text, contains('ثلاثاً وثلاثين'));
      expect(item106.text, contains('أربعاً وثلاثينَ'));

      // Item 114: Multi-step action across 4 paragraphs
      final item114 = realRepository.getById(114)!;
      expect(item114.repeatTarget, isNull);

      // Item 119: 3rd repeat has modified wording and vocalization
      final item119 = realRepository.getById(119)!;
      expect(item119.repeatTarget, isNull);
      expect(item119.text, contains('والثَّالِثَةُ يَجْهَرُ بها'));

      // Item 138: Action count for dry-spitting 3x to the left
      final item138 = realRepository.getById(138)!;
      expect(item138.repeatTarget, isNull);
      expect(item138.text, contains('وَاتْفُلْ عَلَى يَسَارِكَ (ثلاثاً)'));

      // Items 195, 249, 253: Prophetic report/narration rather than simple invocation count
      expect(realRepository.getById(195)!.repeatTarget, isNull);
      expect(realRepository.getById(249)!.repeatTarget, isNull);
      expect(realRepository.getById(253)!.repeatTarget, isNull);

      // Item 236: Long Hajj narrative account with repeated segments
      expect(realRepository.getById(236)!.repeatTarget, isNull);

      // Item 243: Multi-part (Bismillah 3x, supplication 7x)
      final item243 = realRepository.getById(243)!;
      expect(item243.repeatTarget, isNull);
      expect(item243.text, contains('بِسْمِ اللَّهِ، ثَلاَثاً'));
      expect(item243.text, contains('وَقُلْ سَبْعَ مَرَّاتٍ'));

      // Items 254 & 255: Hadith virtue narrations
      expect(realRepository.getById(254)!.repeatTarget, isNull);
      expect(realRepository.getById(255)!.repeatTarget, isNull);
    });
  });

  group('Search Functionality', () {
    test('exact numeric ID search returns specific item directly', () {
      final results = realRepository.search('75');
      expect(results.isNotEmpty, isTrue);
      expect(results.first.id, 75);

      final resultsArabic = realRepository.search('٧٥');
      expect(resultsArabic.isNotEmpty, isTrue);
      expect(resultsArabic.first.id, 75);
    });

    test('search by chapter title returns all chapter items', () {
      final results = realRepository.search('الاستيقاظ');
      expect(results.length, greaterThanOrEqualTo(4));
      expect(results.any((it) => it.id == 1), isTrue);
    });

    test('search with Arabic normalization ignores diacritics', () {
      final withTashkeel = realRepository.search('الْحَمْدُ للَّهِ');
      final withoutTashkeel = realRepository.search('الحمد لله');
      expect(withTashkeel.isNotEmpty, isTrue);
      expect(withoutTashkeel.isNotEmpty, isTrue);
      expect(withTashkeel.length, withoutTashkeel.length);
    });

    test('search by footnote citation matches relevant adhkar', () {
      final results = realRepository.search('صحيح الترمذي');
      expect(results.isNotEmpty, isTrue);
    });

    test('empty or whitespace query returns all 267 items', () {
      expect(realRepository.search('').length, 267);
      expect(realRepository.search('   ').length, 267);
    });

    test('non-matching query returns empty list', () {
      expect(realRepository.search('كلمةغيرموجودةأبداً١٢٣').isEmpty, isTrue);
    });
  });

  group('HisnValidationException Security & Tampering Checks', () {
    test('corrupted SHA-256 in fromBytes throws HisnValidationException', () {
      final corruptedBytes = Uint8List.fromList(realJsonBytes);
      corruptedBytes[corruptedBytes.length - 1] ^= 0xFF;

      expect(
        () => HisnRepositoryImpl.fromBytes(corruptedBytes, verifySha: true),
        throwsA(isA<HisnValidationException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256 mismatch'),
        )),
      );
    });

    test('tampered chapters count throws HisnValidationException', () {
      final jsonMap = jsonDecode(utf8.decode(realJsonBytes)) as Map<String, dynamic>;
      final meta = jsonMap['metadata'] as Map<String, dynamic>;
      meta['total_chapters'] = 131;
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(jsonMap)));

      expect(
        () => HisnRepositoryImpl.fromBytes(tamperedBytes, verifySha: false),
        throwsA(isA<HisnValidationException>().having(
          (e) => e.message,
          'message',
          contains('Metadata total_chapters mismatch'),
        )),
      );
    });

    test('tampered items count throws HisnValidationException', () {
      final jsonMap = jsonDecode(utf8.decode(realJsonBytes)) as Map<String, dynamic>;
      final meta = jsonMap['metadata'] as Map<String, dynamic>;
      meta['total_items'] = 266;
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(jsonMap)));

      expect(
        () => HisnRepositoryImpl.fromBytes(tamperedBytes, verifySha: false),
        throwsA(isA<HisnValidationException>().having(
          (e) => e.message,
          'message',
          contains('Metadata total_items mismatch'),
        )),
      );
    });

    test('duplicate item ID throws HisnValidationException', () {
      final jsonMap = jsonDecode(utf8.decode(realJsonBytes)) as Map<String, dynamic>;
      final items = jsonMap['items'] as List<dynamic>;
      final secondItem = Map<String, dynamic>.from(items[1] as Map<String, dynamic>);
      secondItem['id'] = 1;
      items[1] = secondItem;
      final tamperedBytes = Uint8List.fromList(utf8.encode(jsonEncode(jsonMap)));

      expect(
        () => HisnRepositoryImpl.fromBytes(tamperedBytes, verifySha: false),
        throwsA(isA<HisnValidationException>().having(
          (e) => e.message,
          'message',
          contains('Duplicate item ID'),
        )),
      );
    });
  });
}
