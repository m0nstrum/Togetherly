import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/queue_item.dart';
import 'package:love_app/fork/watch/room_live.dart';
import 'package:love_app/fork/watch/room_queue.dart';
import 'package:love_app/fork/watch/room_shell.dart';

const id = 'aliceaaaaaaaaaa:0000000000000001';
void main() {
  test(
    'page queue metadata is bounded and rejects unsafe URLs or identifiers',
    () {
      final live = ForkRoomLive(partnerName: () => 'Bob');
      live.handle({
        't': 'queue',
        'items': [
          {'id': id, 'url': 'https://youtube.com/watch?v=abcdefghijk'},
          {'id': id, 'url': 'javascript:alert(1)'},
          {'id': '<svg>', 'url': 'https://example.test/video.mp4'},
        ],
      });
      expect(live.queue, hasLength(1));
      expect(live.queue.single.id, id);
      expect(ForkQueuedVideo.parse(null), isNull);
      live.dispose();
    },
  );

  testWidgets(
    'queue actions and current video stay accessible with large text',
    (tester) async {
      final live = ForkRoomLive(partnerName: () => 'Bob');
      live.handle({
        't': 'source',
        'kind': 'youtube',
        'label': 'YouTube',
        'url': 'https://youtube.com/watch?v=abcdefghijk',
      });
      live.handle({
        't': 'queue',
        'items': [
          {'id': id, 'url': 'https://example.test/long-video-name.mp4'},
        ],
      });
      var added = 0, next = 0;
      String? played, removed;
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: ForkRoomQueueScreen(
              live: live,
              onAdd: () => added++,
              onNext: () => next++,
              onPlay: (id) => played = id,
              onRemove: (id) => removed = id,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FilledButton));
        await tester.tap(find.byType(OutlinedButton));
        final item = find.byType(ListTile);
        await tester.scrollUntilVisible(item, 200);
        final remove = find.byType(IconButton);
        await tester.ensureVisible(remove);
        await tester.pumpAndSettle();
        await tester.tap(item);
        await tester.pump();
        await tester.tap(remove);
        expect([added, next], [1, 1]);
        expect(played, id);
        expect(removed, id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        live.dispose();
      }
    },
  );

  testWidgets('empty now-playing panel exposes its queue on a narrow screen', (
    tester,
  ) async {
    final live = ForkRoomLive(partnerName: () => 'Bob');
    var opened = false;
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    try {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ForkNowPlaying(
              live: live,
              onPick: () {},
              onToggle: () {},
              onTogether: () {},
              onPauseBoth: () {},
              onFullscreen: () {},
              onQueue: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextButton));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      live.dispose();
    }
  });
}
