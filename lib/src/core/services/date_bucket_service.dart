import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../../features/progress/presentation/controllers/progress_controller.dart';

bool _timeZonesInitialized = false;

void ensureTimeZonesInitialized() {
  if (!_timeZonesInitialized) {
    tz.initializeTimeZones();
    _timeZonesInitialized = true;
  }
}

/// Injectable clock provider for deterministic time in tests and production
final clockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// Computes the stable timezone-qualified date bucket key ('IANA/Zone|YYYY-MM-DD')
/// for a given point in time and IANA timezone.
/// Throws [ArgumentError] if the provided IANA timezone is invalid or unrecognized.
String computeDateBucket(DateTime dateTime, String ianaTimezone) {
  ensureTimeZonesInitialized();
  try {
    final location = tz.getLocation(ianaTimezone);
    final tzTime = tz.TZDateTime.from(dateTime, location);
    final y = tzTime.year.toString().padLeft(4, '0');
    final m = tzTime.month.toString().padLeft(2, '0');
    final d = tzTime.day.toString().padLeft(2, '0');
    return '$ianaTimezone|$y-$m-$d';
  } on tz.LocationNotFoundException {
    throw ArgumentError.value(
      ianaTimezone,
      'ianaTimezone',
      'Invalid or unsupported IANA timezone',
    );
  } catch (e) {
    throw ArgumentError('Failed to compute date bucket for timezone "$ianaTimezone": $e');
  }
}

/// Validates whether a date bucket string is a strictly qualified, real calendar date bucket
/// in the format 'IANA/Zone|YYYY-MM-DD' or 'YYYY-MM-DD|IANA/Zone'.
bool isValidQualifiedDateBucket(String bucket) {
  if (!bucket.contains('|')) return false;
  final parts = bucket.split('|');
  if (parts.length != 2) return false;

  ensureTimeZonesInitialized();

  // Try format 1: ianaTimezone|YYYY-MM-DD
  String tzCandidate = parts[0];
  String dateCandidate = parts[1];
  if (_isValidTzAndDate(tzCandidate, dateCandidate)) {
    return true;
  }

  // Try format 2: YYYY-MM-DD|ianaTimezone
  tzCandidate = parts[1];
  dateCandidate = parts[0];
  return _isValidTzAndDate(tzCandidate, dateCandidate);
}

bool _isValidTzAndDate(String tzName, String dateStr) {
  if (tzName.isEmpty || dateStr.length != 10) return false;
  final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  if (!dateRegex.hasMatch(dateStr)) return false;

  final parsedDate = DateTime.tryParse(dateStr);
  if (parsedDate == null) return false;
  // Ensure calendar date round-trips (rejects invalid days like 2026-02-31)
  final y = parsedDate.year.toString().padLeft(4, '0');
  final m = parsedDate.month.toString().padLeft(2, '0');
  final d = parsedDate.day.toString().padLeft(2, '0');
  if ('$y-$m-$d' != dateStr) return false;

  try {
    tz.getLocation(tzName);
    return true;
  } catch (_) {
    return false;
  }
}

/// Extracts the human-readable display date ('YYYY-MM-DD') from a storage date bucket key.
String formatDisplayDate(String dateBucket) {
  if (dateBucket.contains('|')) {
    final parts = dateBucket.split('|');
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (dateRegex.hasMatch(parts.last)) return parts.last;
    if (dateRegex.hasMatch(parts.first)) return parts.first;
    return parts.last;
  }
  return dateBucket;
}

/// Extracts the IANA timezone from a qualified storage date bucket key, or returns empty string for legacy bare dates.
String parseTimezoneFromBucket(String dateBucket) {
  if (dateBucket.contains('|')) {
    final parts = dateBucket.split('|');
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (dateRegex.hasMatch(parts.last)) return parts.first;
    if (dateRegex.hasMatch(parts.first)) return parts.last;
    return parts.first;
  }
  return '';
}

/// Status of date bucket readiness based on user preference timezone hydration.
enum DateReadinessStatus { loading, ready, error }

/// Model indicating whether the active date bucket has a validated, hydrated timezone.
@immutable
class DateReadiness {
  final DateReadinessStatus status;
  final String? activeBucket;
  final String? validatedTimezone;
  final Object? error;

  const DateReadiness({
    required this.status,
    this.activeBucket,
    this.validatedTimezone,
    this.error,
  });

  bool get isReady => status == DateReadinessStatus.ready && activeBucket != null && activeBucket!.isNotEmpty;
  bool get isLoading => status == DateReadinessStatus.loading;
  bool get hasError => status == DateReadinessStatus.error;
}

/// Manages the active date bucket, refreshing on midnight rollover, timezone updates,
/// or app foreground lifecycle resumption.
class ActiveDateBucketNotifier extends Notifier<String> with WidgetsBindingObserver {
  Timer? _midnightTimer;
  String? _lastKnownTimezone;

  String? get lastKnownTimezone => _lastKnownTimezone;

  @override
  String build() {
    final clock = ref.watch(clockProvider);
    final prefsAsync = ref.watch(preferencesControllerProvider);

    prefsAsync.whenData((prefs) {
      final selectedTz = prefs.selectedTimezone;
      if (selectedTz.isNotEmpty) {
        try {
          ensureTimeZonesInitialized();
          tz.getLocation(selectedTz);
          _lastKnownTimezone = selectedTz;
        } catch (_) {}
      }
    });

    if (_lastKnownTimezone == null) {
      // Do not guess Cairo before persisted hydration!
      return '';
    }

    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Test environment without WidgetsBinding initialized
    }

    ref.onDispose(() {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _midnightTimer?.cancel();
    });

    _scheduleMidnightTimer(clock, _lastKnownTimezone!);
    return computeDateBucket(clock(), _lastKnownTimezone!);
  }

  void _scheduleMidnightTimer(DateTime Function() clock, String tzName) {
    _midnightTimer?.cancel();
    try {
      final location = tz.getLocation(tzName);
      final nowTz = tz.TZDateTime.from(clock(), location);
      final tomorrowTz = tz.TZDateTime(location, nowTz.year, nowTz.month, nowTz.day + 1);
      final duration = tomorrowTz.difference(nowTz);
      if (duration > Duration.zero) {
        _midnightTimer = Timer(duration + const Duration(milliseconds: 50), () {
          refresh();
        });
      }
    } catch (_) {
      // Ignored for invalid timezones handled during computeDateBucket
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  /// Manually or programmatically refresh date bucket (e.g. after midnight or clock change)
  void refresh() {
    final clock = ref.read(clockProvider);
    final prefs = ref.read(preferencesControllerProvider).valueOrNull;
    final selectedTz = prefs?.selectedTimezone;
    if (selectedTz != null && selectedTz.isNotEmpty) {
      try {
        ensureTimeZonesInitialized();
        tz.getLocation(selectedTz);
        _lastKnownTimezone = selectedTz;
      } catch (_) {}
    }
    if (_lastKnownTimezone != null) {
      final newBucket = computeDateBucket(clock(), _lastKnownTimezone!);
      if (state != newBucket) {
        state = newBucket;
      }
      _scheduleMidnightTimer(clock, _lastKnownTimezone!);
    }
  }
}

/// Provides the active date bucket based on current injected clock and user's selected IANA timezone.
final activeDateBucketProvider = NotifierProvider<ActiveDateBucketNotifier, String>(
  ActiveDateBucketNotifier.new,
);

/// Exposes date bucket readiness state, preventing unhydrated date-sensitive mutations
/// from executing with guessed timezones. Watches the actual state of [activeDateBucketProvider].
final dateReadinessProvider = Provider<DateReadiness>((ref) {
  final activeBucket = ref.watch(activeDateBucketProvider);
  final activeNotifier = ref.watch(activeDateBucketProvider.notifier);
  final lastKnown = activeNotifier.lastKnownTimezone;
  final prefsAsync = ref.watch(preferencesControllerProvider);

  if (lastKnown != null && activeBucket.isNotEmpty) {
    return DateReadiness(
      status: DateReadinessStatus.ready,
      activeBucket: activeBucket,
      validatedTimezone: lastKnown,
    );
  }

  return prefsAsync.when(
    data: (prefs) {
      final tzName = prefs.selectedTimezone;
      try {
        ensureTimeZonesInitialized();
        tz.getLocation(tzName);
        final clock = ref.watch(clockProvider);
        final bucket = computeDateBucket(clock(), tzName);
        return DateReadiness(
          status: DateReadinessStatus.ready,
          activeBucket: bucket,
          validatedTimezone: tzName,
        );
      } catch (e) {
        return DateReadiness(
          status: DateReadinessStatus.error,
          error: e,
        );
      }
    },
    loading: () => const DateReadiness(status: DateReadinessStatus.loading),
    error: (err, _) {
      if (lastKnown != null) {
        final clock = ref.watch(clockProvider);
        return DateReadiness(
          status: DateReadinessStatus.ready,
          activeBucket: computeDateBucket(clock(), lastKnown),
          validatedTimezone: lastKnown,
        );
      }
      return DateReadiness(status: DateReadinessStatus.error, error: err);
    },
  );
});
