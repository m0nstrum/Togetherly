// fork: «сервер» в памяти для тестов обмена ключами E2E.
import 'dart:typed_data';

import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/device_link.dart';
import 'package:love_app/fork/e2e/devices.dart';
import 'package:love_app/fork/e2e/e2e_service.dart';

const alice = 'alice', bob = 'bob', gid = 'g1';

/// Общая база «сервера».
class ServerDb {
  final identities = <String, Map<String, dynamic>>{};
  final grants = <String, (PairKeyGrant, String)>{};
  final handshakes = <HandshakeMsg>[];
  final backups = <String, Map<String, dynamic>>{};
  final links = <String, Map<String, dynamic>>{};
  final members = <String, List<String>>{
    gid: [alice, bob],
  };
  var nextId = 0;

  /// Подмена: что отдать [viewer], когда он спрашивает ключи [uid].
  Map<String, dynamic>? Function(String viewer, String uid)? forge;
}

/// Как сервер выглядит для одного клиента.
class FakeBackend implements E2EBackend {
  FakeBackend(this.db, this.viewer);
  final ServerDb db;
  final String viewer;

  @override
  Future<IdentityRecord?> identity(String uid) async {
    final j = db.forge?.call(viewer, uid) ?? db.identities[uid];
    if (j == null) return null;
    return IdentityRecord(
      accountKey: unb64(j['ak'] as String),
      devices: DeviceList.fromJson(
        (j['devices'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  @override
  Future<void> putIdentity(String uid, Uint8List ak, DeviceList list) async {
    final old = db.identities[uid];
    if (old != null &&
        (old['devices'] as Map)['version'] as int >= list.version) {
      throw StateError('сервер: версия только вперёд');
    }
    db.identities[uid] = {'ak': b64(ak), 'devices': list.toJson()};
  }

  @override
  Future<List<String>> members(String groupId) async => db.members[groupId]!;

  @override
  Future<List<PairKeyGrant>> grantsTo(String uid, String deviceId) async => [
    for (final (g, to) in db.grants.values)
      if (to == uid && g.toDevice == deviceId) g,
  ];

  @override
  Future<void> putGrant(PairKeyGrant g, String toUid) async {
    db.grants.putIfAbsent(
      '${g.groupId}|${g.epoch}|${g.toDevice}',
      () => (g, toUid),
    );
  }

  @override
  Future<void> postHandshake(
    String groupId,
    String fromUid,
    String session,
    String kind,
    Map<String, dynamic> data,
  ) async {
    db.handshakes.add(
      HandshakeMsg(
        id: '${db.nextId++}',
        fromUid: fromUid,
        session: session,
        kind: kind,
        data: data,
        created: DateTime.now(),
      ),
    );
  }

  @override
  Future<List<HandshakeMsg>> handshakes(String groupId) async =>
      List.of(db.handshakes);

  @override
  Future<Map<String, dynamic>?> backup(String uid) async => db.backups[uid];

  @override
  Future<void> putBackup(String uid, Map<String, dynamic> data) async =>
      db.backups[uid] = data;

  @override
  Future<void> putLink(Map<String, dynamic> body) async {
    if (body['user_uid'] != viewer) throw StateError('сервер: чужая привязка');
    db.links[body['id'] as String] = {...body, 'payload': ''};
  }

  @override
  Future<LinkRecord?> link(String id) async {
    final j = db.links[id];
    if (j == null || j['user_uid'] != viewer) return null;
    return LinkRecord(
      id: id,
      uid: j['user_uid'] as String,
      device: DeviceEntry.fromJson((j['device'] as Map).cast<String, dynamic>()),
      mac: unb64(j['mac'] as String),
      payload: j['payload'] as String? ?? '',
    );
  }

  @override
  Future<void> putLinkPayload(String id, String payload) async {
    final j = db.links[id];
    if (j == null || j['user_uid'] != viewer) throw StateError('сервер: нет привязки');
    j['payload'] = payload;
  }

  @override
  Future<void> deleteLink(String id) async => db.links.remove(id);
}
