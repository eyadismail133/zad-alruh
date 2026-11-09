import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/local_settings.dart';

/// Whether the prayer-time adhan plays while the phone is on silent/vibrate
/// (on by default; full Do-Not-Disturb is always respected natively).
class AdhanPlayWhenSilentNotifier extends PersistedBoolNotifier {
  static const MethodChannel _channel =
      MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm');

  AdhanPlayWhenSilentNotifier() : super('adhan.play_when_silent', true);

  @override
  void set(bool value) {
    super.set(value);
    unawaited(syncNative(value));
  }

  static Future<void> syncNative(bool value) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setAdhanOptions', {
        'playWhenSilent': value,
      });
    } catch (_) {}
  }
}

final adhanPlayWhenSilentProvider =
    StateNotifierProvider<AdhanPlayWhenSilentNotifier, bool>(
  (ref) => AdhanPlayWhenSilentNotifier(),
);
