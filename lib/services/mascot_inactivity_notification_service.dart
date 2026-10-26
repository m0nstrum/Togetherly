import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../fork/push/notif_tap.dart';

/// Upgrade cleanup only. The pet never asks people to return on a schedule.
/// Keep notification 9991 cancellation so old installed reminders disappear.
class MascotInactivityNotificationService {
  MascotInactivityNotificationService._();
  static final instance = MascotInactivityNotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initializing;
  bool get _supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  Future<void> init() => _initializing ??= _init();
  Future<void> _init() async {
    if (!_supported) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: ForkNotifTap.onResponse,
    );
    await _plugin.cancel(id: 9991);
  }

  Future<void> markAppOpened() => cancelReminder();
  Future<void> cancelReminder() async {
    await init();
    if (_supported) await _plugin.cancel(id: 9991);
  }

  /// Compatibility for older callers: cancel rather than schedule.
  Future<void> scheduleReminderAfterOneDay() => cancelReminder();
}
