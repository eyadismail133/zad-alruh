import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/services/local_settings.dart';
import '../domain/reminder_settings.dart';

/// Global navigator used to open screens when a reminder is tapped.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Offline reminders (dhikr phrases, adhkar times, Friday) scheduled with the
/// OS alarm manager through flutter_local_notifications. They fire without the
/// app running and without internet.
///
/// Everything is best-effort and no-ops until [init] succeeded (it is only
/// called from `main`, so widget tests never touch the platform channel).
class ReminderService {
  ReminderService._();
  static final ReminderService instance = ReminderService._();

  static const String _settingsKey = 'reminders.settings';
  static const int idBase = 70000;
  static const int idMax = 70999;

  static const _popupChannel = AndroidNotificationChannel(
    'zad_dhikr_popup',
    'تذكيرات الذكر (منبثقة)',
    description: 'تظهر أعلى الشاشة مع صوت خفيف',
    importance: Importance.max,
  );
  static const _quietChannel = AndroidNotificationChannel(
    'zad_dhikr_quiet',
    'تذكيرات الذكر (هادئة)',
    description: 'تظهر في شريط الإشعارات فقط',
    importance: Importance.low,
    playSound: false,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Payload of the notification that launched the app (handled once).
  String? pendingLaunchPayload;

  /// Called when a reminder is tapped while the app is running.
  void Function(String payload)? onTap;

  ReminderSettings get settings =>
      ReminderSettings.decode(LocalSettings.getString(_settingsKey));

  Future<void> init() async {
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final p = response.payload;
          if (p != null && p.isNotEmpty) {
            if (onTap != null) {
              onTap!(p);
            } else {
              pendingLaunchPayload = p;
            }
          }
        },
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_popupChannel);
      await android?.createNotificationChannel(_quietChannel);
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        pendingLaunchPayload = launch?.notificationResponse?.payload;
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Asks for the Android 13+ notification permission. Returns false when it
  /// was refused (reminders then cannot appear).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> save(ReminderSettings s) async {
    LocalSettings.setString(_settingsKey, s.encode());
    await reschedule(s);
  }

  /// Cancels this feature's pending notifications and schedules the next few
  /// days again. Called on every app start so the schedule keeps rolling.
  Future<void> reschedule([ReminderSettings? s]) async {
    if (!_ready) return;
    final current = s ?? settings;
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= idBase && p.id <= idMax) {
          await _plugin.cancel(p.id);
        }
      }
      if (!current.anyEnabled) return;
      final plan = planReminders(current, DateTime.now(), idBase: idBase);
      for (final r in plan) {
        final channel = r.popUp ? _popupChannel : _quietChannel;
        await _plugin.zonedSchedule(
          r.id,
          r.title,
          r.body,
          tz.TZDateTime.from(r.at, tz.UTC),
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: channel.importance,
              priority: r.popUp ? Priority.max : Priority.low,
              category: AndroidNotificationCategory.reminder,
              visibility: NotificationVisibility.public,
              styleInformation: BigTextStyleInformation(r.body),
              ticker: r.body,
              autoCancel: true,
              timeoutAfter: r.popUp ? 10 * 60 * 1000 : null,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: r.payload,
        );
      }
    } catch (_) {
      // Scheduling is best-effort; the next app start retries.
    }
  }

  /// Shows one reminder now (used by the "test" button in settings).
  Future<void> showTest(ReminderSettings s) async {
    if (!_ready) return;
    final phrase = s.phrases.first;
    final channel = s.popUp ? _popupChannel : _quietChannel;
    try {
      await _plugin.show(
        idMax,
        'ذكر',
        phrase.text,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: s.popUp ? Priority.max : Priority.low,
            styleInformation: BigTextStyleInformation(phrase.text),
          ),
        ),
        payload: 'dhikr:${phrase.id}',
      );
    } catch (_) {}
  }
}
