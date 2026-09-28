# KFQC Medina Mushaf (Hafs an Asim 1441 AH) Provenance & Integration

## 1. Overview and Source Substitution Rationale
In earlier milestones, acquiring page images was blocked pending a third-party developer account (e.g., Quran Foundation APIs). An explicit source substitution was made to the official digital artwork of the **King Fahd Glorious Quran Printing Complex (KFQC)** in Medina, Saudi Arabia, which is accessible without account barriers:
- **Corpus Target:** 604 page images of the Medina Mushaf (مصحف المدينة النبوية لأعمال الطباعة), Riwayah Hafs an Asim (1441 AH print edition).
- **Primary Publisher:** King Fahd Glorious Quran Printing Complex (KFQC) / مجمع الملك فهد لطباعة المصحف الشريف بالمدينة المنورة.
- **Original Source Package:** KFQC `1441-AI-hafs.zip`
  - Canonical SHA-256: `280c5d71ca16aaeeb3a343be1b92c76fa6df71d0671e202c026fde12402d9eef`
- **Upstream Open Conversion:** `quran-ws/quran-svg`
  - GitHub Repository: https://github.com/quran-ws/quran-svg
  - Pinned Git Commit: `b4155f07e4aea087d2c458069acff9f7c7e749f6`
  - Notice & Rights: https://github.com/quran-ws/quran-svg/blob/main/NOTICE.md
  - Upstream Provenance Record: https://github.com/quran-ws/quran-svg/blob/main/docs/PROVENANCE.md

## 2. Legal Terms, Permissions & Caveats
- **KFQC Technical Guide:** The KFQC Technical Booklet PDF at https://qurancomplex.gov.sa/wp-content/uploads/isdarat/booklets/complextechguide.pdf (section "مصحف المدينة النبوية لأعمال الطباعة", printed page 51) explicitly describes the digital Hafs and Warsh copies as approved and made public for use in computer applications, educational software, and websites.
- **Developer Portal Caveat:** The official developer page at https://qurancomplex.gov.sa/en/techquran/dev/ also appears to declare broader free digital use, but currently times out from this external test environment. We do not claim independent online retrieval of that specific URL; our rights basis is anchored directly in the published KFQC Technical Guide PDF.
- **Conversion Licensing:** The derivative conversion performed by `quran-ws/quran-svg` is licensed under Creative Commons Attribution 4.0 International (CC BY 4.0), attributing publisher rights to KFQC.
- **Integrity & Approval Warning:** As documented in the upstream `PROVENANCE.md`, the automated conversion to SVG underwent structural verification without independent geometric differential testing. Consequently, human scholarly and visual signoff for the entire corpus remains pending. We do NOT claim official KFQC publisher validation or endorsement of this third-party digital SVG/WebP conversion.

## 3. Reproducible Offline Rendering Pipeline
The source SVGs in `quran-ws/quran-svg` total 373MB and are not bundled directly into the mobile package. Instead, offline lossless WebP images were deterministically generated using the following procedure:
1. **Toolchain:**
   - SVG Renderer: `resvg-js` version `2.6.2`
   - Image Processor: Python `Pillow` version `12.3.0` backed by `libwebp` version `1.6.0`
2. **Parameters:**
   - Dimensions: Rendered at fixed 1200px width (aspect-ratio preserved according to the original KFQC page sheet geometry).
   - Background: Pure solid white `#FFFFFF`.
   - Compression: Lossless WebP, compression effort/method `6`.
3. **Artifact Summary:**
   - 604 WebP files located at `assets/content/quran/pages/001.webp` through `604.webp`.
   - Combined size: exactly `91,492,288` bytes across all 604 files.
   - Pinned digests catalog: `assets/content/quran/quran-pages-digests.json`
     - File SHA-256: `a836ce22d62c5b61243b0e974fb7e6c80ecbcc99c5191a3d02f7ab2f3dec8956`
   - Pinned page boundaries: `assets/content/quran/kfqc-page-bounds.json`
     - File SHA-256: `95f609f8c56e811b8afed9695bee44a0e4766b47c01708a3abb7064b9bc42539`
   - Sample Page Hashes:
     - Page 1 (`001.webp`): `1dd02b643c8b1dcb01aaeb3bb34fa240dfdd824898e402cbddfad01e2e470d87`
     - Page 604 (`604.webp`): `f30b4aad9b322ce7c3d61c5d2bdedaa948eca8e76494eb21c4473dee68365689`

## 4. Alignment with Canonical Quranic Text (Tanzil Uthmani)
- Verbatim Tanzil Uthmani text (`assets/content/quran/quran-uthmani.txt`, SHA-256 `7f30c647...`) and Tanzil metadata XML (`assets/content/quran/quran-data.xml`, SHA-256 `8867c1d8...`) remain byte-for-byte unchanged.
- All 6,236 verses across 114 Surahs map to the 604 KFQC page bounds in strict sequential order without gaps or overlaps.
- **25 Differing Page Boundaries:**
  The printed KFQC Hafs edition places ayah breaks across 25 specific page transitions differently than Tanzil's older reference data:
  `121, 122, 123, 145, 532, 533, 534, 565, 568, 570, 576, 584, 586, 588, 589, 590, 592, 593, 594, 595, 596, 597, 598, 599, 600`.
  The runtime page mapping throughout the application (reader image view, accessible text view, search jump, and bookmarks) has been completely aligned to KFQC so that every verse displayed on a page corresponds strictly to the visual content of that page's sheet.

## 5. Visual Inspections & Pending Religious Signoff
- Visual inspection of rendered assets was conducted on milestone sample pages:
  - Page 1 (Al-Fatihah)
  - Page 2 (Al-Baqarah start)
  - Page 3 (Al-Baqarah continuation)
  - Page 121 (Al-Ma'idah boundary difference)
  - Page 600 (Al-Adiyat boundary difference)
  - Page 604 (Al-Ikhlas, Al-Falaq, An-Nas)
- **Pending Human Review:** Visual sampling verifies rendering correctness and boundary continuity, but full religious and typographical signoff across all 604 pages by a qualified human scholar remains a mandatory pre-release gate documented in `docs/READINESS.md`.
