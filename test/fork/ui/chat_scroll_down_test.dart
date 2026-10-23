import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ui/chat_scroll_down.dart';
import 'package:love_app/models/chat_msg.dart';

void main() {
  ChatMsg msg(int n, {String uid = 'other', bool deleted = false}) => ChatMsg(
    id: '$n',
    uid: uid,
    name: uid,
    text: 'message',
    ts: n,
    deleted: deleted,
  );

  test(
    'new count ignores pagination/own/edits, survives a rolling window, clears at bottom',
    () {
      final tracker = ForkChatBelowTracker();
      expect(tracker.update([], myUid: 'me', atBottom: false), 0);
      expect(tracker.update([msg(10)], myUid: 'me', atBottom: false), 0);
      expect(
        tracker.update(
          [msg(1), msg(10), msg(11), msg(12, uid: 'me')],
          myUid: 'me',
          atBottom: false,
        ),
        1,
      );
      expect(tracker.update([msg(11)], myUid: 'me', atBottom: false), 1);
      for (var i = 13; i <= 112; i++) {
        tracker.update([msg(i)], myUid: 'me', atBottom: false);
      }
      expect(tracker.count, 101);
      expect(
        tracker.update([msg(11, deleted: true)], myUid: 'me', atBottom: false),
        100,
      );
      expect(tracker.update([msg(112)], myUid: 'me', atBottom: true), 0);
      expect(
        tracker.update([msg(1), msg(112)], myUid: 'me', atBottom: false),
        0,
      );
    },
  );

  testWidgets('down action has an accessible exact count and a compact badge', (
    t,
  ) async {
    var taps = 0;
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForkChatScrollDown(
            count: 120,
            onTap: () => taps++,
            surface: Colors.white,
            ink: Colors.black,
          ),
        ),
      ),
    );
    final label = find.bySemanticsLabel(RegExp('120'));
    final node = t.getSemantics(label);
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(find.text('99+'), findsOneWidget);
    await t.tap(find.byType(IconButton));
    expect(taps, 1);
    semantics.dispose();
  });
}
