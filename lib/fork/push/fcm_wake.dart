/// FCM как будильник (docs/history/PLAN.md, S12).
///
/// Пуш несёт только `{type: "sync", event: <id>}`. Нативный
/// `ForkFcmService.kt` будит Dart задачей workmanager, а здесь событие
/// забирается со своего сервера (`/api/fork/wake`) — та же публикация, что
/// ушла бы по сокету, — и проходит через подписки [PbPushService]: тексты,
/// настройки уведомлений и расшифровка те же, что у сокета.
library;

import 'package:flutter/foundation.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:home_widget/home_widget.dart';

import '../../dict_strings.dart' show ruEn;
import '../../services/centrifugo_service.dart';
import '../../services/locale_service.dart';
import '../../services/pb_push_service.dart';
import '../../services/pocketbase_service.dart';
import '../e2e/fork_e2e.dart';
import '../identity.dart';

abstract final class ForkFcmWake {
  /// Задача диспетчера workmanager (`ForkFcmService.TASK`).
  static const task = 'fcmWake';

  /// Сколько ждать, пока колбэки подписок дорисуют уведомление.
  @visibleForTesting
  static Duration settle = const Duration(seconds: 2);

  /// Обработать пуш с [input] (`event`). Всегда true: повтор задачи
  /// WorkManager событие не вернёт.
  static Future<bool> run(Map<String, dynamic>? input) async {
    final event = '${input?['event'] ?? ''}';
    if (event.isEmpty) return true;
    try {
      final svc = PocketBaseService();
      await svc.init();
      final myUid = svc.userId ?? '';
      if (myUid.isEmpty || !svc.isLoggedIn) return true;
      await LocaleService.instance.init();
      final push = PbPushService();
      await push.init();

      final ev = await _fetch(event);
      final groupId =
          await HomeWidget.getWidgetData<String>('love_widget_group_id') ?? '';
      final partnerUid =
          await HomeWidget.getWidgetData<String>('love_widget_partner_uid') ??
          '';
      if (ev == null || groupId.isEmpty || partnerUid.isEmpty) {
        // Событие ушло (сервер перезапускался) или пары нет — нейтрально.
        await push.showLocal(
          id: 'fork_wake$event'.hashCode,
          title: ForkIdentity.appName,
          // UX G16: не «Новое событие» без адресата — человек видит, что это
          // от партнёра и что делать.
          body: ruEn(
            'Партнёр что-то прислал — откройте приложение',
            'Your partner sent something — open the app',
          ),
        );
        return true;
      }
      await ForkE2E.codec(); // ключи для расшифровки публикации
      await push.start(groupId: groupId, myUid: myUid, partnerUid: partnerUid);
      CentrifugoService.instance.deliver(ev.channel, ev.data);
      await Future<void>.delayed(settle);
      await push.stop();
      await CentrifugoService.instance.reset();
    } catch (e) {
      debugPrint('ForkFcmWake: $e');
    }
    return true;
  }

  static Future<({String channel, Map<String, dynamic> data})?> _fetch(
    String event,
  ) async {
    try {
      final res = await PocketBaseService().pb.send(
        '/api/fork/wake',
        method: 'POST',
        body: {'event': event},
      );
      if (res is! Map || res['data'] is! Map) return null;
      return (
        channel: '${res['channel'] ?? ''}',
        data: Map<String, dynamic>.from(res['data'] as Map),
      );
    } catch (e) {
      debugPrint('ForkFcmWake: событие $event — $e');
      return null;
    }
  }
}

/// Токен FCM на своём сервере (`push_tokens`, только сервер его видит).
abstract final class ForkPushToken {
  static String _saved = '';
  static String _owner = '';
  static void resetRegistration() {
    _saved = '';
    _owner = '';
  }

  /// Сервер принял токен и сам умеет слать FCM. Пока нет — фоновый сокет
  /// не гасим: иначе без настроенного Firebase на сервере уведомления
  /// пропали бы совсем.
  static bool get accepted =>
      _saved.isNotEmpty && _owner == PocketBaseService().userId;

  static Future<bool> save(String token) async {
    final owner = PocketBaseService().userId;
    resetRegistration();
    try {
      final res = await PocketBaseService().pb.send(
        '/api/fork/push-token',
        method: 'POST',
        body: {'token': token},
      );
      final on = res is Map && res['enabled'] == true;
      if (owner != PocketBaseService().userId) return false;
      _owner = owner ?? '';
      _saved = on ? token : '';
      return on;
    } catch (e) {
      if (e is ClientException && e.statusCode == 409) rethrow;
      debugPrint('ForkPushToken: не сохранён — $e');
      return false;
    }
  }

  /// При выходе: телефон больше не будит этот аккаунт.
  static Future<void> forget() async {
    final t = _saved;
    if (t.isEmpty) return;
    _saved = '';
    try {
      await PocketBaseService().pb.send(
        '/api/fork/push-token',
        method: 'DELETE',
        body: {'token': t},
      );
    } catch (e) {
      debugPrint('ForkPushToken: не забыт — $e');
    }
  }
}
