// B10: присутствие партнёра в канале пары — что считается признаком жизни,
// когда гаснет и как восстанавливается после переподключения.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/presence_liveness.dart';
import 'package:love_app/services/centrifugo_service.dart';
import 'package:love_app/services/presence_service.dart';
import 'package:pocketbase/pocketbase.dart';

class FakeWire implements PresenceWire {
  final sent = <Map<String, dynamic>>[];
  final raw = <void Function(Map<String, dynamic>)>[];
  final chats = <void Function(RtEvent)>[];
  final who = StreamController<String>.broadcast(sync: true);
  final ready = StreamController<void>.broadcast(sync: true);
  final db = StreamController<int?>.broadcast();

  @override
  String get me => 'alice';

  @override
  Future<RtUnsub> listen(
    String channel,
    void Function(Map<String, dynamic>) onData,
  ) async {
    raw.add(onData);
    return () async => raw.remove(onData);
  }

  @override
  Stream<String> publishers(String channel) => who.stream;

  @override
  Stream<void> subscribed(String channel) => ready.stream;

  @override
  Future<RtUnsub> chat(String channel, void Function(RtEvent) onEvent) async {
    chats.add(onEvent);
    return () async => chats.remove(onEvent);
  }

  /// В заглушке «шифр» — обёртка `sealed`; без неё пакет не открывается.
  @override
  Map<String, dynamic>? open(String channel, Map<String, dynamic> raw) =>
      raw['sealed'] is Map ? Map<String, dynamic>.from(raw['sealed']) : null;

  @override
  void signal(String groupId, String channel, Map<String, dynamic> msg) =>
      sent.add(msg);

  @override
  void store(String uid) {}

  @override
  Stream<int?> stored(String uid) => db.stream;

  @override
  void observe(WidgetsBindingObserver o, bool on) {}

  /// Публикация партнёра: сервер называет отправителя, потом раздаёт пакет.
  void publish(Map<String, dynamic> packet, {String from = 'bob'}) {
    who.add(from);
    for (final l in List.of(raw)) {
      l(packet);
    }
  }
}

void main() {
  late FakeWire wire;
  late PresenceService svc;
  late int now;
  late List<bool> online;
  late StreamSubscription<bool> sub;

  setUp(() async {
    now = 1786650000000;
    wire = FakeWire();
    svc = PresenceService.test(wire, nowMs: () => now);
    svc.start(groupId: 'g');
    await Future<void>.delayed(Duration.zero);
    online = [];
    sub = svc.watchOnline('bob').listen(online.add);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() async {
    await sub.cancel();
    svc.stop();
  });
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('старт здоровается и просит ответа', () {
    expect(wire.sent.first['t'], 'alive');
    expect(wire.sent.first['ask'], isTrue);
  });

  test('«печатает» партнёра — значит в сети, без отдельного alive', () async {
    wire.publish({
      'sealed': {'t': 'typing', 'uid': 'bob', 'at': 0},
    });
    await settle();
    expect(online.last, isTrue);
  });

  test('пакет, который не открылся, всё равно признак жизни', () async {
    // Ключ пары ещё не доехал: содержимое не прочесть, но сервер знает,
    // кто его прислал.
    wire.publish({'t': 'e2e', 'junk': 1});
    await settle();
    expect(online.last, isTrue);
  });

  test('реплика чата партнёра — признак жизни, своя и правка — нет', () async {
    RecordModel rec(String uid) => RecordModel({'id': 'm', 'user_uid': uid});
    wire.chats.single(RtEvent('update', rec('bob')));
    wire.chats.single(RtEvent('create', rec('alice')));
    await settle();
    expect(online.last, isFalse);
    wire.chats.single(RtEvent('create', rec('bob')));
    await settle();
    expect(online.last, isTrue);
  });

  test('часы партнёра спешат на минуту — всё равно в сети', () async {
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now + 60000},
    });
    await settle();
    expect(online.last, isTrue);
  });

  test('приход партнёра — ответ сразу; повторный удар — без ответа', () async {
    wire.sent.clear();
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now},
    });
    expect(wire.sent, hasLength(1));
    expect(wire.sent.single['ask'], isNull, reason: 'ответ не просит ответа');
    now += 6000;
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now},
    });
    expect(wire.sent, hasLength(1));
  });

  test('просьба ответить после переподключения партнёра — отвечаем', () async {
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now},
    });
    wire.sent.clear();
    now += 6000;
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now, 'ask': true},
    });
    expect(wire.sent, hasLength(1));
  });

  test('своя подписка встала заново — снова здороваемся с просьбой', () {
    wire.sent.clear();
    wire.ready.add(null);
    expect(wire.sent.single['t'], 'alive');
    expect(wire.sent.single['ask'], isTrue);
  });

  test('тишина дольше свежести — офлайн', () async {
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now},
    });
    await settle();
    expect(online.last, isTrue);
    now += PresenceLiveness.freshness.inMilliseconds;
    // Отметка базы — повод пересчитать (как и часы раз в десять секунд).
    wire.db.add(null);
    await settle();
    expect(online.last, isFalse);
  });

  test('«ушёл» гасит сразу, хотя пакет пришёл от живого отправителя', () async {
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now},
    });
    await settle();
    wire.publish({
      'sealed': {'t': 'away', 'uid': 'bob', 'at': now},
    });
    await settle();
    expect(online.last, isFalse);
  });

  test('свернули приложение — шлём «ушёл»; вернулись — здороваемся', () {
    wire.sent.clear();
    svc.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(wire.sent, isEmpty, reason: 'шторка или окошко — человек тут');
    svc.didChangeAppLifecycleState(AppLifecycleState.hidden);
    svc.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(wire.sent.map((m) => m['t']), ['away']);
    wire.ready.add(null);
    expect(wire.sent, hasLength(1), reason: 'в фоне не здороваемся');
    svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(wire.sent.last['t'], 'alive');
    expect(wire.sent.last['ask'], isTrue);
  });

  test('в фоне на просьбу партнёра не отвечаем', () {
    svc.didChangeAppLifecycleState(AppLifecycleState.paused);
    wire.sent.clear();
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'bob', 'at': now, 'ask': true},
    });
    svc.noteActivity('bob');
    expect(wire.sent, isEmpty, reason: '«ушёл» не отменяется ответом');
  });

  test('свои сигналы и сигналы чужих каналов не путаются', () async {
    wire.publish({
      'sealed': {'t': 'alive', 'uid': 'alice', 'at': now},
    }, from: 'alice');
    await settle();
    expect(online.last, isFalse);
  });
}
