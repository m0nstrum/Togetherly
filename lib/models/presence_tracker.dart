/// Кого из партнёров сейчас слышно — память признаков жизни (B10).
///
/// Раньше «в сети» держалось на одном сигнале `alive` и на отметке времени,
/// которую ставил сам отправитель. Отсюда «партнёр офлайн, хотя пишет»:
///  * часы телефонов не сверены. Если у партнёра часы спешат хоть на секунду,
///    возраст удара выходил отрицательным и [PresenceLiveness.isOnline]
///    отвечал «нет»; отстают больше чем на 45 секунд — тоже «нет». Теперь
///    свежесть меряется по времени ПРИЁМА на этом телефоне;
///  * печать, прикосновение, реплика — всё это не считалось. Теперь любое
///    действие партнёра в канале пары — признак жизни;
///  * после переподключения ждали следующего удара до двадцати секунд. Теперь
///    своя подписка встала — шлём удар с просьбой ответить ([shouldAnswer]).
///
/// Без сети и таймеров: часы передаются, чтобы тесты шли без ожидания.
library;

import 'presence_liveness.dart';

class PresenceTracker {
  PresenceTracker({int Function()? nowMs})
    : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _now;

  /// Когда партнёра последний раз слышали (по нашим часам): uid → мс.
  final Map<String, int> _heard = <String, int>{};

  /// Партнёр сам сказал «ушёл» (свернул приложение): uid → мс.
  final Map<String, int> _gone = <String, int>{};

  int _answeredAt = 0;

  /// Партнёр [uid] что-то сделал в канале: удар, печать, касание, реплика.
  ///
  /// true — до этого он считался не в сети: стоит сразу ответить своим ударом,
  /// чтобы он тоже увидел нас без ожидания.
  bool heard(String uid) {
    if (uid.isEmpty) return false;
    final was = online(uid);
    _heard[uid] = _now();
    _gone.remove(uid);
    return !was;
  }

  /// Партнёр [uid] свернул приложение или вышел: офлайн сразу, а не через
  /// сорок пять секунд тишины.
  void gone(String uid) {
    if (uid.isEmpty) return;
    _gone[uid] = _now();
    _heard.remove(uid);
  }

  /// В сети ли [uid]. [storedSeenMs] — отметка в базе от сборок постарше.
  ///
  /// После «ушёл» отметка базы не в счёт: её пишет тот же телефон, и она
  /// старше ухода. Новый признак жизни снимает «ушёл».
  bool online(String uid, {int? storedSeenMs}) {
    if (_gone.containsKey(uid)) return false;
    return PresenceLiveness.isOnline(
      channelBeatMs: _heard[uid],
      storedSeenMs: storedSeenMs,
      nowMs: _now(),
    );
  }

  /// Когда видели в последний раз — для подписи «была в 12:33».
  int? lastSeen(String uid, {int? storedSeenMs}) => PresenceLiveness.lastSeenMs(
    channelBeatMs: _heard[uid] ?? _gone[uid],
    storedSeenMs: storedSeenMs,
  );

  /// Просьбу «ответь» исполняем не чаще раза в [answerEvery]: двое,
  /// переподключившиеся разом, не устроят пинг-понг.
  static const Duration answerEvery = Duration(seconds: 5);

  bool shouldAnswer() {
    final now = _now();
    if (now - _answeredAt < answerEvery.inMilliseconds) return false;
    _answeredAt = now;
    return true;
  }

  void clear() {
    _heard.clear();
    _gone.clear();
    _answeredAt = 0;
  }
}
