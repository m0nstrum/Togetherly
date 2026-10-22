import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UX A12: расставание, которое сервер не принял, не сбрасывает пару у себя
/// молча, а диалог честно говорит про историю пары.
void main() {
  String body(String src, String from) {
    final i = src.indexOf(from);
    expect(i, isNonNegative, reason: 'нет $from');
    return src.substring(i, src.indexOf('\n  }\n', i));
  }

  test('Connection.unpair: отказ сервера — пара остаётся', () {
    final src = File('lib/models/connection.dart').readAsStringSync();
    final b = body(src, 'Future<bool> unpair()');
    final check = b.indexOf('!await PbDataService().unpairGroup');
    final reset = b.indexOf('isPaired = false');
    expect(check, isNonNegative);
    expect(reset, greaterThan(check), reason: 'сброс — только после ответа');
    expect(b.substring(check, reset), contains('return false'));
  });

  test('экран показывает отказ и не удаляет связь', () {
    final src = File('lib/screens/connect_partner_screen.dart')
        .readAsStringSync();
    expect(src, contains('final done = await pair.unpair();'));
    expect(src, contains('if (!done) _showSnack(_unpairFailed);'));
    expect(src, contains('if (!ok) {\n                        _showSnack(_unpairFailed);'));
    final mgr = File('lib/models/connections_manager.dart').readAsStringSync();
    expect(mgr,
        contains('if (connection.isPaired && !await connection.unpair()) return false;'));
  });

  test('диалог говорит про переписку и воспоминания', () {
    final src = File('lib/screens/connect_partner_screen.dart')
        .readAsStringSync();
    expect(body(src, 'Future<void> _showUnpairDialog()'),
        contains('Переписка, воспоминания и рисунки этой пары'));
  });
}
