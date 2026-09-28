# Adhan 2.0.0+1 Minimal Vendor Patches

This directory contains the vendored source of `adhan: 2.0.0+1` (MIT License, https://github.com/iamriajul/adhan-dart, https://pub.dev/packages/adhan/versions/2.0.0+1).

## Upstream Provenance

- **Package**: `adhan`
- **Version**: `2.0.0+1`
- **Archive SHA-256**: `e1d3363c8127dc614947ecf312e458fbf4783af3db8e3b465c4a286eb37374ac`
- **Original Source Manifest**: `third_party/adhan/UPSTREAM-SHA256.json`
- **License**: MIT (`third_party/adhan/LICENSE`)

All 28 upstream package files were verified against their original SHA-256 hashes at acquisition. Only the three minimal engine patches documented below have been applied. Astronomy formulas, coordinate handling, and method definitions remain verbatim.

---

## Applied Patches

### Patch 1: Civil Day-of-Year Arithmetic (`lib/src/extensions/datetime.dart`)

- **Target File**: `lib/src/extensions/datetime.dart`
- **Defect**: Upstream `dayOfYear` calculated the elapsed duration to device-local January 1st:
  ```dart
  int get dayOfYear {
    final yearStartDate = DateTime(year);
    return difference(yearStartDate).inDays + 1;
  }
  ```
  On timezones with Daylight Saving Time (DST) shifts (such as Africa/Cairo spring-forward and fall-back), the elapsed duration across 23-hour or 25-hour days caused `difference.inDays` to be off by 1 day (e.g., returning 114 instead of 115 on 2026-04-25, and 269 instead of 270 on 2026-09-27). Passing timezone-shifted instants (such as Kiritimati `+14:00` on 2026-02-01) returned 31 instead of 32.
- **Fix**: Calculate the civil day ordinal purely using UTC civil date components `(year, month, day)` minus `DateTime.utc(year, 1, 1)`:
  ```dart
  int get dayOfYear {
    final yearStartDate = DateTime.utc(year, 1, 1);
    final civilDate = DateTime.utc(year, month, day);
    return civilDate.difference(yearStartDate).inDays + 1;
  }
  ```
- **Provenance**: Confirmed by root diagnostics in `.local/task03-library-investigation.md` and verified by regression test fixtures (Cairo 2026-04-25 = 115, Cairo 2026-09-27 = 270, Kiritimati 2026-02-01 = 32).

---

### Patch 2: UTC-Preserving Minute Rounding (`lib/src/data/calendar_util.dart`)

- **Target File**: `lib/src/data/calendar_util.dart`
- **Defect**: Upstream `PrayerTimes._` calls `CalendarUtil.roundedMinute` on each prayer time after converting to local time (`.toLocal()`). Upstream `CalendarUtil.roundedMinute` used `when.copyWith`:
  ```dart
  static DateTime roundedMinute(DateTime when) {
    final minute = when.minute;
    final second = when.second;
    return when.copyWith(minute: (minute + (second / 60).round()), second: 0);
  }
  ```
  In Dart, calling `copyWith` on a local `DateTime` during an ambiguous repeated hour (such as Cairo 2026-10-29 fall-back where 23:00..00:00 occurs twice, first at UTC+3 and then at UTC+2) causes the Dart constructor to resolve to the first occurrence (UTC+3). Consequently, the second occurrence (UTC 21:30:15 / local 23:30:15 UTC+2) was reconstructed as UTC+3, shifting the resulting UTC instant by 1 hour (to UTC 20:30 instead of UTC 21:30).
- **Fix**: Perform minute rounding on the unambiguous UTC instant and restore the local timezone only if the input was non-UTC:
  ```dart
  static DateTime roundedMinute(DateTime when) {
    final utc = when.toUtc();
    final minuteAddition = (utc.second / 60).round();
    final roundedUtc = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute + minuteAddition,
    );
    return when.isUtc ? roundedUtc : roundedUtc.toLocal();
  }
  ```
- **Provenance**: Observed and reproduced in `.local/adhan-probe/rounding_probe.dart`. Verified by unit tests covering repeated-hour rounding and whole-prayer UTC conversions.

---

### Patch 3: Fixed-Interval Isha with Twilight-Angle Rule (`lib/src/calculation_parameters.dart`)

- **Target File**: `lib/src/calculation_parameters.dart`
- **Defect**: When using calculation methods with a fixed Isha interval (such as Umm Al-Qura with `ishaInterval = 90` minutes and `ishaAngle = null`), selecting `HighLatitudeRule.twilight_angle` threw a `FormatException` because `nightPortions()` unconditionally required `ishaAngle != null`:
  ```dart
  case HighLatitudeRule.twilight_angle:
    {
      if (ishaAngle == null) {
        throw FormatException('ishaAngle\'s value isn\'t define');
      }
      return _NightPortions(fajrAngle / 60.0, ishaAngle! / 60.0);
    }
  ```
  However, in `PrayerTimes._`, when `ishaInterval > 0`, the Isha calculation uses `sunsetComponents.add(Duration(seconds: calculationParameters.ishaInterval * 60))` and never reads `nightPortions.isha`. `nightPortions()` is only evaluated for `safeFajr`. Requiring `ishaAngle` for fixed-interval methods caused valid settings combinations to crash.
- **Fix**: When `ishaInterval > 0`, allow the unused Isha night portion to be `0.0` while computing the Fajr fraction from `fajrAngle / 60.0`. Retain `FormatException` when angle-based Isha genuinely lacks an angle:
  ```dart
  case HighLatitudeRule.twilight_angle:
    {
      if (ishaAngle == null) {
        if (ishaInterval > 0) {
          return _NightPortions(fajrAngle / 60.0, 0.0);
        }
        throw FormatException('ishaAngle\'s value isn\'t define');
      }
      return _NightPortions(fajrAngle / 60.0, ishaAngle! / 60.0);
    }
  ```
- **Provenance**: Observed and proven in `.local/adhan-probe/ummalqura_twilight_probe.dart`. Verified by method/rule matrix tests asserting unchanged Makkah 90-minute Isha with middle-of-the-night, seventh-of-the-night, and twilight-angle rules.
