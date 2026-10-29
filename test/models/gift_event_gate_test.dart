import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:love_app/models/gift_event_gate.dart';

/// RT-7 (аудит 29.10): create и следом update одного подарка запускали два
/// обработчика параллельно, оба видели «список вырос» и открывали подарок
/// дважды.
void main() {
  late List<Map<String, dynamic>> server;
  late List<Map<String, dynamic>> local;
  late List<String> opened;
  late GiftEventGate gate;
  late Completer<void> network;

  setUp(() {
    server = [];
    local = [];
    opened = [];
    network = Completer<void>();
    gate = GiftEventGate(
      load: () async {
        await network.future; // ответ сервера приходит не сразу
        local = List.of(server);
      },
      open: (g) async => opened.add(g['id'] as String),
      shown: () => local,
    );
  });

  test('create+update подарка → показан один раз', () async {
    server = [
      {'id': 'g1', 'gift_key': 'candle'},
    ];
    final a = gate.onEvent(); // create
    final b = gate.onEvent(); // update следом, пока первый ждёт сеть
    network.complete();
    await Future.wait([a, b]);
    expect(opened, ['g1']);

    // Ещё одно запоздавшее событие того же подарка — тоже без повтора.
    await gate.onEvent();
    expect(opened, ['g1']);
  });

  test('новый подарок узнаётся по id, а не по длине списка', () async {
    local = [
      {'id': 'old', 'gift_key': 'candle'},
    ];
    // Старый ушёл (принят), новый пришёл — длина та же.
    server = [
      {'id': 'new', 'gift_key': 'box'},
    ];
    network.complete();
    await gate.onEvent();
    expect(opened, ['new']);
  });

  test('подарок, пришедший во время показа, откроется следом', () async {
    final sheet = Completer<void>();
    gate = GiftEventGate(
      load: () async => local = List.of(server),
      open: (g) async {
        opened.add(g['id'] as String);
        if (opened.length == 1) await sheet.future; // лист открыт
      },
      shown: () => local,
    );
    server = [
      {'id': 'g1'},
    ];
    final first = gate.onEvent();
    await Future<void>.delayed(Duration.zero);
    server = [
      {'id': 'g2'},
      {'id': 'g1'},
    ];
    final second = gate.onEvent();
    expect(opened, ['g1'], reason: 'второй лист не поверх первого');
    sheet.complete();
    await Future.wait([first, second]);
    expect(opened, ['g1', 'g2']);
  });
}
