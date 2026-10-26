import 'dart:async';

import '../fork/e2e/fork_e2e.dart';
import '../fork/ui/feedback.dart';
import 'centrifugo_service.dart';

/// Канал комнаты совместного просмотра.
///
/// Говорит теми же сообщениями, что сайт: `play`, `pause`, `sync`, `source`,
/// `chat`, `hello`, `state`. Поэтому нативный плеер приложения и вкладка
/// браузера сидят в одной комнате и понимают друг друга.
class WatchChannel {
  WatchChannel(this.room, this.me);

  /// Код комнаты пары (выдаёт сервер по связи).
  final String room;

  /// Кто мы в этой комнате: свои же сообщения обратно не применяем.
  final String me;

  String get channel => 'watch:$room';

  RtUnsub? _unsub;

  /// Подписывается на комнату. [onMessage] получает разобранное сообщение.
  Future<void> connect(void Function(Map<String, dynamic>) onMessage) async {
    _unsub = await CentrifugoService.instance.subscribeRaw(channel, (raw) {
      // fork (E2E): сигнализация звонка — только шифром ключа пары.
      var data = raw;
      if (raw['t'] == 'e2e') {
        final open = ForkE2E.openSignal(channel, raw);
        if (open == null) return;
        data = open;
      } else if ('${raw['t']}'.startsWith('voice-')) {
        return;
      }
      if ((data['from'] ?? '') == me) return; // эхо своих команд
      onMessage(data);
    });
  }

  /// fork (UX L5): почему последняя [send] не ушла; null — ушла.
  ForkFailure? lastFailure;

  /// fork (UX L5): true — сообщение ушло в канал. Раньше отказ был немым, и
  /// звонящий ждал ответа на зов, который никуда не ушёл.
  Future<bool> send(
    String type, {
    double at = 0,
    Map<String, dynamic>? extra,
  }) async {
    var payload = <String, dynamic>{'t': type, 'at': at, 'from': me, ...?extra};
    lastFailure = null;
    if (type.startsWith('voice-')) {
      // fork (E2E): SDP несёт отпечаток DTLS, ICE — адреса: открытыми сервер
      // встал бы посередине звонка. Нет ключа пары — звонка нет.
      final sealed = ForkE2E.sealSignal(ForkE2E.activeGroup, channel, payload);
      if (sealed == null) {
        lastFailure = ForkFailure.noKey;
        return false;
      }
      payload = sealed;
    }
    try {
      await CentrifugoService.instance.publish(channel, payload);
      return true;
    } catch (e) {
      // Обрыв связи лечит переподключение centrifuge: команда просто пропадёт,
      // а расхождение подтянет ближайший sync.
      lastFailure = ForkFailure.of(e);
      return false;
    }
  }

  Future<void> dispose() async {
    final u = _unsub;
    _unsub = null;
    if (u != null) await u();
  }
}
