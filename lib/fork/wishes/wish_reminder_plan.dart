/// Расписание напоминаний вишлиста (docs/WISHLIST.md) — чистый расчёт без
/// платформы: что и когда показать. Ставит их WishReminders.
library;

import 'package:flutter/foundation.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/wish.dart';
import '../../models/wish_due.dart';
import '../../models/wish_reservation.dart';
import '../l10n/count_words.dart';
import 'wish_reminder_prefs.dart';

enum WishReminderKind { due, weekly, gift, reserve }

@immutable
class WishReminder {
  const WishReminder({
    required this.key,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
    this.wishId = '',
  });

  /// Стабильный ключ: по нему id уведомления, повторный расчёт ставит то же.
  final String key;
  final WishReminderKind kind;
  final DateTime at;
  final String title;
  final String body;
  final String wishId;

  /// id уведомления в своём диапазоне — не пересекается с другими службами.
  int get notificationId => 0x2A000000 + (_fnv(key) & 0xFFFFF);

  @override
  String toString() => '$key@$at';
}

int _fnv(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Неделя по ISO: `2026-W43`.
String isoWeekKey(DateTime d) {
  final day = DateTime.utc(d.year, d.month, d.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstDay = DateTime.utc(thursday.year, 1, 1);
  final week = thursday.difference(firstDay).inDays ~/ 7 + 1;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

/// «Желание недели»: одно несбывшееся желание пары, одинаковое у обоих —
/// выбор зависит только от пары, недели и самих желаний. Попросили другое
/// (`skip` = эта неделя) — желание выпадает из выбора до конца недели.
Wish? weeklyWish(Iterable<Wish> all, String groupId, String weekKey) {
  final pool = [
    for (final w in all)
      if (!w.done && w.skip != weekKey) w,
  ]..sort((a, b) => a.id.compareTo(b.id));
  if (pool.isEmpty) return null;
  return pool[_fnv('$groupId|$weekKey') % pool.length];
}

/// Повод для подсказки о подарке.
@immutable
class GiftOccasion {
  const GiftOccasion(this.key, this.date, this.title);
  final String key;
  final DateTime date;
  final String title;
}

String _things(int n) => ruEn(
  '$n ${forkRuCountWord(n, 'вещь', 'вещи', 'вещей')}',
  '$n ${n == 1 ? 'thing' : 'things'}',
);

String _inDays(int n) => n == 0
    ? ruEn('Сегодня', 'Today')
    : n == 1
    ? ruEn('Завтра', 'Tomorrow')
    : ruEn(
        'Через $n ${forkRuCountWord(n, 'день', 'дня', 'дней')}',
        'In $n days',
      );

/// Напоминания на [horizon] вперёд от [now], по времени, не больше [limit]
/// (у iOS потолок — 64 запланированных уведомления на приложение).
List<WishReminder> planWishReminders({
  required DateTime now,
  required WishReminderPrefs prefs,
  required String groupId,
  required String myUid,
  required String partnerUid,
  required String partnerName,
  required Iterable<Wish> wishes,
  Iterable<WishReservation> reservations = const [],
  DateTime? partnerBirthday,
  DateTime? startDate,
  DateTime? anniversaryDate,
  Duration horizon = const Duration(days: 60),
  int limit = 40,
}) {
  final end = now.add(horizon);
  final out = <WishReminder>[];
  void add(WishReminder r) {
    if (r.at.isAfter(now) && !r.at.isAfter(end)) out.add(r);
  }

  final open = [
    for (final w in wishes)
      if (!w.done) w,
  ];
  final byId = {for (final w in open) w.id: w};

  // ── срок «когда» ──
  if (prefs.dueOn) {
    for (final w in open) {
      final anchor = w.due.anchor;
      if (anchor == null) continue;
      final ref = DateTime(
        anchor.year,
        anchor.month,
        anchor.day,
        prefs.dueHour,
        prefs.dueMinute,
      );
      for (final o in prefs.dueOffsets) {
        final at = ref.subtract(o.duration);
        final month = w.due.kind == WishDueKind.month;
        final String title;
        if (o.amount == 0) {
          title = month
              ? ruEn('В этом месяце: ${w.title}', 'This month: ${w.title}')
              : ruEn('Сегодня: ${w.title}', 'Today: ${w.title}');
        } else if (o.hours) {
          title = ruEn(
            'Через ${o.amount} ч: ${w.title}',
            'In ${o.amount} h: ${w.title}',
          );
        } else {
          title = '${_inDays(o.amount)}: ${w.title}';
        }
        add(
          WishReminder(
            key: 'due|${w.id}|${o.encode()}|${w.due.encode()}',
            kind: WishReminderKind.due,
            at: at,
            title: title,
            body: ruEn(
              'Хотели к этому сроку — всё в силе?',
              'You planned it for then — still on?',
            ),
            wishId: w.id,
          ),
        );
      }
    }
  }

  // ── желание недели ──
  if (prefs.weeklyOn && open.isNotEmpty) {
    var day = DateTime(
      now.year,
      now.month,
      now.day,
      prefs.weeklyHour,
      prefs.weeklyMinute,
    );
    while (day.weekday != prefs.weeklyDay || !day.isAfter(now)) {
      day = DateTime(
        day.year,
        day.month,
        day.day + 1,
        prefs.weeklyHour,
        prefs.weeklyMinute,
      );
    }
    // Две недели вперёд: расписание пересчитывается при каждом открытии.
    for (var i = 0; i < 2; i++) {
      final at = DateTime(
        day.year,
        day.month,
        day.day + 7 * i,
        prefs.weeklyHour,
        prefs.weeklyMinute,
      );
      final week = isoWeekKey(at);
      final w = weeklyWish(open, groupId, week);
      if (w == null) break;
      add(
        WishReminder(
          key: 'weekly|$week',
          kind: WishReminderKind.weekly,
          at: at,
          title: ruEn('Желание недели', 'Wish of the week'),
          body: ruEn(
            '«${w.title}» — может, на этих выходных?',
            '“${w.title}” — maybe this weekend?',
          ),
          wishId: w.id,
        ),
      );
    }
  }

  // ── подсказки к датам ──
  final mine = {for (final r in reservations) r.wishId};
  final partnerItems = [
    for (final w in open)
      if (w.isItem && w.authorUid == partnerUid && partnerUid.isNotEmpty) w,
  ];
  final takenByMe = partnerItems.any((w) => mine.contains(w.id));
  if (prefs.giftOn && partnerItems.isNotEmpty) {
    DateTime at(DateTime d) => DateTime(
      d.year,
      d.month,
      d.day - prefs.giftLeadDays,
      prefs.dueHour,
      prefs.dueMinute,
    );
    final who = partnerName.trim();
    // Праздники и даты пары — только пока ни одна вещь не взята: взял —
    // значит, уже готовишь.
    if (!takenByMe) {
      final occasions = <GiftOccasion>[
        ...yearlyOccasions(
          now: now,
          end: end.add(Duration(days: prefs.giftLeadDays)),
          birthday: partnerBirthday,
          startDate: startDate,
          anniversaryDate: anniversaryDate,
          holidays: prefs.giftHolidays,
          partnerName: who,
        ),
      ];
      for (final o in occasions) {
        add(
          WishReminder(
            key: 'gift|${o.key}',
            kind: WishReminderKind.gift,
            at: at(o.date),
            title: '${_inDays(prefs.giftLeadDays)} — ${o.title}',
            body: who.isEmpty
                ? ruEn(
                    'В вишлисте ${_things(partnerItems.length)} — вы пока '
                        'ни одну не взяли',
                    'The wishlist has '
                        '${_things(partnerItems.length)} — you haven’t taken any yet',
                  )
                : ruEn(
                    'У $who в вишлисте ${_things(partnerItems.length)} — '
                        'вы пока ни одну не взяли',
                    '$who’s wishlist has '
                        '${_things(partnerItems.length)} — you haven’t taken any yet',
                  ),
          ),
        );
      }
    }
    // Вещь партнёра со сроком: «хочется к 14 ноября — подарить?»
    for (final w in partnerItems) {
      final anchor = w.due.anchor;
      if (anchor == null || mine.contains(w.id)) continue;
      add(
        WishReminder(
          key: 'gift|item|${w.id}|${w.due.encode()}',
          kind: WishReminderKind.gift,
          at: at(anchor),
          title:
              '${_inDays(prefs.giftLeadDays)} — ${ruEn('срок', 'due')}: '
              '${w.title}',
          body: ruEn(
            'Подарить? Партнёр не узнает, пока не подарите',
            'Gift it? Your partner won’t know until you do',
          ),
          wishId: w.id,
        ),
      );
    }
  }

  // ── срок «Дарю» ──
  if (prefs.reserveOn) {
    for (final r in reservations) {
      final u = r.until;
      final w = byId[r.wishId];
      if (u == null || w == null) continue;
      for (final before in const [1, 0]) {
        add(
          WishReminder(
            key: 'reserve|${r.id}|${r.until!.toIso8601String()}|$before',
            kind: WishReminderKind.reserve,
            at: DateTime(
              u.year,
              u.month,
              u.day - before,
              prefs.dueHour,
              prefs.dueMinute,
            ),
            title: before == 1
                ? ruEn('Завтра срок подарка', 'Gift due tomorrow')
                : ruEn('Сегодня срок подарка', 'Gift due today'),
            body: ruEn(
              'Вы обещали подарить «${w.title}»',
              'You promised to gift “${w.title}”',
            ),
            wishId: w.id,
          ),
        );
      }
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

/// Ежегодные поводы для подарка в окне [now]…[end]: день рождения
/// партнёра, годовщины, а с [holidays] — 14 февраля и 8 марта.
List<GiftOccasion> yearlyOccasions({
  required DateTime now,
  required DateTime end,
  DateTime? birthday,
  DateTime? startDate,
  DateTime? anniversaryDate,
  bool holidays = true,
  String partnerName = '',
}) {
  final out = <GiftOccasion>[];
  final seen = <String>{};
  void yearly(String key, DateTime? origin, String title) {
    if (origin == null) return;
    for (var y = now.year; y <= end.year; y++) {
      final last = DateTime(y, origin.month + 1, 0).day;
      final d = DateTime(
        y,
        origin.month,
        origin.day > last ? last : origin.day,
      );
      final dedupe = '${d.month}-${d.day}-$key';
      if (d.isBefore(DateTime(now.year, now.month, now.day)) ||
          d.isAfter(end) ||
          !seen.add(dedupe)) {
        continue;
      }
      out.add(GiftOccasion('$key|$y', d, title));
    }
  }

  final who = partnerName.trim();
  yearly(
    'birthday',
    birthday,
    who.isEmpty
        ? ruEn('день рождения партнёра', 'partner’s birthday')
        : ruEn('день рождения: $who', '$who’s birthday'),
  );
  yearly('together', startDate, ruEn('годовщина', 'anniversary'));
  final sameAsStart =
      anniversaryDate != null &&
      startDate != null &&
      anniversaryDate.month == startDate.month &&
      anniversaryDate.day == startDate.day;
  if (!sameAsStart) {
    yearly('anniversary', anniversaryDate, ruEn('годовщина', 'anniversary'));
  }
  if (holidays) {
    yearly(
      'feb14',
      DateTime(2000, 2, 14),
      ruEn('День святого Валентина', 'Valentine’s Day'),
    );
    yearly(
      'mar8',
      DateTime(2000, 3, 8),
      ruEn('8 Марта', 'International Women’s Day'),
    );
  }
  return out;
}
