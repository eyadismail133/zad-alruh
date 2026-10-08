# Qualified Human Content Review Specification and Sign-off Protocol

## 1. Executive Summary and Critical Machine Limitation Notice

Zad Alruh bundles Islamic religious content: the Holy Quran Uthmani text, Tanzil Quran metadata, 604 Medina Mushaf page images (King Fahd Glorious Quran Printing Complex - KFQC 1441 AH), authentic Hadiths from HadeethEnc, and daily supplications from Hisn al-Muslim (Fortress of the Muslim).

While automated testing verifies byte integrity, cryptographic digests, schema formats, and file containment:

> [!IMPORTANT]
> **CRITICAL MACHINE LIMITATION DISCLAIMER**
> Automated software tools verify cryptographic hashes, file containment, JSON schema structure, and calendar validity.
> **The machine CANNOT authenticate real-world human identity, academic or religious qualifications, reviewer honesty, or theological/religious truth.**
> Religious authority, scholarly consensus, and institutional inspection remain fundamentally human, external responsibilities. Software checks guarantee tamper-evident binding between the recorded inspection and the shipped application bytes, but cannot substitute for scholarly certification.

---

## 2. Scope and Assessment Domains

The bundled human content-review evidence covers exactly **624 canonical offline religious content artifacts**:

| Category | Count | Canonical Source / Edition | Description |
| :--- | :---: | :--- | :--- |
| **Holy Quran Text** | 1 | Tanzil Uthmani v1.1 | Complete Uthmani script (`quran-uthmani.txt`) |
| **Holy Quran Metadata** | 1 | Tanzil Metadata v1.0 | Surahs, ayahs, juzs, and sajdas (`quran-data.xml`) |
| **Hadith Source XLSX** | 1 | HadeethEnc Arabic v1.7.0 | Official Excel spreadsheet source (`hadeethenc-ar.xlsx`) |
| **Hadith Shipped JSON** | 1 | HadeethEnc Arabic v1.7.0 | Bundled authentic (صحيح) collection (`hadith-enc-sahih.json`) |
| **Hisn al-Muslim Source** | 1 | IslamHouse 2019-05-02 | Official DOCX source text (`hisn-muslim-source.docx`) |
| **Hisn al-Muslim JSON** | 1 | IslamHouse / Dr. Al-Qahtani | 267 dhikr entries across 132 chapters (`hisn-muslim.json`) |
| **Mushaf Page Bounds** | 1 | KFQC Medina Mushaf 1441 AH | Canonical verse boundaries per page (`kfqc-page-bounds.json`) |
| **Mushaf Page Digests** | 1 | KFQC / quran-svg | Pinned SHA-256 catalog of all 604 pages (`quran-pages-digests.json`) |
| **Mushaf Page Images** | 604 | KFQC Hafs 1441 AH WebP | Lossless WebP page renders (`001.webp` through `604.webp`) |
| **Adhan Audio Recordings** | 3 | CC-licensed recordings | Full MP3 recordings (Adam, Atcovi, Malmö Mosque Fajr) |
| **Adhan Alert Clips (Assets)** | 3 | Bundled notification clips | 27-second PCM 16-bit 22050Hz mono WAV clips |
| **iOS Alert Clips** | 3 | `ios/Runner/` | Native platform alert copies for UNNotificationSound |
| **Android Alert Clips** | 3 | `android/.../res/raw/` | Native platform notification copies for Android AudioAttributes |
| **TOTAL INVENTORY** | **624** | — | **Exact complete religious content bundle** |

### Excluded and Independent Domains

1. **Mutable Online Quran Streaming & Remote Recordings**:
   Dynamic remote audio streaming URLs or external network endpoints are **not covered** by this bundled static review. The application's source privacy and security boundary isolates remote network operations independently.
2. **GeoNames Cities Database**:
   `cities15000.txt` is an astronomical/geographical coordinate database, not religious corpus. It is verified independently by `ContentValidator`'s provenance integrity check and is excluded from the religious sign-off inventory.
3. **Audio Tajweed and Listening Assessment**:
   Automated signal analysis checks RIFF headers, PCM bit depth, duration (< 30s), and non-zero RMS amplitude. Human ear evaluation of Tajweed pronunciation, melodic appropriateness, and religious correctness must be performed by human scholars.
4. **Astronomical Prayer Calculation Engine**:
   Prayer time calculation formulas (Fajr angle, Asr shadow factor, etc.) depend on astronomical mathematics and geographical coordinates, which are assessed separately from the static content bundle.

---

## 3. Non-Circularity and Anti-Tamper Architecture

To prevent cryptographic circularity:
- The **Evidence Report** contains the cryptographic SHA-256 digests of all 624 religious content artifacts.
- The **Trusted Manifest** (`manifest.json`) records the reviewer credentials, date, relative path to the report (`evidence_path`), report SHA-256 (`evidence_sha256`), and copies the verified hashes (`reviewed_hashes`).
- **Neither document hashes `manifest.json` itself.** This ensures a strict directed acyclic graph (DAG) of verification without self-referential hash recursion:

```
[Religious Artifacts (624 Files)]
             ▲
             │ (SHA-256 digests)
[Evidence Report (JSON)]
             ▲
             │ (evidence_sha256 & evidence_path)
[Trusted Manifest (manifest.json)]
```

---

## 4. Minimal Owner Evidence Report Template

The evidence report must be a UTF-8 encoded JSON file (maximum size 1 MiB) complying strictly with canonical `schema_version: 1`.

The canonical report schema requires exact field names (aliases such as `approved`, `inventory`, `schemaVersion`, `date`, `concerns`, or `limitations` are strictly rejected):
- `schema_version`: integer `1`
- `religious_approval`: boolean `true` (default template has `false`)
- `reviewer_name`: non-blank, bounded string
- `reviewer_qualifications`: non-blank, bounded string
- `review_date`: ISO calendar string `YYYY-MM-DD`
- `scope`: non-blank, bounded string
- `review_method`: non-blank, bounded string
- `coverage`: non-blank, bounded string
- `concerns_and_limitations`: non-blank, bounded string
- `reviewed_hashes`: JSON object mapping relative paths to lowercase 64-hex SHA-256 hashes

> [!CAUTION]
> **DEFAULT TEMPLATE HAS APPROVAL DISABLED (`religious_approval: false`).**
> Do NOT set `religious_approval: true` without an actual, qualified human religious scholar having inspected all content and provided verifiable qualifications.

```json
{
  "schema_version": 1,
  "religious_approval": false,
  "reviewer_name": "<Full Name of Qualified Reviewer>",
  "reviewer_qualifications": "<Specific academic degree, institutional affiliation, and specialization>",
  "review_date": "<YYYY-MM-DD>",
  "scope": "<Detailed description of reviewed content scope>",
  "review_method": "<Methodology used for inspection and religious verification>",
  "coverage": "<Exact coverage description across all 624 bundled religious artifacts>",
  "concerns_and_limitations": "<Any noted constraints; e.g. valid only for offline bundled static files; external streaming endpoints excluded>",
  "reviewed_hashes": {
    "assets/content/quran/quran-uthmani.txt": "7f30c647331a61100ebf24a80507dc0fcdd9f2df97f1312b5b2dfcb982a7f326",
    "assets/content/quran/quran-data.xml": "8867c1d88191472adec9db694b3cd9f135b1a2ef580574d32cf888dcb22c5c7a",
    "assets/content/hadith/hadeethenc-ar.xlsx": "d5d397cb9fc8ddd54c4c6ee88357c2217721db0bd0759c6ec26d8b3fc36f1ec1",
    "assets/content/hadith/hadith-enc-sahih.json": "94a69dbdb44144d2dad2ba0a3fa1ee73c7f7b456c46d945ea15f4332a2eeeda7",
    "assets/content/hisn/hisn-muslim-source.docx": "7509ed8d485bd6f6af1b2edb12f4066f4d12d1959bcafc04697cd319c6ff3e8a",
    "assets/content/hisn/hisn-muslim.json": "8655afe53935baf74fed92164fedb9f0ba7e989c23818f82bd231ebd6d7a773d",
    "assets/content/quran/kfqc-page-bounds.json": "95f609f8c56e811b8afed9695bee44a0e4766b47c01708a3abb7064b9bc42539",
    "assets/content/quran/quran-pages-digests.json": "a836ce22d62c5b61243b0e974fb7e6c80ecbcc99c5191a3d02f7ab2f3dec8956",
    "assets/content/quran/pages/001.webp": "1dd02b643c8b1dcb01aaeb3bb34fa240dfdd824898e402cbddfad01e2e470d87",
    "assets/audio/adhan/adam-converted.mp3": "c3fa9ae67d8cf65474dec44194d8b6a76c2f04ef188c916cf9c4dd6f8eb28dc7",
    "assets/audio/adhan/adam-alert.wav": "de9c50bbf6dbaa6b6d4d6306bdafe2fcfa1139372701859e7b1359f802559c01",
    "ios/Runner/adam-alert.wav": "de9c50bbf6dbaa6b6d4d6306bdafe2fcfa1139372701859e7b1359f802559c01",
    "android/app/src/main/res/raw/adam_alert.wav": "de9c50bbf6dbaa6b6d4d6306bdafe2fcfa1139372701859e7b1359f802559c01"
  }
}
```

---

## 5. Inventory Export Process

The canonical inventory of all 624 items and their expected SHA-256 hashes can be exported using the dedicated tool:

```bash
dart run tool/export_human_review_inventory.dart
```

The tool validates filesystem containment and computes SHA-256 digests on all 624 disk files before emitting JSON strictly to standard output (`stdout`), guaranteeing the tool itself is completely read-only and cannot directly write or overwrite any repository files.

If an owner chooses to redirect standard output to a file (e.g. `> <path>`), ensure the target directory exists and select an explicit, safe destination path, as the shell redirection operator can overwrite existing files without confirmation.

---

## 6. Real Human Sign-off Protocol

When engaging a qualified Islamic scholar for production release certification:

1. **Independent Inspection**:
   The qualified reviewer inspects the Quranic text, metadata, Hadiths, Hisn al-Muslim supplications, Mushaf page images, and listens to the adhan audio recordings.
2. **Documentation of Credentials & Findings**:
   The reviewer supplies:
   - Full name and institutional affiliation.
   - Specific academic and religious qualifications in Quranic sciences / Hadith authentication.
   - Exact review date (`YYYY-MM-DD`).
   - Detailed review scope, methodology, coverage, and any noted limitations.
3. **Signing the Report**:
   The owner incorporates the scholar's findings and complete inventory into `docs/reviews/human_content_review.json` and sets `"religious_approval": true`.
4. **Computing Report SHA-256**:
   Compute the exact SHA-256 of the UTF-8 report file:
   - Linux / macOS: `shasum -a 256 docs/reviews/human_content_review.json`
   - Windows PowerShell: `(Get-FileHash docs/reviews/human_content_review.json -Algorithm SHA256).Hash.ToLower()`
5. **Updating Manifest**:
   Update `assets/content/manifest.json` with the scholar's actual information and verified digests:
   ```json
   "human_review": {
     "status": "approved",
     "approved": true,
     "reviewer_name": "<Full Name of Genuine Scholar>",
     "reviewer_qualifications": "<Verifiable Academic & Religious Credentials>",
     "review_date": "<YYYY-MM-DD>",
     "evidence_path": "docs/reviews/human_content_review.json",
     "evidence_sha256": "<Lowercase 64-hex SHA-256 of the report file>",
     "reviewed_hashes": { ... }
   }
   ```
6. **Execution of Automated Verification**:
   Run strict release validation:
   ```bash
   dart run tool/validate_content.dart
   ```
   If all 624 underlying assets, the evidence report digest, reviewer credentials, calendar date, and containment checks pass, the release blocker is cleared.

> [!NOTE]
> **NO EVIDENCE FABRICATION POLICY**
> Until a real, qualified human reviewer has completed this inspection and supplied legitimate credentials, the repository manifest **must remain in `status: "pending"` and `approved: false`**. No simulated, fabricated, or placeholder approvals may be checked into production releases.
