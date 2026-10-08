import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result snapshot of an attempt to acquire the native manual playback lease.
@immutable
class ManualPlaybackLeaseResult {
  final bool acquired;
  final String? leaseToken;
  final bool idempotent;
  final String? errorCode;
  final String? errorMessageAr;

  const ManualPlaybackLeaseResult({
    required this.acquired,
    this.leaseToken,
    this.idempotent = false,
    this.errorCode,
    this.errorMessageAr,
  });

  static const ManualPlaybackLeaseResult nonAndroidSuccess =
      ManualPlaybackLeaseResult(
    acquired: true,
    leaseToken: 'non_android_noop_lease',
  );

  static const ManualPlaybackLeaseResult failedClosed =
      ManualPlaybackLeaseResult(
    acquired: false,
    errorCode: 'FAIL_CLOSED',
    errorMessageAr: 'تعذر الحصول على إذن التشغيل من النظام',
  );

  @override
  String toString() =>
      'ManualPlaybackLeaseResult(acquired: $acquired, token: $leaseToken, code: $errorCode)';
}

/// Typed OS boundary interface for mutual exclusion between manual in-app audio
/// (Quran recitation, adhan previews) and native Android prayer alarms.
///
/// Communicates with the native Android coordinator via MethodChannel
/// 'dev.zadalruh.zad_alruh/prayer_alarm'.
abstract class NativePrayerAudioControl {
  /// Confirms that active native adhan audio playback has stopped.
  Future<bool> stopActivePlayback();

  /// Acquires the process-local mutual exclusion lease before starting manual audio.
  ///
  /// Atomically confirms synchronous stop of any active native adhan playback,
  /// suppresses scheduled adhan alarms into terminal `MANUAL_SUPPRESSED`, and grants
  /// a unique opaque leaseToken.
  ///
  /// Fails closed on missing response, error, or [MissingPluginException].
  Future<ManualPlaybackLeaseResult> acquireManualPlaybackLease({
    required String requestId,
  });

  /// Releases the held manual playback lease using the matching [leaseToken].
  ///
  /// A matching token clears the lease. Stale or mismatched tokens are harmless no-ops.
  /// Returns `true` if release completed normally on the OS boundary, or `false` on failure.
  Future<bool> releaseManualPlaybackLease({
    required String leaseToken,
  });

  /// Queries whether a manual playback lease is currently active on the native coordinator.
  Future<bool> isManualPlaybackLeaseActive();
}

/// Global monotonic sequence counter guaranteeing unique request IDs across
/// every physical adapter, provider lifetime, and attempt within the Flutter engine.
int _globalManualLeaseSequence = 0;

/// Generates a monotonically unique requestId for lease acquisition.
String generateUniqueLeaseRequestId() {
  return 'lease_seq_${++_globalManualLeaseSequence}';
}

/// Production implementation communicating over 'dev.zadalruh.zad_alruh/prayer_alarm'.
class MethodChannelNativePrayerAudioControl implements NativePrayerAudioControl {
  static const MethodChannel defaultChannel =
      MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm');

  final MethodChannel _channel;
  final bool isAndroidPlatform;

  MethodChannelNativePrayerAudioControl({
    MethodChannel? channel,
    bool? isAndroid,
  })  : _channel = channel ?? defaultChannel,
        isAndroidPlatform =
            isAndroid ?? (defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<bool> stopActivePlayback() async {
    if (!isAndroidPlatform) {
      return true;
    }
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('stopActivePlayback');
      if (result is Map && result['stopped'] == true) {
        return true;
      }
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ManualPlaybackLeaseResult> acquireManualPlaybackLease({
    required String requestId,
  }) async {
    if (!isAndroidPlatform) {
      return ManualPlaybackLeaseResult.nonAndroidSuccess;
    }
    if (requestId.trim().isEmpty || requestId.length > 256) {
      return ManualPlaybackLeaseResult.failedClosed;
    }
    try {
      final dynamic result = await _channel.invokeMethod<dynamic>(
        'acquireManualPlaybackLease',
        <String, dynamic>{'requestId': requestId},
      );
      if (result is Map) {
        final bool acquired = result['acquired'] == true;
        final String? leaseToken = result['leaseToken']?.toString();
        if (acquired && leaseToken != null && leaseToken.isNotEmpty) {
          return ManualPlaybackLeaseResult(
            acquired: true,
            leaseToken: leaseToken,
            idempotent: result['idempotent'] == true,
          );
        }
        final String? errorCode = result['errorCode']?.toString();
        final String? messageAr = result['messageAr']?.toString();
        return ManualPlaybackLeaseResult(
          acquired: false,
          errorCode: errorCode ?? 'LEASE_DENIED',
          errorMessageAr:
              messageAr ?? 'تعذر بدء الاستماع لوجود تشغيل نشط آخر في النظام',
        );
      }
      return ManualPlaybackLeaseResult.failedClosed;
    } on MissingPluginException {
      return const ManualPlaybackLeaseResult(
        acquired: false,
        errorCode: 'MISSING_PLUGIN',
        errorMessageAr: 'خدمة التنبيهات في النظام غير متاحة حالياً',
      );
    } on PlatformException catch (e) {
      return ManualPlaybackLeaseResult(
        acquired: false,
        errorCode: e.code,
        errorMessageAr: 'تعذر الحصول على إذن التشغيل من النظام',
      );
    } catch (_) {
      return ManualPlaybackLeaseResult.failedClosed;
    }
  }

  @override
  Future<bool> releaseManualPlaybackLease({
    required String leaseToken,
  }) async {
    if (!isAndroidPlatform) {
      return true;
    }
    if (leaseToken.trim().isEmpty) {
      return false;
    }
    try {
      final dynamic result = await _channel.invokeMethod<dynamic>(
        'releaseManualPlaybackLease',
        <String, dynamic>{'leaseToken': leaseToken},
      );
      if (result is Map && result['released'] == true) {
        return true;
      }
      return false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isManualPlaybackLeaseActive() async {
    if (!isAndroidPlatform) {
      return false;
    }
    try {
      final dynamic result = await _channel.invokeMethod<dynamic>('getState');
      if (result is Map && result['isManualPlaybackLeaseActive'] is bool) {
        return result['isManualPlaybackLeaseActive'] as bool;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
