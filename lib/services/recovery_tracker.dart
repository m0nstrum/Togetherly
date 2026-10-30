import 'dart:async';

/// Какие каналы после переподключения надо дотягивать запросами (A11).
///
/// Каналы `pair:` и `user:` держат в Centrifugo историю (5 минут, 100
/// публикаций; `deploy/centrifugo/config.json`). Подписка после обрыва
/// просит восстановление, и если Centrifugo отвечает `recovered=true`,
/// пропущенное уже пришло из истории — перечитывать список не нужно.
///
/// Во всех остальных случаях — как без истории: канал попадает в [gaps], и
/// области канала догоняют своё через `SyncCoordinator`:
///  * `recovered=false` — обрыв длиннее истории, история переполнена или
///    Centrifugo перезапускался;
///  * подписка ответила ошибкой;
///  * подписка не встала за [timeout] после переподключения.
class RecoveryTracker {
  RecoveryTracker({this.timeout = const Duration(seconds: 10)});

  /// Сколько ждать ответа подписки после переподключения.
  final Duration timeout;

  /// Канал держит историю на сервере, и его подписка восстанавливается.
  static bool recoverable(String channel) =>
      channel.startsWith('pair:') || channel.startsWith('user:');

  final StreamController<String> _gaps = StreamController<String>.broadcast();

  /// Восстановились из истории после последнего обрыва: ответ подписки может
  /// прийти раньше сигнала «переподключились».
  final Set<String> _recovered = {};

  /// Ждут ответа подписки после переподключения.
  final Map<String, Timer> _awaiting = {};

  /// Каналы, чьё пропущенное за обрыв не пришло из истории.
  Stream<String> get gaps => _gaps.stream;

  /// Сокет оборвался: прошлые восстановления больше не в счёт.
  void dropped() => _recovered.clear();

  /// Сокет переподключился после обрыва; [channels] — каналы с подписками.
  void reconnected(Iterable<String> channels) {
    for (final channel in channels) {
      if (!recoverable(channel) || _recovered.contains(channel)) continue;
      _awaiting[channel] ??= Timer(timeout, () {
        _awaiting.remove(channel);
        _gap(channel);
      });
    }
  }

  /// Подписка на [channel] встала; [recovered] — пропущенное пришло из истории.
  void subscribed(String channel, {required bool recovered}) {
    if (recovered) _recovered.add(channel);
    final waiting = _awaiting.remove(channel);
    if (waiting == null) return;
    waiting.cancel();
    if (!recovered) _gap(channel);
  }

  /// Подписка на [channel] ответила ошибкой.
  void failed(String channel) {
    final waiting = _awaiting.remove(channel);
    if (waiting == null) return;
    waiting.cancel();
    _gap(channel);
  }

  void _gap(String channel) {
    if (!_gaps.isClosed) _gaps.add(channel);
  }

  /// Выход из аккаунта: ожидания снимаются, поток [gaps] остаётся.
  void reset() {
    for (final t in _awaiting.values) {
      t.cancel();
    }
    _awaiting.clear();
    _recovered.clear();
  }
}
