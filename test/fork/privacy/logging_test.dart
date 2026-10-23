import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/privacy/logging.dart';

void main() {
  test('release logging discards even sensitive deep links', () {
    final original = debugPrint;
    addTearDown(() => debugPrint = original);
    final output = <String?>[];
    debugPrint = (message, {wrapWidth}) => output.add(message);
    configureForkLogging(release: false);
    debugPrint('debug diagnostic');
    expect(output, ['debug diagnostic']);
    output.clear();
    configureForkLogging(release: true);
    debugPrint('loveapp://invite#s=secret', wrapWidth: 20);
    debugPrint(null);
    expect(output, isEmpty);
  });
}
