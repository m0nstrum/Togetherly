import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/system_settings.dart';

void main() {
  test('интенты настроек несут пакет форка, а не апстрима', () {
    final intents = androidNotificationSettingsIntents('app.example.fork');
    expect(intents, hasLength(2));
    for (final u in intents) {
      expect(u.toString(), contains('APP_PACKAGE=app.example.fork'));
      expect(u.toString(), isNot(contains('com.togetherly.love')));
    }
    expect(intents.first.toString(), contains('APP_NOTIFICATION_SETTINGS'));
  });
}
