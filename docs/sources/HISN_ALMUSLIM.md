# Hisn al-Muslim Dhikr & Duas Corpus Provenance & Rights

Acquired on 2026-09-28 from the official IslamHouse repository (دار إسلام هاوس).

| Asset | Source / Role | SHA-256 |
|---|---|---|
| `assets/content/hisn/hisn-muslim-source.docx` | Official Word DOCX Attachment (Provenance) | `7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a` |
| `.local/hisn-muslim-source.pdf` | Official Companion Scanned PDF (159 pages, optional provenance) | `c9d40a91517f348bedd39d58132313007f67a2ad69631ee5db075dbbbb35d1e6` |
| `assets/content/hisn/hisn-muslim.json` | Deterministic Offline JSON Bundle (267 Items, 132 Chapters) | `8655afe53935baf74fed92164fedb9f0ba7e989c23818f82bd231ebd6d7a773d` |

---

## 1. Source Identification & Metadata

- **Book Title**: حصن المسلم من أذكار الكتاب والسنة (Fortress of the Muslim)
- **Author**: د. سعيد بن علي بن وهف القحطاني (Dr. Saeed bin Ali bin Wahf Al-Qahtani)
- **Publisher / Repository**: دار إسلام هاوس (IslamHouse.com)
- **Official Listing (Arabic)**: https://islamhouse.com/ar/books/2522
- **Official Listing (English)**: https://islamhouse.com/en/books/2522
- **Attachment Name**: كتاب حصن المسلم word (DOCX 571.8 KB)
- **Attachment Date**: `2019-05-02`
- **Acquisition Date**: `2026-09-28`
- **Corpus Counts**: exactly 132 chapters, 267 consecutively numbered items (1..267), 300 referenced footnotes (footnotes 16..315).

---

## 2. Terms of Use & Redistribution Rights

According to the official IslamHouse API and content redistribution statement (https://github.com/IslamHouse-API/multilingual-quran-hadith-islamic-content-database-api-hub):
1. **Conditional digital reuse**: Offline mobile application reuse, database ingestion, and format conversion are permitted without prior written permission for both commercial and non-commercial projects, subject to faithful preservation of original text, full author and publisher attribution, source link inclusion, and version tracking/updates.
2. **Faithful Transmission**: The original text, metadata, source link, author, publisher, and edition must be preserved without alteration, paraphrase, or AI-generated religious modifications.
3. **Attribution**: Prominently display author (Dr. Saeed bin Ali bin Wahf Al-Qahtani) and source (IslamHouse.com) with external links.
4. **Contextual Integrity**: The application must present the religious text respectfully in a suitable Islamic context without distorting context or meaning.
5. **No Independent Scholarly Claim**: The application does not claim independent authentication or grading; every entry reflects the documented text and references of the author's work.

---

## 3. Structural Parsing & Deterministic Extraction Rules

The source DOCX contains 577 body paragraphs in `word/document.xml` and 317 footnote elements in `word/footnotes.xml`:
1. **Title & Introduction Exclusion**: Paragraphs 0 to 29 contain the title page, author dedication, and general introduction (including "فضل الذكر") with footnotes 2..15. These introductory paragraphs precede the numbered invocations and are omitted from the structured item catalogue.
2. **Table of Contents (TOC) Exclusion**: Paragraphs 440 to 576 contain the Word table of contents (commencing at paragraph 440 with "الفهرس" and paragraph 441 with column headers). The TOC is detected and dropped.
3. **Content Ingestion**: Paragraphs 30 to 439 constitute the active content range:
   - **Chapter Headings**: Paragraphs with Word paragraph style `222` and format `^\s*(\d+)\s*[-–ـ]\s*(.+)$` define the 132 numbered chapters.
   - **Numbered Items**: Paragraphs beginning with `^\s*(\d+)\s*[-–ـ]` denote items 1 through 267.
   - **Continuation Paragraphs**: Unnumbered paragraphs following an item (e.g. Item 19 P[61], Item 74 P[131], Item 114 P[178-180], Item 133 P[209], Item 160 P[253], Item 162 P[257], Item 267 P[438]) are appended to their respective item, retaining all continuation text and embedded references.
   - **Chapter 27 Opening**: Paragraph 133 ("الْحَمْدُ لِلَّهِ وَحْدَهُ، وَالصَّلاَةُ وَالسَّلاَمُ عَلَى مَنْ لاَ نَبِيَّ بَعْدَهُ") with footnote 101 sits under Section 27 before Item 75-(1) and is linked as the opening paragraph of Item 75, guaranteeing no orphan footnotes.
4. **Footnotes Resolution**: System footnotes (`id="-1"`, `id="0"`, `id="1"`) are skipped. Only footnotes referenced by the 267 items (footnotes 16..315, exactly 300 notes) are resolved and bundled into the runtime JSON.

---

## 4. Repetition Target Extraction Rules

To avoid inaccurate counter badges and unsupported ritual obligations, `repeat_target` is assigned **only** when exactly one explicit, unambiguous count applies to the entire displayed entry as an appropriate single repetition badge.

### A. Exclusion Criteria (Target set to `null`)
Entries where numbers appear in source text or footnotes but do NOT constitute a single overall repetition count for the entire displayed entry remain `repeat_target: null`. In all cases, the raw Arabic source text and scholarly footnotes remain completely visible:
- **Multi-Part Formulas**:
  - Item 69: Subhanallah (33x), Alhamdulillah (33x), Allahu Akbar (33x), followed by one Tahlil (1x).
  - Item 106: Subhanallah (33x), Alhamdulillah (33x), Allahu Akbar (34x).
  - Item 243: Bismillah (3x), followed by supplication (7x).
- **Partial Repetitions**:
  - Item 66: Only the initial phrase `أَسْتَغْفِرُ اللَّهَ` is repeated 3 times; the subsequent supplication `اللَّهُمَّ أَنْتَ السَّلاَمُ...` is said once.
  - Item 67: Only the initial sentence `لاَ إِلَهَ إِلاَّ اللَّهُ...` has bracketed `[ثلاثاً]`; remainder is recited once.
- **Alternative / Conditional Options**:
  - Item 92: Provides alternative choices in text: `(عشرَ مرَّات)` or `(مرَّةً واحدةً عندَ الكَسَلِ)`.
- **Action / Bodily Counts**:
  - Item 99: Action sequence narration (`يجمع كفيه ثم ينفث... يفعل ذلك ثلاث مرات`).
  - Item 102: Count in footnote specifies dusting the bed 3 times (`فلينفضه... ثلاث مرات`), not the supplication itself.
  - Item 114: Multi-step action across 4 paragraphs with multiple distinct counts (spitting 3x, seeking refuge 3x, turning over).
  - Item 138: Action count for dry-spitting 3 times to the left (`واتفل على يسارك (ثلاثاً)`).
- **Modified Repetition**:
  - Item 119: Recited 3 times, but the 3rd repetition has a unique louder vocalization and an appended phrase (`[رَبِّ الْمَلاَئِكَةِ وَالرُّوحِ]`).
- **Prophetic Reports & Narrative Virtues**:
  - Items 195, 249, 253: Hadith narrations reporting the Prophet's practice (e.g. repenting 100 times daily or counting 100 in a gathering).
  - Items 254, 255: Hadith narrations stating rewards/virtues for reciting formulas in a day.
  - Item 236: Long Hajj narrative account with repeated segments at Safa and Marwah.

### B. Retained Numeric Targets (Reviewed Whitelist of 17 Items)
Exactly 17 items qualify under the strict single-entry criterion:
| ID | Chapter | Section Title | Target | Source Repetition Phrasing |
|---|---|---|---|---|
| **33** | 11 | دعاء الركوع | `3` | `ثلاث مرَّاتٍ` |
| **41** | 15 | دعاء السجود | `3` | `ثلاث مرَّاتٍ` |
| **72** | 25 | الأذكار بعد الصلاة | `10` | `عَشْرَ مَرّاتٍ بَعْدَ صَلاةِ الْمَغْرِبِ وَالصُّبْحِ` |
| **76** | 27 | أذكار الصباح والمساء | `3` | `(ثلاثَ مرَّاتٍ)` |
| **80** | 27 | أذكار الصباح والمساء | `4` | `(أربعَ مَرَّاتٍ)` |
| **82** | 27 | أذكار الصباح والمساء | `3` | `(ثلاثَ مرَّاتٍ)` |
| **83** | 27 | أذكار الصباح والمساء | `7` | `(سَبْعَ مَرّاتٍ)` |
| **86** | 27 | أذكار الصباح والمساء | `3` | `(ثلاثَ مرَّاتٍ)` |
| **87** | 27 | أذكار الصباح والمساء | `3` | `(ثلاثَ مرَّاتٍ)` |
| **91** | 27 | أذكار الصباح والمساء | `100` | `(مائة مرَّةٍ)` |
| **93** | 27 | أذكار الصباح والمساء | `100` | `(مائةَ مرَّةٍ إذا أصبحَ)` |
| **94** | 27 | أذكار الصباح والمساء | `3` | `(ثلاثَ مرَّاتٍ إذا أصبحَ)` |
| **96** | 27 | أذكار الصباح والمساء | `100` | `(مِائَةَ مَرَّةٍ فِي الْيَوْمِ)` |
| **97** | 27 | أذكار الصباح والمساء | `3` | `(ثلاثَ مرَّاتٍ إذا أمسى)` |
| **98** | 27 | أذكار الصباح والمساء | `10` | `(عشرَ مرَّاتٍ)` |
| **130** | 37 | دعاء من خاف ظلم السلطان | `3` | `(ثلاثَ مرَّاتٍ)` |
| **148** | 49 | الدعاء للمريض في عيادته | `7` | `(سبع مرات)` |

---

## 5. Known Source Rendering Caveats

1. **Private Use Glyphs (PUA) & Arabic Presentation Forms**:
   - `U+FB51`, `U+FB52`, `U+FB53` (`ﭑ ﭒ ﭓ`): Presentation Forms-A glyphs used in King Fahd Quran font traditions for the Bismillah ligature preceding Surahs (e.g. items 70, 76, 99).
   - AGA Arabesque PUA symbols: e.g. `\uF049` ("تعالى"), `\uF074` ("رضي الله عنه"), `\uF072` ("صلى الله عليه وسلم").
   - Typographic shorthand: `^` for "رضي الله عنهما" / "رضي الله عنه", `’` for "رضي الله عنها".
2. **Font Fallback Behavior**:
   Standard system fonts (such as IBM Plex Sans Arabic) may render these historical Word font characters as raw glyphs or fallback boxes. In adherence to the zero-alteration policy, all source characters are preserved verbatim in data storage, and the UI provides clean presentation without destructive text manipulation.

---

## 6. Reproducible Offline Ingestion Procedure

Both Dart and Python implementations produce identical, bit-for-bit output JSON:

```powershell
# Pure Dart CLI execution:
dart run tool/import_hisn.dart

# Or Python CLI execution:
& 'C:\Users\dell\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tool/import_hisn.py
```
