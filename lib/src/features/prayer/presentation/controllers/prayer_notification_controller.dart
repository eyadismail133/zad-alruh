import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/prayer_notification_coordinator.dart';

export '../../domain/services/prayer_notification_coordinator.dart'
    show
        PrayerNotificationStatus,
        PrayerNotificationState,
        prayerNotificationCoordinatorProvider,
        prayerNotificationStateProvider;

/// Controller for UI screens (Settings, Prayers) to interact with prayer notifications.
class PrayerNotificationController {
  final Ref _ref;

  PrayerNotificationController(this._ref);

  PrayerNotificationState get currentState =>
      _ref.read(prayerNotificationStateProvider);

  /// Requests enabling notifications, including permissions.
  Future<bool> enable() async {
    final coordinator = _ref.read(prayerNotificationCoordinatorProvider);
    return coordinator.enableNotifications();
  }

  /// Disables notifications immediately.
  Future<void> disable() async {
    final coordinator = _ref.read(prayerNotificationCoordinatorProvider);
    await coordinator.disableNotifications();
  }

  /// Toggles notifications based on [value].
  Future<void> toggle(bool value) async {
    if (value) {
      await enable();
    } else {
      await disable();
    }
  }

  /// Explicit user action to request exact alarm permission, opening system settings.
  /// Requeries capability after return (intent launch success is NOT a grant).
  Future<void> requestExactAlarmPermission() async {
    final coordinator = _ref.read(prayerNotificationCoordinatorProvider);
    await coordinator.requestExactAlarmPermission();
  }

  /// Recovers from latch or pending cleanups.
  Future<void> recover() async {
    final coordinator = _ref.read(prayerNotificationCoordinatorProvider);
    await coordinator.recoverFromLatch();
  }

  /// Reconciles state passively.
  Future<void> reconcile() async {
    final coordinator = _ref.read(prayerNotificationCoordinatorProvider);
    await coordinator.reconcile(passive: true);
  }
}

/// Provider delivering the [PrayerNotificationController].
final prayerNotificationControllerProvider =
    Provider<PrayerNotificationController>((ref) {
  return PrayerNotificationController(ref);
});
