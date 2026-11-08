import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight key/value store for UI preferences that do not belong in the
/// SQLite `user_preferences` table (reader paper mode, chosen reciter,
/// keep-screen-on…). Failures are swallowed: these are conveniences, and the
/// app must work identically when storage is unavailable (e.g. in tests).
class LocalSettings {
  LocalSettings._();

  static SharedPreferences? _prefs;

  /// Loads the store once at startup. Safe to call multiple times.
  static Future<void> init() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (_) {
      _prefs = null;
    }
  }

  static String? getString(String key) {
    try {
      return _prefs?.getString(key);
    } catch (_) {
      return null;
    }
  }

  static bool? getBool(String key) {
    try {
      return _prefs?.getBool(key);
    } catch (_) {
      return null;
    }
  }

  static void setString(String key, String value) {
    try {
      _prefs?.setString(key, value);
    } catch (_) {}
  }

  static void setBool(String key, bool value) {
    try {
      _prefs?.setBool(key, value);
    } catch (_) {}
  }
}

/// A [StateNotifier] whose value is mirrored to [LocalSettings].
class PersistedStringNotifier extends StateNotifier<String> {
  final String key;

  PersistedStringNotifier(this.key, String fallback)
      : super(LocalSettings.getString(key) ?? fallback);

  void set(String value) {
    state = value;
    LocalSettings.setString(key, value);
  }
}

class PersistedBoolNotifier extends StateNotifier<bool> {
  final String key;

  PersistedBoolNotifier(this.key, bool fallback)
      : super(LocalSettings.getBool(key) ?? fallback);

  void set(bool value) {
    state = value;
    LocalSettings.setBool(key, value);
  }

  void toggle() => set(!state);
}
