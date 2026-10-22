import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:love_app/fork/battery/battery_share.dart';
import 'package:love_app/fork/battery/battery_ui.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/record_codec.dart';

const _gid = 'pairaaaaaaaaaaa';

class _Keys implements E2EKeyring {
  final Map<String, PairKey> byId = {};
  void add(PairKey k) => byId[k.keyId] = k;
  @override
  PairKey? keyFor(String keyId) => byId[keyId];
  @override
  String? groupWith(Set<String> members) => null;
  @override
  PairKey? currentKey(String groupId) {
    for (final k in byId.values) {
      if (k.groupId == groupId) return k;
    }
    return null;
  }
}

/// Заряд телефона партнёру (22.10).
void main() {
  final t0 = DateTime(2026, 10, 22, 12);
  ForkBatteryState s(int l, {bool c = false, Duration after = Duration.zero}) =>
      ForkBatteryState(level: l, charging: c, at: t0.add(after));

  test('пишем редко: 5%, зарядка или полчаса', () {
    expect(ForkBattery.shouldSend(null, s(80)), isTrue);
    expect(ForkBattery.shouldSend(s(80), s(78, after: const Duration(minutes: 5))), isFalse);
    expect(ForkBattery.shouldSend(s(80), s(75, after: const Duration(minutes: 5))), isTrue);
    expect(ForkBattery.shouldSend(s(80), s(80, c: true)), isTrue);
    expect(ForkBattery.shouldSend(s(80), s(79, after: const Duration(minutes: 30))), isTrue);
  });

  test('состояние: разбор, «скоро сядет», свежесть', () {
    final st = ForkBatteryState.fromJson(s(15).toJson())!;
    expect((st.level, st.charging, st.low), (15, false, true));
    expect(ForkBatteryState.fromJson(s(15, c: true).toJson())!.low, isFalse);
    expect(st.fresh(t0.add(const Duration(hours: 5))), isTrue);
    expect(st.fresh(t0.add(const Duration(hours: 7))), isFalse);
    expect(ForkBatteryState.fromJson('e2e1.шифр-без-ключа'), isNull);
    expect(ForkBatteryState.fromJson({'l': 'x'}), isNull);
  });

  test('сервер видит только шифр', () async {
    final c = await E2ECrypto.init();
    final keys = _Keys()..add(PairKey(_gid, 1, c.symmetricKey()));
    final codec = RecordCodec(c, keys);
    final body = {'group_id': _gid, 'user_uid': 'alice', 'state': s(42, c: true).toJson()};
    final sealed = codec.encode(ForkBattery.collection, 'b1', _gid, body);
    expect(sealed['state'], startsWith(e2eFieldPrefix));
    expect('${sealed['state']}', isNot(contains('42')));
    final open = codec.decode(ForkBattery.collection, {'id': 'b1', ...sealed});
    expect(ForkBatteryState.fromJson(open['state'])!.level, 42);
    // Без ключа пары — не уходит открытым текстом.
    expect(() => RecordCodec(c, _Keys()).encode(ForkBattery.collection, 'b1', _gid, body), throwsA(isA<E2ENoKeyError>()));
  });

  test('подписи и значки', () {
    expect(forkBatteryIcon(s(100)), Icons.battery_full_rounded);
    expect(forkBatteryIcon(s(5)), Icons.battery_alert_rounded);
    expect(forkBatteryIcon(s(5, c: true)), Icons.battery_charging_full_rounded);
    expect(forkBatteryNote(s(50), t0), isNotEmpty);
    expect(forkBatteryNote(s(10), t0.add(const Duration(minutes: 40))), contains('40'));
  });
}
