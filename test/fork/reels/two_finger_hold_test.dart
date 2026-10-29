// fork (D10): «чистый экран» в лентах вдвоём (lib/fork/reels/two_finger_hold.dart).
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/reels/two_finger_hold.dart';

void main() {
  group('ForkTwoFingerHold', () {
    late List<bool> calls;
    late int taps;
    late int drags;

    // Лента в миниатюре: под удержанием — «ролик» со своими жестами, поверх —
    // интерфейс, который прячется, пока держат два пальца.
    Future<void> pump(WidgetTester tester) async {
      calls = [];
      taps = 0;
      drags = 0;
      var hidden = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Stack(
              children: [
                Positioned.fill(
                  child: ForkTwoFingerHold(
                    onHold: (on) {
                      calls.add(on);
                      setState(() => hidden = on);
                    },
                    child: GestureDetector(
                      key: const Key('video'),
                      onTap: () => taps++,
                      onVerticalDragEnd: (_) => drags++,
                      child: const ColoredBox(color: Colors.black),
                    ),
                  ),
                ),
                if (!hidden)
                  const Positioned(
                    top: 0,
                    left: 0,
                    child: Text('шапка', key: Key('ui')),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('два пальца прячут интерфейс, отпустил — вернулся', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const Key('ui')), findsOneWidget);

      final a = await tester.startGesture(const Offset(200, 300), pointer: 1);
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsOneWidget, reason: 'один палец');

      final b = await tester.startGesture(const Offset(240, 360), pointer: 2);
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsNothing);

      // Пальцы отрываются не разом: интерфейс не мигает.
      await a.up();
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsNothing);

      await b.up();
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsOneWidget);
      expect(calls, [true, false]);
    });

    testWidgets('отменённое касание тоже возвращает интерфейс', (tester) async {
      await pump(tester);
      final a = await tester.startGesture(const Offset(200, 300), pointer: 1);
      final b = await tester.startGesture(const Offset(240, 360), pointer: 2);
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsNothing);
      await a.cancel();
      await b.cancel();
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsOneWidget);
      expect(calls, [true, false]);
    });

    testWidgets('касание и свайп одним пальцем доходят до ролика', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('video')));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.drag(find.byKey(const Key('video')), const Offset(0, -300));
      await tester.pump();
      expect(taps, 1);
      expect(drags, 1);
      expect(calls, isEmpty);
    });

    testWidgets('мышь интерфейс не прячет', (tester) async {
      await pump(tester);
      final a = await tester.startGesture(
        const Offset(200, 300),
        pointer: 1,
        kind: PointerDeviceKind.mouse,
      );
      final b = await tester.startGesture(const Offset(240, 360), pointer: 2);
      await tester.pump();
      expect(find.byKey(const Key('ui')), findsOneWidget);
      await a.up();
      await b.up();
      expect(calls, isEmpty);
    });
  });

  // Интерфейс ленты рисует страница в браузере — приложение только зовёт её.
  test('лента обёрнута удержанием, страница умеет прятать интерфейс', () {
    final screen = File(
      'lib/screens/together/watch_room_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('ForkTwoFingerHold('));
    expect(screen, contains('window.reelsClear && window.reelsClear('));

    const page = 'pocketbase/pb_public/watch/reels';
    final js = File('$page/reels.js').readAsStringSync();
    final css = File('$page/reels.css').readAsStringSync();
    expect(js, contains('window.reelsClear = '));
    expect(js, contains("classList.toggle('is-clear'"));
    expect(css, contains('.rl.is-clear .rl-ui'));
    expect(
      File('$page/index.html').readAsStringSync(),
      contains('reels.js?v=20261029-d10'),
      reason: 'новая версия скрипта, иначе браузер возьмёт старый из кэша',
    );
  });
}
