@Tags(['fork-runtime'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Из комнаты выходят с первого «назад» (просьба владельца 22.10): второго
/// нажатия с подсказкой «нажмите ещё раз» нет.
void main() {
  test('выход с первого «назад»', () {
    final src = File(
      'lib/screens/together/watch_room_screen.dart',
    ).readAsStringSync();
    expect(src, isNot(contains('watchRoomBackAgain')));
    expect(src, isNot(contains('exitOnBack')));
  });
}
