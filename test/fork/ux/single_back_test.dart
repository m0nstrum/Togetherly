import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Из комнаты и ленты выходят с первого «назад» (просьба владельца 22.10).
void main() {
  test('комната отпускает сразу, до подсказки «нажмите ещё раз»', () {
    final src =
        File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    final i = src.indexOf('bool _allowLeave() {');
    final body = src.substring(i, src.indexOf('\n  }\n', i));
    expect(body.indexOf('ForkFlags.singleBackExit'),
        lessThan(body.indexOf('watchRoomBackAgain')));
  });
}
