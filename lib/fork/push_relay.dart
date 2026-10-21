/// Уведомления хуков сервера без APNs/FCM (docs/fork/PLAN.md, решение 2).
///
/// Зов в совместную ленту, «пойдём порисовать» и подобные события не живут
/// записями в базе: апстрим доставлял их только пушем Firebase/Apple. В форке
/// сервер кладёт их в канал `user:<uid>` Centrifugo
/// (`server/hooks/apns_push.js` → `/internal/notify`), а здесь они
/// превращаются в локальное уведомление — и в приложении, и в фоновом
/// сервисе, который держит сокет.
library;

import 'package:pocketbase/pocketbase.dart';

import '../services/centrifugo_service.dart';
import '../services/reels/reels_invite.dart';

abstract final class ForkPushRelay {
  /// Подписка для [myUid]; [notify] — показ локального уведомления.
  static Future<UnsubscribeFunc> subscribe(
    String myUid,
    Future<void> Function(int id, String title, String body) notify,
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
    Future<void> Function(int id, String title, String body) notify,
  ) {
    final thread = '${rec['thread'] ?? ''}';
    final title = '${rec['title'] ?? ''}';
    final body = '${rec['body'] ?? ''}';
    final data = rec['data'] is Map
        ? Map<String, dynamic>.from(rec['data'] as Map)
        : <String, dynamic>{};
    if (title.isNotEmpty || body.isNotEmpty) {
      notify('fork_notify$id'.hashCode, title, body);
    }
    // Зов в ленту, пока приложение открыто, — лист «присоединиться», как от
    // моста FCM (`ReelsInviteBridge.arrived`).
    if (thread == 'reels') {
      final invite = ReelsInvite.parse({...data, 'kind': 'reels'});
      if (invite != null) ReelsInviteBus.instance.deliver(invite);
    }
  }
}
