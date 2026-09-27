# Content Acquisition, Verification & Import Procedure

This document specifies the strict offline procedure for importing, validating, and bundling religious and media content into **زادُ الروح (Zad Alruh)**.

---

## 1. Principles of Religious Content Integrity

1. **Zero Synthesis & Zero Mock Religious Data**:
   Never generate, paraphrase, synthesize with AI, or manually transcribe religious texts (Quran, Dhikr, Duas, Hadith). Never copy unverified religious text from design mockups into production code.
2. **Byte-for-Byte Verbatim Preservation**:
   All imported sources must retain their original byte stream and provenance. File SHA-256 checksums are calculated immediately upon acquisition and recorded in `assets/content/manifest.json`.
3. **Pure Offline Availability**:
   Core content is bundled locally with the application binary or database; no runtime fetching, remote content endpoints, or dynamic CDNs are permitted for core content.
4. **Separation of Software License from Asset License**:
   A license granting permission to software code or tools does **not** grant rights to third-party assets, images, audio, or texts. Every asset must have documented, verified content reuse rights.

---

## 2. Bundled Sources & Provenance

### A. Quran Text (Tanzil Uthmani v1.1)
- **Source**: Tanzil Project (`https://tanzil.net`).
- **File**: `assets/content/quran/quran-uthmani.txt`
- **Expected SHA-256**: `7f30c647331a61100ebf24a80507dc0fcdd9f2df97f1312b5b2dfcb982a7f326`
- **License**: Creative Commons Attribution 3.0 (`CC-BY 3.0`).
- **Terms**: Verbatim redistribution only, retain Tanzil copyright notice block and attribution link (`https://tanzil.net`).
- **Structure**: Exactly 6,236 numbered verses, delimited as `surah|verse|text`. The trailing comment and license block must be preserved byte-for-byte in the file and ignored only during parsing.

### B. Quran Structural Metadata (Tanzil Metadata v1.0)
- **Source**: Tanzil Project (`https://tanzil.net/res/text/metadata/quran-data.xml`).
- **File**: `assets/content/quran/quran-data.xml`
- **Expected SHA-256**: `8867c1d88191472adec9db694b3cd9f135b1a2ef580574d32cf888dcb22c5c7a`
- **License**: `cc-by` (as declared in the XML root attribute; precise license version remains unspecified per source declaration).
- **Structure**: Exactly 114 chapters, 604 Medina Mushaf page start boundaries, and 30 Juz boundaries.

### C. Offline Geographical Gazetteer (GeoNames cities15000)
- **Source**: GeoNames (`https://download.geonames.org/export/dump/cities15000.zip`).
- **Data File**: `assets/content/cities/cities15000.txt`
- **Data SHA-256**: `c8e0a782e44ba580a2c0f0e3c9538051351629b442d4e6ff244aa609bd790a8d`
- **Readme & License File**: `assets/content/cities/GEONAMES-LICENSE-README.txt`
- **Readme SHA-256**: `b1957379b6c1242c700c98ac9a8aa0a09f56c3c0a50ee72175527005f48ef2c5`
- **License**: Creative Commons Attribution 4.0 (`CC-BY 4.0`).
- **Purpose**: Offline coordinate lookup for prayer time calculations without runtime network access.

---

## 3. Image Import & Verification Procedure (Deferred Milestone)

When Medina Mushaf page images are acquired in a future dedicated milestone:
1. **Source Licensing & Provenance**:
   Acquire from approved Quran Foundation developer terms (`https://api-docs.quran.com/legal/developer-terms/`) or equivalent authorized source under developer license.
2. **Registry Schema Requirements**:
   - Exactly 604 typed page entries (`page_number: 1..604`).
   - Unique IDs, unique file paths, and unique SHA-256 hashes (rejects duplicate entries or repeated paths).
   - Medina Mushaf mapping aligned with `QuranRepository.getPage(P)`.
   - Edition/source provenance and explicit rights reference recorded per image.
3. **Sequential Byte Decoding vs Religious Alignment**:
   - Dedicated future validator will sequentially decode all 604 images to verify file integrity (`width > 0, height > 0`).
   - **Crucial Distinction**: Image decoding verifies byte/format integrity, **NOT** visual religious alignment. Visual religious alignment strictly requires qualified human review evidence.
4. **Task2A Milestone Status**:
   - The repository currently contains **NO** image files; the registry stays empty/pending.
   - Any non-empty entries declared at this milestone are rejected as unsupported imports by `ContentValidator`.
   - Missing 604 page images remains an unconditional release blocker.

---

## 4. Audio Import, WAV Inspection & Duration Constraints (Deferred Milestone)

1. **Standalone WAV Inspector**:
   The standalone helper `ContentValidator.inspectWavHeader` is preserved and tested for future audio ingestion, verifying:
   - Valid `RIFF` container and declared file bounds.
   - `WAVE` format signature.
   - `fmt ` chunk size $\ge 16$ bytes, PCM audio format (`audioFormat == 1`).
   - Channel count $> 0$, sample rate $> 0$, bit depth in $\{8, 16, 24, 32\}$.
   - Consistency check: `blockAlign == channels * (bitDepth / 8)`.
   - Consistency check: `byteRate == sampleRate * blockAlign`.
   - `data` chunk present with positive size and no truncated headers (`dataOffset + dataSize <= file.length`).
   - Mathematically verified positive duration: `duration = dataSize / byteRate`.
   - 2-byte word padding handling on odd chunk boundaries.
2. **Task2A Milestone Status**:
   - The repository currently contains **NO** adhan audio recordings or notification clips.
   - Any declared voices or notification clips in the manifest are rejected as unsupported imports by `ContentValidator`.
   - Missing 3 licensed adhan recordings remains an unconditional release blocker.

---

## 5. Dhikr & Hadith Registries (Deferred Milestone)

1. **Future Ingestion Specifications**:
   - **Dhikr Collection (*Hisn al-Muslim*)**: File-backed corpus registry with documented printed/digital edition, Arabic reuse rights evidence, authentic references, and positive repetition counts.
   - **100 Authentic Hadith Records (*HadeethEnc*)**: File-backed registry with exact SHA-256, schema, IDs, Arabic text, canonical book references, and source-original authenticity grade.
2. **Task2A Milestone Status**:
   - The repository currently contains **NO** dhikr or hadith content files.
   - Any declared non-empty items in `dhikr_duas` or `hadith` are rejected as unsupported imports by `ContentValidator`.
   - Count-only declarations without items (`records_count > 0` with empty `items`) or negative counts are strictly rejected.
   - Both missing collections remain unconditional release blockers.

---

## 6. Structured Human Religious Review & Certification (Deferred Milestone)

1. **Future Certification Specifications**:
   - Reviewer identity, institutional role, and qualifications.
   - Review date (YYYY-MM-DD).
   - Exact SHA-256 references covering all supplied corpora (`quran_text`, `quran_metadata`).
   - Evidence file path and evidence file SHA-256 matching disk bytes.
2. **Task2A Milestone Status**:
   - No human review certification has taken place.
   - Any `"approved": true`, declared evidence path, evidence SHA, or reviewer claims in the manifest are rejected as unsupported pseudo-approvals.
   - Qualified human reviewer religious review remains an unconditional release blocker.

---

## 7. Content Validation Commands

```powershell
# Development verification of supplied files (exits 0 if supplied sources are valid):
dart run tool/validate_content.dart --development

# Strict release readiness verification (fails nonzero until all registries & human review are complete):
dart run tool/validate_content.dart
```
