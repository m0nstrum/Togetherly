import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/models/wish_comment.dart';
import 'package:love_app/models/wish_order.dart';
import 'package:love_app/widgets/wishes/wish_comments_sheet.dart';

/// Общий порядок карточек и комментарии к желаниям (docs/WISHLIST.md).
void main() {
  Wish w(String id, [double? pos]) => Wish(
    id: id,
    title: id,
    authorUid: 'a',
    pos: pos,
    createdAt: DateTime(2026),
  );

  List<String> apply(List<Wish> list, Map<String, double> changed) {
    final next = [
      for (final x in list)
        changed.containsKey(x.id) ? x.copyWith(pos: changed[x.id]) : x,
    ];
    return Wish.dreaming(next).map((x) => x.id).toList();
  }

  group('порядок', () {
    test('между соседями — одна запись в середину', () {
      final list = [w('a', 1), w('b', 2), w('c', 3)];
      final changed = wishReorder(list, 2, 1);
      expect(changed, {'c': 1.5});
      expect(apply(list, changed), ['a', 'c', 'b']);
    });

    test('в начало и в конец — шаг от крайнего', () {
      final list = [w('a', 1), w('b', 2), w('c', 3)];
      expect(apply(list, wishReorder(list, 2, 0)), ['c', 'a', 'b']);
      expect(apply(list, wishReorder(list, 0, 2)), ['b', 'c', 'a']);
      expect(wishReorder(list, 0, 2).length, 1);
    });

    test('без мест — нумерует весь список', () {
      final list = [w('a'), w('b'), w('c', 5)];
      final changed = wishReorder(list, 0, 2);
      expect(apply(list, changed), ['b', 'c', 'a']);
      expect(changed.keys.toSet(), {'a', 'b', 'c'});
    });

    test('зазор кончился — нумерует заново', () {
      final list = [w('a', 1), w('b', 1 + 1e-9), w('c', 3)];
      final changed = wishReorder(list, 2, 1);
      expect(apply(list, changed), ['a', 'c', 'b']);
      expect(changed.length, greaterThan(1));
    });

    test('на то же место — ничего', () {
      expect(wishReorder([w('a', 1), w('b', 2)], 1, 1), isEmpty);
    });
  });

  test('счётчики комментариев', () {
    WishComment c(String id, String wish) => WishComment(
      id: id,
      wishId: wish,
      authorUid: 'a',
      text: 't',
      createdAt: DateTime(2026),
    );
    expect(
      wishCommentCounts([c('1', 'x'), c('2', 'x'), c('3', 'y'), c('4', '')]),
      {'x': 2, 'y': 1},
    );
    final back = WishComment.fromMap(c('1', 'x').toMap(groupId: 'g'));
    expect(back.wishId, 'x');
    expect(back.text, 't');
  });

  testWidgets('лист комментариев: свои удаляются, чужие нет', (tester) async {
    final ctrl = StreamController<List<WishComment>>.broadcast();
    final sent = <String>[];
    final deleted = <String>[];
    final wish = w('x');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WishCommentsSheet(
            wish: wish,
            myUid: 'me',
            comments: ctrl.stream,
            nameOf: (uid) => uid == 'p' ? 'Аня' : '',
            onSend: (t) async => sent.add(t),
            onDelete: (c) async => deleted.add(c.id),
          ),
        ),
      ),
    );
    ctrl.add([
      WishComment(
        id: 'c1',
        wishId: 'x',
        authorUid: 'p',
        text: 'в пятницу?',
        createdAt: DateTime(2026, 5, 1, 10),
      ),
      WishComment(
        id: 'c2',
        wishId: 'x',
        authorUid: 'me',
        text: 'да',
        createdAt: DateTime(2026, 5, 1, 11),
      ),
      WishComment(
        id: 'c3',
        wishId: 'other',
        authorUid: 'me',
        text: 'не сюда',
        createdAt: DateTime(2026, 5, 1, 11),
      ),
    ]);
    await tester.pump();
    expect(find.text('в пятницу?'), findsOneWidget);
    expect(find.text('не сюда'), findsNothing);

    await tester.longPress(find.byKey(const Key('wish-comment-c1')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    await tester.longPress(find.byKey(const Key('wish-comment-c2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
    expect(deleted, ['c2']);

    await tester.enterText(
      find.byKey(const Key('wish-comment-field')),
      '  ок  ',
    );
    await tester.tap(find.byKey(const Key('wish-comment-send')));
    await tester.pump();
    expect(sent, ['ок']);
    await ctrl.close();
  });
}
