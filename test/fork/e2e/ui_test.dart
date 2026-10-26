// fork: плашка ключей и экран сверки (docs/E2E.md §6.3, §12.4).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/backup.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';
import 'package:love_app/fork/e2e/key_store.dart';
import 'package:love_app/fork/e2e/ui.dart';

import 'fake_backend.dart';

void main() {
  late E2ECrypto c;
  setUpAll(() async => c = await E2ECrypto.init());
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ForkE2E.service.value = null);

  Future<E2EService> install(ServerDb db, String uid) async {
    final s = E2EService(
      crypto: c,
      store: E2EKeyStore(c, MemoryVault()),
      backend: FakeBackend(db, uid),
      uid: uid,
    );
    await s.start();
    return s;
  }

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: Column(children: [child])),
  );
  const banner = ForkE2EBanner(
    groupId: gid,
    partnerUid: bob,
    partnerName: 'Bob',
  );

  testWidgets(
    'плашка: без E2E пусто, «не проверено» — зовёт сверить, подмена — громко',
    (t) async {
      await t.pumpWidget(host(banner));
      expect(find.byType(InkWell), findsNothing);

      final db = ServerDb();
      late E2EService a;
      await t.runAsync(() async {
        a = await install(db, alice);
        final b = await install(db, bob);
        for (var i = 0; i < 2; i++) {
          await a.syncGroup(gid);
          await b.syncGroup(gid);
        }
      });
      ForkE2E.service.value = a;
      await t.pump();
      expect(find.textContaining('Compare 7 emoji with Bob'), findsOneWidget);

      a.status.value = {gid: PairE2EStatus.tampered};
      await t.pump();
      expect(find.textContaining('swapped them'), findsOneWidget);

      a.status.value = {gid: PairE2EStatus.verified};
      await t.pump();
      // Проверено, но ключи без бэкапа — плашка зовёт его включить (UX A2).
      expect(find.textContaining('Keys have no backup'), findsOneWidget);

      a.backupMethod.value = BackupMethod.phrase;
      await t.pump();
      expect(find.byType(InkWell), findsNothing);
    },
  );

  testWidgets(
    'ordinary reminder can wait; danger cannot; waiting has no dead verify action',
    (t) async {
      final db = ServerDb();
      late E2EService a;
      await t.runAsync(() async {
        a = await install(db, alice);
        final b = await install(db, bob);
        await a.syncGroup(gid);
        await b.syncGroup(gid);
        await a.syncGroup(gid);
      });
      ForkE2E.service.value = a;
      await t.pumpWidget(host(banner));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Later — remind me in a week'));
      await t.pumpAndSettle();
      expect(find.textContaining('Compare 7 emoji'), findsNothing);
      a.status.value = {gid: PairE2EStatus.keyChanged};
      await t.pumpAndSettle();
      expect(find.textContaining('key changed'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      a.status.value = {gid: PairE2EStatus.tampered};
      await t.pump();
      expect(find.textContaining('swapped them'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
      for (final status in [
        PairE2EStatus.waitingPartner,
        PairE2EStatus.waitingKey,
      ]) {
        a.status.value = {gid: status};
        await t.pump();
        expect(find.text('Verify'), findsNothing);
        expect(t.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
      }
      a.status.value = {gid: PairE2EStatus.verified};
      await t.pumpAndSettle();
      expect(find.textContaining('Keys have no backup'), findsOneWidget);
      expect(find.text('Turn on'), findsOneWidget);
    },
  );

  testWidgets('экран сверки: эмодзи и «Совпадают» → проверено', (t) async {
    final db = ServerDb();
    late E2EService a, b;
    await t.runAsync(() async {
      a = await install(db, alice);
      b = await install(db, bob);
      for (var i = 0; i < 2; i++) {
        await a.syncGroup(gid);
        await b.syncGroup(gid);
      }
    });
    ForkE2E.service.value = a;
    await t.pumpWidget(
      const MaterialApp(
        home: ForkE2EVerifyScreen(
          groupId: gid,
          partnerUid: bob,
          partnerName: 'Bob',
        ),
      ),
    );
    await t.tap(find.text('Start'));
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await b.syncGroup(gid);
      await b.sasAccept();
      await a.syncGroup(gid);
      await b.syncGroup(gid);
    });
    await t.pump();
    final code = (a.sas.value! as SasShowCode).code;
    for (final e in code.emoji) {
      expect(find.text(e.symbol), findsWidgets);
    }
    await t.tap(find.text('They match'));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await t.pump();
    expect(find.textContaining('verified'), findsOneWidget);
    expect(a.status.value[gid], PairE2EStatus.verified);
  });
}
