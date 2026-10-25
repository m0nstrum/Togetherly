import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/wishes/wish_reminder_plan.dart';
import 'package:love_app/fork/wishes/wish_reminder_prefs.dart';
import 'package:love_app/fork/wishes/wish_reminder_settings.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/models/wish_due.dart';
import 'package:love_app/models/wish_reservation.dart';

/// Напоминания вишлиста (docs/WISHLIST.md).
void main() {
  final now = DateTime(2026, 10, 25, 12); // воскресенье

  Wish w(
    String id, {
    String author = 'me',
    WishDue due = WishDue.none,
    bool item = false,
    bool done = false,
    String skip = '',
  }) => Wish(
    id: id,
    title: 'Ж$id',
    authorUid: author,
    due: due,
    isItem: item,
    done: done,
    skip: skip,
    createdAt: DateTime(2026),
  );

  List<WishReminder> plan(
    Iterable<Wish> wishes, {
    WishReminderPrefs prefs = const WishReminderPrefs(),
    List<WishReservation> reservations = const [],
    DateTime? birthday,
  }) => planWishReminders(
    now: now,
    prefs: prefs,
    groupId: 'g',
    myUid: 'me',
    partnerUid: 'p',
    partnerName: 'Аня',
    wishes: wishes,
    reservations: reservations,
    partnerBirthday: birthday,
  );

  group('настройки', () {
    test('туда и обратно, мусор — по умолчанию', () {
      const p = WishReminderPrefs(
        dueOffsets: [WishOffset.hours(3), WishOffset.days(7)],
        weeklyDay: 6,
        giftLeadDays: 7,
        placeRadius: 800,
      );
      final back = WishReminderPrefs.fromJson(p.toJson());
      expect(back.dueOffsets, p.dueOffsets);
      expect(back.weeklyDay, 6);
      expect(back.giftLeadDays, 7);
      expect(back.placeRadius, 800);
      final junk = WishReminderPrefs.fromJson({
        'weeklyDay': 9,
        'dueOffsets': ['x', '2d'],
        'giftOn': 'да',
      });
      expect(junk.weeklyDay, DateTime.friday);
      expect(junk.dueOffsets, [const WishOffset.days(2)]);
      expect(junk.giftOn, isTrue);
    });
  });

  group('срок', () {
    test('за день и в день срока, в своё время', () {
      final r = plan([
        w('1', due: WishDue.date(DateTime(2026, 11, 14))),
      ], prefs: const WishReminderPrefs(weeklyOn: false));
      expect(r.map((x) => x.at), [
        DateTime(2026, 11, 13, 10),
        DateTime(2026, 11, 14, 10),
      ]);
      expect(r.every((x) => x.kind == WishReminderKind.due), isTrue);
    });

    test('свои отметки в часах; прошедшее и сбывшееся не ставятся', () {
      final r = plan(
        [
          w('1', due: WishDue.date(DateTime(2026, 10, 26))),
          w('2', due: WishDue.date(DateTime(2026, 10, 20))),
          w('3', due: WishDue.date(DateTime(2026, 11, 1)), done: true),
        ],
        prefs: const WishReminderPrefs(
          weeklyOn: false,
          dueOffsets: [WishOffset.hours(3), WishOffset.days(2)],
        ),
      );
      expect(r.map((x) => x.at), [DateTime(2026, 10, 26, 7)]);
    });

    test('месяц — от первого числа; выключено — ничего', () {
      final r = plan(
        [w('1', due: WishDue.month(2026, 12))],
        prefs: const WishReminderPrefs(
          weeklyOn: false,
          dueOffsets: [WishOffset.days(0)],
        ),
      );
      expect(r.single.at, DateTime(2026, 12, 1, 10));
      expect(
        plan([
          w('1', due: WishDue.month(2026, 12)),
        ], prefs: const WishReminderPrefs(weeklyOn: false, dueOn: false)),
        isEmpty,
      );
    });
  });

  group('желание недели', () {
    test('одно и то же у обоих и не повторяет отложенное', () {
      final list = [w('a'), w('b'), w('c'), w('d', done: true)];
      final week = isoWeekKey(now);
      final pick = weeklyWish(list, 'g', week)!;
      expect(weeklyWish(list.reversed, 'g', week)!.id, pick.id);
      expect(pick.done, isFalse);
      final skipped = [
        for (final x in list) x.id == pick.id ? x.copyWith(skip: week) : x,
      ];
      expect(weeklyWish(skipped, 'g', week)!.id, isNot(pick.id));
      expect(weeklyWish([w('x', done: true)], 'g', week), isNull);
    });

    test('неделя по ISO', () {
      expect(isoWeekKey(DateTime(2026, 1, 1)), '2026-W01');
      expect(isoWeekKey(DateTime(2027, 1, 1)), '2026-W53');
      expect(isoWeekKey(DateTime(2026, 10, 25)), '2026-W43');
    });

    test('в выбранный день и час, две недели вперёд', () {
      final r = plan([w('a'), w('b')]);
      final weekly = r.where((x) => x.kind == WishReminderKind.weekly).toList();
      expect(weekly.map((x) => x.at), [
        DateTime(2026, 10, 30, 18),
        DateTime(2026, 11, 6, 18),
      ]);
    });
  });

  group('подарки', () {
    final items = [
      w('i1', author: 'p', item: true),
      w('i2', author: 'p', item: true),
    ];
    const prefs = WishReminderPrefs(
      weeklyOn: false,
      dueOn: false,
      giftHolidays: false,
      giftLeadDays: 14,
    );

    test('за 14 дней до дня рождения партнёра', () {
      final r = plan(items, prefs: prefs, birthday: DateTime(1998, 12, 1));
      final g = r.single;
      expect(g.kind, WishReminderKind.gift);
      expect(g.at, DateTime(2026, 11, 17, 10));
      expect(g.body, contains('2 '));
    });

    test('уже взял вещь — молчим; своих вещей нет — молчим', () {
      final res = WishReservation(
        id: 'r',
        wishId: 'i1',
        uid: 'me',
        createdAt: DateTime(2026),
      );
      expect(
        plan(
          items,
          prefs: prefs,
          birthday: DateTime(1998, 12, 1),
          reservations: [res],
        ).where((x) => x.key.startsWith('gift|birthday')),
        isEmpty,
      );
      expect(
        plan(
          [w('mine', item: true)],
          prefs: prefs,
          birthday: DateTime(1998, 12, 1),
        ),
        isEmpty,
      );
    });

    test('праздники по желанию; вещь партнёра со сроком', () {
      final r = plan([
        w(
          'i',
          author: 'p',
          item: true,
          due: WishDue.date(DateTime(2026, 12, 20)),
        ),
      ], prefs: prefs.copyWith(giftHolidays: true));
      expect(r.map((x) => x.key), contains(startsWith('gift|item|i|')));
      final hol = yearlyOccasions(
        now: now,
        end: DateTime(2027, 3, 31),
        holidays: true,
      );
      expect(hol.map((o) => o.date), [
        DateTime(2027, 2, 14),
        DateTime(2027, 3, 8),
      ]);
    });
  });

  test('срок «Дарю»: накануне и в день', () {
    final res = WishReservation(
      id: 'r',
      wishId: 'i',
      uid: 'me',
      createdAt: DateTime(2026),
      until: DateTime(2026, 11, 3),
    );
    final r = plan(
      [w('i', author: 'p', item: true)],
      prefs: const WishReminderPrefs(weeklyOn: false, giftOn: false),
      reservations: [res],
    );
    expect(r.map((x) => x.at), [
      DateTime(2026, 11, 2, 10),
      DateTime(2026, 11, 3, 10),
    ]);
    expect(res.overdue(DateTime(2026, 11, 4)), isTrue);
    expect(res.overdue(DateTime(2026, 11, 3, 23)), isFalse);
  });

  test('потолок и стабильные id', () {
    final many = [
      for (var i = 0; i < 40; i++)
        w('$i', due: WishDue.date(DateTime(2026, 11, 1 + i % 28))),
    ];
    final r = plan(many);
    expect(r.length, 40);
    expect(r.map((x) => x.notificationId).toSet().length, 40);
    expect(
      plan(many).map((x) => x.notificationId),
      r.map((x) => x.notificationId),
    );
  });

  testWidgets('экран настроек: выключить и добавить отметку', (tester) async {
    WishReminderPrefs? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: WishReminderSettingsScreen(
          initial: const WishReminderPrefs(),
          onSaved: (p) => saved = p,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('wish-rem-add-offset')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wish-offset-amount')), '5');
    await tester.tap(find.byKey(const Key('wish-offset-ok')));
    await tester.pumpAndSettle();
    expect(saved!.dueOffsets, contains(const WishOffset.days(5)));

    await tester.tap(find.byKey(const Key('wish-rem-due')));
    await tester.pumpAndSettle();
    expect(saved!.dueOn, isFalse);
    expect(find.byKey(const Key('wish-rem-add-offset')), findsNothing);
  });
}
