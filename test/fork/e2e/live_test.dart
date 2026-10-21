// fork: обмен ключами пары против настоящего сервера (PLAN S8, критерий).
//
// Запускается из server/scripts/smoke.sh после того, как он завёл пару:
//   SMOKE_AFTER='flutter test test/fork/e2e/live_test.dart --tags fork-live' \
//     server/scripts/smoke.sh
@Tags(['fork-live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';
import 'package:love_app/fork/e2e/key_store.dart';
import 'package:love_app/fork/e2e/pb_backend.dart';
import 'package:pocketbase/pocketbase.dart';

void main() {
  final env = Platform.environment;
  final base = env['SMOKE_BASE_URL'];

  test(
    'две установки получают общий ключ пары через сервер; сверка эмодзи',
    () async {
      final c = await E2ECrypto.init();
      E2EService install(String tok, String uid) {
        final pb = PocketBase(base!)..authStore.save(tok, null);
        return E2EService(
          crypto: c,
          store: E2EKeyStore(c, MemoryVault()),
          backend: PbE2EBackend(pb),
          uid: uid,
        );
      }

      final pair = env['SMOKE_PAIR']!;
      final a = install(env['SMOKE_ATOK']!, env['SMOKE_AID']!);
      final b = install(env['SMOKE_BTOK']!, env['SMOKE_BID']!);
      await a.start();
      await b.start();
      for (var i = 0; i < 2; i++) {
        await a.syncGroup(pair);
        await b.syncGroup(pair);
      }
      expect(a.currentKey(pair), isNotNull);
      expect(
        a.currentKey(pair)!.key.extractBytes(),
        b.currentKey(pair)!.key.extractBytes(),
      );
      expect(a.status.value[pair], PairE2EStatus.unverified);

      await a.sasStart(pair, b.uid);
      await b.syncGroup(pair);
      await b.sasAccept();
      await a.syncGroup(pair);
      await b.syncGroup(pair);
      final ca = a.sas.value, cb = b.sas.value;
      expect(ca, isA<SasShowCode>());
      expect((ca as SasShowCode).code, (cb as SasShowCode).code);
      await a.sasConfirm(match: true);
      await b.sasConfirm(match: true);
      expect(a.status.value[pair], PairE2EStatus.verified);
      expect(b.status.value[pair], PairE2EStatus.verified);
    },
    skip: base == null
        ? 'нужен сервер: запускайте через server/scripts/smoke.sh'
        : false,
  );
}
