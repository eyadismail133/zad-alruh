# Zad Alruh — Offline Prayer and City Domain

## Overview

The prayer and city domain is a self-contained, pure Dart subsystem designed for offline prayer time calculations, global city searches, and deterministic next-prayer scheduling. It is completely decoupled from Flutter UI and native plugins, enabling execution within both the application runtime and headless background tasks (such as Android exact alarm scheduling).

---

## 1. GeoNames Offline City Dataset & Search

### Provenance and Integrity
- **Source**: GeoNames `cities15000.txt` (cities with population > 15,000 or regional/national capitals).
- **Location**: `assets/content/cities/cities15000.txt`.
- **License**: Creative Commons Attribution 4.0 International (CC BY 4.0), documented in `assets/content/cities/GEONAMES-LICENSE-README.txt` and `docs/sources/GEONAMES.md`.
- **File Integrity**:
  - Size: 8,534,034 bytes (8.53 MB).
  - Exact Records: 34,149 rows.
  - SHA-256 Checksum: `c8e0a782e44ba580a2c0f0e3c9538051351629b442d4e6ff244aa609bd790a8d`.
  - Upstream Readme Checksum: `b1957379b6c1242c700c98ac9a8aa0a09f56c3c0a50ee72175527005f48ef2c5`.

### Schema & Validation
Each record contains 19 tab-separated columns:
- `id` (col 0): Positive unique integer geonameid.
- `name` (col 1): Geographical point UTF-8 name.
- `asciiname` (col 2): Plain ASCII name.
- `alternatenames` (col 3): Comma-separated aliases (12,358 records contain verified Arabic aliases).
- `latitude` (col 4) & `longitude` (col 5): WGS-84 decimal coordinates validated in `[-90, 90]` and `[-180, 180]`.
- `countryCode` (col 8): ISO-3166 2-letter uppercase country code.
- `population` (col 14): Bigint/integer population count.
- `timezone` (col 17): IANA timezone identifier (all 356 distinct zones verified in `timezone` 0.11.1 `latest_all`).

### Arabic & Latin Search Normalization
The search engine matches queries across primary names, ASCII names, and all localized aliases without modifying the original source text:
- **Diacritics (Tashkeel)**: Strips Harakat (`\u064B`–`\u065F`, `\u0670`) from both queries and indexed aliases.
- **Alef Variants**: Unifies `إ`, `أ`, `آ`, and `ٱ` into bare `ا`.
- **Taa Marbuta**: Normalizes `ة` to `ه`.
- **Alef Maksura / Yaa**: Normalizes `ى` to `ي`.
- **Tatweel (Kashida)**: Strips elongation characters (`ـ`).
- **Whitespace / Compounding**: In Arabic, multi-word city names can be written with or without spaces (e.g. `نيو يورك` vs `نيويورك`, `كفر الشيخ` vs `كفرالشيخ`, `بور سعيد` vs `بورسعيد`). Search keys are evaluated both with spaces collapsed and with spaces removed. Thus, querying `نيو يورك` matches the unspaced GeoNames alias `نيويورك`.
- **Ranking & Disambiguation**: Exact matches rank highest (score 100), followed by prefix matches (score 75), then substring matches (score 50). Tied scores are ordered by `population` descending. Country codes and timezone names are exposed to facilitate user disambiguation.

### Nearest City Suggestion
- Given arbitrary coordinates (e.g. from foreground GPS), `CityRepository.findNearestCity` computes the Haversine great-circle distance to all cities.
- **Limitation**: Nearest city lookup is an approximate proximity suggestion; it is **not** a territorial border polygon lookup. For cities near international borders or timezone boundaries, the user must confirm their selected city.

---

## 2. Timezone & Civil Date Architecture

- **Timezone Database**: Pure Dart `package:timezone/timezone.dart` initialized with `latest_all` database.
- **City-Anchored Civil Dates**: The civil calendar date (year, month, day) is determined solely by the selected city's IANA timezone:
  ```dart
  final cityLocation = tz.getLocation(city.timezone);
  final cityLocalTime = tz.TZDateTime.from(utcNow, cityLocation);
  final todayCivil = DateTime(cityLocalTime.year, cityLocalTime.month, cityLocalTime.day);
  ```
  The device's local timezone **never** determines the prayer calculation date.
- **UTC Instants**: All calculated prayer event times are strictly anchored to UTC `DateTime` instants (`utcDateTime.isUtc == true`). Local time strings are only derived for display via `PrayerEvent.toCityTime(ianaTimezone)`.
- **Canonical Defaults**:
  - Default city: Cairo, Egypt (`id: 360630`, `lat: 30.06263`, `lon: 31.24967`, `Africa/Cairo`, `EG`).
  - Egypt defaults to Egyptian General Authority of Survey (`CalculationMethod.egyptian`).
  - Other countries default to Muslim World League (`CalculationMethod.muslim_world_league`).

---

## 3. Vendored Engine & Minimal Patches

The application vendors `adhan: 2.0.0+1` (MIT License) in `third_party/adhan`. Three minimal patches were applied (documented in `third_party/adhan/PATCHES.md`):

1. **Civil Day-of-Year (`datetime.dart`)**:
   Upstream calculated elapsed days to device-local Jan 1. On timezones with Daylight Saving Time shifts (such as Cairo), this caused off-by-one errors on DST transition dates (e.g. returning 114 instead of 115 on 2026-04-25, and 269 instead of 270 on 2026-09-27). The patch calculates the civil day ordinal purely using UTC civil date components minus `DateTime.utc(year, 1, 1)`.
2. **UTC-Preserving Minute Rounding (`calendar_util.dart`)**:
   Upstream `roundedMinute` used `when.copyWith` on local `DateTime` instances. During ambiguous repeated local DST hours (such as Cairo 2026-10-29 fall-back), `copyWith` selected the earlier occurrence (+3) instead of (+2), corrupting the resulting UTC instant by 1 hour. The patch rounds in UTC and restores local timezone representation only if required.
3. **Fixed-Interval Isha with Twilight-Angle Rule (`calculation_parameters.dart`)**:
   Methods with fixed-interval Isha (such as Umm Al-Qura with 90-minute Isha and null `ishaAngle`) crashed when `HighLatitudeRule.twilight_angle` was selected because `nightPortions` unconditionally required `ishaAngle`. The patch assigns `0.0` to the unused Isha fraction when `ishaInterval > 0` while preserving genuine `fajrAngle / 60.0` fraction calculation.

---

## 4. High-Latitude and Polar Day Policies

- **High-Latitude Twilight Estimation Detection**:
  - `PrayerCalculator` detects estimation by comparing unbounded astronomical angle times (with manual/method offsets and minute rounding via `CalendarUtil.roundedMinute`) against Adhan's final calculated prayer times using pinned internal helpers (`SolarTime`, `TimeComponents`, `CalendarUtil`).
  - An event is marked estimated (`isEstimated: true`) if:
    1. Astronomical twilight angle is undefined (e.g. London summer solstice 18° twilight angle never reached).
    2. A finite angle event was clamped or shifted by an active high-latitude bound (e.g. 1/7th of the night, middle of the night) or seasonal approximation (Moonsighting Committee). For example, London 2026-04-10 with MWL/seventh clamps raw Fajr from 03:12 UTC to 03:47 UTC (+35 min), setting `isEstimated: true`.
  - Ordinary days where astronomical twilight is unconstrained by high-latitude bounds (e.g. London winter with standard MWL angle rules, Cairo year-round) remain strictly `isEstimated: false`. Under Moonsighting Committee, seasonal high-latitude adjustments apply in winter London and are correctly marked `isEstimated: true`. Fixed-interval Isha (Umm Al-Qura) is excluded from angle clamping checks.
- **Polar Days (Midnight Sun / Polar Night)**:
  At extreme latitudes (e.g. Tromsø 69.6492° N), the sun never crosses the horizon during certain periods. Upstream Adhan throws `ArgumentError` (NaN/infinite solar elevation).
  - **Actionable Unresolved Day (Safe Default)**: When `polarResolution == PolarDayResolution.unresolved`, the calculator returns a `PrayerDay` with `isUnresolved: true` and a clear descriptive reason, avoiding fabricated or synthetic sun events.
  - **Nearest Valid Latitude (Aqrab Al-Balad)**: When `polarResolution == PolarDayResolution.nearestLatitude`, the engine steps latitude towards the equator by 0.5° down to a bound of ±45.0°, running the exact same Adhan formula and shared chronological validation at each step. If resolved, it sets `isEstimated: true` with the adjusted latitude in `estimationReason`.
  - **Chronological Order Enforcement**: All prayer days (standard and polar-estimated) share strict chronological validation requiring all 6 UTC events in order (`fajr < sunrise < dhuhr < asr < maghrib < isha`). Invalid offsets (e.g. +120 min Fajr) throw an actionable `StateError` rather than masking sequence errors or looping across latitudes.

---

## 5. Umm Al-Qura Isha Ramadan Adjustment Policy

- In Saudi Arabia, the Umm Al-Qura standard increases the interval between Maghrib and Isha from 90 minutes to 120 minutes (+30 extra minutes) during the month of Ramadan.
- **Islamic Evening Boundary**:
  - The Islamic day begins at sunset (Maghrib).
  - Primary reference SPA https://www.spa.gov.sa/en/w2062566 directly states first Ramadan fasting/calendar day March 11, 2024 based on crescent sighted at March 10 sunset. The ensuing evening is the eve of 1 Ramadan 1445 (first Tarawih night), so Isha on civil date March 10 receives +30 minutes (120 min total).
  - Primary reference SPA https://spa.gov.sa/en/N2081393 records nationwide Eid Al-Fitr prayers on April 10, 2024, corroborating the first Shawwal civil-day calendar fixture. Sunset on April 9 (30 Ramadan daytime) concludes Ramadan; the ensuing evening is the eve of Eid (1 Shawwal), so Isha returns to standard 90 minutes.
  - Evening schedule: March 9 evening = 90 min; first Ramadan night March 10 evening = 120 min; last Ramadan night April 8 evening = 120 min; April 9 evening (eve of Eid) = 90 min.
  - These citations serve as documented calendar boundary fixtures, not as evidence of exact calculated Isha minutes or certified mosque timetables.
- **Hijri Supported Range Guard & Actionable Status**:
  - Pinned `hijri: 3.0.1` supports dates from 1356-01-01 (1937-03-14 CE) to 1500-12-30 (2077-11-16 CE).
  - When automatic Umm Al-Qura Ramadan policy (`eveningOfRamadan` or `civilDay`) is active and the target date falls outside this supported range, `PrayerCalculator` returns an explicit actionable unresolved calendar status (`isUnresolved: true`) with a descriptive status message. It does **not** silently fall back to 90 minutes.
  - To calculate standard 90-minute Isha outside the supported Hijri range, the user explicitly configures `UmmAlQuraRamadanPolicy.disabled`.
  - An immutable `hijriDayAdjustment` setting (-2..+2 days) is provided to accommodate local moon-sighting differences.
  - Manual prayer minute adjustments (`PrayerSettings.manualAdjustments`) remain strictly additive on top of the calculated interval.

---

## 6. Next Prayer Selection

`PrayerCalculator.nextPrayer` takes an injected UTC clock `DateTime utcNow`:
1. Converts `utcNow` to the city's IANA timezone to identify the city's active civil calendar date.
2. Gathers candidate events across the previous civil day, today, and tomorrow in the city's local calendar. This ensures that cross-midnight events (such as high-latitude Isha occurring after local midnight on the following calendar day, e.g. Reykjavik) are selected when strictly future, rather than skipped in favor of today's Fajr.
3. Filters to events strictly in the future (`utcDateTime.isAfter(utcNow)`).
4. Sorts future candidates chronologically by UTC instant. Same-instant ties are broken by canonical prayer order: Fajr < Sunrise < Dhuhr < Asr < Maghrib < Isha.
5. Advances to tomorrow's Fajr when all today's prayers have passed, using UTC civil day +1 arithmetic to prevent 24-hour drift on 25-hour DST fall-back days.
6. Operates deterministically without UI timers or device state.

---

## 7. Limitations & Readiness Notice

- **Algorithmic Nature**: Prayer times are calculated from mathematical solar algorithms and astronomical twilight definitions. They do not claim identical minute-for-minute alignment with every local mosque timetable or Ministry of Islamic Affairs announcement.
- **Qualified Religious Review**: Final review by a qualified Islamic authority remains pending as noted in the project milestone registry.
- **Persistence Boundary**: This task covers the pure domain and asset adapter. Persistence of user settings and database migrations are handled separately in Task 3B.
