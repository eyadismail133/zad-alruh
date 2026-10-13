# Android 0.3.0+3 verification — 2026-10-09

Implementation and independent review used gpt-6.1-sol at medium effort, as requested. No app repository commit or push was performed; unrelated existing work was preserved.

## Delivered behavior

- Hisn has an explicit catalog of genuine supplications; Daily Dua excludes praise-only records and preserves legacy history with replacement guidance.
- Added 24 sourced supplemental records from the bundled HadeethEnc corpus: 16 supplications and 8 adhkar contexts. Canonical Hisn and hadith files, IDs, and digest manifests remain unchanged. See HISN-INVOCATIONS.md for provenance.
- Hadiths sort by numeric source ID, support previous/next reading, and have a direct bottom navigation destination.
- Quran presentation uses the original Mushaf images throughout. Page-scoped surah/ayah references support bookmarks, exact stops, and existing stable favorites.
- Explicit read confirmation persists the next resume page, capped at 604, while preserving the saved exact stop. Schema 4 through 6 migrations preserve old user data.
- Offline licensed Noto Naskh Arabic and ivory/green/gold reader framing replace old presentation fonts.

## Evidence

- Full application suite: 543 tests passed, exit 0.
- After final concurrency fix: 108 relevant persistence, Quran, audio, and daily UI tests passed, exit 0.
- Independent final review: APPROVED; 28 resume/Quran tests passed, analyzer clean. Earlier independent integration review covered 92 tests.
- The stale resume regression failed before the fix (expected page 3, got page 2), then passed with intent sequencing captured before the first await.
- Development content verification passed all 47 checks. Strict production release validation still requires the project's qualified human religious-content review.
- Verified real-font screenshots at Android and iPhone viewport sizes; capture test passed. No physical device was connected, so hardware audio/notification behavior was not tested.
- ASCII build snapshot matched all 760 selected source, asset, test, and dependency files. Final debug APK build succeeded.
- APK package: dev.zadalruh.zad_alruh; versionName 0.3.0, versionCode 3; Android minimum SDK 26.
- APK signature verified: Android Debug certificate SHA256 a6ad6a32a8cb8e50f60bc1d4a97b36ebdfdd1728ece77d30c556853c9a0dae60.
- Packaged assets: 619 original runtime assets verified, all 604 Mushaf pages present, no differences. Noto font and OFL license bytes independently matched source.
- APK size: 281,612,842 bytes. SHA256: 0816E22F80ADA6732CC3638D99753289B14CB50663D75DEC86181EB4EA6B8A1B.
- Download worker: 6 tests passed, including full streaming, ranges, interrupted downloads, HEAD, and original page assets.

This remains a development/debug APK. Existing production prerequisites and documented native-library alignment limitations remain applicable; no store publication was attempted.

## Public delivery

Public Site version 4, source commit f5ba7537c01741f9bbed677afb04a5adbcca881b, deployment appgdep_6ac913fa5e108191b2dc84517719fe06 succeeded at https://zad-alruh.whiterat16.chatgpt.site. Local archive upload timed out twice; remote build completed from the same verified source. Public page and HEAD returned 200, and midpoint byte-range returned 206 with exact local bytes. Full public download verified all 281,612,842 bytes and the exact SHA256 above. Machine-readable evidence is in .local/reader-refresh/public-download-verification.json.
