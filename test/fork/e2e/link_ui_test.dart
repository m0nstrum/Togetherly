// T3: экраны привязки второго телефона по QR.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/backup_ui.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/device_link.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';
import 'package:love_app/fork/e2e/key_store.dart';
import 'package:love_app/fork/e2e/link_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'fake_backend.dart';

void main() {
  const channel = MethodChannel('tethered/screen_security');
  late E2ECrypto crypto;
  setUpAll(() async => crypto = await E2ECrypto.init());
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() => ForkE2E.service.value = null);

  E2EService make(ServerDb db) => E2EService(
    crypto: crypto,
    store: E2EKeyStore(crypto, MemoryVault()),
    backend: FakeBackend(db, alice),
    uid: alice,
  );

  testWidgets('без бэкапа — экран восстановления предлагает только QR и «заново»', (t) async {
    final db = ServerDb();
    late E2EService fresh;
    await t.runAsync(() async {
      await make(db).start();
      fresh = make(db);
      await fresh.start();
    });
    expect(fresh.needsRestore.value, isTrue);
    expect(fresh.restoreMethod, isNull);
    ForkE2E.service.value = fresh;
    await t.pumpWidget(const MaterialApp(home: ForkE2ERestoreScreen()));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing, reason: 'вводить нечего');
    expect(find.text('Link from another phone'), findsOneWidget);
    expect(find.text('No other phone — start over'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('QR на новом телефоне доводит до привязки после ответа старого', (t) async {
    final db = ServerDb();
    late E2EService old, fresh;
    await t.runAsync(() async {
      old = make(db);
      await old.start();
      fresh = make(db);
      await fresh.start();
    });
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ForkE2ELinkShowScreen(
                  service: fresh,
                  poll: const Duration(milliseconds: 100),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 400)); // переход
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump(); // «Ждём…» крутится вечно — без pumpAndSettle
    final shown = t.widget<QrImageView>(find.byType(QrImageView)).key! as ValueKey<String>;
    final qr = LinkQr.parse(shown.value)!;
    expect(qr.uid, alice);

    await t.runAsync(() => old.linkApprove(qr));
    // Тик опроса: запрос к «серверу» — настоящий async.
    for (var i = 0; i < 10 && fresh.needsRestore.value; i++) {
      await t.pump(const Duration(milliseconds: 120));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    await t.pump(const Duration(seconds: 1));
    expect(fresh.needsRestore.value, isFalse);
    expect(fresh.keys.account.publicKey, old.keys.account.publicKey);
    expect(find.byType(ForkE2ELinkShowScreen), findsNothing, reason: 'экран закрылся');
    await t.pumpWidget(const SizedBox.shrink());
  });
}
