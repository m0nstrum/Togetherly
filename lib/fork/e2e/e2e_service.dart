/// Обмен ключами пары (docs/fork/E2E.md §5–6, PLAN S8).
///
/// Сервис не знает про PocketBase: всё общение с сервером — через
/// [E2EBackend]. Так его можно проверить двумя «установками» и сервером,
/// который подменяет ключи (test/fork/e2e/e2e_service_test.dart).
///
/// Что делает [E2EService.syncGroup] для одной пары:
/// 1. проверяет ключи партнёров: подпись списка устройств, откат версии,
///    смену ключа аккаунта;
/// 2. забирает выданные этому устройству ключи пары;
/// 3. если ключа пары ещё нет ни у кого — создаёт эпоху 1 (участник с
///    наименьшим uid, чтобы двое не создали разные);
/// 4. выдаёт ключи пары всем полным устройствам участников;
/// 5. разбирает подтверждения приглашений и шаги сверки эмодзи.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'backup.dart';
import 'crypto.dart';
import 'devices.dart';
import 'envelope.dart';
import 'key_store.dart';
import 'record_codec.dart';
import 'sas.dart';
import '../ui/feedback.dart';

/// Состояние пары для UI.
enum PairE2EStatus {
  /// Новое устройство: на сервере есть бэкап ключей, нужно восстановить.
  needsRestore,

  /// У партнёра ещё нет ключей (старая версия приложения или не входил).
  waitingPartner,

  /// Ключи у всех есть, ключ пары ещё не дошёл.
  waitingKey,

  /// Ключ пары есть, партнёр не проверен — плашка «сверьте эмодзи».
  unverified,

  verified,

  /// Ключ аккаунта партнёра сменился после знакомства — громкая плашка.
  keyChanged,

  /// Сервер отдал ключи, которые не сходятся: подпись, откат версии,
  /// отпечаток из ссылки. Ключ пары таким устройствам не выдаётся.
  tampered,
}

class IdentityRecord {
  IdentityRecord({required this.accountKey, required this.devices});
  final Uint8List accountKey;
  final DeviceList devices;
}

class HandshakeMsg {
  HandshakeMsg({
    required this.id,
    required this.fromUid,
    required this.session,
    required this.kind,
    required this.data,
    required this.created,
  });
  final String id;
  final DateTime created;
  final String fromUid;
  final String session;
  final String kind;
  final Map<String, dynamic> data;
}

abstract interface class E2EBackend {
  /// null — человек ещё не публиковал ключи. [FormatException] — запись
  /// есть, но не разбирается (считаем подменой).
  Future<IdentityRecord?> identity(String uid);
  Future<void> putIdentity(String uid, Uint8List accountKey, DeviceList list);
  Future<List<String>> members(String groupId);
  Future<List<PairKeyGrant>> grantsTo(String uid, String deviceId);

  /// Повтор (та же эпоха тому же устройству) — не ошибка.
  Future<void> putGrant(PairKeyGrant grant, String toUid);
  Future<void> postHandshake(
    String groupId,
    String fromUid,
    String session,
    String kind,
    Map<String, dynamic> data,
  );
  Future<List<HandshakeMsg>> handshakes(String groupId);

  /// Бэкап ключей (`e2e_backups.data`); null — нет.
  Future<Map<String, dynamic>?> backup(String uid);
  Future<void> putBackup(String uid, Map<String, dynamic> data);
}

/// Что видно на экране сверки.
sealed class SasState {
  const SasState(this.groupId, this.partnerUid, this.session);
  final String groupId;
  final String partnerUid;
  final String session;
}

/// Ждём телефон партнёра: [started] — мы позвали и ждём «Сверить»;
/// иначе мы приняли и ждём, пока его телефон откроет эмодзи.
class SasWaiting extends SasState {
  const SasWaiting(
    super.groupId,
    super.partnerUid,
    super.session, {
    this.started = true,
  });
  final bool started;
}

/// Почему сверка встала не из-за эмодзи (UX_AUDIT A10).
enum SasStopWhy {
  /// Партнёр нажал «Отменить» или «Не сейчас».
  partnerCancelled,

  /// Телефон партнёра не ответил за [E2EService.sasWait].
  noAnswer,

  /// Шаг пришёл к телефону, который уже забыл сверку (перезапуск).
  lost,
}

/// Сверка прервалась, эмодзи не сравнивали: начать заново.
class SasStopped extends SasState {
  const SasStopped(
    super.groupId,
    super.partnerUid,
    super.session, {
    required this.why,
  });
  final SasStopWhy why;
}

/// Партнёр зовёт сверить ключи.
class SasIncoming extends SasState {
  const SasIncoming(super.groupId, super.partnerUid, super.session);
}

/// Эмодзи готовы — сравнить голосом.
class SasShowCode extends SasState {
  const SasShowCode(super.groupId, super.partnerUid, super.session, this.code);
  final SasCode code;
}

/// Сверка закончилась: [match] — совпало ли у нас.
class SasFinished extends SasState {
  const SasFinished(
    super.groupId,
    super.partnerUid,
    super.session, {
    required this.match,
  });
  final bool match;
}

class E2EService implements E2EKeyring {
  E2EService({
    required this.crypto,
    required this.store,
    required this.backend,
    required this.uid,
    this.kdfParams,
  });

  /// Параметры Argon2id для нового бэкапа; null — стандартные (§7). Тесты
  /// ставят дешёвые.
  final KdfParams? kdfParams;

  /// Ключей на устройстве нет, а на сервере есть бэкап: ждём фразу или
  /// пароль ([restore]) или «начать заново» ([startFresh]).
  final ValueNotifier<bool> needsRestore = ValueNotifier(false);

  /// Как защищён бэкап этого аккаунта; null — бэкапа нет.
  final ValueNotifier<BackupMethod?> backupMethod = ValueNotifier(null);

  /// Чем защищён бэкап на сервере, пока ждём восстановления.
  BackupMethod? restoreMethod;
  Map<String, dynamic>? _serverBackup;

  final E2ECrypto crypto;
  final E2EKeyStore store;
  final E2EBackend backend;
  final String uid;

  E2EKeys? _keys;
  E2EKeys get keys =>
      _keys ?? (throw StateError('E2EService.start() не вызван'));

  /// Состояние каждой пары после последней синхронизации.
  final ValueNotifier<Map<String, PairE2EStatus>> status = ValueNotifier(
    const {},
  );

  /// Текущая сверка эмодзи (одна за раз).
  final ValueNotifier<SasState?> sas = ValueNotifier(null);

  /// Шаг сверки старше этого — брошенный: после перезапуска не всплывает.
  static const Duration sasTtl = Duration(minutes: 10);

  /// Сколько ждать телефон партнёра на шаге сверки (UX_AUDIT A10): раньше
  /// «Ждём…» висело вечно.
  static Duration sasWait = const Duration(minutes: 2);
  Timer? _sasTimer;

  final Map<String, List<String>> _members = {};
  final Map<String, SasInitiator> _initiators = {};
  final Map<String, SasResponder> _responders = {};
  final Set<String> _seenHandshakes = {};

  /// Ключи на устройстве и опубликованный список устройств.
  Future<void> start() async {
    final loaded = await store.load();
    if (loaded == null) {
      final b = await backend.backup(uid);
      if (b != null) {
        // Новый телефон: свои ключи не создаём, иначе партнёр увидит смену
        // ключа, а история останется нечитаемой.
        _serverBackup = b;
        restoreMethod = BackupMethod.values.byName(b['method'] as String);
        needsRestore.value = true;
        return;
      }
    }
    _keys = (loaded ?? E2EKeys.generate(crypto, b64(crypto.random(9))))
      ..deriveSelf(crypto, uid);
    backupMethod.value = keys.backup?.method;
    await _publish();
    await store.save(keys);
  }

  // --- бэкап ключей (§7) ---

  /// Включить бэкап (или сменить фразу/пароль): шифруется и уходит на сервер.
  Future<void> enableBackup(BackupMethod method, String secret) async {
    // Новый телефон до восстановления: ключей ещё нет — сначала восстановить
    // (UX_AUDIT A3), а не падать «start() не вызван».
    if (_keys == null) throw const ForkFailureError(ForkFailure.noKey);
    final bk = await BackupKey.deriveAsync(
      crypto,
      method,
      secret,
      params: kdfParams,
    );
    keys.backup = bk;
    await _uploadBackup();
    await store.save(keys);
    backupMethod.value = method;
  }

  Future<void> _uploadBackup() async {
    final bk = keys.backup;
    if (bk == null) return;
    await backend.putBackup(
      uid,
      KeyBackup.sealWith(
        crypto,
        user: uid,
        key: bk,
        contents: BackupContents(
          accountSecret: keys.account.secretKey.extractBytes(),
          pairKeys: keys.pairKeys.values.toList(),
        ),
      ),
    );
  }

  /// Восстановить ключи из бэкапа фразой или паролем. Неверные —
  /// [E2EVerifyError]; испорченная фраза — [FormatException].
  Future<void> restore(String secret) async {
    final data = _serverBackup;
    if (data == null) throw StateError('восстанавливать нечего');
    final bk = await BackupKey.forDataAsync(crypto, data, secret);
    final contents = KeyBackup.openWith(crypto, user: uid, data: data, key: bk);
    // Секрет Ed25519 в libsodium — seed ‖ публичный ключ.
    final account = KeyPair(
      publicKey: Uint8List.fromList(contents.accountSecret.sublist(32)),
      secretKey: crypto.keyFromBytes(contents.accountSecret),
    );
    final prev = _keys;
    _keys = E2EKeys(
      account: account,
      device: DeviceKeys.generate(crypto, b64(crypto.random(9))),
      pairKeys: {for (final k in contents.pairKeys) k.keyId: k},
      backup: bk,
    )..deriveSelf(crypto, uid);
    // Сбой сети на публикации не должен оставить полусостояние, после
    // которого повтор отвечает «нечего восстанавливать» (UX_AUDIT A5):
    // бэкап с сервера забываем только после успеха.
    try {
      await _publish();
      await store.save(keys);
    } catch (_) {
      _keys = prev;
      rethrow;
    }
    _serverBackup = null;
    backupMethod.value = bk.method;
    needsRestore.value = false;
  }

  /// Без фразы и пароля: новые ключи, старая история не читается, партнёр
  /// увидит смену ключа. Бэкап нужно включить заново.
  Future<void> startFresh() async {
    final prev = _keys;
    _keys = E2EKeys.generate(crypto, b64(crypto.random(9)))
      ..deriveSelf(crypto, uid);
    try {
      await _publish();
      await store.save(keys);
    } catch (_) {
      _keys = prev; // повтор начнёт с того же места (UX_AUDIT A7)
      rethrow;
    }
    _serverBackup = null;
    backupMethod.value = null;
    needsRestore.value = false;
  }

  Future<void> _publish() async {
    IdentityRecord? rec;
    try {
      rec = await backend.identity(uid);
    } on FormatException {
      rec = null;
    }
    final me = keys.device.entry();
    var devices = <DeviceEntry>[me];
    var version = 1;
    if (rec != null) {
      final ours = bytesEqual(rec.accountKey, keys.account.publicKey);
      final valid = ours && _verifies(rec.devices, rec.accountKey, uid, 0);
      version = rec.devices.version + 1;
      if (valid) {
        if (rec.devices.device(me.id) != null) {
          keys.listVersion = rec.devices.version;
          return;
        }
        devices = [...rec.devices.devices, me];
      }
      // Чужой ключ аккаунта в нашей записи — переустановка без бэкапа (или
      // подмена): публикуем свой, партнёр увидит смену ключа.
    }
    final list = DeviceList.create(crypto, keys.account, uid, version, devices);
    await backend.putIdentity(uid, keys.account.publicKey, list);
    keys.listVersion = version;
  }

  bool _verifies(DeviceList l, Uint8List ak, String user, int seen) {
    try {
      l.verify(crypto, ak, user: user, seenVersion: seen);
      return true;
    } on E2EVerifyError {
      return false;
    }
  }

  // --- приглашения (§6.2) ---

  /// Фрагмент для ссылки приглашения с кодом [code]: секрет и отпечаток
  /// своего ключа аккаунта. Секрет запоминается до подтверждения.
  String inviteFragment(String code) {
    var secret = keys.inviteSecrets[code];
    if (secret == null) {
      secret = keys.inviteSecrets[code] = b64(crypto.random(32));
      store.save(keys);
    }
    final f = b64(accountFingerprint(crypto, keys.account.publicKey));
    return 's=$secret&f=$f';
  }

  /// Мы приняли приглашение из ссылки или QR с [fragment]. Подтверждение
  /// уйдёт при ближайшей синхронизации пары, когда ключи партнёра видны.
  Future<void> acceptedInvite(
    String groupId,
    String code,
    String fragment,
  ) async {
    final q = Uri.splitQueryString(fragment);
    if (q['s'] == null || q['f'] == null) return;
    keys.inviteSecrets['accepted:$groupId'] = jsonEncode({
      'code': code,
      's': q['s'],
      'f': q['f'],
    });
    await store.save(keys);
  }

  // --- синхронизация пары ---

  Future<PairE2EStatus> syncGroup(String groupId) async {
    if (_keys == null) {
      status.value = {...status.value, groupId: PairE2EStatus.needsRestore};
      return PairE2EStatus.needsRestore;
    }
    final keysBefore = keys.pairKeys.length;
    final members = await backend.members(groupId);
    _members[groupId] = members;
    final lists = <String, DeviceList>{};
    final per = <PairE2EStatus>[];

    final own = await backend.identity(uid);
    if (own != null &&
        bytesEqual(own.accountKey, keys.account.publicKey) &&
        _verifies(own.devices, own.accountKey, uid, 0)) {
      lists[uid] = own.devices;
    }

    for (final p in members.where((m) => m != uid)) {
      IdentityRecord? rec;
      try {
        rec = await backend.identity(p);
      } on FormatException {
        per.add(PairE2EStatus.tampered);
        continue;
      }
      if (rec == null) {
        per.add(PairE2EStatus.waitingPartner);
        continue;
      }
      final peer = keys.peers[p];
      final sameKey =
          peer != null && bytesEqual(peer.accountKey, rec.accountKey);
      if (!_verifies(
        rec.devices,
        rec.accountKey,
        p,
        sameKey ? peer.seenVersion : 0,
      )) {
        per.add(PairE2EStatus.tampered);
        continue;
      }
      if (peer == null) {
        keys.peers[p] = PeerState(
          accountKey: rec.accountKey,
          seenVersion: rec.devices.version,
        );
      } else if (!sameKey) {
        peer
          ..accountKey = rec.accountKey
          ..seenVersion = rec.devices.version
          ..verified = false
          ..keyChanged = true;
      } else {
        peer.seenVersion = rec.devices.version;
      }
      lists[p] = rec.devices;
    }

    if (await _checkAcceptedInvite(groupId, lists)) {
      per.add(PairE2EStatus.tampered);
    }
    final before = keys.groupMembers[groupId];
    if (before != null && before.any((m) => !members.contains(m))) {
      keys.rotateNeeded.add(groupId); // ушедший не читает новое (§6.5)
    }
    keys.groupMembers[groupId] = List.of(members);

    await _receiveGrants(groupId, lists, per);
    await _createKeyIfFirst(groupId, members, lists);
    await _rotateIfNeeded(groupId, members);
    if (keys.pairKeys.length != keysBefore) await _uploadBackup();
    await _grantAll(groupId, lists);
    await _handshakes(groupId, lists, per);
    await store.save(keys);

    final s = _aggregate(groupId, members, per);
    status.value = {...status.value, groupId: s};
    return s;
  }

  /// true — отпечаток из ссылки не совпал с ключом партнёра (подмена).
  Future<bool> _checkAcceptedInvite(
    String groupId,
    Map<String, DeviceList> lists,
  ) async {
    final raw = keys.inviteSecrets['accepted:$groupId'];
    if (raw == null) return false;
    final inviter = lists.keys.where((u) => u != uid).toList();
    if (inviter.length != 1) return false;
    final p = inviter.single;
    final a = jsonDecode(raw) as Map<String, dynamic>;
    final peer = keys.peers[p]!;
    if (!bytesEqual(
      accountFingerprint(crypto, peer.accountKey),
      unb64(a['f'] as String),
    )) {
      peer
        ..verified = false
        ..tampered = true;
      keys.inviteSecrets.remove('accepted:$groupId');
      return true;
    }
    peer
      ..verified = true
      ..keyChanged = false
      ..tampered = false;
    final secret = crypto.keyFromBytes(unb64(a['s'] as String));
    final tag = InviteProof.make(crypto, secret, keys.account.publicKey);
    secret.dispose();
    keys.inviteSecrets.remove('accepted:$groupId');
    await backend.postHandshake(
      groupId,
      uid,
      'invite:${a['code']}',
      'invite_proof',
      {'code': a['code'], 'mac': b64(tag)},
    );
    return false;
  }

  Future<void> _receiveGrants(
    String groupId,
    Map<String, DeviceList> lists,
    List<PairE2EStatus> per,
  ) async {
    for (final g in await backend.grantsTo(uid, keys.device.id)) {
      if (g.groupId != groupId ||
          keys.pairKeys.containsKey('$groupId:${g.epoch}')) {
        continue;
      }
      final senders = lists[g.fromUser];
      if (senders == null) continue;
      try {
        final k = g.open(crypto, keys.device, senders);
        keys.pairKeys[k.keyId] = k;
      } on E2EVerifyError {
        per.add(PairE2EStatus.tampered);
      }
    }
  }

  Future<void> _createKeyIfFirst(
    String groupId,
    List<String> members,
    Map<String, DeviceList> lists,
  ) async {
    if (keys.currentKey(groupId) != null || members.isEmpty) return;
    // Пара с пустым местом (человек в армии): ключ заводит единственный
    // участник — написанное до возвращения партнёр прочтёт, получив ключ.
    // Иначе ключ создаёт участник с наименьшим uid, и только когда ключи
    // опубликованы у всех: иначе двое могли бы создать разные эпохи 1.
    if (members.any((m) => !lists.containsKey(m))) return;
    if ((members.toList()..sort()).first != uid) return;
    final k = PairKey(groupId, 1, crypto.symmetricKey());
    keys.pairKeys[k.keyId] = k;
  }

  /// Новая эпоха ключа пары (§6.5). Создаёт её участник с наименьшим uid —
  /// иначе двое создали бы разные эпохи с одним номером; остальные просят.
  Future<void> _rotateIfNeeded(String groupId, List<String> members) async {
    if (!keys.rotateNeeded.contains(groupId)) return;
    final cur = keys.currentKey(groupId);
    if (cur == null) {
      keys.rotateNeeded.remove(groupId);
      return;
    }
    keys.rotateNeeded.remove(groupId);
    if ((members.toList()..sort()).first == uid) {
      final k = PairKey(groupId, cur.epoch + 1, crypto.symmetricKey());
      keys.pairKeys[k.keyId] = k;
    } else {
      await backend.postHandshake(
        groupId,
        uid,
        'rotate:${cur.epoch}',
        'rotate_request',
        {'epoch': cur.epoch},
      );
    }
  }

  Future<void> _grantAll(String groupId, Map<String, DeviceList> lists) async {
    final mine = keys.pairKeys.values
        .where((k) => k.groupId == groupId)
        .toList();
    if (mine.isEmpty) return;
    for (final e in lists.entries) {
      // Помеченному как подмена ключи не выдаём, пока сверка не подтвердит.
      if (e.key != uid && (keys.peers[e.key]?.tampered ?? false)) continue;
      for (final d in e.value.devices) {
        if (d.kind != DeviceKind.full || d.id == keys.device.id) continue;
        for (final k in mine) {
          final tag = '${k.keyId}|${d.id}';
          if (keys.granted.contains(tag)) continue;
          await backend.putGrant(
            PairKeyGrant.issue(crypto, k, d, uid, keys.device),
            e.key,
          );
          keys.granted.add(tag);
        }
      }
    }
  }

  PairE2EStatus _aggregate(
    String groupId,
    List<String> members,
    List<PairE2EStatus> per,
  ) {
    if (per.contains(PairE2EStatus.tampered)) return PairE2EStatus.tampered;
    if (per.contains(PairE2EStatus.waitingPartner) || members.length < 2) {
      return PairE2EStatus.waitingPartner;
    }
    final peers = [
      for (final m in members)
        if (m != uid) keys.peers[m],
    ];
    if (peers.any((p) => p?.tampered ?? false)) return PairE2EStatus.tampered;
    if (keys.currentKey(groupId) == null) return PairE2EStatus.waitingKey;
    if (peers.any((p) => p?.keyChanged ?? false)) {
      return PairE2EStatus.keyChanged;
    }
    if (peers.any((p) => !(p?.verified ?? false))) {
      return PairE2EStatus.unverified;
    }
    return PairE2EStatus.verified;
  }

  // --- подтверждения и сверка ---

  Future<void> _handshakes(
    String groupId,
    Map<String, DeviceList> lists,
    List<PairE2EStatus> per,
  ) async {
    for (final m in await backend.handshakes(groupId)) {
      if (m.fromUid == uid || _seenHandshakes.contains(m.id)) continue;
      final peer = keys.peers[m.fromUid];
      // Ключей автора ещё не видели — разберём при следующей синхронизации.
      if (peer == null) continue;
      _seenHandshakes.add(m.id);
      if (m.kind.startsWith('sas_') &&
          DateTime.now().difference(m.created) > sasTtl) {
        continue;
      }
      switch (m.kind) {
        case 'invite_proof':
          final secret = keys.inviteSecrets[m.data['code']];
          if (secret == null) break;
          final key = crypto.keyFromBytes(unb64(secret));
          final ok = InviteProof.valid(
            crypto,
            key,
            peer.accountKey,
            unb64(m.data['mac'] as String),
          );
          key.dispose();
          keys.inviteSecrets.remove(m.data['code']);
          if (ok) {
            peer
              ..verified = true
              ..keyChanged = false
              ..tampered = false;
          } else {
            peer
              ..verified = false
              ..tampered = true;
            per.add(PairE2EStatus.tampered);
          }
        case 'sas_start' when m.data['to'] == uid:
          // Оба нажали «Начать» (UX_AUDIT A10): сверка должна быть одна.
          // Ведёт тот, чей id меньше; второй сам принимает его зов.
          final mine = sas.value;
          final crossed = mine is SasWaiting &&
              mine.started &&
              mine.partnerUid == m.fromUid &&
              _initiators.containsKey(mine.session);
          if (crossed && uid.compareTo(m.fromUid) < 0) break;
          if (crossed) _dropSas(mine.session);
          _responders[m.session] = SasResponder(
            crypto,
            myAccount: keys.account.publicKey,
            theirAccount: peer.accountKey,
            commitment: unb64(m.data['commitment'] as String),
          );
          sas.value = SasIncoming(groupId, m.fromUid, m.session);
          if (crossed) await sasAccept();
        case 'sas_accept':
          final ini = _initiators.remove(m.session);
          if (ini == null) {
            // Мы эту сверку уже забыли (перезапуск) — скажем партнёру, а не
            // оставим его ждать.
            await _tellLost(groupId, m.session);
            break;
          }
          try {
            final (reveal, code) = ini.onAccept(
              unb64(m.data['ephemeral'] as String),
            );
            await backend.postHandshake(groupId, uid, m.session, 'sas_reveal', {
              'ephemeral': b64(reveal),
            });
            _sasTimer?.cancel(); // эмодзи пришли — больше не ждём
            sas.value = SasShowCode(groupId, m.fromUid, m.session, code);
          } on E2EVerifyError {
            sas.value = SasFinished(
              groupId,
              m.fromUid,
              m.session,
              match: false,
            );
          } finally {
            ini.dispose();
          }
        case 'sas_reveal':
          final res = _responders.remove(m.session);
          if (res == null) {
            await _tellLost(groupId, m.session);
            break;
          }
          try {
            final code = res.onReveal(unb64(m.data['ephemeral'] as String));
            _sasTimer?.cancel(); // эмодзи пришли — больше не ждём
            sas.value = SasShowCode(groupId, m.fromUid, m.session, code);
          } on E2EVerifyError {
            sas.value = SasFinished(
              groupId,
              m.fromUid,
              m.session,
              match: false,
            );
          } finally {
            res.dispose();
          }
        case 'rotate_request':
          if ((m.data['epoch'] as int?) == keys.currentKey(groupId)?.epoch) {
            keys.rotateNeeded.add(groupId);
          }
        case 'sas_done':
          final cur = sas.value;
          if (cur != null &&
              cur.session == m.session &&
              m.data['match'] != true) {
            _dropSas(m.session);
            sas.value = SasFinished(
              groupId,
              m.fromUid,
              m.session,
              match: false,
            );
          }
        case 'sas_cancel':
          // Отмена — не «эмодзи не совпали» (UX_AUDIT A10): говорим как есть.
          final cur = sas.value;
          if (cur != null &&
              cur.session == m.session &&
              cur is! SasFinished &&
              cur is! SasStopped) {
            _dropSas(m.session);
            sas.value = SasStopped(
              groupId,
              m.fromUid,
              m.session,
              why: m.data['lost'] == true
                  ? SasStopWhy.lost
                  : SasStopWhy.partnerCancelled,
            );
          }
      }
    }
  }

  /// Начать сверку с [partnerUid]: дальше ход за его устройством.
  Future<void> sasStart(String groupId, String partnerUid) async {
    final peer = keys.peers[partnerUid];
    if (peer == null) throw StateError('ключей партнёра ещё нет');
    final session = b64(crypto.random(12));
    final ini = SasInitiator(
      crypto,
      myAccount: keys.account.publicKey,
      theirAccount: peer.accountKey,
    );
    _initiators[session] = ini;
    await backend.postHandshake(groupId, uid, session, 'sas_start', {
      'to': partnerUid,
      'commitment': b64(ini.commitment),
    });
    sas.value = SasWaiting(groupId, partnerUid, session);
    _armWait(session);
  }

  /// Ждём телефон партнёра не дольше [sasWait].
  void _armWait(String session) {
    _sasTimer?.cancel();
    _sasTimer = Timer(sasWait, () async {
      final cur = sas.value;
      if (cur is! SasWaiting || cur.session != session) return;
      _dropSas(session);
      sas.value = SasStopped(
        cur.groupId,
        cur.partnerUid,
        session,
        why: SasStopWhy.noAnswer,
      );
      try {
        await backend.postHandshake(
            cur.groupId, uid, session, 'sas_cancel', const {});
      } catch (e) {
        debugPrint('E2E: отмена просроченной сверки — $e');
      }
    });
  }

  /// Шаг сверки, которую мы не помним: партнёру — «потерялась».
  Future<void> _tellLost(String groupId, String session) async {
    try {
      await backend.postHandshake(
          groupId, uid, session, 'sas_cancel', const {'lost': true});
    } catch (e) {
      debugPrint('E2E: сверка $session потерялась, партнёру не сказали — $e');
    }
  }

  /// Принять входящую сверку.
  Future<void> sasAccept() async {
    final cur = sas.value;
    if (cur is! SasIncoming) return;
    final res = _responders[cur.session];
    if (res == null) return;
    await backend.postHandshake(cur.groupId, uid, cur.session, 'sas_accept', {
      'ephemeral': b64(res.ephemeral),
    });
    sas.value = SasWaiting(
      cur.groupId,
      cur.partnerUid,
      cur.session,
      started: false,
    );
    _armWait(cur.session);
  }

  /// Человек сравнил эмодзи голосом: [match] — совпали ли.
  Future<void> sasConfirm({required bool match}) async {
    final cur = sas.value;
    if (cur is! SasShowCode) return;
    if (match) {
      final peer = keys.peers[cur.partnerUid];
      if (peer != null) _markVerified(cur.groupId, peer);
      await store.save(keys);
      status.value = {
        ...status.value,
        cur.groupId: _aggregate(
          cur.groupId,
          _members[cur.groupId] ?? const [],
          const [],
        ),
      };
    }
    await backend.postHandshake(cur.groupId, uid, cur.session, 'sas_done', {
      'match': match,
    });
    sas.value = SasFinished(
      cur.groupId,
      cur.partnerUid,
      cur.session,
      match: match,
    );
  }

  Future<void> sasCancel() async {
    final cur = sas.value;
    if (cur == null) return;
    _dropSas(cur.session);
    sas.value = null;
    if (cur is! SasFinished && cur is! SasStopped) {
      await backend.postHandshake(
        cur.groupId,
        uid,
        cur.session,
        'sas_cancel',
        const {},
      );
    }
  }

  void _dropSas(String session) {
    _sasTimer?.cancel();
    _sasTimer = null;
    _initiators.remove(session)?.dispose();
    _responders.remove(session)?.dispose();
  }

  /// Партнёр подтверждён сверкой. Если до этого ключ сменился или была
  /// подмена, старый ключ пары мог уйти чужому устройству — новая эпоха.
  void _markVerified(String groupId, PeerState peer) {
    if (peer.keyChanged || peer.tampered) keys.rotateNeeded.add(groupId);
    peer
      ..verified = true
      ..keyChanged = false
      ..tampered = false;
  }

  // --- QR (§6.3) ---

  static const String _qrPrefix = 'tethered-verify:';

  /// Что показать в QR для сверки с [partnerUid]: полный отпечаток пары
  /// в том виде, как его видит это устройство. null — ключей партнёра нет.
  String? qrPayload(String partnerUid) {
    final peer = keys.peers[partnerUid];
    if (peer == null) return null;
    return _qrPrefix +
        b64(pairFingerprint(crypto, keys.account.publicKey, peer.accountKey));
  }

  /// Отсканирован QR партнёра. true — отпечатки совпали, партнёр проверен.
  Future<bool> verifyByQr(
    String groupId,
    String partnerUid,
    String scanned,
  ) async {
    final mine = qrPayload(partnerUid);
    if (mine == null || !scanned.startsWith(_qrPrefix)) return false;
    final ok = bytesEqual(utf8Bytes(mine), utf8Bytes(scanned.trim()));
    final peer = keys.peers[partnerUid]!;
    if (ok) {
      _markVerified(groupId, peer);
    } else {
      peer
        ..verified = false
        ..tampered = true;
    }
    await store.save(keys);
    status.value = {
      ...status.value,
      groupId: _aggregate(groupId, _members[groupId] ?? const [], const []),
    };
    return ok;
  }

  /// Ключи пары для конверта (S9). Ждём восстановления — ключей нет вовсе:
  /// писать нечем, читать тоже.
  @override
  PairKey? keyFor(String keyId) => _keys?.keyFor(keyId);
  @override
  PairKey? currentKey(String groupId) => _keys?.currentKey(groupId);
  @override
  String? groupWith(Set<String> members) => _keys?.groupWith(members);
}
