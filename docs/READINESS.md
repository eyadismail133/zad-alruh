# Milestone acceptance status

This record separates implemented work, verified work and external prerequisites. No item implies religious certification or store approval.

| Area | Verified/current evidence | Remaining work |
|---|---|---|
| Design | Supplied archive, logo, Arabic fonts and original licenses retained; actual foundation widget renders inspected | Compare subsequent screens with design and verify accessibility on devices |
| Tooling | Flutter3.47.5/Dart3.13.4, AndroidAPI36/NDK28 installed; debug and profile APKs built | iOS requires macOS/Xcode; native16KB RELRO finding and runtime tests remain |
| Foundation | Astra APPROVED Task1; analyze and24tests passed; approved commit03b57a7 | Later feature/schema/native milestones require separate review |
| Quran source/domain | Historical Astra APPROVED Task2A; canonical hashes,114chapters/6236verses/604boundaries/30juz; original assets verified unchanged in latest debug APK | Content/image/religious review |
| Quran interface | GPT-6 Sol APPROVED Task2B; offline index/search/reader/explicit stop/bookmarks/favorites/source notices; full113tests and analyze passed, fresh debug build14.0s | Physical-device accessibility and image-mode acceptance when approved604images are supplied |
| Mushaf images | No approved images supplied | Quran Foundation access/permission,604images, alignment and human review |
| Global cities | Original GeoNames cities15000 snapshot34149records and CC BY4.0 attribution; offline Arabic/Latin search and nearest-city domain reviewed by GPT-6 Sol; the eight legacy settings cities now display real prayer results | Global city picker and persisted selection beyond those eight cities |
| Prayer calculation domain | GPT-6 Sol APPROVED Task3A; pinned MIT Adhan engine with 3 documented patches, city-anchored timezone/DST, method settings, estimated/polar-day policy and cross-midnight next prayer; full158 tests, analyze clean, debug APK built | Persist choices, schedule and device-verify notifications/adhan; qualified review of prayer times |
| Prayer presentation | GPT-6 Sol APPROVED Task3B1; Home and prayer screen use actual offline calculation for eight settings cities, showing next prayer by instant, countdown, sunrise, method and explicit error/unsupported states; full169 tests, analyze clean, fresh debug APK | Global city picker, method settings UI, notification activation and native device verification |
| Visual preview | Screenshots rendered from Flutter widgets at Android360x800 and iPhone390x844, with a clickable gallery at [preview/index.html](preview/index.html) | This is a screenshot simulation, not a native iOS build or device acceptance test |
| Dhikr/duas/hadith | No licensed digital corpus imported | Exact-edition rights, referenced records and qualified human review |
| Adhan | No licensed recordings supplied | Three voices including Fajr and permitted clips; playback/device verification |
| Prayer notifications | Foundation activation disabled pending implementation | Native Android exact/fallback scheduling and iOS rolling horizon |
| Persistence | Foundation realSQLite tests cover transactions, failures, reset and reopen | Later schema migrations and feature/device acceptance |
| Store delivery | Development platform templates only | Final owner identity, signing/accounts/support URLs/device tests/submission |

## Verified foundation

Independent Astra verdict and bounded acceptance are recorded in [FOUNDATION-REVIEW.md](FOUNDATION-REVIEW.md). Local evidence: foundation-fix07 analyze/test logs and fresh debug APK build10.4s. Task2A has separate independent approval, recorded in [QURAN-REVIEW.md](QURAN-REVIEW.md). Its89tests and fresh debug build do not approve subsequent UI/native/store milestones.

Task2B was separately approved by GPT-6 Sol on2026-09-28 after the actual production/test diff and final113-test/analyzer/build/source-integrity evidence were reviewed. See [QURAN-UI-REVIEW.md](QURAN-UI-REVIEW.md). Future reviews use GPT-6 Sol, as requested by the owner.

Task3A prayer and city domain was separately approved by GPT-6 Sol on2026-09-28. Focused tests45/45 and full suite158/158 passed, `flutter analyze --no-pub` found no issues, `git diff --check` passed, and a fresh debug APK was built. See [PRAYER-DOMAIN.md](PRAYER-DOMAIN.md) for the implemented policy and limits.

Task3B1 prayer presentation was approved by GPT-6 Sol on2026-09-28 after two review findings were corrected: tomorrow's Fajr no longer highlights today's Fajr row after Isha, and asset errors no longer expose internal details to users. Focused tests11/11, full suite169/169, `flutter analyze --no-pub`, content development validation and a fresh debug APK succeeded. The gallery in [preview/index.html](preview/index.html) shows the current screens, including Android and iPhone-size prayer views. Native iOS and notification testing remain open.

## Native compatibility

Debug and profile APK LOAD alignment and zipalign checks passed. Stricter GNU_RELRO end checks failed some prebuilt Flutter/SQLite libraries in both artifacts. A runtime crash has not been observed; actual16KB runtime acceptance remains pending. The installed16KB emulator cannot start with the available Windows hypervisor configuration. No driver/firmware changes or binary patches were made. See [BUILD-ENVIRONMENT.md](BUILD-ENVIRONMENT.md) for exact versions/checks and local evidence.

## External prerequisites

Owner confirmed no Quran Foundation/developer-store accounts, licensed adhan recordings or Mac. Independent local implementation continues; content rights/human review, signed iOS builds and publication cannot finish without those resources. See [EXTERNAL-REQUIREMENTS.md](EXTERNAL-REQUIREMENTS.md). Rights-request drafts are prepared for owner use, not sent.

