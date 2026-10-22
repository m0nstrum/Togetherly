@Tags(['fork-runtime'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/flags.dart';

void main() {
  test('выход с первого «назад» включён в сборке форка', () {
    expect(ForkFlags.singleBackExit, isTrue);
  });
}
