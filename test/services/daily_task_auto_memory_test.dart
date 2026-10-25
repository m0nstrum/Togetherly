import 'package:flutter_test/flutter_test.dart';

import '../support/flat_source.dart';

/// Задание дня закрывает только запись, которую сделал человек. Копии,
/// которые приложение само кладёт в ленту с виджета (сообщение, фото,
/// песня), его не закрывают: утреннее сообщение в виджете отмечало
/// «Вспомни любимый момент», хотя на задание никто не отвечал
/// (обращение 236, 05.10.2026).
void main() {
  test('автокопии с виджета не засчитываются в задание', () {
    final src = flatSource('lib/services/widget_service.dart');
    final calls = RegExp(
      r'MemoryRepository\(\)\.add\(([\s\S]*?)\);',
    ).allMatches(src).toList();
    expect(
      calls.length,
      greaterThanOrEqualTo(3),
      reason: 'сообщение, фото и песня',
    );
    for (final c in calls) {
      expect(
        c.group(1),
        contains(flat('countsForDailyTask: false')),
        reason: 'копия с виджета без флага снова закроет задание дня',
      );
    }
  });

  test('репозиторий не зовёт задание для автокопий', () {
    final src = flatSource('lib/services/memory_repository.dart');
    expect(src, contains(flat('bool countsForDailyTask = true')));
    expect(
      RegExp(
        r'if\(countsForDailyTask[^)]*\)\{unawaited\(DailyTaskService',
      ).hasMatch(src),
      isTrue,
      reason: 'onMemoryCreated должен стоять под проверкой флага',
    );
  });
}
