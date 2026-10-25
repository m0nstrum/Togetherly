import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/wishes/wish_memory.dart';
import 'package:love_app/fork/wishes/wish_wall.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/services/pb_data_service.dart';

/// Сбывшееся: воспоминание и стена (docs/WISHLIST.md).
void main() {
  Wish w(
    String id, {
    DateTime? doneAt,
    String memory = '',
    List<String> also = const [],
  }) => Wish(
    id: id,
    title: 'Ж$id',
    authorUid: 'a',
    done: doneAt != null,
    doneAt: doneAt,
    memoryId: memory,
    also: also,
    createdAt: DateTime(2025),
  );

  Memory m(String id, DateTime at, {String? title}) => Memory(
    id: id,
    groupId: 'g',
    authorUid: 'a',
    authorName: 'A',
    type: MemoryType.values.first,
    createdAt: at,
    title: title,
  );

  test('привязка переживает запись и уходит общим полем', () {
    final back = Wish.fromMap(
      w('1', doneAt: DateTime(2026, 5, 1), memory: 'm1').toMap(groupId: 'g'),
    );
    expect(back.memoryId, 'm1');
    expect(PbDataService.wishMarkBody({'memory': 'm1'}), {'memory': 'm1'});
    expect(
      PbDataService.wishUpsertBody('g', w('2').toMap(groupId: 'g'))['memory'],
      '',
    );
  });

  test('кандидаты: рядом с датой исполнения — первыми', () {
    final wish = w('1', doneAt: DateTime(2026, 5, 10));
    final list = wishMemoryCandidates(wish, [
      m('old', DateTime(2025, 1, 1)),
      m('fresh', DateTime(2026, 9, 1)),
      m('near', DateTime(2026, 5, 12)),
    ]);
    expect(list.map((x) => x.id), ['near', 'fresh', 'old']);
    expect(wishMemoryLabel(m('t', DateTime(2026), title: ' Каток ')), 'Каток');
  });

  test('счётчики стены', () {
    final now = DateTime(2026, 10, 25);
    final s = WishWallStats.of([
      w('1', doneAt: DateTime(2026, 1, 1), memory: 'm', also: const ['b']),
      w('2', doneAt: DateTime(2025, 6, 1)),
      w('3'),
    ], now);
    expect(s.total, 2);
    expect(s.thisYear, 1);
    expect(s.together, 1);
    expect(s.withMemory, 1);
  });

  testWidgets('стена: плитки и тап', (tester) async {
    Wish? opened;
    final list = Wish.fulfilled([
      w('1', doneAt: DateTime(2026, 1, 1), memory: 'm'),
      w('2', doneAt: DateTime(2026, 2, 1)),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: WishWallScreen(fulfilled: list, onOpen: (x) => opened = x),
      ),
    );
    expect(find.byKey(const Key('wish-wall-1')), findsOneWidget);
    expect(find.byKey(const Key('wish-wall-2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('wish-wall-2')));
    expect(opened?.id, '2');
  });
}
