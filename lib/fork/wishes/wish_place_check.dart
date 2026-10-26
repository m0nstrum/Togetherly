/// «Если пара оказалась там вместе — напомнить» (docs/WISHLIST.md): расчёт
/// без платформы. Считает телефон по своей точке и точке партнёра; координаты
/// мест на сервер не уходят.
library;

import '../../models/wish.dart';

/// Точка с моментом снятия.
class GeoFix {
  const GeoFix(this.lat, this.lng, this.at, {this.accuracy = 0});
  final double lat;
  final double lng;
  final DateTime at;

  /// Погрешность, метров: размытая точка «рядом» не считается.
  final double accuracy;
}

/// Не чаще раза в неделю на одно место.
const Duration wishPlaceCooldown = Duration(days: 7);

/// Точка партнёра старше этого — не «вместе сейчас».
const Duration wishPartnerFresh = Duration(minutes: 15);

/// Желания-места, рядом с которыми сейчас оба: [radius] метров от точки
/// каждого, точка партнёра свежая, место не напоминало последнюю неделю.
List<Wish> wishPlacesTogether({
  required Iterable<Wish> wishes,
  required GeoFix me,
  required GeoFix? partner,
  required DateTime now,
  required double radius,
  Map<String, DateTime> lastNotified = const {},
}) {
  if (partner == null || now.difference(partner.at) > wishPartnerFresh) {
    return const [];
  }
  bool near(GeoFix f, Wish w) =>
      f.accuracy <= radius &&
      w.place!.metersTo(f.lat, f.lng) <= radius + f.accuracy / 2;
  return [
    for (final w in wishes)
      if (!w.done &&
          w.place != null &&
          near(me, w) &&
          near(partner, w) &&
          !_recent(lastNotified[w.id], now))
        w,
  ];
}

/// Рядом ли хоть одно место со мной — дешёвая проверка до запроса точки
/// партнёра.
bool anyWishPlaceNear(Iterable<Wish> wishes, GeoFix me, double radius) =>
    wishes.any(
      (w) =>
          !w.done &&
          w.place != null &&
          w.place!.metersTo(me.lat, me.lng) <= radius + me.accuracy / 2,
    );

bool _recent(DateTime? at, DateTime now) =>
    at != null && now.difference(at) < wishPlaceCooldown;
