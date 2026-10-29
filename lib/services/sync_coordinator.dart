import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;

import '../fork/realtime/verified_delta.dart';
import 'catch_up_driver.dart';
import 'centrifugo_service.dart';

/// Единый догон того, что прошло мимо сокета (RT-2, RT-3).
///
/// Сокет Centrifugo не досылает события, случившиеся в разрыв, а разрывов
/// много: мобильная сеть, сон телефона, перезапуск сервера. Раньше дотягивали
/// пропущенное только чат и дом питомца; воспоминания, настроения, желания,
/// подарки и остальное ждали смены сети устройства (`onOnlineChanged`), и
/// изменение партнёра могло не появиться часами.
///
/// Каждая живая область (кэш-список, документ, подписка экрана) регистрирует
/// здесь свой `sync` и получает догон по трём поводам:
///  * сокет переподключился ([CentrifugoService.reconnected]);
///  * приложение вернулось на экран после паузы;
///  * снова доступен ключ подписи сервера, а дельты канала области до этого
///    отбрасывались ([ForkVerifiedDelta.keyRecovered]).
///
/// Правила догона — в [CatchUpDriver], одном на область: разброс по времени,
/// чтобы все области и все клиенты не пришли за данными одной секундой; не
/// вперехлёст; не чаще [minInterval] — частые переподключения не становятся
/// штормом запросов.
class SyncCoordinator {
  SyncCoordinator({
    required Stream<void> reconnected,
    required Stream<bool> foreground,
    required Stream<String> keyRecovered,
    required bool Function(String channel) isSubscribed,
    this.minInterval = const Duration(seconds: 3),
    Duration Function()? jitter,
    DateTime Function()? now,
  }) : _reconnected = reconnected,
       _foreground = foreground,
       _keyRecovered = keyRecovered,
       _isSubscribed = isSubscribed,
       _jitter = jitter,
       _now = now;

  static SyncCoordinator? _instance;
  static SyncCoordinator get instance => _instance ??= _live();

  static SyncCoordinator _live() {
    final visible = StreamController<bool>.broadcast();
    try {
      // Один слушатель жизненного цикла на всё приложение вместо своего у
      // каждого списка.
      AppLifecycleListener(
        onShow: () => visible.add(true),
        onHide: () => visible.add(false),
      );
    } catch (_) {
      // тихо: привязки Flutter нет (юнит-тест без неё) — без повода «вернулись».
    }
    return SyncCoordinator(
      reconnected: CentrifugoService.instance.reconnected,
      foreground: visible.stream,
      keyRecovered: ForkVerifiedDelta.keyRecovered,
      isSubscribed: CentrifugoService.instance.isSubscribed,
    );
  }

  final Stream<void> _reconnected;
  final Stream<bool> _foreground;
  final Stream<String> _keyRecovered;
  final bool Function(String channel) _isSubscribed;
  final Duration Function()? _jitter;
  final DateTime Function()? _now;

  /// Не чаще одного догона области за это время.
  final Duration minInterval;

  int _active = 0;

  /// Сколько областей сейчас под догоном (для тестов и отладки).
  int get activeScopes => _active;

  /// Поставить область под догон. [channel] — канал Centrifugo, по которому
  /// идут её дельты: по нему узнаём «ключ вернулся» и живость подписки.
  /// [pollWithoutSocket] — пока подписки на канал нет и приложение на экране,
  /// дотягивать раз в 15 секунд (чат: там пропуск виден сразу).
  /// Ошибки [sync] глотаются — следующий повод попробует снова.
  SyncHandle register({
    required Future<void> Function() sync,
    String? channel,
    bool pollWithoutSocket = false,
  }) {
    final driver = CatchUpDriver(
      catchUp: sync,
      reconnected: _reconnected,
      foreground: _foreground,
      nudges: channel == null ? null : _keyRecovered.where((c) => c == channel),
      subscribed: () => channel == null || _isSubscribed(channel),
      pollEvery: pollWithoutSocket && channel != null
          ? const Duration(seconds: 15)
          : null,
      minInterval: minInterval,
      jitter: _jitter,
      now: _now,
    );
    _active++;
    return SyncHandle._(() {
      driver.dispose();
      _active--;
    });
  }
}

/// Регистрация области в [SyncCoordinator]; [dispose] снимает догон.
class SyncHandle {
  SyncHandle._(this._release);
  void Function()? _release;

  void dispose() {
    final release = _release;
    _release = null;
    release?.call();
  }
}
