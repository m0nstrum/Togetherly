import 'dart:async';

/// Отписка от канала; совпадает с `RtUnsub` из `CentrifugoService`.
typedef SubscribedUnsub = Future<void> Function();

/// Поток поверх подписки, которая поднимается асинхронно (`subscribeRaw`,
/// `subscribeDelta`).
///
/// ЗАЧЕМ (аудит RT-5): прежний рецепт `onListen: () async { unsub = await
/// subscribeRaw(...); }` терял отписку, если слушатель уходил раньше, чем
/// кончался `await`: `onCancel` видел `unsub == null`, и канал Centrifugo
/// (а в чате ещё и таймер) жили до конца процесса.
///
/// Здесь на каждого слушателя — свой сеанс:
///  • [start] — синхронный запуск своих ресурсов (подписка на БД, таймер,
///    первый запрос); освобождает их [stop];
///  • [subscribe] — сама подписка; ей и [start] передаётся `add`, который
///    после отмены молча ничего не делает;
///  • отмена до конца [subscribe] зовёт [stop] сразу, а отписку — как только
///    подписка поднимется; ошибка подписки уходит в поток, пока он слушается.
///
/// Одиночный поток закрывается при отмене; широковещательный ([broadcast])
/// остаётся открытым — новый слушатель поднимет новый сеанс.
Stream<T> subscribedStream<T>({
  required Future<SubscribedUnsub> Function(void Function(T value) add)
  subscribe,
  void Function(void Function(T value) add)? start,
  FutureOr<void> Function()? stop,
  bool broadcast = false,
}) {
  late StreamController<T> ctrl;
  _Session? session;

  void onListen() {
    final s = _Session();
    session = s;
    void add(T value) {
      if (!s.cancelled && !ctrl.isClosed) ctrl.add(value);
    }

    start?.call(add);
    s.unsub = Future.sync(() => subscribe(add)).then<SubscribedUnsub?>(
      (u) => u,
      onError: (Object e, StackTrace st) {
        if (!s.cancelled && !ctrl.isClosed) ctrl.addError(e, st);
        return null;
      },
    );
  }

  Future<void> onCancel() async {
    final s = session;
    session = null;
    if (s == null) return;
    s.cancelled = true;
    try {
      await stop?.call();
    } finally {
      // Подписка ещё в пути — дождёмся её и сразу снимем.
      final unsub = await s.unsub;
      await unsub?.call();
      if (!broadcast) await ctrl.close();
    }
  }

  ctrl = broadcast
      ? StreamController<T>.broadcast(onListen: onListen, onCancel: onCancel)
      : StreamController<T>(onListen: onListen, onCancel: onCancel);
  return ctrl.stream;
}

class _Session {
  bool cancelled = false;
  Future<SubscribedUnsub?>? unsub;
}
