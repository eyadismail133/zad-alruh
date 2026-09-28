#!/usr/bin/env python3
"""
Hisn al-Muslim Arabic Corpus Ingestion Tool for Zad Alruh.

Extracts 267 sourced dhikr/dua items across 132 chapters from official IslamHouse
Hisn al-Muslim Word DOCX attachment (2019-05-02) and generates a deterministic,
compact JSON asset for offline bundling.

Source provenance:
- IslamHouse Listing: https://islamhouse.com/ar/books/2522 (and https://islamhouse.com/en/books/2522)
- Author: Dr. Saeed bin Ali bin Wahf Al-Qahtani (د. سعيد بن علي بن وهف القحطاني)
- Attachment: "كتاب حصن المسلم word" (DOCX 571.8 KB dated 2019-05-02)
- Expected Source SHA-256: 7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a
- Expected Chapters: 132
- Expected Items: 267
- Expected Footnotes: 300
"""

import argparse
import hashlib
import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

EXPECTED_SOURCE_SHA256 = "7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a"
EXPECTED_CHAPTERS_COUNT = 132
EXPECTED_ITEMS_COUNT = 267
EXPECTED_FOOTNOTES_COUNT = 300

NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
}


def sha256_file(filepath: str) -> str:
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest().lower()


def extract_node_text(elem) -> str:
    buf = []
    for node in elem.iter():
        tag = node.tag.split('}')[-1] if '}' in node.tag else node.tag
        if tag == 't':
            if node.text:
                buf.append(node.text)
        elif tag == 'br':
            buf.append('\n')
        elif tag == 'tab':
            buf.append('\t')
        elif tag == 'sym':
            char_hex = node.get(f"{{{NS['w']}}}char")
            if char_hex:
                try:
                    buf.append(chr(int(char_hex, 16)))
                except Exception:
                    pass
    return ''.join(buf)


def extract_footnote_refs(elem) -> list:
    refs = []
    for node in elem.iter():
        tag = node.tag.split('}')[-1] if '}' in node.tag else node.tag
        if tag == 'footnoteReference':
            fn_id = node.get(f"{{{NS['w']}}}id")
            if fn_id:
                refs.append(fn_id)
    return refs


# Reviewed whitelist of items where exactly one explicit, unambiguous repetition
# count applies to the entire displayed entry as an appropriate single repetition badge.
#
# In Hisn al-Muslim, permissive regex extraction incorrectly flagged entries with
# multi-part, partial, action, or narrative repetition references.
#
# Items deliberately set to null with full source text and footnotes preserved:
# - Item 66: Partial repetition (only initial 'أستغفر الله' is repeated 3 times; 'اللهم أنت السلام...' is said once).
# - Item 67: Partial repetition (only initial sentence marked '[ثلاثاً]', subsequent sentences said once).
# - Item 69: Multi-part formula (Tasbih 33x, Tahmid 33x, Takbir 33x, plus concluding Tahlil 1x to complete 100).
# - Item 92: Alternative options ('عشر مرات' or 'مرة واحدة عند الكسل').
# - Item 99: Action/ritual sequence narration ('يجمع كفيه ثم ينفث... يفعل ذلك ثلاث مرات').
# - Item 102: Action in footnote (dusting bed 'ثلاث مرات', not the supplication utterance).
# - Item 106: Multi-part compound count (Tasbih 33x, Tahmid 33x, Takbir 34x).
# - Item 114: Multi-part action sequence across 4 paragraphs with distinct counts.
# - Item 119: Modified repeat (3 times, with 3rd having unique vocalization and appended phrase).
# - Item 138: Action count (dry-spitting 3 times to the left).
# - Item 195: Prophetic practice report (counted 100 times in a single gathering).
# - Item 236: Long Hajj narrative account with repeated segments at Safa and Marwah.
# - Item 243: Multi-part (Bismillah 3 times, supplication 7 times).
# - Items 249 & 253: Prophetic practice reports (repents / seeks forgiveness 100 times daily).
# - Items 254 & 255: Hadith narrations stating virtues/rewards for repeating in a day.
#
# Retained items (exactly 17):
# - Item 33 (target 3): Ch 11 (دعاء الركوع) - ((سبحان ربي العظيم)) ثلاث مرات
# - Item 41 (target 3): Ch 15 (دعاء السجود) - ((سبحان ربي الأعلى)) ثلاث مرات
# - Item 72 (target 10): Ch 25 (أذكار بعد الصلاة) - Tahlil 10 times after Maghrib & Fajr
# - Item 76 (target 3): Ch 27 (أذكار الصباح والمساء) - Mu'awwidhat 3 times
# - Item 80 (target 4): Ch 27 (أذكار الصباح والمساء) - ((اللهم إني أصبحت أشهدك...)) 4 times
# - Item 82 (target 3): Ch 27 (أذكار الصباح والمساء) - ((اللهم عافني في بدني...)) 3 times
# - Item 83 (target 7): Ch 27 (أذكار الصباح والمساء) - ((حسبي الله لا إله إلا هو...)) 7 times
# - Item 86 (target 3): Ch 27 (أذكار الصباح والمساء) - ((بسم الله الذي لا يضر...)) 3 times
# - Item 87 (target 3): Ch 27 (أذكار الصباح والمساء) - ((رضيت بالله رباً...)) 3 times
# - Item 91 (target 100): Ch 27 (أذكار الصباح والمساء) - ((سبحان الله وبحمده)) 100 times
# - Item 93 (target 100): Ch 27 (أذكار الصباح والمساء) - Tahlil 100 times in morning
# - Item 94 (target 3): Ch 27 (أذكار الصباح والمساء) - ((سبحان الله وبحمده: عدد خلقه...)) 3 times
# - Item 96 (target 100): Ch 27 (أذكار الصباح والمساء) - ((أستغفر الله وأتوب إليه)) 100 times daily
# - Item 97 (target 3): Ch 27 (أذكار الصباح والمساء) - ((أعوذ بكلمات الله التامات...)) 3 times in evening
# - Item 98 (target 10): Ch 27 (أذكار الصباح والمساء) - ((اللهم صل وسلم على نبينا محمد)) 10 times
# - Item 130 (target 3): Ch 37 (دعاء من خاف ظلم السلطان) - Supplication 3 times
# - Item 148 (target 7): Ch 49 (الدعاء للمريض في عيادته) - Supplication 7 times
REVIEWED_REPEAT_TARGETS = {
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
}


def extract_repetition_target(item_id: int, body_text: str, footnote_texts: list):
    return REVIEWED_REPEAT_TARGETS.get(item_id)


def import_hisn(source_path: str, output_path: str) -> dict:
    if not os.path.isfile(source_path):
        raise FileNotFoundError(f"Source file not found: {source_path}")

    actual_source_sha = sha256_file(source_path)
    if actual_source_sha != EXPECTED_SOURCE_SHA256:
        raise ValueError(
            f"Source file SHA-256 mismatch!\n"
            f"Expected: {EXPECTED_SOURCE_SHA256}\n"
            f"Actual:   {actual_source_sha}"
        )

    with zipfile.ZipFile(source_path, 'r') as zf:
        doc_xml = zf.read('word/document.xml')
        fn_xml = zf.read('word/footnotes.xml')

    fn_tree = ET.fromstring(fn_xml)
    footnotes_map = {}
    for fn in fn_tree.findall(f".//{{{NS['w']}}}footnote"):
        fn_id = fn.get(f"{{{NS['w']}}}id")
        fn_type = fn.get(f"{{{NS['w']}}}type")
        if not fn_id or fn_type in ('separator', 'continuationSeparator', 'continuationNotice'):
            continue
        text = extract_node_text(fn).strip()
        footnotes_map[fn_id] = text

    doc_tree = ET.fromstring(doc_xml)
    body = doc_tree.find(f".//{{{NS['w']}}}body")
    paragraphs = body.findall(f"./{{{NS['w']}}}p")

    if len(paragraphs) != 577:
        raise ValueError(f"Expected 577 paragraphs in DOCX body, found {len(paragraphs)}")

    toc_heading = extract_node_text(paragraphs[440]).strip()
    if 'الفهرس' not in toc_heading:
        raise ValueError(f"Expected TOC heading at paragraph 440, got '{toc_heading}'")

    section_regex = re.compile(r'^\s*(\d+)\s*[-–ـ]\s*(.+)$')
    item_regex = re.compile(r'^\s*(\d+)\s*[-–ـ]')

    current_chap_num = 0
    current_chap_title = ''
    current_item_num = 0

    chapters = {}
    items = {}
    referenced_footnote_ids = set()

    for p_idx in range(30, 440):
        p_elem = paragraphs[p_idx]
        style_elem = p_elem.find(f".//{{{NS['w']}}}pStyle")
        style = style_elem.get(f"{{{NS['w']}}}val") if style_elem is not None else None
        raw_text = extract_node_text(p_elem)
        text = raw_text.strip()
        fn_refs = extract_footnote_refs(p_elem)

        if style == '222':
            m = section_regex.match(text)
            if m:
                current_chap_num = int(m.group(1))
                current_chap_title = m.group(2).strip()
                chapters[current_chap_num] = {
                    'number': current_chap_num,
                    'title': current_chap_title,
                    'item_ids': [],
                }
            continue

        if not text and not fn_refs:
            continue

        m = item_regex.match(text)
        if m:
            current_item_num = int(m.group(1))
            if current_item_num in items:
                if current_item_num == 75 and 75 in items:
                    items[75]['paragraphs'].append(text)
                    items[75]['footnote_ids'].extend(fn_refs)
                    referenced_footnote_ids.update(fn_refs)
                    continue
                raise ValueError(f"Duplicate item number {current_item_num} at paragraph {p_idx}")

            items[current_item_num] = {
                'id': current_item_num,
                'number': current_item_num,
                'chapter_number': current_chap_num,
                'chapter_title': current_chap_title,
                'paragraphs': [text],
                'footnote_ids': list(fn_refs),
            }
            chapters[current_chap_num]['item_ids'].append(current_item_num)
            referenced_footnote_ids.update(fn_refs)
        else:
            if p_idx == 133:
                current_item_num = 75
                items[75] = {
                    'id': 75,
                    'number': 75,
                    'chapter_number': current_chap_num,
                    'chapter_title': current_chap_title,
                    'paragraphs': [text],
                    'footnote_ids': list(fn_refs),
                }
                chapters[current_chap_num]['item_ids'].append(75)
                referenced_footnote_ids.update(fn_refs)
            elif current_item_num > 0 and current_item_num in items:
                items[current_item_num]['paragraphs'].append(text)
                items[current_item_num]['footnote_ids'].extend(fn_refs)
                referenced_footnote_ids.update(fn_refs)
            else:
                raise ValueError(f"Orphan unnumbered paragraph at {p_idx}: '{text}'")

    if len(chapters) != EXPECTED_CHAPTERS_COUNT:
        raise ValueError(f"Expected {EXPECTED_CHAPTERS_COUNT} chapters, got {len(chapters)}")
    if len(items) != EXPECTED_ITEMS_COUNT:
        raise ValueError(f"Expected {EXPECTED_ITEMS_COUNT} items, got {len(items)}")

    for i in range(1, EXPECTED_ITEMS_COUNT + 1):
        if i not in items:
            raise ValueError(f"Missing item number {i}")

    if len(referenced_footnote_ids) != EXPECTED_FOOTNOTES_COUNT:
        raise ValueError(f"Expected {EXPECTED_FOOTNOTES_COUNT} footnotes, got {len(referenced_footnote_ids)}")

    structured_items = []
    for item_id in range(1, EXPECTED_ITEMS_COUNT + 1):
        raw_item = items[item_id]
        paras = raw_item['paragraphs']
        fn_ids = raw_item['footnote_ids']
        fn_list = []

        for fn_id in fn_ids:
            fn_text = footnotes_map.get(fn_id)
            if not fn_text:
                raise ValueError(f"Item {item_id} references missing footnote {fn_id}")
            fn_list.append({'id': fn_id, 'text': fn_text})

        full_text = '\n\n'.join(paras)
        repeat_target = extract_repetition_target(item_id, full_text, [f['text'] for f in fn_list])

        structured_items.append({
            'id': item_id,
            'number': item_id,
            'chapter_number': raw_item['chapter_number'],
            'chapter_title': raw_item['chapter_title'],
            'text': full_text,
            'paragraphs': paras,
            'footnote_ids': fn_ids,
            'footnotes': fn_list,
            'repeat_target': repeat_target,
        })

    structured_chapters = []
    for c_num in range(1, EXPECTED_CHAPTERS_COUNT + 1):
        chap = chapters[c_num]
        item_ids = chap['item_ids']
        structured_chapters.append({
            'number': c_num,
            'title': chap['title'],
            'items_count': len(item_ids),
            'item_ids': item_ids,
        })

    payload = {
        'metadata': {
            'title': 'حصن المسلم من أذكار الكتاب والسنة',
            'author': 'د. سعيد بن علي بن وهف القحطاني',
            'source': 'https://islamhouse.com/ar/books/2522',
            'source_en': 'https://islamhouse.com/en/books/2522',
            'api_terms': 'https://github.com/IslamHouse-API/multilingual-quran-hadith-islamic-content-database-api-hub',
            'edition': 'كتاب حصن المسلم word (IslamHouse attachment 2019-05-02)',
            'language': 'العربية',
            'total_chapters': EXPECTED_CHAPTERS_COUNT,
            'total_items': EXPECTED_ITEMS_COUNT,
            'total_footnotes': EXPECTED_FOOTNOTES_COUNT,
            'source_docx_sha256': actual_source_sha,
            'acquisition_date': '2026-09-28',
        },
        'chapters': structured_chapters,
        'items': structured_items,
    }

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    compact_json = json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
    json_bytes = compact_json.encode('utf-8')

    with open(output_path, 'wb') as f:
        f.write(json_bytes)

    out_sha = hashlib.sha256(json_bytes).hexdigest().lower()
    return {
        'source_path': source_path,
        'source_sha256': actual_source_sha,
        'output_path': output_path,
        'output_sha256': out_sha,
        'output_bytes': len(json_bytes),
        'chapters_count': len(structured_chapters),
        'items_count': len(structured_items),
        'footnotes_count': len(referenced_footnote_ids),
    }


def main():
    if sys.platform == 'win32':
        sys.stdout.reconfigure(encoding='utf-8')

    parser = argparse.ArgumentParser(description="Import Hisn al-Muslim Word DOCX to JSON")
    parser.add_argument(
        '--source',
        default='assets/content/hisn/hisn-muslim-source.docx',
        help='Path to source DOCX file'
    )
    parser.add_argument(
        '--output',
        default='assets/content/hisn/hisn-muslim.json',
        help='Path to output JSON asset file'
    )
    args = parser.parse_args()

    print("Importing Hisn al-Muslim Corpus...")
    res = import_hisn(args.source, args.output)
    print("Import successful!")
    print(f"  Source:       {res['source_path']}")
    print(f"  Source SHA:   {res['source_sha256']}")
    print(f"  Output:       {res['output_path']}")
    print(f"  Output SHA:   {res['output_sha256']}")
    print(f"  Output size:  {res['output_bytes']:,} bytes")
    print(f"  Chapters:     {res['chapters_count']}")
    print(f"  Items:        {res['items_count']}")
    print(f"  Footnotes:    {res['footnotes_count']}")


if __name__ == '__main__':
    main()
