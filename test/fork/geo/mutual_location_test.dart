import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/geo/mutual_location.dart';

/// D11: точку партнёра видно, только пока делишься сам.
void main() {
  late ValueNotifier<bool> sharing;
  late StreamController<int?> source;
  late int opened;

  Stream<int?> watch() => whileMutual<int>(
    gate: sharing,
    isOpen: () => sharing.value,
    open: () {
      opened++;
      return source.stream;
    },
  );

  setUp(() {
    sharing = ValueNotifier(false);
    source = StreamController<int?>.broadcast();
    opened = 0;
  });

  test('не делишься — подписки нет, поток отдаёт null', () async {
    final got = <int?>[];
    final sub = watch().listen(got.add);
    await pumpEventQueue();
    expect(opened, 0);
    expect(got, [null]);
    await sub.cancel();
  });

  test('включил — точки идут, выключил — сразу null и отписка', () async {
    final got = <int?>[];
    final sub = watch().listen(got.add);
    sharing.value = true;
    await pumpEventQueue();
    expect(opened, 1);
    source.add(7);
    await pumpEventQueue();
    expect(got, [null, 7]);

    sharing.value = false;
    await pumpEventQueue();
    expect(got.last, isNull, reason: 'метка партнёра не исчезла');
    expect(source.hasListener, isFalse, reason: 'подписка на канал осталась');
    source.add(8);
    await pumpEventQueue();
    expect(got, [null, 7, null], reason: 'точка после выключения дошла');
    await sub.cancel();
  });

  test('повторное включение поднимает подписку заново', () async {
    final sub = watch().listen((_) {});
    sharing.value = true;
    sharing.value = false;
    sharing.value = true;
    await pumpEventQueue();
    expect(opened, 2);
    await sub.cancel();
    expect(source.hasListener, isFalse);
  });

  test('уход слушателя снимает и подписку, и слушатель флага', () async {
    sharing.value = true;
    final sub = watch().listen((_) {});
    await pumpEventQueue();
    await sub.cancel();
    expect(source.hasListener, isFalse);
    sharing.value = false;
    sharing.value = true;
    await pumpEventQueue();
    expect(opened, 1, reason: 'после отмены поток ожил от флага');
  });
}
