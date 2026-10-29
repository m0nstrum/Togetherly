import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож A2 (аудит B-6): QR приглашения кодирует только `inviteDeepLink`.
///
/// В апстриме QR в 10 % случаев вёл на рикролл, и партнёр не мог
/// подключиться. Ловим возврат шутки с мёржами апстрима: ни ролика, ни
/// случайного выбора ссылки в экране приглашения.
void main() {
  test('в lib/ нет ссылки на рикролл', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i].toLowerCase();
        if (l.contains('dqw4w9wgxcq') || l.contains('rickroll')) {
          offenders.add('${f.path.replaceAll('\\', '/')}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'рикролл в коде клиента');
  });

  test('QR приглашения — всегда inviteDeepLink', () {
    final src = File(
      'lib/screens/connect_partner_screen.dart',
    ).readAsStringSync();
    expect(src, contains('final qrData = pair.inviteDeepLink;'));
    expect(src, isNot(contains('Random()')));
  });
}
