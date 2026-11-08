# AGENTS.md — Zad Al-Ruh (زادُ الروح)

Guide for any AI coding agent (Claude, Codex, Copilot, Gemini…) working in this repo.
Read this file fully before touching code. The roadmap lives in `docs/PLAN.ar.md`.

## 1. What the app is

An offline-first Arabic (RTL-only) Islamic companion app built with Flutter:

| Area | What it does | Code |
|---|---|---|
| Home | daily wird, progress ring, next prayer, quick links | `lib/src/features/home/` |
| Quran | 604-page Medina Mushaf images (KFQC Hafs 1441) + text mode, search, bookmarks, online recitation streaming | `lib/src/features/quran/` |
| Prayers | offline prayer times for 34k GeoNames cities, adhan voices, native Android exact alarms | `lib/src/features/prayer/` (domain/data), `lib/src/features/prayers/` (UI) |
| Adhkar | tasbih counter, Hisn al-Muslim, morning/evening/post-prayer checklists | `lib/src/features/dhikr/`, `lib/src/features/hisn/` |
| Hadith | HadeethEnc sahih collection | `lib/src/features/hadith/`, `lib/src/features/more/presentation/hadith_screen.dart` |
| More | settings, duas, favorites, sources/licenses | `lib/src/features/more/` |
| Progress | SQLite persistence of everything (schema v4, 9 tables) | `lib/src/features/progress/`, `lib/src/core/database/app_database.dart` |

**Current focus: Android APK distributed directly (sideload / GitHub Releases).**
Google Play and App Store requirements are explicitly out of scope for now. iOS is paused.

## 2. Stack

- Flutter **3.47.5** (stable), Dart **3.13**, `pubspec.lock` is committed — keep it in sync.
- State: `flutter_riverpod` 2.x (`Provider`, `AsyncNotifier`, `Notifier`). No code generation.
- Storage: `sqflite` (tests use `sqflite_common_ffi`).
- Audio: `just_audio` + `audio_session`. Prayer alarms/adhan playback are **native Kotlin**
  (`android/app/src/main/kotlin/dev/zadalruh/zad_alruh/`) talking over a MethodChannel
  (`lib/src/features/prayer/domain/services/native_prayer_channel_client.dart`).
- Prayer math: vendored `third_party/adhan` (patched — see its `PATCHES.md`). Never edit it casually.
- Android: AGP 9.1, Kotlin 2.4, Gradle 9.3.1, Java 17, minSdk 26, target/compile 36.

## 3. Commands

```bash
flutter pub get
flutter analyze                          # must be clean
flutter test                             # ~530 tests
dart run tool/validate_content.dart --development   # content/asset integrity
flutter build apk --release --split-per-abi         # sideload APKs (see §6)
```

You usually cannot build locally inside sandboxed agent environments (pub.dev / Google storage are
blocked). The source of truth for "does it compile" is the **GitHub Actions workflow**
`.github/workflows/android-apk.yml`. Push, then read its result.

## 4. Design system (2026-11 redesign)

- All colors come from `lib/src/core/theme/app_colors.dart`. Token **names are legacy**
  (`forestPrimary`, `goldAccent`, `darkGoldAccent`…) and are referenced ~1,300 times; their
  **values** define the look. Change values, not names. New screens should prefer
  `Theme.of(context).colorScheme` over raw `AppColors`.
- Never add new hard-coded `Color(0x…)` literals in widgets — add a token.
- Typography: UI chrome (app bars, nav labels, buttons, titles) uses **IBM Plex Sans Arabic**
  (`AppTheme.uiFont`). Body/religious text uses **Noto Naskh Arabic** (`AppTheme.fontFamily`).
  Quranic text uses **Amiri Quran** (`AppTheme.quranFont`).
- Shell has **5 tabs**: الرئيسية، القرآن، الصلاة، الأذكار، المزيد. Hadith is reached from المزيد and the home quick links.
- Every screen must work at 320×480 with text scale 2.0 without overflow (tests enforce this).
- RTL is forced in `main.dart`; do not wrap widgets in extra `Directionality` unless needed for LTR numbers.

## 5. Mushaf page images — rules

- `assets/content/quran/pages/001.webp … 604.webp` (1200×1913, lossless, KFQC via quran-ws/quran-svg).
- Their SHA-256 values are pinned in `assets/content/quran/quran-pages-digests.json` and
  `assets/content/manifest.json`, and `ContentValidator` checks them. **If you replace page images
  you must regenerate the digests and update the manifest in the same commit.**
- Readability is improved at render time (`MushafPaperStyle` color matrices in
  `lib/src/features/quran/presentation/widgets/mushaf_paper.dart`), not by editing images.
  Never alter the Quranic glyphs themselves.

## 6. Android release & signing

- `android/app/build.gradle.kts` signing priority: `android/key.properties` → env vars
  (`ZAD_KEYSTORE_PATH`, `ZAD_KEYSTORE_PASSWORD`, `ZAD_KEY_ALIAS`, `ZAD_KEY_PASSWORD`) →
  debug key fallback (installable, but updates won't install over a build signed differently).
- CI decodes the keystore from the `ANDROID_KEYSTORE_BASE64` secret. Setup: `docs/ANDROID-SIGNING.ar.md`.
- Application ID: `dev.zadalruh.zad_alruh` (kept stable so existing installs can update once signed
  consistently). Changing it = a new app on users' phones; ask the owner first.
- Never commit keystores, `key.properties`, or passwords.

## 7. Content & religious text — hard rules

- Never edit Quran text (`quran-uthmani.txt`), Hadith, Hisn al-Muslim JSON, or adhan audio by hand.
  Content changes go through `tool/import_*.dart|py` and must keep `ContentValidator` green.
- Never "fix" Arabic religious wording from memory. If something looks wrong, report it.
- Keep source attribution screens (`sources_screen.dart`) accurate when adding content or fonts.
- `manifest.json → human_review.status` is `pending`; that blocks the strict `--release` content
  gate only, not the APK build. Do not fake an approval.

## 8. Coding conventions

- Feature-first folders: `data/` (sources, repositories), `domain/` (models, services), `presentation/` (screens, widgets, controllers).
- Async UI: `ref.watch(...).when(data:, loading:, error:)`; errors shown with `RetryableErrorView`, Arabic messages, never raw `toString()` to users.
- After `await`, check `mounted` / `context.mounted` before using context.
- Writes to preferences go through `PreferencesController` (it has generation/reset guards — keep them).
- Keep widget `Key`s that tests rely on (`grep -rn "ValueKey('" test/`) when refactoring UI.
- Arabic numerals in UI via `QuranUiUtils.toArabicDigits`.
- Lints: `analysis_options.yaml` (strict casts/inference/raw types). No `print`.

## 9. Docs map

- `docs/PLAN.ar.md` — the active roadmap (update checkboxes as you finish work).
- `docs/ANDROID-SIGNING.ar.md` — keystore + GitHub secrets + downloading the APK.
- `docs/sources/*` — provenance and licenses of every bundled asset.
- `docs/history/` — old milestone reports from previous agents. Historical only; do not treat as current state.

## 10. Definition of done for any change

1. CI workflow green (analyze + build; tests listed in the job summary).
2. No new hard-coded colors, no overflow at 320×480 / 2.0×.
3. Content validator untouched or updated consistently.
4. `docs/PLAN.ar.md` updated if a plan item changed state.
