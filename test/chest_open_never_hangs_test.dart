import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож «Открываем…» без конца (обращение 211, 29.09.2026).
///
/// Между концом ролика и призом сундук ждёт трёх ответов сети: начисление
/// за ролик, розыгрыш на сервере и файл анимации. Кнопка на всё это время
/// стоит в «Открываем…», и любое ожидание без предела держало её вечно:
/// человек досмотрел пять роликов, сервер засчитал все пять, а до
/// розыгрыша дошёл один. Поэтому каждое из трёх ожиданий обязано кончаться.
void main() {
  String read(String path) => File(path).readAsStringSync();

  // fork: «ответ о начислении за ролик ждётся не дольше kAdGrantWait» убран — рекламы в форке нет (TOUCHPOINTS.md).

  test('запрос открытия сундука ограничен openLimit', () {
    final source = read('lib/services/chest_service.dart');
    final open = source.substring(source.indexOf("'/api/chest/open'"));
    expect(open.substring(0, open.indexOf(';')).contains('.timeout(openLimit)'), isTrue,
        reason: 'потерянный ответ держит кнопку на «Открываем…» навсегда');
  });

  test('обрыв и молчание сети повторяются сами тем же номером', () {
    final source = read('lib/services/chest_service.dart');
    expect(source.contains("error == 'network' || error == 'timeout'"), isTrue);
    expect(RegExp(r'openAttempts\s*=\s*[2-9]').hasMatch(source), isTrue,
        reason: 'без повтора человек видит отказ на первом же обрыве');
  });

  // fork: «сам вызов показа рекламы ограничен» убран — рекламы в форке нет (TOUCHPOINTS.md).

  test('файл анимации ждётся с пределом, экран и виджет ждут одну загрузку', () {
    final source = read('lib/widgets/chest/chest_frames.dart');
    expect(source.contains('getSingleFile(url).timeout(prefetchLimit)'), isTrue,
        reason: 'полтора мегабайта на зависшей сети держали открытие без конца');
    expect(source.contains('_loading[url] ??='), isTrue,
        reason: 'виджет начинал бы свою загрузку и ждал её заново после экрана');
  });
}
