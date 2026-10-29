import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/fork_schema.dart';

/// B8: время уходит на сервер в UTC, рядом — пояс автора `tz`. Без поля в
/// схеме PocketBase молча выбрасывает пояс, и PairTime.read читает новую
/// запись как старую: комментарии к воспоминаниям шли по Гринвичу.
void main() {
  test('каждая коллекция, куда клиент пишет tz, держит его в схеме', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    final target = RegExp(r"(?:_upsertById\(|\.collection\()\s*'(\w+)'");
    final writes = <String>{};
    var at = 0;
    while (true) {
      at = src.indexOf("'tz':", at);
      if (at < 0) break;
      final before = src.substring(0, at);
      final col = target.allMatches(before).lastOrNull?.group(1);
      expect(col, isNotNull, reason: "не нашли коллекцию для 'tz' @$at");
      writes.add(col!);
      at += 5;
    }
    // Те, о которых знаем: если пропадут из записи, разбор выше сломался.
    expect(
      writes,
      containsAll(['memories', 'memory_comments', 'mood_entries']),
    );
    for (final col in writes) {
      expect(forkFields(col), contains('tz'), reason: 'нет tz в схеме: $col');
    }
  });

  test('комментарий читает пояс из записи', () {
    final src = File('lib/models/comment.dart').readAsStringSync();
    expect(src, contains("PairTime.read(d['created_at'], (d['tz']"));
  });
}
