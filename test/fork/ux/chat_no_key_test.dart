import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';

/// UX_AUDIT C1: без ключа пары сообщение не получает «отправлено».
void main() {
  test('без группы и без входа писать нечем', () async {
    expect(await ForkE2E.canSeal(''), isFalse);
    expect(await ForkE2E.canSeal('group1'), isFalse);
  });

  test('ChatService.send проверяет ключ до кэша и очереди', () {
    final src = File('lib/services/chat_service.dart').readAsStringSync();
    final check = src.indexOf('ForkE2E.canSeal(groupId)');
    final cache = src.indexOf("LocalStore.instance.upsertRaw('chat_messages'");
    expect(check, greaterThan(0));
    expect(check, lessThan(cache), reason: 'проверка должна стоять до оптимистичного кэша');
    expect(src, contains('lastSendFailure = ForkFailure.noKey'));
  });

  test('экран чата показывает причину', () {
    final src = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(src, contains('_chat.lastSendFailure'));
    expect(src, contains('ForkNotice.failure(context, why)'));
  });
}
