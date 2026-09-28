import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Pinned canonical SHA-256 for official IslamHouse Hisn al-Muslim DOCX source
/// Downloaded from https://islamhouse.com/ar/books/2522 (dated 2019-05-02)
const String kExpectedHisnSourceSha256 =
    '7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a';

const int kExpectedHisnChaptersCount = 132;
const int kExpectedHisnItemsCount = 267;
const int kExpectedHisnFootnotesCount = 300;

String sha256Bytes(List<int> bytes) {
  return sha256.convert(bytes).toString().toLowerCase();
}

String sha256File(String filePath) {
  final file = File(filePath);
  return sha256Bytes(file.readAsBytesSync());
}

String extractParagraphText(XmlElement pElem) {
  final buffer = StringBuffer();
  for (final node in pElem.descendantElements) {
    if (node.name.local == 't') {
      buffer.write(node.innerText);
    } else if (node.name.local == 'br') {
      buffer.write('\n');
    } else if (node.name.local == 'tab') {
      buffer.write('\t');
    } else if (node.name.local == 'sym') {
      final charHex = node.getAttribute('w:char');
      if (charHex != null && charHex.isNotEmpty) {
        try {
          final codePoint = int.parse(charHex, radix: 16);
          buffer.write(String.fromCharCode(codePoint));
        } catch (_) {}
      }
    }
  }
  return buffer.toString();
}

List<String> extractParagraphFootnoteRefs(XmlElement pElem) {
  final refs = <String>[];
  for (final node in pElem.descendantElements) {
    if (node.name.local == 'footnoteReference') {
      final id = node.getAttribute('w:id');
      if (id != null && id.isNotEmpty) {
        refs.add(id);
      }
    }
  }
  return refs;
}

/// Reviewed whitelist of items where exactly one explicit, unambiguous repetition
/// count applies to the entire displayed entry as an appropriate single repetition badge.
///
/// In Hisn al-Muslim, permissive regex extraction incorrectly flagged entries with
/// multi-part, partial, action, or narrative repetition references.
///
/// Items deliberately set to null with full source text and footnotes preserved:
/// - Item 66: Partial repetition (only initial 'أستغفر الله' is repeated 3 times; 'اللهم أنت السلام...' is said once).
/// - Item 67: Partial repetition (only initial sentence marked '[ثلاثاً]', subsequent sentences said once).
/// - Item 69: Multi-part formula (Tasbih 33x, Tahmid 33x, Takbir 33x, plus concluding Tahlil 1x to complete 100).
/// - Item 92: Alternative options ('عشر مرات' or 'مرة واحدة عند الكسل').
/// - Item 99: Action/ritual sequence narration ('يجمع كفيه ثم ينفث... يفعل ذلك ثلاث مرات').
/// - Item 102: Action in footnote (dusting bed 'ثلاث مرات', not the supplication utterance).
/// - Item 106: Multi-part compound count (Tasbih 33x, Tahmid 33x, Takbir 34x).
/// - Item 114: Multi-part action sequence across 4 paragraphs with distinct counts.
/// - Item 119: Modified repeat (3 times, with 3rd having unique vocalization and appended phrase).
/// - Item 138: Action count (dry-spitting 3 times to the left).
/// - Item 195: Prophetic practice report (counted 100 times in a single gathering).
/// - Item 236: Long Hajj narrative account with repeated segments at Safa and Marwah.
/// - Item 243: Multi-part (Bismillah 3 times, supplication 7 times).
/// - Items 249 & 253: Prophetic practice reports (repents / seeks forgiveness 100 times daily).
/// - Items 254 & 255: Hadith narrations stating virtues/rewards for repeating in a day.
///
/// Retained items (exactly 17):
/// - Item 33 (target 3): Ch 11 (دعاء الركوع) - ((سبحان ربي العظيم)) ثلاث مرات
/// - Item 41 (target 3): Ch 15 (دعاء السجود) - ((سبحان ربي الأعلى)) ثلاث مرات
/// - Item 72 (target 10): Ch 25 (أذكار بعد الصلاة) - Tahlil 10 times after Maghrib & Fajr
/// - Item 76 (target 3): Ch 27 (أذكار الصباح والمساء) - Mu'awwidhat 3 times
/// - Item 80 (target 4): Ch 27 (أذكار الصباح والمساء) - ((اللهم إني أصبحت أشهدك...)) 4 times
/// - Item 82 (target 3): Ch 27 (أذكار الصباح والمساء) - ((اللهم عافني في بدني...)) 3 times
/// - Item 83 (target 7): Ch 27 (أذكار الصباح والمساء) - ((حسبي الله لا إله إلا هو...)) 7 times
/// - Item 86 (target 3): Ch 27 (أذكار الصباح والمساء) - ((بسم الله الذي لا يضر...)) 3 times
/// - Item 87 (target 3): Ch 27 (أذكار الصباح والمساء) - ((رضيت بالله رباً...)) 3 times
/// - Item 91 (target 100): Ch 27 (أذكار الصباح والمساء) - ((سبحان الله وبحمده)) 100 times
/// - Item 93 (target 100): Ch 27 (أذكار الصباح والمساء) - Tahlil 100 times in morning
/// - Item 94 (target 3): Ch 27 (أذكار الصباح والمساء) - ((سبحان الله وبحمده: عدد خلقه...)) 3 times
/// - Item 96 (target 100): Ch 27 (أذكار الصباح والمساء) - ((أستغفر الله وأتوب إليه)) 100 times daily
/// - Item 97 (target 3): Ch 27 (أذكار الصباح والمساء) - ((أعوذ بكلمات الله التامات...)) 3 times in evening
/// - Item 98 (target 10): Ch 27 (أذكار الصباح والمساء) - ((اللهم صل وسلم على نبينا محمد)) 10 times
/// - Item 130 (target 3): Ch 37 (دعاء من خاف ظلم السلطان) - Supplication 3 times
/// - Item 148 (target 7): Ch 49 (الدعاء للمريض في عيادته) - Supplication 7 times
const Map<int, int> kReviewedRepeatTargets = {
  33: 3,
  41: 3,
  72: 10,
  76: 3,
  80: 4,
  82: 3,
  83: 7,
  86: 3,
  87: 3,
  91: 100,
  93: 100,
  94: 3,
  96: 100,
  97: 3,
  98: 10,
  130: 3,
  148: 7,
};

int? extractRepetitionTarget(int itemNumber, String bodyText, List<String> footnoteTexts) {
  return kReviewedRepeatTargets[itemNumber];
}

Map<String, dynamic> parseHisnFromXml({
  required String documentXml,
  required String footnotesXml,
  required String sourceDocxSha256,
}) {
  final fnDoc = XmlDocument.parse(footnotesXml);
  final footnotesMap = <String, String>{};
  for (final fn in fnDoc.findAllElements('w:footnote')) {
    final id = fn.getAttribute('w:id');
    final type = fn.getAttribute('w:type');
    if (id == null ||
        type == 'separator' ||
        type == 'continuationSeparator' ||
        type == 'continuationNotice') {
      continue;
    }
    final text = extractParagraphText(fn).trim();
    footnotesMap[id] = text;
  }

  final doc = XmlDocument.parse(documentXml);
  final body = doc.findAllElements('w:body').first;
  final paragraphs = body.findElements('w:p').toList();

  if (paragraphs.length != 577) {
    throw StateError(
      'Expected 577 paragraphs in source DOCX, found ${paragraphs.length}',
    );
  }

  final tocHeading = paragraphs[440];
  final tocText = extractParagraphText(tocHeading).trim();
  if (!tocText.contains('الفهرس')) {
    throw StateError('Expected TOC heading at paragraph 440, got "$tocText"');
  }

  final sectionRegExp = RegExp(r'^\s*(\d+)\s*[-–ـ]\s*(.+)$');
  final itemRegExp = RegExp(r'^\s*(\d+)\s*[-–ـ]');

  int currentChapNum = 0;
  String currentChapTitle = '';
  int currentItemNum = 0;

  final chapters = <int, Map<String, dynamic>>{};
  final items = <int, Map<String, dynamic>>{};
  final referencedFootnoteIds = <String>{};

  for (int pIdx = 30; pIdx < 440; pIdx++) {
    final pElem = paragraphs[pIdx];
    final style = pElem
        .findAllElements('w:pStyle')
        .firstOrNull
        ?.getAttribute('w:val');
    final rawText = extractParagraphText(pElem);
    final text = rawText.trim();
    final fnRefs = extractParagraphFootnoteRefs(pElem);

    if (style == '222') {
      final m = sectionRegExp.firstMatch(text);
      if (m != null) {
        currentChapNum = int.parse(m.group(1)!);
        currentChapTitle = m.group(2)!.trim();
        chapters[currentChapNum] = {
          'number': currentChapNum,
          'title': currentChapTitle,
          'item_ids': <int>[],
        };
      }
      continue;
    }

    if (text.isEmpty && fnRefs.isEmpty) {
      continue;
    }

    final m = itemRegExp.firstMatch(text);
    if (m != null) {
      currentItemNum = int.parse(m.group(1)!);
      if (items.containsKey(currentItemNum)) {
        if (currentItemNum == 75 && items[75] != null) {
          // Paragraph 133 was preamble; paragraph 134 is the 75-(1) body
          (items[75]!['paragraphs'] as List<String>).add(text);
          (items[75]!['footnote_ids'] as List<String>).addAll(fnRefs);
          referencedFootnoteIds.addAll(fnRefs);
          continue;
        }
        throw StateError(
          'Duplicate item number $currentItemNum at paragraph $pIdx',
        );
      }

      items[currentItemNum] = {
        'id': currentItemNum,
        'number': currentItemNum,
        'chapter_number': currentChapNum,
        'chapter_title': currentChapTitle,
        'paragraphs': <String>[text],
        'footnote_ids': <String>[...fnRefs],
      };
      (chapters[currentChapNum]!['item_ids'] as List<int>).add(currentItemNum);
      referencedFootnoteIds.addAll(fnRefs);
    } else {
      // Continuation paragraph or special case
      if (pIdx == 133) {
        // Special case: Introductory praise & hadith under Chapter 27, before Item 75
        currentItemNum = 75;
        items[75] = {
          'id': 75,
          'number': 75,
          'chapter_number': currentChapNum,
          'chapter_title': currentChapTitle,
          'paragraphs': <String>[text],
          'footnote_ids': <String>[...fnRefs],
        };
        (chapters[currentChapNum]!['item_ids'] as List<int>).add(75);
        referencedFootnoteIds.addAll(fnRefs);
      } else if (currentItemNum > 0 && items.containsKey(currentItemNum)) {
        (items[currentItemNum]!['paragraphs'] as List<String>).add(text);
        (items[currentItemNum]!['footnote_ids'] as List<String>).addAll(fnRefs);
        referencedFootnoteIds.addAll(fnRefs);
      } else {
        throw StateError(
          'Orphan unnumbered paragraph at $pIdx without preceding item: "$text"',
        );
      }
    }
  }

  if (chapters.length != kExpectedHisnChaptersCount) {
    throw StateError(
      'Expected $kExpectedHisnChaptersCount chapters, got ${chapters.length}',
    );
  }
  if (items.length != kExpectedHisnItemsCount) {
    throw StateError(
      'Expected $kExpectedHisnItemsCount items, got ${items.length}',
    );
  }
  for (int i = 1; i <= kExpectedHisnItemsCount; i++) {
    if (!items.containsKey(i)) {
      throw StateError('Missing item number $i in 1..$kExpectedHisnItemsCount');
    }
  }

  if (referencedFootnoteIds.length != kExpectedHisnFootnotesCount) {
    throw StateError(
      'Expected $kExpectedHisnFootnotesCount referenced footnotes, got ${referencedFootnoteIds.length}',
    );
  }

  // Construct structured item entries
  final structuredItems = <Map<String, dynamic>>[];
  for (int id = 1; id <= kExpectedHisnItemsCount; id++) {
    final rawItem = items[id]!;
    final paras = (rawItem['paragraphs'] as List<String>);
    final fnIds = (rawItem['footnote_ids'] as List<String>);
    final fnList = <Map<String, String>>[];

    for (final fnId in fnIds) {
      final fnText = footnotesMap[fnId];
      if (fnText == null || fnText.isEmpty) {
        throw StateError('Item $id references unresolved footnote $fnId');
      }
      fnList.add({'id': fnId, 'text': fnText});
    }

    final fullText = paras.join('\n\n');
    final repeatTarget = extractRepetitionTarget(
      id,
      fullText,
      fnList.map((e) => e['text']!).toList(),
    );

    structuredItems.add({
      'id': id,
      'number': id,
      'chapter_number': rawItem['chapter_number'],
      'chapter_title': rawItem['chapter_title'],
      'text': fullText,
      'paragraphs': paras,
      'footnote_ids': fnIds,
      'footnotes': fnList,
      'repeat_target': repeatTarget,
    });
  }

  final structuredChapters = <Map<String, dynamic>>[];
  for (int cNum = 1; cNum <= kExpectedHisnChaptersCount; cNum++) {
    final chap = chapters[cNum]!;
    final itemIds = chap['item_ids'] as List<int>;
    structuredChapters.add({
      'number': cNum,
      'title': chap['title'],
      'items_count': itemIds.length,
      'item_ids': itemIds,
    });
  }

  return {
    'metadata': {
      'title': 'حصن المسلم من أذكار الكتاب والسنة',
      'author': 'د. سعيد بن علي بن وهف القحطاني',
      'source': 'https://islamhouse.com/ar/books/2522',
      'source_en': 'https://islamhouse.com/en/books/2522',
      'api_terms':
          'https://github.com/IslamHouse-API/multilingual-quran-hadith-islamic-content-database-api-hub',
      'edition': 'كتاب حصن المسلم word (IslamHouse attachment 2019-05-02)',
      'language': 'العربية',
      'total_chapters': kExpectedHisnChaptersCount,
      'total_items': kExpectedHisnItemsCount,
      'total_footnotes': kExpectedHisnFootnotesCount,
      'source_docx_sha256': sourceDocxSha256,
      'acquisition_date': '2026-09-28',
    },
    'chapters': structuredChapters,
    'items': structuredItems,
  };
}

Future<void> main(List<String> args) async {
  String sourcePath = 'assets/content/hisn/hisn-muslim-source.docx';
  String outputPath = 'assets/content/hisn/hisn-muslim.json';

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--source' && i + 1 < args.length) {
      sourcePath = args[i + 1];
    } else if (args[i] == '--output' && i + 1 < args.length) {
      outputPath = args[i + 1];
    }
  }

  // Fallback to .local if assets not found yet
  if (!await File(sourcePath).exists() &&
      await File('.local/hisn-muslim-source.docx').exists()) {
    sourcePath = '.local/hisn-muslim-source.docx';
  }

  final sourceFile = File(sourcePath);
  if (!await sourceFile.exists()) {
    stderr.writeln('Source DOCX file not found at: $sourcePath');
    exit(1);
  }

  final actualSourceSha = sha256File(sourcePath);
  if (actualSourceSha != kExpectedHisnSourceSha256) {
    stderr.writeln('Source DOCX SHA-256 mismatch!');
    stderr.writeln('  Expected: $kExpectedHisnSourceSha256');
    stderr.writeln('  Actual:   $actualSourceSha');
    exit(1);
  }

  // Create temp dir to unpack XML files
  final tempDir = await Directory.systemTemp.createTemp('hisn_import_');
  try {
    final tarRes = await Process.run('tar.exe', [
      '-xf',
      p.canonicalize(sourcePath),
      '-C',
      tempDir.path,
      'word/document.xml',
      'word/footnotes.xml',
    ]);

    if (tarRes.exitCode != 0) {
      // Fallback: PowerShell Expand-Archive
      final psRes = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -LiteralPath "${p.canonicalize(sourcePath)}" -DestinationPath "${tempDir.path}" -Force',
      ]);
      if (psRes.exitCode != 0) {
        stderr.writeln('Failed to extract DOCX: ${tarRes.stderr}');
        exit(1);
      }
    }

    final docFile = File(p.join(tempDir.path, 'word', 'document.xml'));
    final fnFile = File(p.join(tempDir.path, 'word', 'footnotes.xml'));

    if (!await docFile.exists() || !await fnFile.exists()) {
      stderr.writeln('Extracted word/document.xml or word/footnotes.xml missing.');
      exit(1);
    }

    final documentXml = await docFile.readAsString();
    final footnotesXml = await fnFile.readAsString();

    final data = parseHisnFromXml(
      documentXml: documentXml,
      footnotesXml: footnotesXml,
      sourceDocxSha256: actualSourceSha,
    );

    final outputFile = File(outputPath);
    await outputFile.parent.create(recursive: true);

    final compactJson = jsonEncode(data);
    final jsonBytes = utf8.encode(compactJson);
    await outputFile.writeAsBytes(jsonBytes);

    final outputSha = sha256Bytes(jsonBytes);

    stdout.writeln('Hisn al-Muslim ingestion successful:');
    stdout.writeln('  Source path:   $sourcePath');
    stdout.writeln('  Source SHA:    $actualSourceSha');
    stdout.writeln('  Output path:   $outputPath');
    stdout.writeln('  Output SHA:    $outputSha');
    stdout.writeln('  Output size:   ${jsonBytes.length} bytes');
    stdout.writeln('  Chapters:      ${(data["chapters"] as List).length}');
    stdout.writeln('  Items:         ${(data["items"] as List).length}');
    stdout.writeln(
      '  Footnotes:     ${data["metadata"]["total_footnotes"]}',
    );
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }
}
