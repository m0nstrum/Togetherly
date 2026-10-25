import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UX_AUDIT A1: вход не пробует пароль на чужих «опечаточных» адресах.
void main() {
  test('вход идёт только на введённую почту', () {
    final src = File('lib/screens/login_screen.dart').readAsStringSync();
    expect(src, isNot(contains('emailTypoVariants')));
    expect(
      src,
      contains('auth.signInWithEmail(email: email, password: password)'),
    );
  });
}
