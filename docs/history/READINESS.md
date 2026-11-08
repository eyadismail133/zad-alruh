## Current Android revision — 2026-10-09

Android is the active target; iOS work is paused. The older milestone rows below describe historical builds and must not be read as evidence for a new APK.

Completed scoped verification before the current notification integration edits: native Android 111 JUnit tests (commits `ee743e7`, `4508779`); progress/settings 69 tests; manual audio/reset 12 tests; SDK audio/preferences 32 tests; reader layout/navigation 36 tests; Quran/audio/source interface 77 tests; daily checklist/dua interface 13 tests; Hisn interface/repository 38 tests; Hadith interface 16 tests; notification planner 36 tests; human-review validator 33 tests. Each focused gate passed, with the analyzer passing after the corresponding completed Dart task. These counts are separate runs, not a unique full-suite total or approval of the subsequent notification integration edits.

Hisn/Hadith compact interface review and Android notification integration are closed for this testing revision. Root repaired the legacy test harness regressions without weakening production validation. The final full Flutter suite passed **528 tests with zero failures** (2m07s), and `flutter analyze --no-pub` found no issues. A fresh debug APK was built from a physical ASCII source snapshot after verifying 833 files against the original checkout; the junction alone did not resolve JNI's Unicode path failure. APK verification passed for all 619 runtime content/audio files, all 604 Mushaf images, uncompressed audio and APK v2 signing. See [the current APK report](ANDROID-APK-2026-10-09.md) for the exact artifact, hash and limits.

Physical phone playback and OEM background delivery remain unverified: ADB reported no connected device at handoff. ZIP and ELF LOAD 16KB checks passed, but six prebuilt libraries failed the GNU_RELRO end alignment check; no 16KB runtime acceptance is claimed. Google Play submission still needs these compatibility/device gates, the owner's account, signing identity, publisher/support details and required content review. Canonical human-review metadata remains pending; no religious certification is claimed.

Content development validation passed; strict release validation remains blocked by qualified human review. The exported review inventory contains 624 source hashes, including provenance files and paused iOS audio copies; only the required Android runtime subset belongs in an APK. No synthetic test approval was written to the canonical review manifest.

# Historical milestone acceptance status

This record separates implemented work, verified work and external prerequisites. No item implies religious certification or store approval.

| Area | Verified/current evidence | Remaining work |
|---|---|---|
| Design | Supplied archive, logo, Arabic fonts and original licenses retained; actual foundation widget renders inspected | Compare subsequent screens with design and verify accessibility on devices |
| Tooling | Flutter 3.47.5 / Dart 3.13.4, Android API 36 / NDK 28 installed; debug and profile APKs built | iOS requires macOS/Xcode; native 16KB RELRO finding and runtime tests remain |
| Foundation | Astra APPROVED Task 1; analyze and 24 tests passed; approved commit 03b57a7 | Later feature/schema/native milestones require separate review |
| Quran source/domain | Historical Astra APPROVED Task 2A; canonical hashes, 114 chapters / 6236 verses / 604 boundaries / 30 juz; original assets verified unchanged in latest debug APK | Content/image/religious review |
| Quran interface | GPT-6 Sol APPROVED Task 2B; offline index/search/reader/explicit stop/bookmarks/favorites/source notices; full 113 tests and analyze passed, fresh debug build 14.0s | Physical-device accessibility verification |
| Mushaf images | Bundled and verified: 604 KFQC Medina Mushaf page images (Hafs 1441 AH) via quran-ws/quran-svg (CC BY 4.0), 91.5MB WebP, canonical 604-page boundary map aligned with Tanzil text, 25 differing page boundary breaks handled | Comprehensive human scholarly religious signoff on full 604-page conversion remains pending |
| Global cities | Original GeoNames cities15000 snapshot 34,149 records and CC BY 4.0 attribution; offline Arabic/Latin search and nearest-city domain reviewed by GPT-6 Sol; the eight legacy settings cities now display real prayer results | Global city picker and persisted selection beyond those eight cities |
| Prayer calculation domain | GPT-6 Sol APPROVED Task 3A; pinned MIT Adhan engine with 3 documented patches, city-anchored timezone/DST, method settings, estimated/polar-day policy and cross-midnight next prayer; full 158 tests, analyze clean, debug APK built | Persist choices, schedule and device-verify notifications/adhan; qualified review of prayer times |
| Prayer presentation | GPT-6 Sol APPROVED Task 3B1; Home and prayer screen use actual offline calculation for eight settings cities, showing next prayer by instant, countdown, sunrise, method and explicit error/unsupported states; full 169 tests, analyze clean, fresh debug APK | Global city picker, method settings UI, notification activation and native device verification |
| Visual preview | Screenshots rendered from Flutter widgets at Android 360x800 and iPhone 390x844, with a clickable gallery at [preview/index.html](preview/index.html) | This is a screenshot simulation, not a native iOS build or device acceptance test |
| Hadith | Bundled and verified: 3,213 authentic ("صحيح") records from HadeethEnc Arabic v1.7.0 with provenance XLSX, compact JSON asset, offline lazy list/search/detail, attribution and source links | Qualified human religious review |
| Dhikr/duas | Bundled and verified: 267 supplication items in 132 chapters from Hisn al-Muslim (IslamHouse / Dr. Saeed al-Qahtani) with 300 footnotes, provenance DOCX, compact JSON asset | Qualified human religious review |
| Adhan | Bundled source corpus verified (+77 validator pass, 3 licensed adhan recordings: Adam-synagda CC0 1.0, Atcovi CC BY-SA 4.0, Islamic Center Malmö CC BY 3.0 Fajr; 27s PCM WAV alert clips); offline playback runtime, persisted voice selection, and UI implemented, unverified pending Codex verification gates and independent Sol review | Scheduled background/notification playback milestone, real physical-device audio test, and qualified human religious listening signoff |
| Quran recitation (audio) | Implemented foreground full-surah streaming (all 114 surahs, Mishary Alafasy, Hafs 'an 'Asim via MP3Quran HTTPS CDN, single shared audio ownership with adhan preview, bounded network timeouts/retries, pause/resume/stop, route/lifecycle stop, source/privacy disclosures); test suite added | Fresh Codex gates, real physical-device audible listening verification, and qualified human religious signoff pending |
| Prayer notifications | Foundation activation disabled pending implementation | Native Android exact/fallback scheduling and iOS rolling horizon |
| Persistence | Foundation real SQLite tests cover schema v1 to v2 migration, transactions, concurrent preference updates, reset and reopen | Feature and real device acceptance |
| Store delivery | Development platform templates only | Final owner identity, signing/accounts/support URLs/device tests/submission |

## Verified foundation

Independent Astra verdict and bounded acceptance are recorded in [FOUNDATION-REVIEW.md](FOUNDATION-REVIEW.md). Local evidence: foundation-fix07 analyze/test logs and fresh debug APK build 10.4s. Task 2A has separate independent approval, recorded in [QURAN-REVIEW.md](QURAN-REVIEW.md). Its 89 tests and fresh debug build do not approve subsequent UI/native/store milestones.

Task 2B was separately approved by GPT-6 Sol on 2026-09-28 after the actual production/test diff and final 113-test/analyzer/build/source-integrity evidence were reviewed. See [QURAN-UI-REVIEW.md](QURAN-UI-REVIEW.md). Future reviews use GPT-6 Sol, as requested by the owner.

Task 3A prayer and city domain was separately approved by GPT-6 Sol on 2026-09-28. Focused tests 45/45 and full suite 158/158 passed, `flutter analyze --no-pub` found no issues, `git diff --check` passed, and a fresh debug APK was built. See [PRAYER-DOMAIN.md](PRAYER-DOMAIN.md) for the implemented policy and limits.

Task 3B1 prayer presentation was approved by GPT-6 Sol on 2026-09-28 after two review findings were corrected: tomorrow's Fajr no longer highlights today's Fajr row after Isha, and asset errors no longer expose internal details to users. Focused tests 11/11, full suite 169/169, `flutter analyze --no-pub`, content development validation and a fresh debug APK succeeded. The gallery in [preview/index.html](preview/index.html) shows the current screens, including Android and iPhone-size prayer views. Native iOS and notification testing remain open.

## Native compatibility

Debug and profile APK LOAD alignment and zipalign checks passed. Stricter GNU_RELRO end checks failed some prebuilt Flutter/SQLite libraries in both artifacts. A runtime crash has not been observed; actual 16KB runtime acceptance remains pending. The installed 16KB emulator cannot start with the available Windows hypervisor configuration. No driver/firmware changes or binary patches were made. See [BUILD-ENVIRONMENT.md](BUILD-ENVIRONMENT.md) for exact versions/checks and local evidence.

## External prerequisites

Owner confirmed developer-store accounts or Mac are pending. The Quran Foundation developer account prerequisite was superseded by the KFQC digital artwork substitution; the missing adhan recordings prerequisite was resolved with the three bundled free-licensed recordings. Independent local implementation continues; scheduled notification mechanics, qualified human religious review, signed iOS builds, and store publication cannot finish without those resources. See [EXTERNAL-REQUIREMENTS.md](EXTERNAL-REQUIREMENTS.md). Rights-request drafts are prepared for owner use, not sent.
