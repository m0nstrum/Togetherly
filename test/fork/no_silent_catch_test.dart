import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Код форка не глотает ошибки молча (docs/history/UX_AUDIT.md): пустой
/// `catch` допустим, только если рядом сказано, почему молчать правильно
/// (`// тихо: …`). Остальное — через `ForkNotice`/`Outcome`
/// (lib/fork/ui/feedback.dart).
void main() {
  test('пустой catch в lib/fork объяснён', () {
    final empty = RegExp(r'catch\s*\([^)]*\)\s*\{\s*\}');
    final bad = <String>[];
    for (final f in Directory('lib/fork').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (empty.hasMatch(lines[i]) && !lines[i].contains('// тихо:')) {
          bad.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'Объясните молчание (`// тихо: …`) или скажите человеку');
  });
}
