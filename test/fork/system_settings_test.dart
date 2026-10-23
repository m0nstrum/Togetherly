import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/system_settings.dart';

void main() {
  test('резервный путь открывает настройки приложения', () async {
    var calls = 0;
    expect(
      await openSystemNotificationSettings(
        fallback: () async {
          calls++;
          return true;
        },
      ),
      isTrue,
    );
    expect(calls, 1);
  });

  test('отказ и исключение резервного пути возвращают false', () async {
    expect(
      await openSystemNotificationSettings(fallback: () async => false),
      isFalse,
    );
    expect(
      await openSystemNotificationSettings(
        fallback: () async {
          throw StateError('no settings activity');
        },
      ),
      isFalse,
    );
  });
}
