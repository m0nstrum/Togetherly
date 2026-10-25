import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сортировка по полю, которого нет в коллекции, — это 400 от PocketBase на
/// каждый запрос. Ловится такое плохо: вызовы обёрнуты в `catch`, экран молча
/// показывает пустоту, а в журнал сервера сыплется «invalid sort field».
/// Так `watch_videos_service` сортировал `memories` по `created`, которого у
/// коллекции нет (там `created_at`), — 2298 отказов за сутки, и видео-
/// воспоминания не появлялись в комнате просмотра вообще никогда.
///
/// Тест сверяет каждый `sort:` в `lib/` со схемой сервера форка.
/// Коллекции, которой в схеме нет, он не касается: судить о ней не по чему.
void main() {
  test('sort ссылается только на существующие поля коллекции', () {
    // Схема сервера форка после всех миграций (снимок Go-теста).
    final raw =
        jsonDecode(
              File(
                'server/internal/migrations/testdata/fields.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final fieldsOf = <String, Set<String>>{
      for (final e in raw.entries)
        e.key: (e.value as List).cast<String>().toSet(),
    };

    final callRe = RegExp(r"""collection\(\s*'([a-z_]+)'\s*\)""");
    final sortRe = RegExp(r"""sort:\s*'([^']+)'""");

    final problems = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Строчные комментарии гасим пробелами: разбор в них тоже поминает
      // поля сортировки, и тест ловил бы описание бага вместо самого бага.
      // Пробелы вместо вырезания — чтобы не съехали номера строк.
      final source = entity.readAsStringSync().replaceAllMapped(
        RegExp(r'//[^\n]*'),
        (m) => ' ' * m.group(0)!.length,
      );

      for (final call in callRe.allMatches(source)) {
        final name = call.group(1)!;
        final known = fieldsOf[name];
        if (known == null) continue;

        // Окно = ровно этот вызов: от имени коллекции до его закрывающей
        // скобки. Без границы регулярка цепляет `sort:` соседнего метода.
        final tail = source.substring(call.end);
        final end = tail.indexOf(');');
        final call_ = end == -1 ? tail : tail.substring(0, end);

        for (final sort in sortRe.allMatches(call_)) {
          for (final part in sort.group(1)!.split(',')) {
            final field = part.trim().replaceFirst(RegExp(r'^[-+]'), '');
            if (field.isEmpty || field.startsWith('@')) continue;
            if (known.contains(field)) continue;

            final line =
                '\n'.allMatches(source.substring(0, call.start)).length + 1;
            problems.add(
              '${entity.path}:$line — коллекция «$name» сортируется по «$field», '
              'такого поля в схеме нет',
            );
          }
        }
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
