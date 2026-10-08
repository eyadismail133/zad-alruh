import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/prayer/domain/services/prayer_notification_coordinator.dart';

/// Exception thrown when native OS prayer alarm reset fails.
/// Provides stable Arabic user-facing text and structured technical error codes.
@immutable
class NativeResetException implements Exception {
  final String messageArabic;
  final String? technicalCode;

  const NativeResetException(this.messageArabic, [this.technicalCode]);

  @override
  String toString() => technicalCode != null
      ? 'NativeResetException: $messageArabic ($technicalCode)'
      : 'NativeResetException: $messageArabic';
}

/// Typed contract for cancelling all scheduled native OS prayer alarms
/// and wiping native persistence during full reset.
abstract class NativeAlarmResetBoundary {
  /// Enqueues and awaits native alarm disable before manual SDK cleanup.
  Future<void> prepareReset();

  /// Cancels all scheduled native OS alarms and wipes native tokens.
  Future<void> resetAll();
}

/// Production implementation communicating with the coordinator
/// which owns the physical OS queue and enforces the single native owner principle.
class CoordinatorNativeAlarmResetBoundary implements NativeAlarmResetBoundary {
  final Ref _ref;

  CoordinatorNativeAlarmResetBoundary(this._ref);

  @override
  Future<void> prepareReset() {
    return _ref.read(prayerNotificationCoordinatorProvider).executePrepareReset();
  }

  @override
  Future<void> resetAll() {
    return _ref.read(prayerNotificationCoordinatorProvider).executeResetAll();
  }
}

/// Direct channel implementation communicating with the native Android coordinator
/// via MethodChannel 'dev.zadalruh.zad_alruh/prayer_alarm'.
class MethodChannelNativeAlarmResetBoundary implements NativeAlarmResetBoundary {
  static const MethodChannel defaultChannel =
      MethodChannel('dev.zadalruh.zad_alruh/prayer_alarm');

  final MethodChannel _channel;
  final bool isAndroidPlatform;

  MethodChannelNativeAlarmResetBoundary({
    MethodChannel? channel,
    bool? isAndroid,
  })  : _channel = channel ?? defaultChannel,
        isAndroidPlatform =
            isAndroid ?? (defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<void> prepareReset() async {
    if (!isAndroidPlatform) {
      return;
    }
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('disableAlarms');
      if (result is! Map) {
        throw const NativeResetException(
          'فشلت استجابة النظام أثناء تعطيل التنبيهات.',
          'MALFORMED_OR_NULL_RESPONSE',
        );
      }
      final success = result['success'] == true;
      final partialFailure = result['partialFailure'] == true;
      final errorCode = result['errorCode']?.toString();
      if (!success ||
          partialFailure ||
          (errorCode != null && errorCode.isNotEmpty)) {
        throw NativeResetException(
          result['messageAr']?.toString() ??
              'تعذر إلغاء تنبيهات الأذان في النظام.',
          errorCode ?? 'PREPARE_RESET_FAILED',
        );
      }
    } on PlatformException catch (e) {
      throw NativeResetException(
        'تعذر إلغاء تنبيهات الأذان في النظام.',
        '${e.code}${e.message != null ? ': ${e.message}' : ''}',
      );
    }
  }

  @override
  Future<void> resetAll() async {
    if (!isAndroidPlatform) {
      return;
    }

    try {
      final dynamic result = await _channel.invokeMethod<dynamic>('resetAll');
      if (result is! Map) {
        throw const NativeResetException(
          'فشلت استجابة النظام أثناء إلغاء التنبيهات.',
          'MALFORMED_OR_NULL_RESPONSE',
        );
      }

      final success = result['success'] == true;
      final partialFailure = result['partialFailure'] == true;
      final errorCode = result['errorCode']?.toString();
      final hasErrorCode = errorCode != null && errorCode.isNotEmpty;
      final isIncompleteCleanup = errorCode == 'OS_CLEANUP_INCOMPLETE' ||
          errorCode == 'ALARM_SCHEDULING_INCOMPLETE';

      if (!success || partialFailure || isIncompleteCleanup || hasErrorCode) {
        final messageAr = result['messageAr']?.toString() ??
            'فشلت إعادة ضبط مواعيد الأذان في النظام.';
        final technicalCode = errorCode ??
            (partialFailure ? 'PARTIAL_FAILURE' : 'NATIVE_RESET_FAILED');
        throw NativeResetException(messageAr, technicalCode);
      }
    } on MissingPluginException {
      throw const NativeResetException(
        'خدمة التنبيهات في النظام غير متاحة حالياً.',
        'MISSING_PLUGIN',
      );
    } on PlatformException catch (e) {
      throw NativeResetException(
        'تعذر إلغاء تنبيهات الأذان في النظام.',
        '${e.code}${e.message != null ? ': ${e.message}' : ''}',
      );
    } on NativeResetException {
      rethrow;
    } catch (e) {
      throw NativeResetException(
        'حدث خطأ غير متوقع أثناء إلغاء تنبيهات النظام.',
        e.toString(),
      );
    }
  }
}

/// Riverpod provider delivering the native alarm reset boundary wired to coordinator.
final nativeAlarmResetBoundaryProvider =
    Provider<NativeAlarmResetBoundary>((ref) {
  return CoordinatorNativeAlarmResetBoundary(ref);
});
