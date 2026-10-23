import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:love_app/fork/touch/touch_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/e2e/room_chat.dart';
import 'package:love_app/fork/touch/touch_session.dart';

class Keys implements E2EKeyring {
  Keys(this.key);
  final PairKey? key;
  @override
  PairKey? currentKey(String groupId) => groupId == 'group' ? key : null;
  @override
  PairKey? keyFor(String id) => key?.keyId == id ? key : null;
  @override
  String? groupWith(Set<String> members) => null;
}

class Bus {
  final wire = <Map<String, dynamic>>[];
  final listeners = <void Function(Map<String, dynamic>)>[];
  bool failing = false;
  void deliver(Map<String, dynamic> packet) {
    for (final listener in List.of(listeners))
      scheduleMicrotask(() => listener(packet));
  }
}

class Transport implements RoomTransport {
  Transport(this.bus);
  final Bus bus;
  @override
  Future<void> send(Map<String, dynamic> msg) async {
    if (bus.failing) throw StateError('offline');
    bus.wire.add(msg);
    bus.deliver(msg);
  }

  @override
  Future<Future<void> Function()> listen(
    void Function(Map<String, dynamic>) onMessage,
  ) async {
    bus.listeners.add(onMessage);
    return () async {
      bus.listeners.remove(onMessage);
    };
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late E2ECrypto crypto;
  setUpAll(() async => crypto = await E2ECrypto.init());
  late RecordCodec codec;
  late Bus bus;
  late ForkTouchSession alice, bob;
  late DateTime time;
  late bool allowed;
  late int aBuzz, bBuzz;
  setUp(() async {
    codec = RecordCodec(
      crypto,
      Keys(PairKey('group', 1, crypto.symmetricKey())),
    );
    bus = Bus();
    time = DateTime.utc(2026, 10, 23);
    allowed = true;
    aBuzz = bBuzz = 0;
    alice = ForkTouchSession(
      group: 'group',
      me: 'alice',
      partner: 'bob',
      codec: codec,
      transport: Transport(bus),
      allowed: () => allowed,
      now: () => time,
      vibrate: () async {
        aBuzz++;
      },
    );
    bob = ForkTouchSession(
      group: 'group',
      me: 'bob',
      partner: 'alice',
      codec: codec,
      transport: Transport(bus),
      allowed: () => allowed,
      now: () => time,
      vibrate: () async {
        bBuzz++;
      },
    );
    await alice.start();
    await bob.start();
  });
  tearDown(() {
    alice.dispose();
    bob.dispose();
  });

  test('two fingers meet through ciphertext and each vibrates once', () async {
    alice.point(const Offset(.5, .5));
    bob.point(const Offset(.52, .5));
    await settle();
    expect(alice.matched, isTrue);
    expect(bob.matched, isTrue);
    expect([aBuzz, bBuzz], [1, 1]);
    final text = jsonEncode(bus.wire);
    expect(text, isNot(contains('"x"')));
    expect(text, isNot(contains('"down"')));
    time = time.add(const Duration(milliseconds: 500));
    alice.tick();
    bob.tick();
    await settle();
    expect([aBuzz, bBuzz], [1, 1]);
    bob.point(null);
    await settle();
    expect(alice.peer, isNull);
    expect(alice.matched, isFalse);
  });

  test('distant points do not vibrate, lost release expires', () async {
    alice.point(const Offset(.1, .1));
    bob.point(const Offset(.9, .9));
    await settle();
    expect([aBuzz, bBuzz], [0, 0]);
    time = time.add(const Duration(seconds: 3));
    alice.tick();
    expect(alice.peer, isNull);
    expect(alice.matched, isFalse);
  });

  test(
    'replays, tampered routing and malformed coordinates are rejected',
    () async {
      bob.point(const Offset(.2, .3));
      await settle();
      final original = Map<String, dynamic>.from(bus.wire.last);
      bob.point(null);
      await settle();
      expect(alice.peer, isNull);
      bus.deliver(original);
      await settle();
      expect(alice.peer, isNull);
      bus.deliver({...original, 'at': time.millisecondsSinceEpoch + 10});
      bus.deliver({...original, 'from': 'outsider'});
      await settle();
      expect(alice.peer, isNull);
      final at = time.millisecondsSinceEpoch + 20;
      alice.receive({
        't': 'fork-touch',
        'from': 'bob',
        'at': at,
        'e2e': codec.sealChannel(
          ChannelPlace('pair:group', 'fork-touch:bob', at),
          {'down': true, 'x': 2, 'y': .5},
          codec.keys.currentKey('group')!,
        ),
      });
      expect(alice.peer, isNull);
      alice.receive({...original, 'at': time.millisecondsSinceEpoch + 5000});
      expect(alice.peer, isNull);
    },
  );

  test(
    'pair or account revocation clears both points and stops sending',
    () async {
      alice.point(const Offset(.5, .5));
      bob.point(const Offset(.5, .5));
      await settle();
      allowed = false;
      alice.tick();
      bob.tick();
      final count = bus.wire.length;
      alice.point(const Offset(.5, .5));
      await settle();
      expect(alice.mine, isNull);
      expect(alice.peer, isNull);
      expect(alice.matched, isFalse);
      expect(bus.wire.length, count);
    },
  );

  test(
    'failed publish is visible; a held finger renews after recovery',
    () async {
      bus.failing = true;
      alice.point(const Offset(.5, .5));
      await settle();
      expect(alice.failed, isTrue);
      expect(bus.wire, isEmpty);
      bus.failing = false;
      time = time.add(const Duration(seconds: 1));
      alice.tick();
      await settle();
      expect(alice.failed, isFalse);
      expect(bob.peer, const Offset(.5, .5));
    },
  );

  test('suspending sends a release and clears local state', () async {
    alice.point(const Offset(.5, .5));
    await settle();
    alice.suspend();
    await settle();
    expect(alice.mine, isNull);
    expect(bob.peer, isNull);
  });

  testWidgets(
    'dragging touch surface moves a finger without scrolling; background releases it',
    (tester) async {
      final app = ForkTouchSession(
        group: 'group',
        me: 'alice',
        partner: 'bob',
        codec: codec,
        transport: Transport(bus),
        allowed: () => true,
        now: () => time,
        vibrate: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ForkTouchScreen(
            groupId: 'group',
            myUid: 'alice',
            partnerUid: 'bob',
            session: app,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final listener = find.byWidgetPredicate(
        (widget) =>
            widget is Listener &&
            widget.onPointerDown != null &&
            widget.onPointerMove != null &&
            widget.onPointerCancel != null,
      );
      expect(listener, findsOneWidget);
      final origin = tester.getTopLeft(listener);
      final gesture = await tester.startGesture(tester.getCenter(listener));
      await tester.pump();
      expect(app.mine, isNotNull);
      await gesture.moveBy(const Offset(0, -50));
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.getTopLeft(listener), origin);
      expect(app.mine!.dy, lessThan(.5));
      await gesture.up();
      await tester.pump();
      expect(app.mine, isNull);
      app.point(const Offset(.4, .4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(app.mine, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test('missing key never sends a plaintext fallback', () async {
    final app = ForkTouchSession(
      group: 'other',
      me: 'alice',
      partner: 'bob',
      codec: codec,
      transport: Transport(bus),
      allowed: () => true,
      vibrate: () async {},
    );
    await app.start();
    app.point(const Offset(.5, .5));
    await settle();
    expect(app.ready, isFalse);
    expect(app.failed, isTrue);
    expect(bus.wire, isEmpty);
    app.dispose();
  });
}
