import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Exception thrown when native OS prayer alarm bridge encounters malformed or inconsistent data.
@immutable
class NativeBridgeException implements Exception {
  final String messageAr;
  final String technicalCode;

  const NativeBridgeException(this.messageAr, this.technicalCode);

  @override
  String toString() =>
      'NativeBridgeException($technicalCode): $messageAr';
}

/// Snapshot of the native Android prayer alarm store and system capabilities.
@immutable
class NativeAlarmState {
  final bool isSupported;
  final bool enabled;
  final int generationToken;
  final bool canScheduleExactAlarms;
  final bool notificationsAllowed;
  final bool isPlaybackStatusChannelBlocked;
  final bool isDndOrSilentActive;
  final bool isServiceRunning;
  final bool isManualPlaybackLeaseActive;
  final int futureEventsCount;
  final int pendingCleanupCount;
  final int cityId;
  final String cityNameAr;
  final String timezone;
  final int coverageHorizonUtc;
  final int consumedLedgerCount;

  const NativeAlarmState({
    this.isSupported = true,
    required this.enabled,
    required this.generationToken,
    required this.canScheduleExactAlarms,
    required this.notificationsAllowed,
    required this.isPlaybackStatusChannelBlocked,
    required this.isDndOrSilentActive,
    required this.isServiceRunning,
    required this.isManualPlaybackLeaseActive,
    required this.futureEventsCount,
    required this.pendingCleanupCount,
    required this.cityId,
    required this.cityNameAr,
    required this.timezone,
    required this.coverageHorizonUtc,
    required this.consumedLedgerCount,
  });

  static const NativeAlarmState unsupported = NativeAlarmState(
    isSupported: false,
    enabled: false,
    generationToken: 0,
    canScheduleExactAlarms: false,
    notificationsAllowed: false,
    isPlaybackStatusChannelBlocked: false,
    isDndOrSilentActive: false,
    isServiceRunning: false,
    isManualPlaybackLeaseActive: false,
    futureEventsCount: 0,
    pendingCleanupCount: 0,
    cityId: 0,
    cityNameAr: '',
    timezone: '',
    coverageHorizonUtc: 0,
    consumedLedgerCount: 0,
  );

  /// Strictly validates and parses the raw map returned by native Android `getState()`.
  /// Fails closed on any missing required field, negative count, fractional token, or invalid type.
  factory NativeAlarmState.fromMap(Map<dynamic, dynamic> map) {
    bool requireBool(dynamic value, String fieldName) {
      if (value is bool) return value;
      throw NativeBridgeException(
        'بيانات حالة التنبيهات من النظام غير صالحة ($fieldName).',
        'MALFORMED_STATE_FIELD',
      );
    }

    int requireNonNegativeInt(dynamic value, String fieldName) {
      if (value is int && value >= 0) return value;
      if (value is num && value >= 0 && value.toInt() == value) return value.toInt();
      throw NativeBridgeException(
        'قيمة غير صالحة أو سالبة في استجابة النظام ($fieldName).',
        'MALFORMED_STATE_NUMBER',
      );
    }

    String requireString(dynamic value, String fieldName) {
      if (value is String) return value;
      throw NativeBridgeException(
        'قيمة نصية مفقودة في استجابة النظام ($fieldName).',
        'MALFORMED_STATE_STRING',
      );
    }

    return NativeAlarmState(
      isSupported: true,
      enabled: requireBool(map['enabled'], 'enabled'),
      generationToken: requireNonNegativeInt(map['generationToken'], 'generationToken'),
      canScheduleExactAlarms: requireBool(map['canScheduleExactAlarms'], 'canScheduleExactAlarms'),
      notificationsAllowed: requireBool(map['notificationsAllowed'], 'notificationsAllowed'),
      isPlaybackStatusChannelBlocked: requireBool(map['isPlaybackStatusChannelBlocked'], 'isPlaybackStatusChannelBlocked'),
      isDndOrSilentActive: requireBool(map['isDndOrSilentActive'], 'isDndOrSilentActive'),
      isServiceRunning: requireBool(map['isServiceRunning'], 'isServiceRunning'),
      isManualPlaybackLeaseActive: requireBool(map['isManualPlaybackLeaseActive'], 'isManualPlaybackLeaseActive'),
      futureEventsCount: requireNonNegativeInt(map['futureEventsCount'], 'futureEventsCount'),
      pendingCleanupCount: requireNonNegativeInt(map['pendingCleanupCount'], 'pendingCleanupCount'),
      cityId: requireNonNegativeInt(map['cityId'], 'cityId'),
      cityNameAr: requireString(map['cityNameAr'], 'cityNameAr'),
      timezone: requireString(map['timezone'], 'timezone'),
      coverageHorizonUtc: requireNonNegativeInt(map['coverageHorizonUtc'], 'coverageHorizonUtc'),
      consumedLedgerCount: requireNonNegativeInt(map['consumedLedgerCount'], 'consumedLedgerCount'),
    );
  }

  @override
  String toString() =>
      'NativeAlarmState(enabled: $enabled, token: $generationToken, exact: $canScheduleExactAlarms, '
      'notifAllowed: $notificationsAllowed, pendingCleanup: $pendingCleanupCount, '
      'futureEvents: $futureEventsCount, cityId: $cityId)';
}

/// Response returned by the native coordinator when replacing a prayer plan.
@immutable
class ReplacePlanResponse {
  final bool success;
  final bool authorizationInvalidated;
  final int? token;
  final bool partialFailure;
  final String? errorCode;
  final String? messageAr;
  final String? detail;
  final int? scheduledCount;
  final int? attemptedCount;
  final int? exactScheduledCount;
  final int? companionScheduledCount;
  final bool exactAlarmsUsed;
  final bool companionAlarmsUsed;
  final int? currentToken;

  const ReplacePlanResponse({
    required this.success,
    this.authorizationInvalidated = false,
    this.token,
    this.partialFailure = false,
    this.errorCode,
    this.messageAr,
    this.detail,
    this.scheduledCount,
    this.attemptedCount,
    this.exactScheduledCount,
    this.companionScheduledCount,
    this.exactAlarmsUsed = false,
    this.companionAlarmsUsed = false,
    this.currentToken,
  });

  bool get isStaleToken => errorCode == 'STALE_AUTHORIZATION_TOKEN';

  factory ReplacePlanResponse.fromMap(Map<dynamic, dynamic> map) {
    final bool rawSuccess = map['success'] == true;
    final bool rawPartial = map['partialFailure'] == true;
    final String? rawErrorCode = map['errorCode']?.toString();
    final bool hasErrorCode = rawErrorCode != null && rawErrorCode.isNotEmpty;

    // Consistency guard: success cannot coexist with partial failure or error codes
    if (rawSuccess && (rawPartial || hasErrorCode)) {
      return ReplacePlanResponse(
        success: false,
        authorizationInvalidated: map['authorizationInvalidated'] == true,
        token: (map['token'] is int && (map['token'] as int) >= 0) ? (map['token'] as int) : null,
        partialFailure: true,
        errorCode: rawErrorCode ?? 'INCONSISTENT_RESPONSE',
        messageAr: 'استجابة غير متسقة من النظام أثناء جدولة المواعيد.',
      );
    }

    final rawToken = map['token'];
    final bool isTokenValidInt = rawToken is int && rawToken >= 0;
    final int? token = isTokenValidInt ? rawToken : null;

    final rawScheduled = map['scheduledCount'];
    final rawAttempted = map['attemptedCount'];
    final rawExact = map['exactScheduledCount'];
    final rawCompanion = map['companionScheduledCount'];

    final bool areCountsValidInts = rawScheduled is int &&
        rawScheduled >= 0 &&
        rawAttempted is int &&
        rawAttempted >= 0 &&
        rawExact is int &&
        rawExact >= 0 &&
        rawCompanion is int &&
        rawCompanion >= 0;

    final bool areBoolsValid = map['exactAlarmsUsed'] is bool &&
        map['companionAlarmsUsed'] is bool &&
        (map['partialFailure'] == null || map['partialFailure'] is bool);

    // Consistency guard for success:
    // Requires actual integer non-negative fields/bools for successful response,
    // counters <= attempted, complete success covers attempted, booleans consistent with counts,
    // and pair accepted <= exact when exactUsed, <= companion when companionUsed.
    if (rawSuccess) {
      if (!isTokenValidInt || !areCountsValidInts || !areBoolsValid) {
        return const ReplacePlanResponse(
          success: false,
          partialFailure: true,
          errorCode: 'INVALID_SUCCESS_METRICS',
          messageAr: 'بيانات تأكيد الجدولة من النظام غير صالحة.',
        );
      }

      final exactUsed = map['exactAlarmsUsed'] == true;
      final compUsed = map['companionAlarmsUsed'] == true;

      final bool countsConsistent = rawScheduled <= rawAttempted &&
          rawExact <= rawAttempted &&
          rawCompanion <= rawAttempted &&
          rawScheduled == rawAttempted &&
          exactUsed == (rawExact > 0) &&
          compUsed == (rawCompanion > 0) &&
          (!exactUsed || rawScheduled <= rawExact) &&
          (!compUsed || rawScheduled <= rawCompanion);

      if (!countsConsistent) {
        return const ReplacePlanResponse(
          success: false,
          partialFailure: true,
          errorCode: 'INVALID_SUCCESS_METRICS',
          messageAr: 'بيانات تأكيد الجدولة من النظام غير صالحة.',
        );
      }
    }

    final int? scheduledCount =
        (rawScheduled is int && rawScheduled >= 0) ? rawScheduled : null;
    final int? attemptedCount =
        (rawAttempted is int && rawAttempted >= 0) ? rawAttempted : null;
    final int? exactScheduledCount =
        (rawExact is int && rawExact >= 0) ? rawExact : null;
    final int? companionScheduledCount =
        (rawCompanion is int && rawCompanion >= 0) ? rawCompanion : null;

    return ReplacePlanResponse(
      success: rawSuccess,
      authorizationInvalidated: map['authorizationInvalidated'] == true,
      token: token,
      partialFailure: rawPartial,
      errorCode: rawErrorCode,
      messageAr: map['messageAr']?.toString(),
      detail: map['detail']?.toString(),
      scheduledCount: scheduledCount,
      attemptedCount: attemptedCount,
      exactScheduledCount: exactScheduledCount,
      companionScheduledCount: companionScheduledCount,
      exactAlarmsUsed: map['exactAlarmsUsed'] == true,
      companionAlarmsUsed: map['companionAlarmsUsed'] == true,
      currentToken: (map['currentToken'] is int && (map['currentToken'] as int) >= 0)
          ? (map['currentToken'] as int)
          : null,
    );
  }

  factory ReplacePlanResponse.failed(String errorCode, String messageAr) {
    return ReplacePlanResponse(
      success: false,
      errorCode: errorCode,
      messageAr: messageAr,
    );
  }

  @override
  String toString() =>
      'ReplacePlanResponse(success: $success, scheduled: $scheduledCount/$attemptedCount, '
      'exactUsed: $exactAlarmsUsed, partial: $partialFailure, error: $errorCode)';
}

/// Response returned by the native coordinator when disabling alarms.
@immutable
class DisableAlarmsResponse {
  final bool success;
  final bool authorizationInvalidated;
  final int? token;
  final bool partialFailure;
  final String? errorCode;
  final String? messageAr;

  const DisableAlarmsResponse({
    required this.success,
    this.authorizationInvalidated = false,
    this.token,
    this.partialFailure = false,
    this.errorCode,
    this.messageAr,
  });

  factory DisableAlarmsResponse.fromMap(Map<dynamic, dynamic> map) {
    final bool rawSuccess = map['success'] == true;
    final bool rawPartial = map['partialFailure'] == true;
    final String? rawErrorCode = map['errorCode']?.toString();
    final bool hasErrorCode = rawErrorCode != null && rawErrorCode.isNotEmpty;

    if (rawSuccess && (rawPartial || hasErrorCode)) {
      return DisableAlarmsResponse(
        success: false,
        authorizationInvalidated: map['authorizationInvalidated'] == true,
        token: (map['token'] is int && (map['token'] as int) >= 0)
            ? (map['token'] as int)
            : null,
        partialFailure: true,
        errorCode: rawErrorCode ?? 'INCONSISTENT_RESPONSE',
        messageAr: 'استجابة غير متسقة من النظام أثناء تعطيل التنبيهات.',
      );
    }

    final rawToken = map['token'];
    final bool isTokenValidInt = rawToken is int && rawToken >= 0;
    final bool isPartialValid =
        map['partialFailure'] == null || map['partialFailure'] is bool;
    if (rawSuccess && (!isTokenValidInt || !isPartialValid)) {
      return const DisableAlarmsResponse(
        success: false,
        partialFailure: true,
        errorCode: 'INVALID_TOKEN',
        messageAr: 'رمز التفويض في استجابة النظام غير صالح.',
      );
    }

    return DisableAlarmsResponse(
      success: rawSuccess,
      authorizationInvalidated: map['authorizationInvalidated'] == true,
      token: isTokenValidInt ? rawToken : null,
      partialFailure: rawPartial,
      errorCode: rawErrorCode,
      messageAr: map['messageAr']?.toString(),
    );
  }

  factory DisableAlarmsResponse.failed(String errorCode, String messageAr) {
    return DisableAlarmsResponse(
      success: false,
      errorCode: errorCode,
      messageAr: messageAr,
    );
  }

  @override
  String toString() =>
      'DisableAlarmsResponse(success: $success, token: $token, partial: $partialFailure, error: $errorCode)';
}

/// Response returned by the native coordinator when resetting state.
@immutable
class ResetAllResponse {
  final bool success;
  final bool authorizationInvalidated;
  final int? token;
  final bool partialFailure;
  final String? errorCode;
  final String? messageAr;

  const ResetAllResponse({
    required this.success,
    this.authorizationInvalidated = false,
    this.token,
    this.partialFailure = false,
    this.errorCode,
    this.messageAr,
  });

  factory ResetAllResponse.fromMap(Map<dynamic, dynamic> map) {
    final bool rawSuccess = map['success'] == true;
    final bool rawPartial = map['partialFailure'] == true;
    final String? rawErrorCode = map['errorCode']?.toString();
    final bool hasErrorCode = rawErrorCode != null && rawErrorCode.isNotEmpty;

    if (rawSuccess && (rawPartial || hasErrorCode)) {
      return ResetAllResponse(
        success: false,
        authorizationInvalidated: map['authorizationInvalidated'] == true,
        token: (map['token'] is int && (map['token'] as int) >= 0)
            ? (map['token'] as int)
            : null,
        partialFailure: true,
        errorCode: rawErrorCode ?? 'INCONSISTENT_RESPONSE',
        messageAr: 'استجابة غير متسقة من النظام أثناء إعادة الضبط.',
      );
    }

    final rawToken = map['token'];
    final bool isTokenValidInt = rawToken is int && rawToken >= 0;
    final bool isPartialValid =
        map['partialFailure'] == null || map['partialFailure'] is bool;
    if (rawSuccess && (!isTokenValidInt || !isPartialValid)) {
      return const ResetAllResponse(
        success: false,
        partialFailure: true,
        errorCode: 'INVALID_TOKEN',
        messageAr: 'رمز التفويض في استجابة النظام غير صالح.',
      );
    }

    return ResetAllResponse(
      success: rawSuccess,
      authorizationInvalidated: map['authorizationInvalidated'] == true,
      token: isTokenValidInt ? rawToken : null,
      partialFailure: rawPartial,
      errorCode: rawErrorCode,
      messageAr: map['messageAr']?.toString(),
    );
  }

  factory ResetAllResponse.failed(String errorCode, String messageAr) {
    return ResetAllResponse(
      success: false,
      errorCode: errorCode,
      messageAr: messageAr,
    );
  }

  @override
  String toString() =>
      'ResetAllResponse(success: $success, token: $token, partial: $partialFailure, error: $errorCode)';
}

/// Typed client contract for communicating with the native Android prayer alarm channel.
abstract class NativePrayerChannelClient {
  /// Fetches the current monotonic generation token from the native store.
  Future<int?> getAuthorizationToken();

  /// Replaces the active native prayer schedule plan with CAS token check.
  Future<ReplacePlanResponse> replacePlan(Map<String, dynamic> planMap);

  /// Disables prayer alarms and stops active playback.
  Future<DisableAlarmsResponse> disableAlarms();

  /// Completely resets all native alarm state and clears consumed ledger.
  Future<ResetAllResponse> resetAll();

  /// Reads the current snapshot of native alarm state and capabilities.
  /// Throws [NativeBridgeException] on Android error or malformed response; never returns false clean.
  Future<NativeAlarmState> getState();

  /// Queries whether the app currently has permission to schedule exact alarms.
  Future<bool> canScheduleExactAlarms();

  /// Queries whether notifications are currently allowed for the app.
  Future<bool> canPostNotifications();

  /// Explicitly requests notification permission from the user (Android 13+ POST_NOTIFICATIONS).
  Future<bool> requestNotificationPermission();

  /// Explicitly launches the system settings for exact alarm permission.
  Future<bool> requestExactAlarmPermission();

  /// Requests stopping any currently active adhan audio playback service.
  Future<bool> stopActivePlayback();
}

/// Production implementation of [NativePrayerChannelClient] using MethodChannel.
class MethodChannelNativePrayerChannelClient
    implements NativePrayerChannelClient {
  static const MethodChannel defaultChannel =
      MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm');

  final MethodChannel _channel;
  final bool isAndroidPlatform;

  MethodChannelNativePrayerChannelClient({
    MethodChannel? channel,
    bool? isAndroid,
  })  : _channel = channel ?? defaultChannel,
        isAndroidPlatform =
            isAndroid ?? (defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<int?> getAuthorizationToken() async {
    if (!isAndroidPlatform) return null;
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('getAuthorizationToken');
      if (result is Map && result['token'] is num) {
        final num val = result['token'] as num;
        if (val.toInt() == val && val >= 0) {
          return val.toInt();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<ReplacePlanResponse> replacePlan(Map<String, dynamic> planMap) async {
    if (!isAndroidPlatform) {
      return ReplacePlanResponse.failed(
        'UNSUPPORTED_PLATFORM',
        'تنبيهات النظام مدعومة حالياً على نظام أندرويد فقط.',
      );
    }
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('replacePlan', planMap);
      if (result is Map) {
        return ReplacePlanResponse.fromMap(result);
      }
      return ReplacePlanResponse.failed(
        'MALFORMED_RESPONSE',
        'استجابة غير صالحة من النظام أثناء جدولة المواعيد.',
      );
    } on PlatformException catch (e) {
      return ReplacePlanResponse.failed(
        e.code,
        'تعذر تحديث جدول مواعيد الصلاة في النظام.',
      );
    } catch (_) {
      return ReplacePlanResponse.failed(
        'UNKNOWN_ERROR',
        'حدث خطأ غير متوقع أثناء جدولة المواعيد.',
      );
    }
  }

  @override
  Future<DisableAlarmsResponse> disableAlarms() async {
    if (!isAndroidPlatform) {
      return DisableAlarmsResponse.failed(
        'UNSUPPORTED_PLATFORM',
        'تنبيهات النظام مدعومة على أندرويد فقط.',
      );
    }
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('disableAlarms');
      if (result is Map) {
        return DisableAlarmsResponse.fromMap(result);
      }
      return DisableAlarmsResponse.failed(
        'MALFORMED_RESPONSE',
        'استجابة غير صالحة من النظام أثناء تعطيل التنبيهات.',
      );
    } on PlatformException catch (e) {
      return DisableAlarmsResponse.failed(
        e.code,
        'تعذر تعطيل تنبيهات الصلاة في النظام.',
      );
    } catch (_) {
      return DisableAlarmsResponse.failed(
        'UNKNOWN_ERROR',
        'حدث خطأ غير متوقع أثناء تعطيل التنبيهات.',
      );
    }
  }

  @override
  Future<ResetAllResponse> resetAll() async {
    if (!isAndroidPlatform) {
      return ResetAllResponse.failed(
        'UNSUPPORTED_PLATFORM',
        'تنبيهات النظام مدعومة على أندرويد فقط.',
      );
    }
    try {
      final dynamic result = await _channel.invokeMethod<dynamic>('resetAll');
      if (result is Map) {
        return ResetAllResponse.fromMap(result);
      }
      return ResetAllResponse.failed(
        'MALFORMED_RESPONSE',
        'استجابة غير صالحة من النظام أثناء إعادة الضبط.',
      );
    } on PlatformException catch (e) {
      return ResetAllResponse.failed(
        e.code,
        'تعذر إعادة ضبط تنبيهات الصلاة في النظام.',
      );
    } catch (_) {
      return ResetAllResponse.failed(
        'UNKNOWN_ERROR',
        'حدث خطأ غير متوقع أثناء إعادة الضبط.',
      );
    }
  }

  @override
  Future<NativeAlarmState> getState() async {
    if (!isAndroidPlatform) {
      return NativeAlarmState.unsupported;
    }
    try {
      final dynamic result = await _channel.invokeMethod<dynamic>('getState');
      if (result is! Map) {
        throw const NativeBridgeException(
          'استجابة غير صالحة من النظام أثناء قراءة حالة التنبيهات.',
          'MALFORMED_STATE_RESPONSE',
        );
      }
      return NativeAlarmState.fromMap(result);
    } on PlatformException catch (e) {
      throw NativeBridgeException(
        'تعذر قراءة حالة تنبيهات الصلاة من النظام.',
        e.code,
      );
    } on NativeBridgeException {
      rethrow;
    } catch (_) {
      throw const NativeBridgeException(
        'حدث خطأ غير متوقع أثناء قراءة حالة التنبيهات.',
        'UNKNOWN_ERROR',
      );
    }
  }

  @override
  Future<bool> canScheduleExactAlarms() async {
    if (!isAndroidPlatform) return false;
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('canScheduleExactAlarms');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> canPostNotifications() async {
    if (!isAndroidPlatform) return false;
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('canPostNotifications');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (!isAndroidPlatform) return false;
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('requestNotificationPermission');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    if (!isAndroidPlatform) return false;
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('requestExactAlarmPermission');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopActivePlayback() async {
    if (!isAndroidPlatform) return true;
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('stopActivePlayback');
      if (result is Map && result['stopped'] == true) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

/// Riverpod provider delivering the native prayer channel client.
final nativePrayerChannelClientProvider =
    Provider<NativePrayerChannelClient>((ref) {
  return MethodChannelNativePrayerChannelClient();
});
