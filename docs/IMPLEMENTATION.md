# Zad Alruh implementation contract

Approved by the owner on 2026-09-27. This is a new project, initially containing only `zad-alruh-design.zip`. The unmodified design is extracted into `design/`; supplied branding and licensed fonts are in `assets/`.

## Product

Flutter Android and iOS application, Arabic RTL, entirely free, no ads, no end-user account, no backend and no telemetry. Core content is bundled, never fetched at runtime. Full Madani Hafs Mushaf: 604 trusted page images, offline Quran search and accessible text. Reading position, bookmarks, dhikr counts/sessions, favorites, daily progress and preferences persist locally in SQLite. No import/export or cloud synchronization. Updates preserve user state. Delete/reset explicitly deletes local data. Device loss/uninstall may lose state.

Five navigation destinations: home, Quran, prayers, dhikr, more. More leads to duas, hadith, favorites, settings and sources/privacy. Follow warm cream, forest green and gold light design in `design/zad-alruh-light.html`; use the supplied logo and IBM Plex Sans Arabic fonts. Dark UI is supported, but Mushaf image colors are never inverted. Screens adapt to small phones, large text, safe areas and screen readers. No Quran recitation/player/reciter choice in v1.

## Services and data

- QuranRepository: chapters, juz, verses, page mapping, Arabic search over separate normalized keys (never change source verse text), immutable page references.
- ProgressRepository: real SQLite persistence, schema versions and migrations; reading page autosaved, optional exact verse selected manually; named bookmarks and favorites; dhikr sessions keyed by stable ID/date/category; transaction-backed capped increments. Unfinished sessions from previous dates remain resumable. An explicit new-session action never silently deletes old progress.
- PrayerCalculator: offline Adhan calculations for coordinates/date/IANA timezone/method/Asr madhab/high-latitude rule/minute adjustments; no fixed UTC offsets for cities. Cairo uses Egyptian method; other cities default Muslim World League. User chooses other supported methods. Umm al-Qura Ramadan adjustment needs an explicit tested policy. Manual cities always available; optional foreground-only location. Include offline world city/timezone data with provenance. No background location permissions.
- PrayerScheduler: permission-aware deterministic schedules and cancellation, refresh after settings changes/app foreground/timezone/time changes. Android uses user-granted SCHEDULE_EXACT_ALARM; denied permission yields approximate notification only and honest state. iOS schedules 10 days * 5 prayer notifications + one renewal reminder (51 <= 64), replaces stale schedules without duplicates and exposes last covered date. No indefinite iOS background promise.
- AdhanPlayer: bundled licensed audio preview/stop. Android full adhan started by a permitted exact alarm through a visible mediaPlayback foreground service; stop action, audio focus, calls, DND/silent handling and duplicate prevention. Reboot/update only reschedule; never play immediately. iOS custom notification clips under 30 seconds and user-initiated full playback inside app.

Use Riverpod, sqflite, Adhan and timezone. Isolate platform APIs at real OS boundaries. Test SQLite with a real temporary database (sqflite_common_ffi). Feature-focused files; no god controller and no unnecessary abstraction. Secrets and signing credentials stay outside Git.

## Content integrity: mandatory release gates

Do not invent, paraphrase, manually transcribe or generate Quran/dhikr/hadith/adhan content. Never use mock fixtures or religious text from design HTML in production. Content absence must be reported explicitly in Arabic UI and in release readiness; it must never look like complete content.

Quran pages: approved Quran Foundation APIs/documented CDN source and active developer account, source attribution and saved rights evidence. See https://api-docs.quran.com/legal/developer-terms/ . Account availability is not yet established. Quran text: exact Tanzil Uthmani v1.1 source with its original license/comment block retained and attribution https://tanzil.net/docs/Text_License . Metadata must be verified against the same Hafs 604-page Mushaf; do not assume unrelated numbering aligns. Keep source URLs, release version, acquisition date and SHA-256 file checksums. No source substitution without disclosure.

Dhikr/duas: documented Hisn al-Muslim edition and digital reuse permission, references and repetition counts. Hadith: 100 authentic records from HadeethEnc with reference/authenticity and documented Arabic reuse rights. A qualified human reviewer must approve the religious corpus. Audio: three licensed recordings, including Fajr version, explicit bundling and permitted short excerpt rights; real correct names only. A license to software is not a license to its content. Unavailable rights/assets block content release, not routine infrastructure work.

Implement a machine-readable content manifest and a strict CLI release validator: missing files/counts, altered hashes, invalid page/verse mappings, incomplete references, unapproved licenses/human review must fail release readiness with actionable errors. Development builds may run with clearly labeled missing-content states, never with synthetic religious content.

## User behavior

Daily progress has five independent tasks: Quran daily goal (default 2 pages, configurable and explicitly confirmed), morning dhikr completion, evening dhikr completion, a post-prayer dhikr session completion, dua of the day explicitly confirmed. Dhikr completion follows required counts. It is personal organization, not a religious score. Daily buckets use the selected timezone; do not wipe unfinished sessions at midnight. Choosing another timezone must not overwrite existing historical buckets.

Bookmarks can be named/deleted; search result opens the mapped page. Page navigation/zoom is RTL-correct, with only nearby images cached. Text size changes UI/accessible text, not original images. Permission requests follow an explicit contextual user action, never block other sections. Notifications default off. Reset all local data requires a confirmation and cancels schedules/stops sound. Provide retryable Arabic error states on load/persistence failure.

## Execution workflow

Codex owns investigation, briefs, actual verification and acceptance. Antigravity via `agy-delegate` and global implement lane owns implementation; default model; no commit or further delegation. Astra reviews actual diff with APPROVED or CHANGES_REQUESTED plus evidence. Delta briefs return to the recorded Antigravity conversation. Codex only commits reviewed changes. Do not bypass Antigravity permissions, change global allow rules, publish, push, pay for services, create owner accounts, or fabricate credentials.

## Verification and delivery

Project commands once bootstrapped: `flutter analyze`, `flutter test`, relevant integration tests, `flutter build appbundle --release`, `flutter build ipa --release` on macOS. Run domain tests with real infrastructure; regression tests before fixes. Record commands that actually ran separately from pending device/manual checks.

Acceptance: complete 604-page/114-chapter Quran and all verified metadata offline on first install; exact source text; airplane-mode usable assets; persisted state after force-close/restart/update; migrations keep historical data; daily/dhikr boundaries; city timezone/DST/Ramadan/high-latitude fixtures; denied/revoked permissions; lockscreen/background/battery/call/reboot behaviors on Pixel, Samsung, Xiaomi and real iPhone; screen reader/large font/small screen; 16 KB native library compatibility. Religious review and device checks cannot be claimed from unit tests.

Target Android 8+ (API 26), target API 36+ per current store policy; iOS 15+ built with current compliant SDK (iOS 26+). Placeholder application identity is DEVELOPMENT ONLY; final owner-controlled identity must be verified before first store upload. Owner signing secrets excluded. Public HTTPS support/privacy pages and support contact must be configured for release. App Store privacy manifests, Data Safety/App Privacy, content rating, permissions, no-account review notes, actual screenshots/icons, signing and store test tracks are release prerequisites. New personal Google accounts may require 12 continuously opted-in testers for 14 days. macOS/iPhone access, content source accounts/rights, developer accounts, signing, human review and public support URL are external requirements not presently established.

## Milestones

1. Tooling, repository, design assets; small verified app + platform feasibility.
2. Trusted content pipeline and responsive UI.
3. Quran browsing/search/bookmarks, persistent sessions/favorites/daily progress.
4. Offline global prayer calculations, permission-aware scheduling and native audio.
5. Signed build/device/integration review, store artifacts and actual owner-controlled launch.

All five milestones are the request. Do not describe a development shell or a passing test suite as store-ready. Keep a readiness report identifying verified, implemented/unverified and externally blocked acceptance criteria.
