import 'package:flutter_test/flutter_test.dart';

import '../support/flat_source.dart';

/// Обращение 403 (1.38.0, общая раскраска): «Отменить» горела, а нажатие не
/// делало ничего. Свой штрих на общем холсте после записи на сервере меняет
/// временный id на серверный, а номер действия оставался под старым: отмена
/// не находила его и молча выходила. Правило живёт в `canvas_undo.dart`, здесь
/// — что экран холста им пользуется.
void main() {
  final src = flatSource('lib/screens/draw_screen.dart');

  test('при смене id своего штриха номер действия переезжает следом', () {
    final swap = src.indexOf(flat('updatedMyIds[i] = remote.id'));
    expect(swap, greaterThan(0));
    final after = src.substring(swap, swap + 600);
    expect(
      after,
      contains(flat('adoptStrokeId(_strokeSeq, _mirrorGroupOf')),
      reason: 'без переезда отмена теряет штрих после ответа сервера',
    );
  });

  test('общий холст поднимает свои прошлые линии в историю отмены', () {
    final remote = src.indexOf(flat('void _onRemoteStrokes('));
    expect(remote, greaterThan(0));
    final body = src.substring(remote, remote + 4000);
    expect(
      body,
      contains(flat('ownStrokeHistory(parsed, _myUid)')),
      reason: 'без этого линию прошлого захода в общем холсте не отменить',
    );
  });

  test('отмена берёт номер своего штриха через ownStrokeSeq', () {
    final undo = src.indexOf(flat('Future<void> _undo()'));
    expect(undo, greaterThan(0));
    final body = src.substring(undo, undo + 400);
    expect(
      body,
      contains(flat('ownStrokeSeq(_strokeSeq, _myStrokeIds.last)')),
      reason: 'штрих без номера (поднятый с диска) тоже обязан отменяться',
    );
  });
}
