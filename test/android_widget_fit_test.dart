import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// B7: виджет рабочего стола не должен терять низ в ячейке, которую лончер
/// гарантирует (`minHeight` в `res/xml/*_info.xml`). Так на OnePlus 9R у
/// «Скучаю» 2×2 пропала кнопка: блоки фиксированной высоты в сумме давали
/// ≈148dp при 110dp, а RemoteViews молча срезает лишнее.
///
/// Высоту оценивает `tool/fork/widget_fit.py`: он же говорит, что делать,
/// когда страж упал. Здесь — только запуск и проверки, которых скрипт не
/// делает: компактные разметки повторяют id полных, иначе общий код привязки
/// писал бы в пустоту.
void main() {
  const layouts = 'android/app/src/main/res/layout';

  ProcessResult fit([List<String> args = const []]) =>
      Process.runSync('python3', ['tool/fork/widget_fit.py', ...args]);

  test('каждый виджет влезает в гарантированную ячейку', () {
    final r = fit();
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  test('оценка видит исходную поломку «Скучаю» 2×2', () {
    // Если оценщик разучится складывать высоты, страж выше станет вечно
    // зелёным. Полная разметка «Скучаю» 2×2 обязана не влезать в 110dp —
    // ради этого у неё и есть компактная.
    final r = fit(['--all']);
    final line = (r.stdout as String)
        .split('\n')
        .firstWhere((l) => l.contains('tg_miss_2x2_info'), orElse: () => '');
    final need = RegExp(r'нужно\s+([\d.]+)dp').firstMatch(line);
    expect(need, isNotNull, reason: r.stdout as String);
    expect(double.parse(need!.group(1)!), greaterThan(110));
    expect(line, contains('компактная'));
  });

  test('компактные разметки повторяют id полных', () {
    Set<String> ids(File f) => RegExp(
      r'@\+id/(\w+)',
    ).allMatches(f.readAsStringSync()).map((m) => m.group(1)!).toSet();

    final compacts = Directory(layouts)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_compact.xml'))
        .toList();
    expect(compacts, isNotEmpty);
    for (final c in compacts) {
      final full = File(c.path.replaceFirst('_compact.xml', '.xml'));
      expect(full.existsSync(), isTrue, reason: 'нет полной для ${c.path}');
      expect(ids(c), ids(full), reason: c.path);
    }
  });
}
