import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/secret_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Map<String, String>> stores;
  bool failWrite = false;
  setUp(() {
    stores = {
      '': {'auth': 'token', 'cache': 'cache-key', 'e2e': 'pair-keys'},
    };
    failWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final args = call.arguments as Map;
            final options = args['options'] as Map;
            expect(options['resetOnError'], 'false');
            final ns = options['storageNamespace'] as String? ?? '';
            final data = stores.putIfAbsent(ns, () => {});
            final key = args['key'] as String;
            switch (call.method) {
              case 'read':
                return data[key];
              case 'write':
                if (failWrite) throw PlatformException(code: 'write_failed');
                data[key] = args['value'] as String;
              case 'delete':
                data.remove(key);
            }
            return null;
          },
        );
  });

  test('migration copies keys without touching other legacy stores', () async {
    expect(
      await ForkSecretStorage.read(ForkSecretStorage.e2e, 'e2e'),
      'pair-keys',
    );
    expect(stores[''], {'auth': 'token', 'cache': 'cache-key'});
    expect(stores['TetheredE2E'], {'e2e': 'pair-keys'});
    expect(
      await ForkSecretStorage.read(ForkSecretStorage.auth, 'auth'),
      'token',
    );
    expect(
      await ForkSecretStorage.read(ForkSecretStorage.cache, 'cache'),
      'cache-key',
    );
    expect(stores[''], isEmpty);
    await ForkSecretStorage.delete(ForkSecretStorage.auth, 'auth');
    expect(stores['TetheredE2E']!['e2e'], 'pair-keys');
    expect(stores['TetheredCache']!['cache'], 'cache-key');
  });

  test(
    'failed migration preserves the original and propagates the failure',
    () async {
      failWrite = true;
      await expectLater(
        ForkSecretStorage.read(ForkSecretStorage.e2e, 'e2e'),
        throwsA(isA<PlatformException>()),
      );
      expect(stores['']!['e2e'], 'pair-keys');
      expect(stores['TetheredE2E'], isEmpty);
      failWrite = false;
      expect(
        await ForkSecretStorage.read(ForkSecretStorage.e2e, 'e2e'),
        'pair-keys',
      );
    },
  );

  test('current keys win and clearing cannot revive a legacy token', () async {
    stores['TetheredAuth'] = {'auth': 'new-token'};
    expect(
      await ForkSecretStorage.read(ForkSecretStorage.auth, 'auth'),
      'new-token',
    );
    await ForkSecretStorage.delete(ForkSecretStorage.auth, 'auth');
    expect(
      await ForkSecretStorage.read(ForkSecretStorage.auth, 'auth'),
      isNull,
    );
  });

  test(
    'every secret namespace is excluded from cloud backup and device transfer',
    () {
      final files = ['FlutterSecureStorage.xml', 'FlutterSecureKeyStorage.xml'];
      final names = <String>{};
      for (final storage in <FlutterSecureStorage>[
        ForkSecretStorage.auth,
        ForkSecretStorage.cache,
        ForkSecretStorage.e2e,
      ]) {
        final ns = storage.aOptions.toMap()['storageNamespace']!;
        expect(names.add(ns), isTrue, reason: 'stores must be fully isolated');
        files.addAll([
          '$ns.xml',
          'FlutterSecureKeyStorage:$ns.xml',
          'FlutterSecureStorageConfiguration:$ns.xml',
        ]);
      }
      final old = File(
        'android/app/src/main/res/xml/backup_rules.xml',
      ).readAsStringSync();
      final modern = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      final blocks = [
        old,
        ...RegExp(
          r'<(cloud-backup|device-transfer)>([\s\S]*?)</\1>',
        ).allMatches(modern).map((m) => m[2]!),
      ];
      expect(blocks, hasLength(3));
      for (final block in blocks) {
        for (final file in files) {
          expect(
            block,
            contains('domain="sharedpref" path="$file"'),
            reason: file,
          );
        }
      }
    },
  );
}
