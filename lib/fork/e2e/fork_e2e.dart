/// Точка входа E2E для приложения (PLAN S8).
///
/// Живёт только в главном изоляте: фоновый сервис уведомлений ключи не
/// трогает — два изолята, пишущие одну запись Keystore, затирали бы друг
/// другу ключи пары.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pocketbase/pocketbase.dart';

import '../../services/centrifugo_service.dart';
import '../../services/pocketbase_service.dart';
import 'crypto.dart';
import 'e2e_service.dart';
import 'key_store.dart';
import 'password_policy.dart';
import 'pb_backend.dart';

abstract final class ForkE2E {
  /// Сервис текущего пользователя; null — не вошли или libsodium не
  /// загрузилась (тогда приложение работает как без E2E).
  static final ValueNotifier<E2EService?> service = ValueNotifier(null);

  static Future<E2EService?>? _starting;
  static String _uid = '';
  static String _group = '';
  static final List<UnsubscribeFunc> _subs = [];
  static Future<void> _chain = Future.value();

  /// Фрагменты ссылок приглашения по коду, пока код не принят.
  static final Map<String, String> _pendingFragments = {};

  static Future<E2EService?> ensure(String uid) {
    if (uid.isEmpty) return Future.value(null);
    if (_uid == uid && _starting != null) return _starting!;
    _uid = uid;
    service.value = null;
    return _starting = () async {
      try {
        final c = await E2ECrypto.init();
        final s = E2EService(
          crypto: c,
          store: E2EKeyStore(
            c,
            const SecureStorageVault(),
            slot: 'fork_e2e_keys_v1_$uid',
          ),
          backend: PbE2EBackend(PocketBaseService().pb),
          uid: uid,
        );
        await s.start();
        if (_uid == uid) service.value = s;
        return s;
      } catch (e) {
        debugPrint('ForkE2E: не запустился — $e');
        _starting = null;
        return null;
      }
    }();
  }

  /// Активная пара на главном экране: синхронизация ключей сейчас и по
  /// каждому шагу обмена в канале пары.
  static Future<void> attach(String groupId, String uid) async {
    if (groupId.isEmpty ||
        (groupId == _group && _subs.isNotEmpty && _uid == uid)) {
      return;
    }
    await detach();
    _group = groupId;
    final s = await ensure(uid);
    if (s == null || _group != groupId) return;
    unawaited(sync(groupId));
    for (final col in const ['e2e_handshake', 'e2e_grants']) {
      try {
        _subs.add(
          await CentrifugoService.instance.subscribeDelta(
            'pair:$groupId',
            col,
            (e) {
              if (e.action == 'create') unawaited(sync(groupId));
            },
          ),
        );
      } catch (e) {
        debugPrint('ForkE2E: подписка $col — $e');
      }
    }
  }

  static Future<void> detach() async {
    _group = '';
    for (final u in _subs) {
      try {
        await u();
      } catch (_) {}
    }
    _subs.clear();
  }

  /// Синхронизации пары идут по одной: состояние ключей общее.
  static Future<PairE2EStatus?> sync(String groupId) {
    final s = service.value;
    if (s == null) return Future.value(null);
    final done = Completer<PairE2EStatus?>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await s.syncGroup(groupId));
      } catch (e) {
        debugPrint('ForkE2E: синхронизация $groupId — $e');
        done.complete(null);
      }
    });
    return done.future;
  }

  /// Выход из аккаунта.
  static Future<void> reset() async {
    await detach();
    _uid = '';
    _starting = null;
    service.value = null;
  }

  // --- бэкап (§7) ---

  static List<String>? _wordlist;
  static LeakedPasswords? _leaked;

  /// Список слов BIP39 из ассетов.
  static Future<List<String>> wordlist() async => _wordlist ??=
      (await rootBundle.loadString('assets/fork/bip39_english.txt'))
          .split('\n')
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList(growable: false);

  /// Словарь утёкших паролей из ассетов (фильтр Блума).
  static Future<LeakedPasswords?> leakedPasswords() async {
    final s = service.value;
    if (s == null) return null;
    if (_leaked != null) return _leaked;
    final data = await rootBundle.load('assets/fork/leaked_passwords.bloom');
    return _leaked = LeakedPasswords.parse(
      s.crypto,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  /// Почта входа — пароль бэкапа не должен её содержать.
  static String get email {
    try {
      return PocketBaseService().pb.authStore.record?.getStringValue('email') ??
          '';
    } catch (_) {
      return '';
    }
  }

  // --- приглашения (§6.2) ---

  /// Фрагмент для ссылки приглашения с кодом [code]; пусто — E2E не готов.
  static String inviteFragment(String code) {
    final s = service.value;
    if (s == null || code.isEmpty) return '';
    try {
      return s.inviteFragment(code);
    } catch (_) {
      return '';
    }
  }

  /// Ссылка или QR пришли с фрагментом: запомнить до приёма кода.
  static void rememberFragment(String code, String fragment) {
    if (code.isEmpty || fragment.isEmpty) return;
    _pendingFragments[code.toUpperCase()] = fragment;
  }

  /// Код принят, пара [groupId]. Если код пришёл ссылкой с секретом —
  /// подтверждение уйдёт при ближайшей синхронизации.
  static Future<void> accepted(String code, String groupId) async {
    final fragment = _pendingFragments.remove(code.toUpperCase());
    final s = service.value;
    if (fragment == null || s == null) return;
    await s.acceptedInvite(groupId, code.toUpperCase(), fragment);
    unawaited(sync(groupId));
  }
}
