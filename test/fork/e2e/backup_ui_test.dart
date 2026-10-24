import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/backup.dart';
import 'package:love_app/fork/e2e/backup_ui.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';
import 'package:love_app/fork/e2e/key_store.dart';
import 'fake_backend.dart';

void main() {
  const channel = MethodChannel('tethered/screen_security');
  late E2ECrypto crypto;
  setUpAll(() async => crypto = await E2ECrypto.init());
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    ForkE2E.service.value = null;
  });

  testWidgets(
    'backup keeps the settings theme, explains mismatch, and can show passwords',
    (t) async {
      late E2EService service;
      await t.runAsync(() async {
        service = E2EService(
          crypto: crypto,
          store: E2EKeyStore(crypto, MemoryVault()),
          backend: FakeBackend(ServerDb(), alice),
          uid: alice,
        );
        await service.start();
      });
      ForkE2E.service.value = service;
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Theme(
              data: ThemeData(colorScheme: scheme),
              child: const ForkE2EBackupRow(),
            ),
          ),
        ),
      );
      await t.tap(find.text('Encryption key backup'));
      await t.pumpAndSettle();
      expect(
        Theme.of(t.element(find.byType(ForkE2EBackupScreen))).colorScheme,
        scheme,
      );
      await t.tap(find.text('Password'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'weak1');
      await t.enterText(find.byType(TextField).last, 'weak2');
      await t.pumpAndSettle();
      expect(find.text('Passwords don’t match'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField).first).obscureText,
        isTrue,
      );
      await t.tap(find.byTooltip('Show password').first);
      await t.pump();
      expect(
        t.widget<TextField>(find.byType(TextField).first).obscureText,
        isFalse,
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
      service.restoreMethod = BackupMethod.password;
      await t.pumpWidget(const MaterialApp(home: ForkE2ERestoreScreen()));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Show password'));
      await t.pump();
      expect(t.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpAndSettle();
    },
  );
}
