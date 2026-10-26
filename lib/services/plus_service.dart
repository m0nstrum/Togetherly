import 'package:flutter/foundation.dart';

import 'plus_access.dart';

/// Что открывает Togetherly+ в апстриме. В форке открыто всё и всем.
enum PlusFeature {
  /// Все платные темы оформления разом.
  themes,

  /// Календарь цикла с прогнозом и статистикой.
  cycle,

  /// Новый каталог виджетов: «Вместе», «Скучаю», «Настроение», «До встречи».
  widgets,
}

/// Доступ к Togetherly+.
///
/// В Tethered платного нет (решение 1): всё открыто у всех, покупок, подарков
/// доступа и недели из сундука нет. Сервис остался ради экранов апстрима,
/// которые спрашивают [active], [gate] и [visible], — ответ у него всегда
/// «открыто», и замков нигде не появляется.
class PlusService extends ChangeNotifier {
  PlusService._();
  static final PlusService instance = PlusService._();
  factory PlusService() => instance;

  /// Открыто всё.
  bool get active => true;

  /// Ответ известен сразу: спрашивать сервер не о чем.
  bool get known => true;

  /// Покупки через биллинг магазина нет.
  static bool get buysInStore => false;

  /// Предлагать покупку негде.
  static bool get canPurchase => false;

  /// Что рисовать на месте платной вещи — всегда «открыто».
  PlusGate get gate => PlusAccess.gate(active: true, exists: true);

  /// Платное место в интерфейсе есть и открыто.
  bool get visible => true;

  /// Открыта ли возможность — да.
  bool allows(PlusFeature feature) => true;

  /// Совместимость с экранами апстрима: перечитывать нечего.
  Future<void> ensureLoaded() async {}

  Future<void> refresh() async {}
}
