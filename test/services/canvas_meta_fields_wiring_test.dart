import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/fork_schema.dart';

/// Поле записи о холсте (`canvas_meta`), которого нет в схеме сервера,
/// выбрасывается МОЛЧА: ответ 200, запись без поля. Так контур своей раскраски (`coloring_outline`) ни разу не доехал
/// до партнёра: на проде к 23.09.2026 51 своя раскраска, колонки не было, и
/// второму доставался пустой лист без контура.
void main() {
  final fields = forkFields('canvas_meta');

  test('каждое поле, которое приложение пишет в canvas_meta, есть в схеме', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    // Вызов после `dart format` разнесён по строкам — режем по началу имени.
    final body = src
        .split('Future<bool> upsertCanvasMeta(')[1]
        .split(RegExp(r"_upsertByFilter\(\s*'canvas_meta'"))[0];
    final keys =
        RegExp(
          r"body\['([a-z_]+)'\]",
        ).allMatches(body).map((m) => m.group(1)!).toSet()..addAll(
          RegExp(r"'([a-z_]+)'\s*:").allMatches(body).map((m) => m.group(1)!),
        );
    expect(
      keys,
      contains('coloring_outline'),
      reason: 'сканер разучился находить поля записи',
    );
    for (final k in keys) {
      expect(
        fields,
        contains(k),
        reason: 'сервер выбросит $k молча — добавь поле миграцией',
      );
    }
  });
}
