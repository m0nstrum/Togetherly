import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/picture_in_picture.dart';

class Remembered extends StatefulWidget {
  const Remembered(this.started, {super.key});
  final VoidCallback started;
  @override
  State<Remembered> createState() => _RememberedState();
}

class _RememberedState extends State<Remembered> {
  @override
  void initState() {
    super.initState();
    widget.started();
  }

  @override
  Widget build(BuildContext context) => const Text('private chrome');
}

void main() {
  test(
    'video-only frame is prepared before native entry; concurrent requests do not cancel it',
    () async {
      final ready = Completer<void>();
      var calls = 0;
      final pip = ForkPictureInPicture(
        available: () async => true,
        prepare: () => ready.future,
        activate: () async {
          calls++;
          return true;
        },
      );
      final owner = Object();
      final entering = pip.enter(owner);
      await Future<void>.delayed(Duration.zero);
      expect(pip.videoOnly, isTrue);
      expect(calls, 0);
      expect(await pip.enter(owner), ForkPipOutcome.failed);
      expect(pip.preparing, isTrue);
      ready.complete();
      expect(await entering, ForkPipOutcome.entered);
      expect(calls, 1);
      expect(pip.active, isTrue);
      pip.modeChanged(false);
      expect(pip.videoOnly, isFalse);
      pip.dispose();
    },
  );

  test('unsupported device never prepares or enters', () async {
    final pip = ForkPictureInPicture(
      available: () async => false,
      prepare: () async => fail('must not prepare'),
      activate: () async {
        fail('must not activate');
      },
    );
    expect(await pip.enter(Object()), ForkPipOutcome.unsupported);
    expect(pip.videoOnly, isFalse);
    expect(pip.owner, isNull);
    pip.dispose();
  });

  for (final throwing in [false, true]) {
    test(
      'native ${throwing ? 'exception' : 'refusal'} restores the regular layout',
      () async {
        final pip = ForkPictureInPicture(
          available: () async => true,
          prepare: () async {},
          activate: () async {
            if (throwing) throw StateError('OS unavailable');
            return false;
          },
        );
        expect(await pip.enter(Object()), ForkPipOutcome.failed);
        expect(pip.videoOnly, isFalse);
        expect(pip.busy, isFalse);
        pip.dispose();
      },
    );
  }

  test('a newer OS callback wins over an earlier native reply', () async {
    final ack = Completer<bool>();
    final pip = ForkPictureInPicture(
      available: () async => true,
      prepare: () async {},
      activate: () => ack.future,
    );
    final entering = pip.enter(Object());
    await Future<void>.delayed(Duration.zero);
    pip.modeChanged(true);
    pip.modeChanged(false);
    ack.complete(true);
    expect(await entering, ForkPipOutcome.entered);
    expect(pip.active, isFalse);
    pip.dispose();
  });

  test(
    'route removed during preparation cannot put a different screen in PiP',
    () async {
      final ready = Completer<void>();
      var calls = 0;
      final owner = Object();
      final pip = ForkPictureInPicture(
        available: () async => true,
        prepare: () => ready.future,
        activate: () async {
          calls++;
          return true;
        },
      );
      final entering = pip.enter(owner);
      await Future<void>.delayed(Duration.zero);
      pip.release(owner);
      ready.complete();
      expect(await entering, ForkPipOutcome.failed);
      expect(calls, 0);
      expect(pip.videoOnly, isFalse);
      pip.dispose();
    },
  );

  test(
    'closing is distinct from expanding and belongs to the current room',
    () async {
      final owner = Object();
      final pip = ForkPictureInPicture(
        available: () async => true,
        prepare: () async {},
        activate: () async => true,
      );
      await pip.enter(owner);
      pip.release(Object());
      expect(pip.ownedBy(owner), isTrue);
      pip.modeChanged(false);
      expect(pip.closedSequence, 0);
      await pip.enter(owner);
      pip.closed();
      expect(pip.active, isFalse);
      expect(pip.closedSequence, 1);
      expect(pip.ownedBy(owner), isTrue);
      pip.release(owner);
      expect(pip.owner, isNull);
      pip.dispose();
    },
  );

  testWidgets('global chrome is hidden without destroying state', (
    tester,
  ) async {
    var starts = 0;
    final pip = ForkPictureInPicture(
      available: () async => true,
      prepare: () async {},
      activate: () async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForkPipHideChrome(
            controller: pip,
            child: Remembered(() => starts++),
          ),
        ),
      ),
    );
    expect(find.text('private chrome'), findsOneWidget);
    await pip.enter(Object());
    await tester.pump();
    expect(find.text('private chrome'), findsNothing);
    pip.modeChanged(false);
    await tester.pump();
    expect(find.text('private chrome'), findsOneWidget);
    expect(starts, 1);
    await tester.pumpWidget(const SizedBox());
    pip.dispose();
  });

  testWidgets('orphaned OS window stays opaque until Android exits PiP', (
    tester,
  ) async {
    final owner = Object();
    final pip = ForkPictureInPicture(
      available: () async => true,
      prepare: () async {},
      activate: () async => true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ForkPipOrphanGuard(
          controller: pip,
          child: const Text('private route'),
        ),
      ),
    );
    await pip.enter(owner);
    pip.release(owner);
    await tester.pump();
    expect(pip.active, isTrue);
    expect(find.text('private route'), findsNothing);
    pip.modeChanged(false);
    await tester.pump();
    expect(find.text('private route'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pip.dispose();
  });
  test(
    'a different route taking focus during frame preparation cancels native entry',
    () async {
      final ready = Completer<void>();
      var current = true, entered = false;
      final pip = ForkPictureInPicture(
        available: () async => true,
        prepare: () => ready.future,
        activate: () async {
          entered = true;
          return true;
        },
      );
      final pending = pip.enter(Object(), canEnter: () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      ready.complete();
      expect(await pending, ForkPipOutcome.failed);
      expect(entered, isFalse);
      expect(pip.videoOnly, isFalse);
      pip.dispose();
    },
  );
}
