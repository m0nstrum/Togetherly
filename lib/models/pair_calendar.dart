/// Общий календарь пары (BACKLOG D8): всё, что привязано ко времени, — в
/// одной сетке с настроениями.
///
/// Здесь только сбор событий по дням. Календарь сам решает, как их рисовать:
/// точка у воспоминаний, значок у праздника, строки в листе дня.
library;

import 'memory.dart';
import 'wish.dart';
import 'wish_due.dart';

enum PairEventKind {
  /// Воспоминание этого дня.
  memory,

  /// Капсула времени открывается в этот день.
  capsule,

  /// Годовщина отношений (от даты начала).
  anniversary,

  /// Отдельная годовщина, которую пара отметила сама (свадьба, помолвка).
  celebration,

  /// Первый поцелуй — ежегодно.
  firstKiss,

  /// День рождения участника.
  birthday,

  /// Срок желания из «Хочу с тобой» (docs/WISHLIST.md).
  wish,
}

class PairEvent {
  const PairEvent(
    this.kind, {
    this.memory,
    this.wish,
    this.uid = '',
    this.years = 0,
  });

  final PairEventKind kind;

  /// Для [PairEventKind.memory] и [PairEventKind.capsule].
  final Memory? memory;

  /// Для [PairEventKind.wish].
  final Wish? wish;

  /// Чей день рождения.
  final String uid;

  /// Сколько лет исполняется (годовщины и дни рождения); 0 — не считаем.
  final int years;

  /// Праздник, а не запись: такие дни календарь отмечает значком.
  bool get special => kind != PairEventKind.memory;
}

/// Ключ дня «гггг-мм-дд» в часах читателя.
String pairDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// События пары по дням за [from]…[to] включительно.
///
/// Ежегодные даты (годовщины, дни рождения) повторяются в каждом году
/// диапазона; 29 февраля в невисокосный год — 28-го.
Map<String, List<PairEvent>> pairCalendarEvents({
  required DateTime from,
  required DateTime to,
  Iterable<Memory> memories = const [],
  DateTime? startDate,
  DateTime? anniversaryDate,
  DateTime? firstKissDate,
  Map<String, DateTime> birthdays = const {},
  Iterable<Wish> wishes = const [],
}) {
  final first = DateTime(from.year, from.month, from.day);
  final last = DateTime(to.year, to.month, to.day);
  final out = <String, List<PairEvent>>{};
  bool inRange(DateTime d) => !d.isBefore(first) && !d.isAfter(last);
  void add(DateTime d, PairEvent e) {
    if (inRange(d)) (out[pairDayKey(d)] ??= []).add(e);
  }

  for (final m in memories) {
    final at = m.createdAt.toLocal();
    add(
      DateTime(at.year, at.month, at.day),
      PairEvent(PairEventKind.memory, memory: m),
    );
    final open = m.openAt?.toLocal();
    if (m.sealed && open != null) {
      add(
        DateTime(open.year, open.month, open.day),
        PairEvent(PairEventKind.capsule, memory: m),
      );
    }
  }

  // Желания со сроком-датой; месяц и «когда-нибудь» в сетку не ложатся.
  for (final w in wishes) {
    if (w.done || w.due.kind != WishDueKind.date) continue;
    add(w.due.anchor!, PairEvent(PairEventKind.wish, wish: w));
  }

  void yearly(DateTime? origin, PairEvent Function(int years) make) {
    if (origin == null) return;
    for (var y = first.year; y <= last.year; y++) {
      final years = y - origin.year;
      if (years < 1) continue;
      final lastDay = DateTime(y, origin.month + 1, 0).day;
      add(
        DateTime(y, origin.month, origin.day > lastDay ? lastDay : origin.day),
        make(years),
      );
    }
  }

  yearly(startDate, (n) => PairEvent(PairEventKind.anniversary, years: n));
  final ownAnniversary = anniversaryDate;
  final sameAsStart =
      ownAnniversary != null &&
      startDate != null &&
      ownAnniversary.month == startDate.month &&
      ownAnniversary.day == startDate.day;
  if (!sameAsStart) {
    yearly(
      ownAnniversary,
      (n) => PairEvent(PairEventKind.celebration, years: n),
    );
  }
  yearly(firstKissDate, (n) => PairEvent(PairEventKind.firstKiss, years: n));
  birthdays.forEach((uid, date) {
    yearly(date, (n) => PairEvent(PairEventKind.birthday, uid: uid, years: n));
  });
  // Праздники выше записей: лист дня начинает с них.
  for (final list in out.values) {
    list.sort((a, b) => (a.special ? 0 : 1).compareTo(b.special ? 0 : 1));
  }
  return out;
}
