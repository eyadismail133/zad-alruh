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

/// Extracts the human-readable display date ('YYYY-MM-DD') from a storage date bucket key.
String formatDisplayDate(String dateBucket) {
  if (dateBucket.contains('|')) {
    return dateBucket.split('|').last;
  }
  return dateBucket;
}

/// Extracts the IANA timezone from a qualified storage date bucket key, or returns empty string for legacy bare dates.
String parseTimezoneFromBucket(String dateBucket) {
  if (dateBucket.contains('|')) {
    return dateBucket.split('|').first;
  }
  return '';
}

/// Manages the active date bucket, refreshing on midnight rollover, timezone updates,
/// or app foreground lifecycle resumption.
class ActiveDateBucketNotifier extends Notifier<String> with WidgetsBindingObserver {
  Timer? _midnightTimer;

  @override
  String build() {
    final clock = ref.watch(clockProvider);
    final prefsAsync = ref.watch(preferencesControllerProvider);
    final timezone = prefsAsync.valueOrNull?.selectedTimezone ?? 'Africa/Cairo';

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

    _scheduleMidnightTimer(clock, timezone);
    return computeDateBucket(clock(), timezone);
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
    final timezone = prefs?.selectedTimezone ?? 'Africa/Cairo';
    final newBucket = computeDateBucket(clock(), timezone);
    if (state != newBucket) {
      state = newBucket;
    }
    _scheduleMidnightTimer(clock, timezone);
  }
}

/// Provides the active date bucket based on current injected clock and user's selected IANA timezone.
final activeDateBucketProvider = NotifierProvider<ActiveDateBucketNotifier, String>(
  ActiveDateBucketNotifier.new,
);
