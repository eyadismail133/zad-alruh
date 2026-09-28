# Pending Content, Rights & Human Review Status

This document records the exact status of pending religious and media content for **زادُ الروح (Zad Alruh)**. These items represent genuine external dependencies that are not yet established.

---

## 1. Status Overview

| Content Asset | Current Status | Blocker & Pending External Requirements |
|---|---|---|
| **Quran Text (Tanzil v1.1)** | ✅ Bundled & Verified | SHA-256 `7f30c647...` verified against Tanzil source. CC-BY 3.0 attribution retained. |
| **Quran Metadata (Tanzil v1.0)** | ✅ Bundled & Verified | SHA-256 `8867c1d8...` verified. 114 surahs, 604 page boundaries, 30 juz verified. Declares `cc-by`. |
| **GeoNames Gazetteer (cities15000)** | ✅ Bundled & Verified | SHA-256 `c8e0a782...` (data) and `b1957379...` (readme) verified. CC-BY 4.0 license retained. |
| **604 Quran Page Images** | ❌ PENDING (Missing) | Owner has **NO** Quran Foundation developer account or approved CDN access. Visual religious alignment uncertified. Registry stays empty/pending. |
| **Dhikr & Duas Digital Edition** | ❌ PENDING (Missing) | Documented *Hisn al-Muslim* edition, digital reuse permission, verified references and positive counts pending. |
| **Hadith Corpus (HadeethEnc v1.7.0)** | ✅ Bundled & Verified | 3,213 authentic ("صحيح") records bundled offline from HadeethEnc Arabic v1.7.0 with provenance XLSX, verified JSON asset, and rights evidence in `docs/sources/HADEETHENC.md`. |
| **3 Licensed Adhan Recordings** | ❌ PENDING (Missing) | 3 distinct voices, Fajr recording, and <30s notification clips pending. WAV header inspection verified by pipeline. |
| **Qualified Human Religious Review** | ❌ PENDING (Unapproved) | Structured review covering exact SHA-256 hashes of supplied corpora pending qualified scholar evaluation. |

---

## 2. Detailed Pending Requirements

### A. 604 Medina Mushaf Page Images
- **Current Reality**: Although `quran-data.xml` defines 604 page boundary entries, **zero page images are bundled**.
- **Prerequisites for Resolution**:
  1. An approved developer account under Quran Foundation developer terms (`https://api-docs.quran.com/legal/developer-terms/`).
  2. Downloading the official 604 high-resolution page images into `assets/content/quran/images/`.
  3. Image registry entries defining unique page numbers (1..604), unique paths, unique SHA-256 hashes, and rights references (no duplicate paths/hashes).
  4. Dedicated future image validator sequentially decoding all 604 images to verify file integrity.
  5. **Crucial**: Image decoding confirms byte-level decoding integrity, **NOT** visual religious alignment. Visual religious alignment requires qualified human review evidence.

### B. Dhikr & Duas Collection
- **Target Source**: *Hisn al-Muslim* (حصن المسلم) by Shaykh Sa'id bin Ali bin Wahf al-Qahtani.
- **Prerequisites for Resolution**:
  1. Documenting the specific printed/digital edition used.
  2. Securing and recording digital reproduction permission for mobile applications.
  3. Extracting exact Arabic text, authentic source references, and strictly positive repetition counts.
  4. Validating registry with actual items (count-only integer without items is strictly rejected).

### C. Hadith Corpus (Resolved & Bundled)
- **Source**: *HadeethEnc* (Encyclopedia of Translated Prophetic Hadiths), Arabic v1.7.0.
- **Resolution**:
  1. Complete offline bundle of all 3,213 exact "صحيح" records from the 3,582 workbook rows.
  2. Preserved original Arabic text, canonical takhrij references, and source authenticity grades.
  3. Official reuse terms documented in `docs/sources/HADEETHENC.md`.
  4. Verified by `ContentValidator` against pinned hashes, counts, and required fields. Release blocker dropped.

### D. Adhan Audio Recordings
- **Prerequisites for Resolution**:
  1. Obtaining licenses for 3 distinct muaddhin voices (never 3 clips of the same performer):
     - At least 1 Fajr Adhan (with *الصلاة خير من النوم*).
     - 2 Standard full Adhans.
  2. Producing short notification excerpt clips strictly under 30 seconds (`duration < 30.0s`) for iOS background notification sound restrictions.
  3. Verifying PCM WAV headers (RIFF bounds, fmt chunk $\ge 16$, PCM format == 1, channel/sampleRate/bitDepth consistency, data chunk bounds, positive duration) or documenting media probe evidence.

### E. Qualified Human Review
- **Prerequisites for Resolution**:
  1. A qualified Islamic scholar or specialized institution must inspect the digital text, diacritics, and surah/aya divisions.
  2. Structured manifest entry: reviewer identity/role/qualifications, review date, exact SHA-256 references covering all supplied corpora (`quran_text`, `quran_metadata`), and evidence file SHA-256.
  3. Evidence file on disk must exist, be non-empty, match recorded SHA-256, and contain verifiable sign-off matching manifest claims.
  4. **Strict Policy**: Review of supplied text/metadata certifies only the reviewed files. Even if text review is approved, missing images/audio/dhikr/hadith still block release. Review records are never fabricated to force release checks to pass.

---

## 3. Impact on Quality Gates

- `dart run tool/validate_content.dart --development` evaluates only the currently supplied source files (`quran-uthmani.txt`, `quran-data.xml`, and GeoNames data/readme), verifying their hashes, structure, boundary mappings, and search keys. It exits `0` when supplied files are valid.
- `dart run tool/validate_content.dart` (default release mode) **strictly fails with exit code 1** until every pending requirement listed above is resolved with verifiable evidence.

---

## 4. Concrete Future Content Pipeline Milestones

The current Task2A milestone delivers the trusted offline Quran repository, verified domain models, search indexing, and foundation content validator with pending registry preflight. All external media imports (images, audio, dhikr, hadith), digital rights evidence, and qualified human religious review pipelines are deferred and explicitly release-blocked until dedicated future milestones. No deferred work is claimed as completed:

1. **Mushaf Images Pipeline**:
   - Establish authorized Quran Foundation developer account.
   - Batch acquisition script with retry and SHA-256 generation.
   - Dedicated visual alignment verification tool against Medina Mushaf printings.
2. **Audio Acquisition & Ingestion Pipeline**:
   - Secure licenses from 3 distinct muaddhins (including 1 dedicated Fajr adhan).
   - Produce bounded <30s notification sound clips conforming to iOS/Android limits.
   - Ingest into audio registry with performer rights and excerpt permissions.
3. **Hisn al-Muslim & HadeethEnc Ingestion Pipeline**:
   - Parse and record specific printed edition provenance and mobile reuse rights.
   - Compile 100 core authentic hadiths with canonical book references and grades.
   - Structured JSON registry with positive repetition counts and cross-referenced categories.
4. **Qualified Human Religious Review Certification**:
   - Formal inspection by qualified scholars of the entire bundled text, diacritics, and boundary models.
   - Sign-off referencing exact SHA-256 hashes of all bundled corpora.
