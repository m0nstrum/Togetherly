import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/screen_source.dart';

/// Шлифовка ленты воспоминаний (28.09.2026): цвета только из темы, листы
/// только общие, мёртвой старой карточки нет. Белый и чёрный поверх фото и
/// видео (затемнение, значки на кадре) разрешены — там они к месту.
void main() {
  final src = screenSource('lib/screens/memory_lane_screen.dart');

  test('в ленте нет вшитых цветов мимо темы', () {
    // Лента — сам экран и вынесенное из него по A12-2. Части `part of`
    // (карточка, галерея, плееры) сторож не покрывал и раньше: там значки
    // поверх фото.
    final feed = [
      File('lib/screens/memory_lane_screen.dart').readAsStringSync(),
      for (final f in Directory('lib/screens/memory_lane').listSync())
        if (f is File && f.path.endsWith('.dart'))
          if (f.readAsStringSync() case final code
              when !code.startsWith('part of'))
            code,
    ].join('\n');
    final hits = RegExp(
      r'Colors\.(red|grey|green|blue|amber|orange|pink|purple)',
    ).allMatches(feed).map((m) => m.group(0)).toList();
    expect(hits, isEmpty);
  });

  test('листы открываются общим showAppSheet', () {
    expect(src, isNot(contains('showModalBottomSheet(')));
  });

  test('старой карточки и её сирот больше нет', () {
    expect(src, isNot(contains('_showMemoryDetailLEGACY')));
    expect(src, isNot(contains('Widget _mediaCollage(')));
  });
}
