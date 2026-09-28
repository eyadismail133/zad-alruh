#!/usr/bin/env python3
"""
HadeethEnc Arabic Corpus Ingestion Tool for Zad Alruh.

Extracts authentic ("صحيح") Hadith records from HadeethEnc official Arabic Excel export
(v1.7.0, 2025-11-12) and generates a deterministic, compact JSON asset for offline bundling.

Source provenance:
- Original download: https://hadeethenc.com/browse/download/ar
- Update check URL: https://hadeethenc.com/en/check/ar/v1.7.0
- Expected Source SHA-256: d5d397cb9fc8ddd54c4c6ee88357c2217721db0bd0759c6ec26d8b3fc36f1ec1
- Total workbook rows: 3582
- Sahih records: exactly 3213
"""

import argparse
import hashlib
import json
import os
import sys
import openpyxl

EXPECTED_SOURCE_SHA256 = "d5d397cb9fc8ddd54c4c6ee88357c2217721db0bd0759c6ec26d8b3fc36f1ec1"
EXPECTED_SAHIH_COUNT = 3213
EXPECTED_COLUMNS = [
    'id', 'title', 'hadith_text', 'explanation',
    'word_meanings', 'benefits', 'grade', 'takhrij', 'link'
]


def sha256_file(filepath: str) -> str:
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest().lower()


def import_hadith(source_path: str, output_path: str) -> dict:
    if not os.path.isfile(source_path):
        raise FileNotFoundError(f"Source file not found: {source_path}")

    actual_source_sha = sha256_file(source_path)
    if actual_source_sha != EXPECTED_SOURCE_SHA256:
        raise ValueError(
            f"Source file SHA-256 mismatch!\n"
            f"Expected: {EXPECTED_SOURCE_SHA256}\n"
            f"Actual:   {actual_source_sha}"
        )

    wb = openpyxl.load_workbook(source_path, read_only=True)
    sheet = wb.active

    a1_raw = sheet['A1'].value
    if not a1_raw or "v1.7.0" not in str(a1_raw):
        raise ValueError(f"Unexpected A1 metadata block: {a1_raw}")

    # Row 2 contains headers
    row2 = [cell.value for cell in sheet[2]]
    if row2[:len(EXPECTED_COLUMNS)] != EXPECTED_COLUMNS:
        raise ValueError(f"Header mismatch. Expected {EXPECTED_COLUMNS}, got {row2}")

    seen_ids = set()
    items = []

    for row_idx, row in enumerate(sheet.iter_rows(min_row=3, values_only=True), start=3):
        grade = row[6]
        if grade == 'صحيح':
            h_id, title, text, expl, words, benefits, gr, takhrij, link = row[:9]

            if h_id is None:
                raise ValueError(f"Row {row_idx}: Hadith ID is null")

            int_id = int(h_id)
            if int_id in seen_ids:
                raise ValueError(f"Duplicate Hadith ID: {int_id} at row {row_idx}")
            seen_ids.add(int_id)

            # Ensure essential columns are non-empty
            essential = {
                'id': int_id,
                'title': title,
                'hadith_text': text,
                'grade': gr,
                'takhrij': takhrij,
                'link': link,
            }
            for col_name, val in essential.items():
                if val is None or str(val).strip() == '':
                    raise ValueError(f"Row {row_idx} (ID {int_id}): Missing essential field '{col_name}'")

            items.append({
                'id': int_id,
                'title': str(title) if title is not None else '',
                'hadith_text': str(text) if text is not None else '',
                'explanation': str(expl) if expl is not None else '',
                'word_meanings': str(words) if words is not None else '',
                'benefits': str(benefits) if benefits is not None else '',
                'grade': str(gr) if gr is not None else '',
                'takhrij': str(takhrij) if takhrij is not None else '',
                'link': str(link) if link is not None else '',
            })

    if len(items) != EXPECTED_SAHIH_COUNT:
        raise ValueError(
            f"Expected {EXPECTED_SAHIH_COUNT} sahih records, but imported {len(items)}"
        )

    metadata = {
        'source': 'https://hadeethenc.com/ar',
        'download_url': 'https://hadeethenc.com/browse/download/ar',
        'check_url': 'https://hadeethenc.com/en/check/ar/v1.7.0',
        'edition': 'HadeethEnc Arabic v1.7.0 (2025-11-12)',
        'version': 'v1.7.0',
        'last_update': '2025-11-12 00:00:55',
        'language': 'العربية',
        'selection_grade': 'صحيح',
        'total_records': len(items),
        'raw_a1_block': a1_raw,
    }

    payload = {
        'metadata': metadata,
        'items': items,
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
        'records_count': len(items),
    }


def main():
    if sys.platform == 'win32':
        sys.stdout.reconfigure(encoding='utf-8')

    parser = argparse.ArgumentParser(description="Import HadeethEnc Arabic Excel to JSON")
    parser.add_argument(
        '--source',
        default='assets/content/hadith/hadeethenc-ar.xlsx',
        help='Path to source Excel file'
    )
    parser.add_argument(
        '--output',
        default='assets/content/hadith/hadith-enc-sahih.json',
        help='Path to output JSON asset file'
    )
    args = parser.parse_args()

    print("Importing HadeethEnc Arabic Corpus...")
    res = import_hadith(args.source, args.output)
    print("Import successful!")
    print(f"  Source:       {res['source_path']}")
    print(f"  Source SHA:   {res['source_sha256']}")
    print(f"  Output:       {res['output_path']}")
    print(f"  Output SHA:   {res['output_sha256']}")
    print(f"  Output size:  {res['output_bytes']:,} bytes")
    print(f"  Records:      {res['records_count']}")


if __name__ == '__main__':
    main()
