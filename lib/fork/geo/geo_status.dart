/// Что с передачей геопозиции на самом деле (UX_AUDIT G3, G5, G7, G8, G14).
///
/// Переключатель «показывать» говорит о намерении, а не о результате: передачи
/// может не быть из-за отсутствия партнёра, отказа в доступе, выключенной
/// геолокации телефона или запуска из фона. Здесь — причины словами и подписи
/// карты, которые не обещают лишнего. Чистые функции, без Flutter-виджетов.
library;

import '../../dict_strings.dart' show ruEn;
import '../../models/live_point_age.dart';
import '../../models/map_distance.dart';

/// Почему включённый показ не работает. [none] — работает (или выключен).
enum ShareIssue {
  none,
  noPartner,
  denied,
  deniedForever,
  servicesOff,
  needsForeground,
  noConsent,
  streamFailed;

  /// Нужна ли человеку кнопка в системные настройки.
  bool get needsAppSettings => this == denied || this == deniedForever;
  bool get needsLocationSettings => this == servicesOff;

  /// Объяснение для плашки. null — говорить нечего.
  String? get text => switch (this) {
    none => null,
    noPartner => ruEn(
      'Партнёра пока нет — делиться геопозицией не с кем',
      'No partner yet — nobody to share your location with',
    ),
    denied => ruEn(
      'Нет доступа к геопозиции — партнёр вас не видит',
      'No location access — your partner can’t see you',
    ),
    deniedForever => ruEn(
      'Доступ к геопозиции запрещён — разрешите его в настройках',
      'Location access is blocked — allow it in settings',
    ),
    servicesOff => ruEn(
      'Геолокация на телефоне выключена — партнёр вас не видит',
      'Location is turned off on this phone — your partner can’t see you',
    ),
    needsForeground => ruEn(
      'Откройте приложение, чтобы передача началась',
      'Open the app to start sharing',
    ),
    noConsent => ruEn(
      'Показ выключен: партнёр сменился. Включите заново',
      'Sharing is off: your partner changed. Turn it on again',
    ),
    streamFailed => ruEn(
      'Передача не запустилась — выключите и включите показ',
      'Sharing didn’t start — turn it off and on again',
    ),
  };

  /// Подпись кнопки под [text].
  String? get actionLabel => switch (this) {
    denied ||
    deniedForever ||
    servicesOff => ruEn('Открыть настройки', 'Open settings'),
    _ => null,
  };
}

/// Точка свежая: видно, что партнёр на связи, а не просто был здесь когда-то.
/// Без времени (старые записи) — не свежая: утверждать нечего.
bool pointIsFresh(int updatedAtMs, {required int nowMs}) =>
    LivePointAge.of(updatedAtMs, nowMs: nowMs).unit == LivePointAgeUnit.fresh;

String _two(int v) => v.toString().padLeft(2, '0');

/// «на месте с 14:20».
///
/// Точка уходит при смещении, а не по таймеру: у того, кто стоит на месте,
/// время точки — это когда он пришёл. «Обновлено» тут врало: выглядело как
/// «связь была только что». Про сам телефон партнёра подпись ничего не
/// утверждает.
String hereSince(int updatedAtMs, {required DateTime now}) {
  final at = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final hm = '${_two(at.hour)}:${_two(at.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return ruEn('на месте с $hm', 'here since $hm');
  if (days == 1)
    return ruEn('на месте с $hm вчера', 'here since $hm yesterday');
  final date = '${_two(at.day)}.${_two(at.month)}';
  return ruEn('на месте с $date, $hm', 'here since $date, $hm');
}

/// Подпись под именем партнёра; null — точка свежая, подписывать нечего.
String? partnerPointCaption(int updatedAtMs, {required DateTime now}) {
  final age = LivePointAge.of(updatedAtMs, nowMs: now.millisecondsSinceEpoch);
  if (!age.needsCaption) return null;
  return hereSince(updatedAtMs, now: now);
}

/// Расстояние между людьми. «Рядом» и точные метры — только по свежим точкам
/// обоих: иначе «рядом» говорится про место, где партнёр был утром.
/// По устаревшей точке меньше 50 м честно пишем «до 50 м».
String distanceLabel(
  double meters, {
  required bool fresh,
  required String lang,
  required String nearby,
  required String unitM,
  required String unitKm,
}) {
  if (fresh || meters >= 50) {
    return formatMapDistance(
      meters,
      lang: lang,
      nearby: nearby,
      unitM: unitM,
      unitKm: unitKm,
    );
  }
  return ruEn('до 50 $unitM', 'under 50 $unitM');
}

/// Ожидание партнёра: что именно мы ждём и что с этим делать (G14).
String waitingPartnerHint({required bool iShare}) => iShare
    ? ruEn(
        'Партнёр пока не делится геопозицией. Попросите его открыть '
            '«Где мы» и нажать «Показывать».',
        'Your partner isn’t sharing yet. Ask them to open “Where we are” '
            'and turn sharing on.',
      )
    : ruEn(
        'Включите показ у себя и попросите партнёра сделать то же — '
            'тогда вы увидите друг друга.',
        'Turn sharing on and ask your partner to do the same — then you’ll '
            'see each other.',
      );
