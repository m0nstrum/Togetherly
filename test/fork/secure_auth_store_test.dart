import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/secure_auth_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keystore в тесте — словарь за каналом плагина.
Map<String, String> fakeKeystore() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          final args = (call.arguments as Map).cast<String, dynamic>();
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return store[key];
            case 'write':
              store[key!] = args['value'] as String;
              return null;
            case 'delete':
              store.remove(key);
              return null;
            case 'containsKey':
              return store.containsKey(key);
          }
          return null;
        },
      );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'pb_auth';

  test(
    'токен из SharedPreferences переезжает в Keystore и стирается',
    () async {
      SharedPreferences.setMockInitialValues({key: '{"token":"old"}'});
      final keystore = fakeKeystore();

      final store = await ForkSecureAuthStore.open(
        key,
        storage: const FlutterSecureStorage(),
      );

      expect(keystore[key], contains('"token":"old"'));
      expect((await SharedPreferences.getInstance()).getString(key), isNull);
      expect(store, isNotNull);
    },
  );

  test('новый токен пишется только в Keystore', () async {
    SharedPreferences.setMockInitialValues({});
    final keystore = fakeKeystore();
    final store = await ForkSecureAuthStore.open(
      key,
      storage: const FlutterSecureStorage(),
    );

    store.save('tkn', null);
    await Future<void>.delayed(Duration.zero);

    expect(keystore[key], contains('tkn'));
    expect((await SharedPreferences.getInstance()).getString(key), isNull);

    store.clear();
    await Future<void>.delayed(Duration.zero);
    expect(keystore.containsKey(key), isFalse);
  });

  test('первая установка: сессия стирается без клиента (B-7)', () async {
    SharedPreferences.setMockInitialValues({});
    final keystore = fakeKeystore();
    keystore[key] = '{"token":"from-keychain"}';

    await ForkSecureAuthStore.wipe(key, storage: const FlutterSecureStorage());

    expect(keystore.containsKey(key), isFalse);
    final store = await ForkSecureAuthStore.open(
      key,
      storage: const FlutterSecureStorage(),
    );
    expect(store.token, isEmpty);
  });
}
