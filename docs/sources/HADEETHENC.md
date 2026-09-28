# HadeethEnc Prophetic Hadith Corpus Provenance & Rights

Acquired on 2026-09-28 from the official HadeethEnc (موسوعة الأحاديث النبوية) Arabic download service.

| Asset | Source / Role | SHA-256 |
|---|---|---|
| `assets/content/hadith/hadeethenc-ar.xlsx` | Official Arabic Excel Export (Provenance) | `d5d397cb9fc8ddd54c4c6ee88357c2217721db0bd0759c6ec26d8b3fc36f1ec1` |
| `assets/content/hadith/hadith-enc-sahih.json` | Deterministic Offline JSON Bundle (3,213 Sahih Records) | `94a69dbdb44144d2dad2ba0a3fa1ee73c7f7b456c46d945ea15f4332a2eeeda7` |

---

## 1. Source Identification & Version

- **Publisher / Source**: موسوعة الأحاديث النبوية (HadeethEnc.com)
- **Official Portal**: https://hadeethenc.com/ar
- **Download Link**: https://hadeethenc.com/browse/download/ar
- **Source Version**: `v1.7.0`
- **Source Timestamp**: `2025-11-12 00:00:55`
- **Official Check URL**: https://hadeethenc.com/en/check/ar/v1.7.0
- **Acquisition Date**: `2026-09-28`
- **Total Rows in Workbook**: 3,582 data rows (+ A1 metadata header and Row 2 column headers)

---

## 2. Terms of Use & Redistribution Rights

According to the official HadeethEnc terms (https://hadeethenc.com/ar):
1. **Preserve Integrity**: Do not modify, alter, paraphrase, or truncate religious texts.
2. **Clear Attribution**: Attribute HadeethEnc.com and publishers prominently.
3. **Retain Metadata & Versioning**: Display version (`v1.7.0`) and source update check links.
4. **Maintenance**: Check for updates when newer versions are officially published.
5. **Contextual Purity**: Free of inappropriate advertisements and commercial distortions.
6. **No Independent Scholarly Claim**: The application does not claim independent scholarly certification or re-evaluation of grades; it faithfully transmits the authentic grades established by the source encyclopedia.

---

## 3. Selection Method & Completeness

- From the 3,582 data rows in the official Arabic workbook (3,584 total worksheet rows, comprising the A1 version/source metadata block, Row 2 column headers, and 3,582 data rows), exactly **3,213 rows** have `grade == "صحيح"`.
- Every one of the 3,213 authentic rows is bundled deterministically in the exact sequence of the workbook.
- No rows are omitted, deduplicated, or re-graded.
- All six essential columns (`id`, `title`, `hadith_text`, `grade`, `takhrij`, `link`) are non-empty across all 3,213 records.
- All non-null textual values (characters, line breaks, and punctuation) are preserved verbatim across all 3,213 selected rows; optional null cells in the source workbook (such as absent explanation, word meanings, or benefits) are normalized to empty strings in the compact JSON asset schema.

---

## 4. Reproducible Offline Import Procedure

The conversion from the source Excel workbook to the compact offline JSON asset is 100% deterministic and runs completely offline without any network access:

```powershell
# Using the pre-bundled Python runtime and openpyxl:
& 'C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tool/import_hadith.py
```

The tool validates:
1. Exact SHA-256 of `assets/content/hadith/hadeethenc-ar.xlsx` (`d5d397cb9fc8ddd54c4c6ee88357c2217721db0bd0759c6ec26d8b3fc36f1ec1`).
2. Intact A1 version header block (`v1.7.0`).
3. Exactly 9 standard columns in Row 2.
4. Exactly 3,213 records matching `grade == "صحيح"`.
5. Non-emptiness of essential fields and uniqueness of IDs.
6. Outputs compact JSON at `assets/content/hadith/hadith-enc-sahih.json` with SHA-256 `94a69dbdb44144d2dad2ba0a3fa1ee73c7f7b456c46d945ea15f4332a2eeeda7`.
