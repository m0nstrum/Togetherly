/// Уведомления хуков сервера без APNs/FCM (docs/fork/PLAN.md, решение 2).
///
/// Зов в совместную ленту, «пойдём порисовать» и подобные события не живут
/// записями в базе: апстрим доставлял их только пушем Firebase/Apple. В форке
/// сервер кладёт их в канал `user:<uid>` Centrifugo
/// (`server/hooks/apns_push.js` → `/internal/notify`), а здесь они
/// превращаются в локальное уведомление — и в приложении, и в фоновом
/// сервисе, который держит сокет.
library;

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../dict_strings.dart' show ruEn;
import '../services/centrifugo_service.dart';
import '../services/reels/reels_invite.dart';
import 'push/notif_tap.dart';

abstract final class ForkPushRelay {
  /// Подписка для [myUid]; [notify] — показ локального уведомления.
  static Future<UnsubscribeFunc> subscribe(
    String myUid,
    Future<void> Function(int id, String title, String body, {String? payload}) notify,
  ) => CentrifugoService.instance.subscribeDelta('user:$myUid', 'fork_notify', (
    e,
  ) {
    final r = e.record;
    if (e.action != 'create' || r == null) return;
    handle(r.id, r.data, notify);
  });

  /// Разбор одного уведомления. Виден тестам.
  static void handle(
    String id,
    Map<String, dynamic> rec,
    Future<void> Function(int id, String title, String body, {String? payload}) notify,
  ) {
    final thread = '${rec['thread'] ?? ''}';
    final title = '${rec['title'] ?? ''}';
    final body = '${rec['body'] ?? ''}';
    final data = rec['data'] is Map
        ? Map<String, dynamic>.from(rec['data'] as Map)
        : <String, dynamic>{};
    if (thread == 'call') {
      _call(id, data, notify);
      return;
    }
    if (title.isNotEmpty || body.isNotEmpty) {
      // UX D8: тап ведёт туда, о чём уведомление («порисовать» — к холсту).
      notify('fork_notify$id'.hashCode, title, body,
          payload: ForkNotifTap.forThread(thread));
    }
    // Зов в ленту, пока приложение открыто, — лист «присоединиться», как от
    // моста FCM (`ReelsInviteBridge.arrived`).
    if (thread == 'reels') {
      final invite = ReelsInvite.parse({...data, 'kind': 'reels'});
      if (invite != null) ReelsInviteBus.instance.deliver(invite);
    }
  }

  /// Сколько живёт зов: звонящий сдаётся через 45 с (`WatchVoiceService.ringFor`).
  static const callFresh = Duration(seconds: 45);

  /// Открытое приложение покажет карточку входящего само.
  @visibleForTesting
  static bool Function() appInFront = () {
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } catch (_) {
      // тихо: фоновый изолят без привязки виджетов — приложение не на экране.
      return false;
    }
  };

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// Партнёр звонит (UX_AUDIT L6). Сервер текста не кладёт: подпись своя.
  /// Пуш мог опоздать — старый зов не показываем.
  static void _call(
    String id,
    Map<String, dynamic> data,
    Future<void> Function(int id, String title, String body, {String? payload}) notify,
  ) {
    final at = int.tryParse('${data['at'] ?? ''}') ?? 0;
    final age = now().difference(DateTime.fromMillisecondsSinceEpoch(at));
    if (at <= 0 || age.abs() > callFresh) {
      return;
    }
    if (appInFront()) return;
    notify(
      'fork_call${data['group_id'] ?? ''}'.hashCode,
      ruEn('Входящий звонок', 'Incoming call'),
      ruEn('Партнёр звонит — откройте приложение, чтобы ответить',
          'Your partner is calling — open the app to answer'),
      payload: 'loveapp://home',
    );
  }
}
