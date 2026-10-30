/// Взаимность геопозиции (BACKLOG D11): точку партнёра видит только тот, кто
/// делится сам.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Поток точки, открытый только пока [isOpen] — правда.
///
/// Закрыто — подписки на канал нет вовсе (сервер её и не выдаст), а поток
/// отдаёт null: экран сразу прячет метку и забывает её координаты. Открылось
/// — поднимаем [open] заново; закрылось на ходу — снимаем его. Перепроверка —
/// на каждое изменение [gate].
Stream<T?> whileMutual<T>({
  required Listenable gate,
  required bool Function() isOpen,
  required Stream<T?> Function() open,
}) {
  late StreamController<T?> ctrl;
  StreamSubscription<T?>? inner;
  bool? shown;

  void sync() {
    if (ctrl.isClosed) return;
    final on = isOpen();
    if (on == shown) return;
    shown = on;
    if (on) {
      inner = open().listen(
        (v) {
          if (shown == true && !ctrl.isClosed) ctrl.add(v);
        },
        onError: (Object e, StackTrace st) {
          if (shown == true && !ctrl.isClosed) ctrl.addError(e, st);
        },
      );
    } else {
      final s = inner;
      inner = null;
      if (s != null) unawaited(s.cancel());
      ctrl.add(null);
    }
  }

  ctrl = StreamController<T?>(
    onListen: () {
      gate.addListener(sync);
      sync();
    },
    onCancel: () async {
      gate.removeListener(sync);
      final s = inner;
      inner = null;
      shown = null;
      await s?.cancel();
    },
  );
  return ctrl.stream;
}
