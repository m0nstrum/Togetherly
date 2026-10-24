/// [E2EBackend] на коллекциях PocketBase сервера форка
/// (server/internal/migrations/e2e.go).
library;

import 'dart:typed_data';

import 'package:pocketbase/pocketbase.dart';

import 'crypto.dart';
import 'devices.dart';
import 'e2e_service.dart';

class PbE2EBackend implements E2EBackend {
  PbE2EBackend(this._pb);

  final PocketBase _pb;

  String _q(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';

  Future<RecordModel?> _identityRecord(String uid) async {
    final r = await _pb
        .collection('e2e_identities')
        .getList(perPage: 1, filter: 'user_uid = ${_q(uid)}');
    return r.items.isEmpty ? null : r.items.first;
  }

  @override
  Future<IdentityRecord?> identity(String uid) async {
    final r = await _identityRecord(uid);
    if (r == null) return null;
    final devices = r.data['devices'];
    if (devices is! Map) {
      throw const FormatException('список устройств не JSON');
    }
    return IdentityRecord(
      accountKey: unb64(r.getStringValue('account_key')),
      devices: DeviceList.fromJson(devices.cast<String, dynamic>()),
    );
  }

  @override
  Future<void> putIdentity(
    String uid,
    Uint8List accountKey,
    DeviceList list,
  ) async {
    final body = {
      'user_uid': uid,
      'account_key': b64(accountKey),
      'version': list.version,
      'devices': list.toJson(),
    };
    final old = await _identityRecord(uid);
    if (old == null) {
      await _pb.collection('e2e_identities').create(body: body);
    } else {
      await _pb.collection('e2e_identities').update(old.id, body: body);
    }
  }

  @override
  Future<List<String>> members(String groupId) async {
    final g = await _pb.collection('groups').getOne(groupId);
    final m = g.data['members'];
    return m is List ? [for (final x in m) x.toString()] : const [];
  }

  @override
  Future<List<PairKeyGrant>> grantsTo(String uid, String deviceId) async {
    final items = await _pb
        .collection('e2e_grants')
        .getFullList(
          filter: 'to_uid = ${_q(uid)} && to_device = ${_q(deviceId)}',
        );
    final out = <PairKeyGrant>[];
    for (final r in items) {
      final d = r.data['data'];
      if (d is! Map) continue;
      try {
        out.add(PairKeyGrant.fromJson(d.cast<String, dynamic>()));
      } on Object {
        // Битая запись — не наша забота: ключ из неё всё равно не открылся бы.
      }
    }
    return out;
  }

  @override
  Future<void> putGrant(PairKeyGrant g, String toUid) async {
    try {
      await _pb
          .collection('e2e_grants')
          .create(
            body: {
              'group_id': g.groupId,
              'user_uid': g.fromUser,
              'to_uid': toUid,
              'to_device': g.toDevice,
              'epoch': g.epoch,
              'data': g.toJson(),
            },
          );
    } on ClientException catch (e) {
      // Уникальность (группа, эпоха, устройство): ключ уже выдан.
      if (e.statusCode != 400 ||
          !e.toString().contains('validation_not_unique')) {
        rethrow;
      }
    }
  }

  @override
  Future<void> postHandshake(
    String groupId,
    String fromUid,
    String session,
    String kind,
    Map<String, dynamic> data,
  ) => _pb
      .collection('e2e_handshake')
      .create(
        body: {
          'group_id': groupId,
          'user_uid': fromUid,
          'session': session,
          'kind': kind,
          'data': data,
        },
      );

  @override
  Future<List<HandshakeMsg>> handshakes(String groupId) async {
    final now = DateTime.now().toUtc();
    final sasSince = now
        .subtract(E2EService.sasTtl)
        .toIso8601String()
        .replaceFirst('T', ' ');
    final inviteSince = now
        .subtract(const Duration(days: 30))
        .toIso8601String()
        .replaceFirst('T', ' ');
    final items = await _pb
        .collection('e2e_handshake')
        .getFullList(
          filter: _pb.filter(
            'group_id = {:g} && ((kind = "invite_proof" && created >= {:invite}) || '
            '(kind != "invite_proof" && created >= {:sas}))',
            {'g': groupId, 'invite': inviteSince, 'sas': sasSince},
          ),
          sort: 'created',
        );
    return [
      for (final r in items)
        HandshakeMsg(
          id: r.id,
          fromUid: r.getStringValue('user_uid'),
          session: r.getStringValue('session'),
          kind: r.getStringValue('kind'),
          data: (r.data['data'] as Map?)?.cast<String, dynamic>() ?? const {},
          created:
              DateTime.tryParse(r.getStringValue('created'))?.toLocal() ??
              DateTime.now(),
        ),
    ];
  }

  @override
  Future<Map<String, dynamic>?> backup(String uid) async {
    final r = await _pb
        .collection('e2e_backups')
        .getList(perPage: 1, filter: 'user_uid = ${_q(uid)}');
    if (r.items.isEmpty) return null;
    final d = r.items.first.data['data'];
    return d is Map ? d.cast<String, dynamic>() : null;
  }

  @override
  Future<void> putBackup(String uid, Map<String, dynamic> data) async {
    final r = await _pb
        .collection('e2e_backups')
        .getList(perPage: 1, filter: 'user_uid = ${_q(uid)}');
    final body = {'user_uid': uid, 'data': data};
    if (r.items.isEmpty) {
      await _pb.collection('e2e_backups').create(body: body);
    } else {
      await _pb.collection('e2e_backups').update(r.items.first.id, body: body);
    }
  }
}
