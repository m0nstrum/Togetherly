import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/pair_calendar.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/models/wish_due.dart';
import 'package:love_app/services/pb_data_service.dart';

/// «Когда», «я тоже хочу» и общий порядок желаний (docs/WISHLIST.md).
void main() {
  Wish wish(
    String id, {
    WishDue due = WishDue.none,
    List<String> also = const [],
    double? pos,
    bool done = false,
    DateTime? createdAt,
  }) =>
      Wish(
        id: id,
        title: 'Желание $id',
        authorUid: 'a',
        due: due,
        also: also,
        pos: pos,
        done: done,
        createdAt: createdAt ?? DateTime(2026, 1, 1),
      );

  group('WishDue', () {
    test('строка туда и обратно', () {
      for (final d in [
        WishDue.none,
        WishDue.someday,
        WishDue.date(DateTime(2026, 11, 4)),
        WishDue.month(2027, 3),
      ]) {
        expect(WishDue.parse(d.encode()), d);
      }
      expect(WishDue.date(DateTime(2026, 11, 4)).encode(), '2026-11-04');
      expect(WishDue.month(2027, 3).encode(), '2027-03');
    });

    test('мусор и несуществующие даты — «без срока»', () {
      for (final raw in ['завтра', '2026-02-30', '2026-13', '26-1-1', null]) {
        expect(WishDue.parse(raw), WishDue.none, reason: '$raw');
      }
    });

    test('месяц прошёл только когда кончился', () {
      final now = DateTime(2026, 11, 30, 23);
      expect(WishDue.month(2026, 11).isPast(now), isFalse);
      expect(WishDue.month(2026, 10).isPast(now), isTrue);
      expect(WishDue.date(DateTime(2026, 11, 30)).isPast(now), isFalse);
      expect(WishDue.date(DateTime(2026, 11, 29)).isPast(now), isTrue);
      expect(WishDue.someday.isPast(now), isFalse);
    });

    test('подпись: год только у не-текущего', () {
      final gen = List.generate(12, (i) => 'г$i');
      final nom = List.generate(12, (i) => 'и$i');
      String label(WishDue d) => d.label(
            genitive: gen,
            nominative: nom,
            somedayLabel: 'когда-нибудь',
            now: DateTime(2026, 6, 1),
          );
      expect(label(WishDue.date(DateTime(2026, 11, 4))), '4 г10');
      expect(label(WishDue.date(DateTime(2027, 1, 2))), '2 г0 2027');
      expect(label(WishDue.month(2026, 3)), 'и2');
      expect(label(WishDue.month(2028, 3)), 'и2 2028');
      expect(label(WishDue.someday), 'когда-нибудь');
      expect(label(WishDue.none), '');
    });
  });

  group('Wish', () {
    test('срок, «я тоже» и порядок переживают запись', () {
      final w = wish('1',
          due: WishDue.month(2027, 5), also: const ['b'], pos: 1.5);
      final back = Wish.fromMap(w.toMap(groupId: 'g'));
      expect(back.due, WishDue.month(2027, 5));
      expect(back.also, ['b']);
      expect(back.pos, 1.5);
      expect(back.wantedByBoth, isTrue);
      expect(wish('2').wantedByBoth, isFalse);
      expect(wish('3', also: const ['a']).wantedByBoth, isFalse);
    });

    test('отмена отметки не теряет срок и «я тоже»', () {
      final w = wish('1', due: WishDue.someday, also: const ['b'], pos: 3)
          .markDone(by: 'b')
          .undone();
      expect(w.due, WishDue.someday);
      expect(w.also, ['b']);
      expect(w.pos, 3);
    });

    test('мечты: сначала без места (новые сверху), потом по порядку', () {
      final list = Wish.dreaming([
        wish('p2', pos: 2),
        wish('old', createdAt: DateTime(2026, 1, 1)),
        wish('p1', pos: 1),
        wish('new', createdAt: DateTime(2026, 2, 1)),
        wish('done', pos: 0, done: true),
      ]);
      expect(list.map((w) => w.id), ['new', 'old', 'p1', 'p2']);
    });
  });

  group('тела запросов', () {
    test('автор шлёт срок, «я тоже» и порядок; пустой срок стирает', () {
      final body = PbDataService.wishUpsertBody(
          'g', wish('1', due: WishDue.someday, pos: 2).toMap(groupId: 'g'));
      expect(body['due'], 'someday');
      expect(body['pos'], '2');
      expect(body['also'], '');
      final cleared = PbDataService.wishUpsertBody(
          'g', wish('1').toMap(groupId: 'g'));
      expect(cleared['due'], '');
    });

    test('партнёр шлёт только поменянные общие поля', () {
      expect(PbDataService.wishMarkBody({'also': 'b'}), {'also': 'b'});
      expect(PbDataService.wishMarkBody({'pos': '3'}), {'pos': '3'});
      // Задание прежней сборки: все поля отметки.
      expect(
        PbDataService.wishMarkBody({
          'done': true,
          'done_at': null,
          'done_by': 'b',
          'done_note': '',
        }).keys,
        unorderedEquals(['done', 'done_at', 'done_by', 'done_note']),
      );
    });
  });

  test('календарь: только несбывшиеся желания с датой', () {
    final events = pairCalendarEvents(
      from: DateTime(2026, 11, 1),
      to: DateTime(2026, 11, 30),
      wishes: [
        wish('d', due: WishDue.date(DateTime(2026, 11, 14))),
        wish('m', due: WishDue.month(2026, 11)),
        wish('s', due: WishDue.someday),
        wish('x', due: WishDue.date(DateTime(2026, 11, 14)), done: true),
        wish('far', due: WishDue.date(DateTime(2027, 11, 14))),
      ],
    );
    expect(events.keys, ['2026-11-14']);
    final e = events['2026-11-14']!.single;
    expect(e.kind, PairEventKind.wish);
    expect(e.wish!.id, 'd');
    expect(e.special, isTrue);
  });
}
