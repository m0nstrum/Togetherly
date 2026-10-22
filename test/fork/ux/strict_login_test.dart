import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UX_AUDIT A1: вход не пробует пароль на чужих «опечаточных» адресах.
void main() {
  test('перебор опечаток стоит за ForkFlags.strictLogin', () {
    final src = File('lib/screens/login_screen.dart').readAsStringSync();
    final guard = src.indexOf('if (ForkFlags.strictLogin) rethrow;');
    final loop = src.indexOf('for (final typo in emailTypoVariants');
    expect(guard, greaterThan(0), reason: 'проверка флага пропала');
    expect(guard, lessThan(loop), reason: 'флаг должен стоять до перебора');
  });
}
