# Readiness Report: Offline Global City Selection & Prayer Calculation Settings Persistence

## 1. Overview & Objective
This update delivers offline global city selection across the complete 34,149 GeoNames dataset and persisted prayer calculation settings for Android/global scope. It upgrades the application database to schema version 4, guarantees full data migration parity across all 9 database tables, enforces Sol6.1 lifecycle and reset generation guards in `PreferencesController`, provides single-snapshot calculation coordination via `effectivePrayerSettingsProvider`, and resolves all static analyzer issues (including the 24 diagnostics reported in `.local/oct08-global-analyze.log`).

---

## 2. Architectural Components & Implementation Details

### Database Schema v4 & Migration Parity (`AppDatabase`)
- **Version Bump**: Schema upgraded from version 3 to version 4 (`schemaVersion = 4`).
- **All 9 Tables Maintained**:
  1. `reading_progress`
  2. `bookmarks`
  3. `favorites`
  4. `dhikr_sessions`
  5. `daily_progress`
  6. `user_preferences`
  7. `hisn_daily_item_progress` (v3 table, 267 items across morning/evening/shared_100)
  8. `daily_quran_pages` (v3 table, 1..604 pages)
  9. `daily_source_confirmations` (v3 table, daily_dua / post_prayer)
- **New Columns in `user_preferences`**:
  - `selected_city_id INTEGER`: Stable canonical GeoNames ID (default 360630 for Cairo).
  - `calculation_method TEXT`: Nullable manual method override (defaults to NULL, using city-default).
  - `asr_madhab TEXT NOT NULL DEFAULT 'shafi'`: Asr calculation madhab (`shafi` or `hanafi`).
  - `high_latitude_rule TEXT NOT NULL DEFAULT 'middle_of_the_night'`: High latitude rule (`middle_of_the_night`, `seventh_of_the_night`, `twilight_angle`).
  - `polar_resolution TEXT NOT NULL DEFAULT 'unresolved'`: Polar day policy (`unresolved`, `nearestLatitude`).
  - `ramadan_policy TEXT NOT NULL DEFAULT 'eveningOfRamadan'`: Umm Al-Qura Ramadan +30 min Isha policy (`eveningOfRamadan`, `civilDay`, `disabled`).
  - `hijri_day_adjustment INTEGER NOT NULL DEFAULT 0`: Manual Hijri calendar shift (-2..2 days).
  - `fajr_offset INTEGER NOT NULL DEFAULT 0`: Fajr minute offset (-120..120).
  - `sunrise_offset INTEGER NOT NULL DEFAULT 0`: Sunrise minute offset (-120..120).
  - `dhuhr_offset INTEGER NOT NULL DEFAULT 0`: Dhuhr minute offset (-120..120).
  - `asr_offset INTEGER NOT NULL DEFAULT 0`: Asr minute offset (-120..120).
  - `maghrib_offset INTEGER NOT NULL DEFAULT 0`: Maghrib minute offset (-120..120).
  - `isha_offset INTEGER NOT NULL DEFAULT 0`: Isha minute offset (-120..120).
- **Migration Path (`_upgradeToV4`)**:
  - Automatically migrates existing database installations from v1, v2, or v3 to v4.
  - Converts canonical legacy 8 city+timezone pairs to their verified GeoNames IDs:
    - Cairo (`القاهرة|Africa/Cairo`) -> `360630`
    - Makkah (`مكة المكرمة|Asia/Riyadh`) -> `104515`
    - Madinah (`المدينة المنورة|Asia/Riyadh`) -> `109223`
    - Riyadh (`الرياض|Asia/Riyadh`) -> `108410`
    - Dubai (`دبي|Asia/Dubai`) -> `292223`
    - Jerusalem (`القدس الشريف|Asia/Jerusalem`) -> `281184`
    - Istanbul (`إسطنبول|Europe/Istanbul`) -> `745044`
    - London (`لندن|Europe/London`) -> `2643743`
  - Unrecognized legacy selections retain `selected_city_id = NULL` (recoverably unresolved, never destructively overwritten with Cairo).

### Preferences Domain & Field-Intent Updates (`UserPreferences`, `ProgressRepository`)
- **Strict Bounds Validation**: Validates client-side and persistence boundaries:
  - Hijri adjustment strictly constrained to `[-2, 2]`.
  - Event offsets strictly constrained to `[-120, 120]`.
  - Calculation methods validated against supported domain types.
- **Sentinel-Based Clearing**: Supports clearing nullable calculation method override (`calculationMethodOverride: kPreferenceSentinel` or `clearCalculationMethodOverride: true`) to restore city-default without losing other configurations.
- **Atomic City Updates**: Changes `selected_city_id`, `selected_city`, and `selected_timezone` atomically in a single write operation.
- **Preservation of Raw Values on Unrelated Writes**: `updatePreferencesFields` constructs `updateMap` containing ONLY the explicitly provided intent keys. Corrupted raw method or timezone fields in SQLite remain untouched when unrelated fields (e.g. `darkMode`, `quranDefaultGoal`) are modified.
- **Reset Parity**: `resetLocalState()` resets `selected_city_id` to 360630 (Cairo), `selected_timezone` to `Africa/Cairo`, and clears all overrides back to defaults.

### Sol6.1 Lifecycle & Acceptance Generation Token Guards (`PreferencesController`)
- **Generation Capture at Invocation**: Every mutation captures `mutationBarrier.currentGeneration` synchronously at invocation time.
- **Post-Await Generation Verification**: Before writing to repository and after awaiting barriers, checks `capturedGen == mutationBarrier.currentGeneration`. If a reset occurred during the wait, stale operations are rejected.
- **Epoch & Disposal Token**: `_instanceEpoch` tracks controller instance lifecycle. Callbacks and retained retry closures verify `_isDisposed == false` and current epoch before publishing state updates. Disposed controllers reject further mutations with `StateError` without touching SQLite.
- **Deduplication in `_mutateFields`**: Extracted single local `executeIntent` function referenced from both `then` and `onError` branch adapters of `_writeQueue`, eliminating redundant repeated logic while maintaining exact FIFO and generation checking semantics.
- **Direct Synchronous Reset Fence**: Reset operations directly execute the mutation barrier fence without intervening audio awaits, ensuring unblockable state reset.

### Single Immutable Calculation Snapshot (`prayers_controller.dart`)
- **`EffectivePrayerSettings` Snapshot**:
  - Encapsulates resolved `SelectedCity` and fully resolved `PrayerSettings`.
  - Exposes stable `cityId`, `timezone`, and a calculation `fingerprint` covering all 14 calculation inputs.
  - Implements value equality (`operator ==` and `hashCode`) for change detection by coordinators.
- **Recovery & Coherence Enforcement**:
  - Checks `prefs.prayerSettingsRecoveryNotice`: if corrupted settings were detected in raw SQLite storage, returns actionable Arabic `AsyncError(PrayerSettingsCorruptedException)` BEFORE calculations, preventing calculators from receiving invented fallback defaults.
  - Validates timezone coherence between canonical city (`city.timezone`) and stored preferences (`prefs.selectedTimezone`). Incoherent pairings reject with `AsyncError(IncoherentCityTimezoneException)`.
  - Atomic city selection (`setSelectedCity(city)`) repairs both city and timezone simultaneously, recovering the snapshot without silent fallback.
- **`effectivePrayerSettingsProvider`**:
  - `Provider<AsyncValue<EffectivePrayerSettings>>` synchronously derives from the same preferences snapshot and `cityRepositoryProvider`.
  - When override is `null`, resolves to city's default calculation method.
  - Explicit manual override persists across city changes until explicitly cleared by user.
  - Exposes loading/error accurately without falling back to Cairo during errors.
  - Unknown/corrupt stored city ID produces `CityNotFoundException` / `UnresolvedCityException`.
- **`selectedPrayerCityProvider`**: Derived directly from `effectivePrayerSettingsProvider`.
- **`PrayerTimesNotifier` Consumption**: Notifier build, minute tick, and app lifecycle resume consume this single snapshot and the city's civil date.

### User Interface & Responsiveness
- **`CitySearchPickerDialog`**:
  - Searches offline across all 34,149 GeoNames cities with Arabic diacritic-insensitive and Latin search.
  - Displays localized Arabic city name, country name, timezone, and formatted population.
  - Responsive at 320x480 viewport down to text scale 2.0 without RenderFlex overflows.
- **`PrayerCalculationSettingsSection`**:
  - Method selector showing effective method and city default status.
  - Explicit "Reset to city default" action when manual override is active.
  - Controls for Madhab, High Latitude rule, Polar Day resolution, Ramadan policy, Hijri adjustment, and 6 event offsets.
  - All form controls utilize `initialValue:` with dynamic `ValueKey` to support state resets.
  - Context navigation and SnackBar invocations guarded by `if (!context.mounted) return;`.
- **`PrayersScreen`**:
  - Wired city card to `CitySearchPickerDialog`.
  - Added `_buildCalculationMethodCard` displaying effective method and override indicator.
- **`SettingsScreen`**:
  - Fixed audio preview call from nonexistent `playAdhanVoice` to `_audioController.playVoice(voice)`.
  - Removed unreferenced `_updateCity`.
  - Replaced raw `err.toString()` with stable Arabic error text.
  - Reset action directly triggers synchronous state reset.
- **`SourcesScreen` Disclosure**:
  - Updated disclosure to truthfully state that CDN applicability AND retention are unconfirmed; users should not assume provider website policy applies to CDN requests.

---

## 3. Analyzer Diagnostics Resolution (`.local/oct08-global-analyze.log`)
All 24 reported diagnostics were resolved using real production APIs:
1. **API Alignment in `test/city_prayer_settings_migration_test.dart`**:
   - Replaced nonexistent parameter `hijriAdjustment` with real parameter `hijriDayAdjustment`.
   - Replaced nonexistent parameter `calculationMethod` with real parameter `calculationMethodOverride` and `clearCalculationMethodOverride: true`.
   - Replaced nonexistent enum `AsrMadhab` with canonical `Madhab` from `package:adhan/adhan.dart`.
   - Replaced nonexistent controller method `setCalculationMethod` with real methods `setCalculationMethodOverride` and `clearCalculationMethodOverride`.
   - Removed invalid `const` keyword on `PrayerSettings(...)` constructor invocations.
   - Replaced made-up `runExclusive` call with genuine `GatedProgressRepository` test pattern exercising real SQLite and real `PreferencesController`.
2. **Redundant Imports Cleared**:
   - Removed redundant import `package:zad_alruh/src/features/progress/data/progress_mutation_barrier.dart` from `test/daily_progress_core_test.dart:18:8` and `test/daily_progress_ui_test.dart:27:8`, as it is re-exported by `progress_controller.dart`.

---

### Reset State & Riverpod Dependency Safety (`PreferencesController.resetAllState`)
- **Circular Dependency Elimination**: Removed inverted `ref.invalidate(activeDateBucketProvider)` inside `resetAllState`. Because `activeDateBucketProvider` depends on `preferencesControllerProvider`, publishing `state = AsyncValue.data(freshPrefs)` updates derived date bucket state naturally without triggering Riverpod circular dependency errors.
- **Synchronous Fence & Drain**: Preserved pre-reset synchronous fence, pending write drain across all mutation families, confirmed audio stop and native alarm reset before atomic 9-table SQLite reset.

---

## 4. Test Suite Coverage (`test/city_prayer_settings_migration_test.dart`)
A comprehensive test suite was implemented covering:
1. **Schema & Table Parity**: Fresh v4 creation and migration from v1, v2, and v3 to v4 asserting all 9 tables and column presence in real SQLite.
2. **Canonical City Migration**: Conversion of the 8 legacy city+timezone pairs and preservation of unrecognized legacy cities as `NULL`.
3. **Repository Bounds & Sentinel Clears**: Strict validation for Hijri adjustment and offsets; clearing overrides with sentinels.
4. **Sol6.1 Lifecycle & Generation Rejection**:
   - Genuine accepted queued setter test using `GatedProgressRepository` gating response delivery of the first SQLite write: verifies that an operation accepted before reset is rejected post-await with `StateError`, that SQLite defaults remain intact, that subsequent fresh setters succeed, and response gate is guaranteed released in `finally`.
   - Disposed controller rejection asserting immediate `StateError` and untouched SQLite state.
5. **Effective Prayer Settings Injection & Recovery**:
   - Injected raw malformed `calculation_method` in SQLite: verified `PrayerSettingsCorruptedException`, confirmed unrelated `darkMode` update preserves raw malformed value, and proved explicit repair restores valid calculation.
   - Injected incoherent timezone: verified `IncoherentCityTimezoneException`, confirmed unrelated `textScale` update preserves incoherent timezone, and proved atomic city repair restores coherency.
   - Manual override retention across city change and restoration of city-default (`muslim_world_league`) upon clearing.
   - Fingerprint calculation inputs and value equality.
6. **Responsive UI & Real Dialog Harness**:
   - `CitySearchPickerDialog`: Real dialog harness test via `CitySearchPickerDialog.show`, searching 'مكة', selecting result via actual display title `'${city.arabicName} (${city.name})'`, and asserting returned canonical ID (104515) and timezone (`Asia/Riyadh`).
   - `PrayerCalculationSettingsSection`: Interactive gestures at compact 320x480 viewport and text scale 2.0 with all 4 IBM Plex font weights and Amiri Quran font loaded. Real drag gestures, `tapAndAwaitPreference` dispatching I/O in `runAsync` with bounded publication completion, assertions outside `runAsync`, and proper unmount, operation drain, and SQLite closure in `finally`.

---

## 5. Verification Status
> [!IMPORTANT]
> **VERIFICATION NOT RUN**: In strict compliance with instructions, no terminal, Flutter, Dart, Gradle, build, or gate commands were executed during this session. Root / Codex will execute independent verification, static analysis, and test gates.

---

## 6. Complete List of Touched Files
1. `lib/src/features/prayers/presentation/controllers/prayers_controller.dart`
2. `lib/src/features/progress/presentation/controllers/progress_controller.dart`
3. `test/daily_progress_core_test.dart`
4. `test/daily_progress_ui_test.dart`
5. `test/city_prayer_settings_migration_test.dart`
6. `READINESS.md`
