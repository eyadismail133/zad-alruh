# Android testing APK — 2026-10-09

## Artifact

- Version: **0.2.0+2**, package `dev.zadalruh.zad_alruh`.
- File: `D:\projects\زادُ الروح\dist\android\zad-alruh-0.2.0+2-debug.apk`.
- Size: **281,428,813 bytes**. Minimum Android: **8 / API 26**; target API 36.
- SHA-256: `4AF5D939B101FB54134C96D09820B8E037E56D7EC66EF17AA7031D99A70F53FC`.
- Debug signing: APK v2 verification passed. This is not a publisher-signed store artifact.

## Completed verification

Codex performed the final review and verification directly, following the owner's instruction to stop Antigravity/Flash delegation.

| Gate | Result |
|---|---|
| `flutter analyze --no-pub` | No issues, 2.8s |
| `flutter test --no-pub --concurrency 2 --timeout 3m --reporter expanded` | 528 passed, zero failures, 2m07s |
| Native Android JUnit, unchanged native revision `4508779` | Earlier scoped gate: 111 passed |
| Physical ASCII staging snapshot | 833 source/runtime files match original SHA-256; IDE `.iml` deliberately excluded |
| `flutter pub get --offline --enforce-lockfile` | Passed; original/staged lock hashes identical |
| `flutter build apk --debug --no-pub` | Passed, 18.7s (final rebuild after whitespace cleanup) |
| Packaged source inventory | All 619 required content/audio files match source hashes; all 604 Mushaf images present |
| Audio packaging | All 9 bundled Flutter/native audio entries stored uncompressed |
| APK signing | Verification passed, v2 signature |
| 16KB ZIP / ELF LOAD alignment | Passed for all 10 native libraries |
| GNU_RELRO end alignment | Failed for 6 prebuilt libraries; store compatibility remains open |
| USB install / physical sound / OEM background delivery | Not performed: ADB device list empty at handoff |

The JNI build failed from the original Arabic path even through its ASCII junction. The successful build used a physical verified snapshot at `D:\tools\zad-android-apk-20261009`. The original checkout was not moved. This snapshot is not linked to future source edits.

The tested revision includes the separate Mushaf image/chrome layout and zoom/navigation, Quran streaming with shared audio ownership, persisted adhan voice and native notification controls, daily morning/evening/Hisn/dua progress, database migration/reset/recovery, and compact Arabic interfaces for Hisn/Hadith/source details. Automated checks preserve source text and footnotes; they do not replace qualified religious review. Quran audio is online, full-surah streaming rather than page-synchronized playback.

## Remaining publication and device gates

GNU_RELRO failures affect arm64 `libdartjni.so`, `libflutter.so`, `libsqlite3.so`; armeabi-v7a `libdartjni.so`; and x86_64 `libflutter.so`, `libsqlite3.so`. No native binary patches were applied and no runtime crash or successful 16KB execution is claimed. Android documents alignment requirements in [16KB page size support](https://developer.android.com/guide/practices/page-sizes). The installed emulator still requires a working Windows hypervisor.

Before public release: verify readable pages/large text and audible Quran/adhan on a phone, notification permission/refusal/reboot/background behavior, device date rollover and reset; resolve 16KB findings and verify runtime compatibility; complete qualified human content review and publisher signing/account/support/privacy details. The owner has no Google Play developer account yet. iOS development is paused.

## Local evidence

Logs remain under `.local/` and are not shipped: `oct09-apk-analyze.log`, `oct09-apk-full-suite.log` (exit 0), `oct09-stage-source-verification.json`, `oct09-stage-pubget.log`, `oct09-stage-debug-build.log`, `oct08-apk-content-results.json` (contains the new artifact/hash despite its historical filename), `oct09-apk-signature.log`, `oct09-apk-badging.log`, and `oct09-new-debug-alignment-results.json`.
