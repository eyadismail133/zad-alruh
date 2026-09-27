import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:zad_alruh/src/features/quran/data/parsers/quran_parser.dart';
import 'package:zad_alruh/src/features/quran/data/quran_repository.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_asset_loader.dart';
import 'package:zad_alruh/src/features/quran/data/sources/quran_source_verifier.dart';

void main() {
  late Uint8List textBytes;
  late Uint8List xmlBytes;
  late String textContent;
  late String xmlMetadataContent;
  late QuranRepository repo;

  setUpAll(() async {
    final textFile = File('assets/content/quran/quran-uthmani.txt');
    final xmlFile = File('assets/content/quran/quran-data.xml');

    textBytes = await textFile.readAsBytes();
    xmlBytes = await xmlFile.readAsBytes();
    textContent = utf8.decode(textBytes);
    xmlMetadataContent = utf8.decode(xmlBytes);

    repo = QuranRepository.fromBytes(textBytes: textBytes, xmlBytes: xmlBytes);
  });

  group('QuranRepository - Bundled Corpus Counts & Literal Boundaries', () {
    test('verifies exact 114 chapters and 6236 sequential verses', () {
      final surahs = repo.getSurahs();
      expect(surahs.length, 114);

      final verses = repo.getVerses();
      expect(verses.length, 6236);

      // Verify sequential numbering
      int globalIndex = 0;
      for (final s in surahs) {
        final surahVerses = repo.getVersesForSurah(s.number);
        expect(surahVerses.length, s.versesCount);
        for (int i = 0; i < surahVerses.length; i++) {
          final v = surahVerses[i];
          expect(v.surahNumber, s.number);
          expect(v.verseNumber, i + 1);
          expect(verses[globalIndex].id, v.id);
          globalIndex++;
        }
      }
      expect(globalIndex, 6236);
    });

    test('verifies contiguous 604 Medina Mushaf pages and 30 Juz', () {
      final pages = repo.getPages();
      expect(pages.length, 604);
      for (int i = 0; i < 604; i++) {
        expect(pages[i].pageNumber, i + 1);
        expect(repo.getPage(i + 1).pageNumber, i + 1);
      }

      final juzs = repo.getJuzs();
      expect(juzs.length, 30);
      for (int i = 0; i < 30; i++) {
        expect(juzs[i].number, i + 1);
        expect(repo.getJuz(i + 1).number, i + 1);
      }
    });

    test(
      'verifies first and last verse references with exact verbatim text',
      () {
        // 1:1 Al-Fatiha
        final firstVerse = repo.getVerse(1, 1);
        expect(firstVerse.surahNumber, 1);
        expect(firstVerse.verseNumber, 1);
        expect(firstVerse.pageNumber, 1);
        expect(firstVerse.juzNumber, 1);
        expect(firstVerse.text, 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ');

        // 114:6 An-Naas
        final lastVerse = repo.getVerse(114, 6);
        expect(lastVerse.surahNumber, 114);
        expect(lastVerse.verseNumber, 6);
        expect(lastVerse.pageNumber, 604);
        expect(lastVerse.juzNumber, 30);
        expect(lastVerse.text, 'مِنَ ٱلْجِنَّةِ وَٱلنَّاسِ');
      },
    );

    test('verifies Chapter 9 starts strictly at Page 187 Aya 1', () {
      final page187 = repo.getPage(187);
      expect(page187.startSurahNumber, 9);
      expect(page187.startVerseNumber, 1);

      final surah9Aya1 = repo.getVerse(9, 1);
      expect(surah9Aya1.pageNumber, 187);
      expect(surah9Aya1.juzNumber, 10);

      // Previous verse (8:75) must be on page 186
      final surah8Aya75 = repo.getVerse(8, 75);
      expect(surah8Aya75.pageNumber, 186);

      // Page 187 verses: 9:1 through 9:6
      final page187Verses = repo.getVersesForPage(187);
      expect(page187Verses.first.id, '9:1');
      expect(page187Verses.last.id, '9:6');
      expect(page187Verses.length, 6);

      // Page 188 starts at 9:7
      final page188 = repo.getPage(188);
      expect(page188.startSurahNumber, 9);
      expect(page188.startVerseNumber, 7);
    });

    test('verifies Page 604 boundaries and complete verse coverage', () {
      final page604 = repo.getPage(604);
      expect(page604.startSurahNumber, 112);
      expect(page604.startVerseNumber, 1);

      final page604Verses = repo.getVersesForPage(604);
      // Page 604 contains Surah 112 (4 ayas), Surah 113 (5 ayas), Surah 114 (6 ayas) = 15 verses
      expect(page604Verses.length, 15);
      expect(page604Verses.first.id, '112:1');
      expect(page604Verses.last.id, '114:6');

      for (final v in page604Verses) {
        expect(v.pageNumber, 604);
        expect(v.juzNumber, 30);
      }
    });

    test('verifies Juz 30 start boundary at Chapter 78 Aya 1', () {
      final juz30 = repo.getJuz(30);
      expect(juz30.startSurahNumber, 78);
      expect(juz30.startVerseNumber, 1);

      final surah78Aya1 = repo.getVerse(78, 1);
      expect(surah78Aya1.juzNumber, 30);
      expect(surah78Aya1.pageNumber, 582);

      // Previous verse (77:50) must belong to Juz 29
      final surah77Aya50 = repo.getVerse(77, 50);
      expect(surah77Aya50.juzNumber, 29);
      expect(surah77Aya50.pageNumber, 581);
    });

    test(
      'verifies every single verse maps to valid contiguous page and juz boundaries',
      () {
        final allVerses = repo.getVerses();
        for (final v in allVerses) {
          expect(v.pageNumber, inInclusiveRange(1, 604));
          expect(v.juzNumber, inInclusiveRange(1, 30));
          expect(v.text, isNotEmpty);
          expect(v.normalizedText, isNotEmpty);
        }
      },
    );
  });

  group('QuranRepository - Arabic Search & Verbatim Byte Preservation', () {
    test(
      'search finds matches while preserving exact original display bytes',
      () {
        final results = repo.search('الله');
        expect(results, isNotEmpty);

        final firstMatch = results.first;
        expect(firstMatch.id, '1:1');
        expect(firstMatch.text, 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ');
        expect(
          repo.getVerse(1, 1).text,
          'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
        );
      },
    );

    test(
      'search handles queries with or without diacritics and alef variants',
      () {
        final resultsNormalized = repo.search('اياك');
        final resultsOriginal = repo.search('إِيَّاكَ');

        expect(resultsNormalized, isNotEmpty);
        expect(resultsOriginal, isNotEmpty);
        expect(resultsNormalized.map((v) => v.id), contains('1:5'));
        expect(resultsOriginal.map((v) => v.id), contains('1:5'));

        final v15Normalized = resultsNormalized.firstWhere(
          (v) => v.id == '1:5',
        );
        final v15Original = resultsOriginal.firstWhere((v) => v.id == '1:5');
        expect(v15Normalized.text, 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ');
        expect(v15Original.text, 'إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ');
      },
    );

    test(
      'empty or whitespace-only search returns empty list and does not mutate repository',
      () {
        expect(repo.search(''), isEmpty);
        expect(repo.search('   '), isEmpty);
        expect(repo.getVerses().length, 6236);
      },
    );
  });

  group(
    'QuranRepository - Shared Pure-Dart Source Byte Verifier & Loader Boundary (Finding 1)',
    () {
      test(
        'QuranRepository.fromBytes loads successfully with genuine canonical assets',
        () {
          final r = QuranRepository.fromBytes(
            textBytes: textBytes,
            xmlBytes: xmlBytes,
          );
          expect(r.getSurahs().length, 114);
          expect(r.getVerses().length, 6236);
        },
      );

      test(
        'QuranRepository.fromBytes rejects altered verse text with same IDs/count at SHA-256 boundary before parsing',
        () {
          // Modify a single character in the verse text while retaining all 6236 lines and exact IDs
          final alteredText = textContent.replaceFirst(
            'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ',
            'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمُ', // altered final haraka
          );
          final alteredBytes = Uint8List.fromList(utf8.encode(alteredText));

          expect(
            () => QuranRepository.fromBytes(
              textBytes: alteredBytes,
              xmlBytes: xmlBytes,
            ),
            throwsA(
              isA<QuranValidationException>().having(
                (e) => e.message,
                'message',
                contains('Quran text SHA-256 hash mismatch'),
              ),
            ),
          );
        },
      );

      test(
        'QuranRepository.fromBytes rejects altered XML metadata bytes at SHA-256 boundary before parsing',
        () {
          final alteredXml = '$xmlMetadataContent ';
          final alteredBytes = Uint8List.fromList(utf8.encode(alteredXml));

          expect(
            () => QuranRepository.fromBytes(
              textBytes: textBytes,
              xmlBytes: alteredBytes,
            ),
            throwsA(
              isA<QuranValidationException>().having(
                (e) => e.message,
                'message',
                contains('Quran metadata SHA-256 hash mismatch'),
              ),
            ),
          );
        },
      );
    },
  );

  group('QuranParser - Page & Juz Boundary Integrity (Finding 2)', () {
    test(
      'rejects XML page boundary resolving to non-existent verse (e.g. Page 186 at 8:76)',
      () {
        // Sura 8 only has 75 ayas. Boundary 8:76 does not exist!
        // In Tanzil metadata, page 186 is: <page index="186" sura="8" aya="70" />
        // Mutating to 8:76 keeps it strictly before page 187 (9:1), but 8:76 is not in the corpus.
        final corruptXml = xmlMetadataContent.replaceFirst(
          '<page index="186" sura="8" aya="70" />',
          '<page index="186" sura="8" aya="76" />',
        );
        expect(corruptXml, isNot(equals(xmlMetadataContent)));

        expect(
          () => QuranParser.parse(
            textContent: textContent,
            xmlMetadataContent: corruptXml,
          ),
          throwsA(
            isA<QuranValidationException>().having(
              (e) => e.message,
              'message',
              contains(
                'Page 186 start boundary (8:76) does not resolve to an actual verse in the corpus',
              ),
            ),
          ),
        );
      },
    );

    test('rejects XML with first page not starting at 1:1', () {
      final corruptXml = xmlMetadataContent.replaceFirst(
        '<page index="1" sura="1" aya="1" />',
        '<page index="1" sura="1" aya="2" />',
      );
      expect(corruptXml, isNot(equals(xmlMetadataContent)));

      expect(
        () => QuranParser.parse(
          textContent: textContent,
          xmlMetadataContent: corruptXml,
        ),
        throwsA(
          isA<QuranValidationException>().having(
            (e) => e.message,
            'message',
            contains('First page must start at 1:1'),
          ),
        ),
      );
    });

    test('rejects XML with first juz not starting at 1:1', () {
      final corruptXml = xmlMetadataContent.replaceFirst(
        '<juz index="1" sura="1" aya="1" />',
        '<juz index="1" sura="1" aya="2" />',
      );
      expect(corruptXml, isNot(equals(xmlMetadataContent)));

      expect(
        () => QuranParser.parse(
          textContent: textContent,
          xmlMetadataContent: corruptXml,
        ),
        throwsA(
          isA<QuranValidationException>().having(
            (e) => e.message,
            'message',
            contains('First juz must start at 1:1'),
          ),
        ),
      );
    });

    test(
      'enforces every single page and juz is a non-empty interval matching trusted metadata boundaries',
      () {
        final pages = repo.getPages();
        expect(pages.length, 604);
        int totalPageVerses = 0;

        for (int p = 1; p <= 604; p++) {
          final page = repo.getPage(p);
          expect(page.pageNumber, p);
          final versesOnPage = repo.getVersesForPage(p);
          expect(versesOnPage, isNotEmpty);
          totalPageVerses += versesOnPage.length;

          // Verify the first verse on the page matches the metadata start boundary
          final firstVerse = versesOnPage.first;
          expect(firstVerse.surahNumber, page.startSurahNumber);
          expect(firstVerse.verseNumber, page.startVerseNumber);
          expect(firstVerse.pageNumber, p);

          // Verify all verses on this page are tagged with pageNumber p
          for (final v in versesOnPage) {
            expect(v.pageNumber, p);
          }
        }
        expect(totalPageVerses, 6236);

        final juzs = repo.getJuzs();
        expect(juzs.length, 30);
        int totalJuzVerses = 0;

        for (int j = 1; j <= 30; j++) {
          final juz = repo.getJuz(j);
          expect(juz.number, j);
          final versesInJuz = repo.getVersesForJuz(j);
          expect(versesInJuz, isNotEmpty);
          totalJuzVerses += versesInJuz.length;

          // Verify the first verse in the juz matches the metadata start boundary
          final firstVerse = versesInJuz.first;
          expect(firstVerse.surahNumber, juz.startSurahNumber);
          expect(firstVerse.verseNumber, juz.startVerseNumber);
          expect(firstVerse.juzNumber, j);

          // Verify all verses in this juz are tagged with juzNumber j
          for (final v in versesInJuz) {
            expect(v.juzNumber, j);
          }
        }
        expect(totalJuzVerses, 6236);
      },
    );
  });

  group(
    'QuranParser - Chapter Cumulative Start, Revelation Order, & Rukus (Finding 3)',
    () {
      test(
        'enforces cumulative preceding verse counts for chapter start (Chapter 2 start must be 7, not 8)',
        () {
          // Chapter 1 has 7 ayas, so Chapter 2 must start at index 7. Modify to 8.
          final corruptXml = xmlMetadataContent.replaceFirst(
            'start="7"',
            'start="8"',
          );

          expect(
            () => QuranParser.parse(
              textContent: textContent,
              xmlMetadataContent: corruptXml,
            ),
            throwsA(
              isA<QuranValidationException>().having(
                (e) => e.message,
                'message',
                contains('start index mismatch: expected cumulative 7'),
              ),
            ),
          );
        },
      );

      test('enforces unique revelation orders 1..114 across all chapters', () {
        // Modify sura 2 order from 87 to 5 (duplicate of sura 1 order 5)
        final corruptXml = xmlMetadataContent.replaceFirst(
          'order="87"',
          'order="5"',
        );

        expect(
          () => QuranParser.parse(
            textContent: textContent,
            xmlMetadataContent: corruptXml,
          ),
          throwsA(
            isA<QuranValidationException>().having(
              (e) => e.message,
              'message',
              contains('duplicate revelation order'),
            ),
          ),
        );
      });

      test('enforces positive ruku counts for all chapters', () {
        // Modify sura 1 rukus from 7 to 0
        final corruptXml = xmlMetadataContent.replaceFirst(
          'rukus="7"',
          'rukus="0"',
        );

        expect(
          () => QuranParser.parse(
            textContent: textContent,
            xmlMetadataContent: corruptXml,
          ),
          throwsA(
            isA<QuranValidationException>().having(
              (e) => e.message,
              'message',
              contains('ruku count must be positive'),
            ),
          ),
        );
      });
    },
  );

  group(
    'QuranParser - Verbatim Record Preservation without trimRight (Finding 4)',
    () {
      test(
        'preserves exact text field trailing whitespace on real asset record copy without trimming',
        () {
          // Create a modified copy of textContent where verse 1:1 has an intentional trailing tab and space
          // Record format: 1|1|بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ \n
          const targetPrefix = '1|1|بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ';
          const replacementWithWhitespace =
              '1|1|بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ \t ';
          final textWithWhitespace = textContent.replaceFirst(
            targetPrefix,
            replacementWithWhitespace,
          );

          final parsed = QuranParser.parse(
            textContent: textWithWhitespace,
            xmlMetadataContent: xmlMetadataContent,
          );

          final v11 = parsed.verses.first;
          // VERBATIM preservation contract: trailing whitespace in the text field is NOT trimmed!
          expect(v11.text, 'بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ \t ');
          expect(v11.text.endsWith(' \t '), isTrue);
        },
      );
    },
  );

  group('QuranRepository - Corrupt, Duplicate, Missing Records Rejection', () {
    test(
      'trailing license comments in source file are preserved and ignored while parsing',
      () {
        expect(
          textContent,
          contains('# PLEASE DO NOT REMOVE OR CHANGE THIS COPYRIGHT BLOCK'),
        );
        expect(repo.getVerses().length, 6236);
      },
    );

    test('rejects source with missing verse (e.g. 6235 verses)', () {
      final lines = textContent.split('\n');
      lines.removeWhere((l) => l.startsWith('1|2|'));
      final modifiedText = lines.join('\n');

      expect(
        () => QuranRepository.fromContent(
          textContent: modifiedText,
          xmlMetadataContent: xmlMetadataContent,
        ),
        throwsA(isA<QuranValidationException>()),
      );
    });

    test('rejects source with duplicate verse ID', () {
      final lines = textContent.split('\n');
      final index1 = lines.indexWhere((l) => l.startsWith('1|1|'));
      lines.insert(index1 + 1, '1|1|بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ');
      final modifiedText = lines.join('\n');

      expect(
        () => QuranRepository.fromContent(
          textContent: modifiedText,
          xmlMetadataContent: xmlMetadataContent,
        ),
        throwsA(isA<QuranValidationException>()),
      );
    });

    test('rejects source with out-of-order verse sequence', () {
      final lines = textContent.split('\n');
      final idx2 = lines.indexWhere((l) => l.startsWith('1|2|'));
      final idx3 = lines.indexWhere((l) => l.startsWith('1|3|'));
      final temp = lines[idx2];
      lines[idx2] = lines[idx3];
      lines[idx3] = temp;
      final modifiedText = lines.join('\n');

      expect(
        () => QuranRepository.fromContent(
          textContent: modifiedText,
          xmlMetadataContent: xmlMetadataContent,
        ),
        throwsA(isA<QuranValidationException>()),
      );
    });

    test('rejects corrupted XML metadata with mismatched sura aya count', () {
      final modifiedXml = xmlMetadataContent.replaceFirst(
        'ayas="7"',
        'ayas="8"',
      );

      expect(
        () => QuranRepository.fromContent(
          textContent: textContent,
          xmlMetadataContent: modifiedXml,
        ),
        throwsA(isA<QuranValidationException>()),
      );
    });
  });

  group(
    'QuranSourceVerifier & QuranAssetLoader - Canonical SHA & Bundle Boundary',
    () {
      test('QuranSourceVerifier.verifyBytes verifies genuine source bytes', () {
        final verified = QuranSourceVerifier.verifyBytes(
          textBytes: textBytes,
          xmlBytes: xmlBytes,
        );
        expect(verified.textContent, textContent);
        expect(verified.xmlMetadataContent, xmlMetadataContent);
      });

      test('QuranSourceVerifier rejects altered text bytes', () {
        final alteredTextBytes = Uint8List.fromList(textBytes);
        alteredTextBytes[0] = alteredTextBytes[0] ^ 0xFF;

        expect(
          () => QuranSourceVerifier.verifyBytes(
            textBytes: alteredTextBytes,
            xmlBytes: xmlBytes,
          ),
          throwsA(
            isA<QuranValidationException>().having(
              (e) => e.message,
              'message',
              contains('Quran text SHA-256 hash mismatch'),
            ),
          ),
        );
      });

      test('QuranSourceVerifier rejects altered XML metadata bytes', () {
        final alteredXmlBytes = Uint8List.fromList(xmlBytes);
        alteredXmlBytes[0] = alteredXmlBytes[0] ^ 0xFF;

        expect(
          () => QuranSourceVerifier.verifyBytes(
            textBytes: textBytes,
            xmlBytes: alteredXmlBytes,
          ),
          throwsA(
            isA<QuranValidationException>().having(
              (e) => e.message,
              'message',
              contains('Quran metadata SHA-256 hash mismatch'),
            ),
          ),
        );
      });

      test(
        'QuranAssetLoader loads repository using genuine AssetBundle bytes',
        () async {
          final bundle = _TestAssetBundle({
            QuranAssetLoader.textAssetPath: ByteData.sublistView(textBytes),
            QuranAssetLoader.xmlAssetPath: ByteData.sublistView(xmlBytes),
          });

          final repoFromLoader = await QuranAssetLoader.loadBundledRepository(
            bundle: bundle,
          );
          expect(repoFromLoader.getSurahs().length, 114);
          expect(repoFromLoader.getVerses().length, 6236);
        },
      );

      test(
        'QuranAssetLoader rejects altered text asset bytes from AssetBundle',
        () async {
          final alteredTextBytes = Uint8List.fromList(textBytes);
          alteredTextBytes[0] = alteredTextBytes[0] ^ 0xFF;

          final bundle = _TestAssetBundle({
            QuranAssetLoader.textAssetPath: ByteData.sublistView(
              alteredTextBytes,
            ),
            QuranAssetLoader.xmlAssetPath: ByteData.sublistView(xmlBytes),
          });

          expect(
            () => QuranAssetLoader.loadBundledRepository(bundle: bundle),
            throwsA(
              isA<QuranValidationException>().having(
                (e) => e.message,
                'message',
                contains('Quran text SHA-256 hash mismatch'),
              ),
            ),
          );
        },
      );

      test(
        'QuranAssetLoader rejects altered XML metadata asset bytes from AssetBundle',
        () async {
          final alteredXmlBytes = Uint8List.fromList(xmlBytes);
          alteredXmlBytes[0] = alteredXmlBytes[0] ^ 0xFF;

          final bundle = _TestAssetBundle({
            QuranAssetLoader.textAssetPath: ByteData.sublistView(textBytes),
            QuranAssetLoader.xmlAssetPath: ByteData.sublistView(
              alteredXmlBytes,
            ),
          });

          expect(
            () => QuranAssetLoader.loadBundledRepository(bundle: bundle),
            throwsA(
              isA<QuranValidationException>().having(
                (e) => e.message,
                'message',
                contains('Quran metadata SHA-256 hash mismatch'),
              ),
            ),
          );
        },
      );
    },
  );
}

class _TestAssetBundle extends AssetBundle {
  final Map<String, ByteData> _assets;
  _TestAssetBundle(this._assets);

  @override
  Future<ByteData> load(String key) async {
    final data = _assets[key];
    if (data == null) {
      throw Exception('Asset not found: $key');
    }
    return data;
  }
}
