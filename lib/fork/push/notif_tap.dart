/// Тап по уведомлению ведёт туда, о чём оно (UX_AUDIT D8).
///
/// Раньше тап просто открывал приложение на главной: «Аня зовёт порисовать»
/// не вело к холсту, и человек искал его сам. Теперь уведомление несёт ту же
/// ссылку `loveapp://…`, что и виджет рабочего стола, а главная разбирает её
/// своим `_handleWidgetUri` — холст, карта и прочее открываются одинаково.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../services/deep_link_service.dart';

abstract final class ForkNotifTap {
  /// Куда ведёт уведомление хука сервера с [thread] (`fork_notify`).
  /// null — на главную, как раньше.
  static String? forThread(String thread) => switch (thread) {
        'draw' => 'loveapp://draw',
        'watch' => 'loveapp://watch', // зов в комнату просмотра
        _ => null,
      };

  /// Разобрать полезную нагрузку уведомления. Чужое — мимо.
  static Uri? parse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    final uri = Uri.tryParse(payload);
    if (uri == null || uri.scheme != 'loveapp' || uri.host.isEmpty) return null;
    return uri;
  }

  /// Колбэк плагина: человек нажал на уведомление открытого приложения.
  static void onResponse(NotificationResponse r) => open(r.payload);

  static void open(String? payload) {
    final uri = parse(payload);
    if (uri != null) DeepLinkService().openAction(uri);
  }

  /// Приложение запустили тапом по уведомлению — ссылка ждёт главную.
  static Future<void> checkLaunch(FlutterLocalNotificationsPlugin ln) async {
    try {
      final d = await ln.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) {
        open(d?.notificationResponse?.payload);
      }
    } catch (e) {
      debugPrint('ForkNotifTap: $e');
    }
  }
}
