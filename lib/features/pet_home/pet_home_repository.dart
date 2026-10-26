import 'dart:math';
import 'package:pocketbase/pocketbase.dart';
import '../../fork/e2e/fork_e2e.dart';
import '../../fork/e2e/record_codec.dart';
import '../../services/pocketbase_service.dart';
import 'pet_home_model.dart';

class PetHomeSnapshot {
  const PetHomeSnapshot(this.revision, this.home);
  final int revision;
  final PetHome home;
}

/// Encrypted read/modify/CAS with conflict rebasing and lost-response dedup.
/// Cosmetic credit is not money; all game rules run on the trusted clients.
class PetHomeRepository {
  PetHomeRepository({required this.pb, required this.codec, required this.uid});
  final PocketBase pb;
  final Future<RecordCodec?> Function() codec;
  final String Function() uid;
  static PetHomeRepository production() => PetHomeRepository(
    pb: PocketBaseService().pb,
    codec: ForkE2E.codec,
    uid: () => PocketBaseService().userId ?? '',
  );

  String _path(String group) => '/api/pet-home/${Uri.encodeComponent(group)}';

  Future<PetHomeSnapshot> _decode(
    String group,
    Map<String, dynamic> raw,
  ) async {
    if (raw['group_id'] != group || raw['revision'] is! int) {
      throw const FormatException('Invalid home response');
    }
    final revision = raw['revision'] as int;
    if (revision == 0 && raw['state'] == null) {
      return PetHomeSnapshot(0, PetHome());
    }
    if (revision < 1 || !isSealedValue(raw['state'])) {
      throw const FormatException('Unencrypted home response');
    }
    final c = await codec();
    if (c == null) throw E2ENoKeyError('pet_homes');
    final decoded = c.decode('pet_homes', raw);
    final state = decoded['state'];
    if (state is! Map) throw E2ENoKeyError('pet_homes');
    if (state['group'] != group || state['home'] is! Map) {
      throw const FormatException('Home belongs to another group');
    }
    return PetHomeSnapshot(revision, PetHome.fromJson(state['home'] as Map));
  }

  Future<PetHomeSnapshot> load(String group) async {
    final raw = await pb.send<Map<String, dynamic>>(_path(group));
    return _decode(group, raw);
  }

  Future<PetHomeSnapshot> change(
    String group,
    void Function(PetHome) mutate, {
    int xp = 0,
    String? operation,
  }) async {
    final actor = uid();
    void checkOwner() {
      if (actor.isEmpty || uid() != actor) throw StateError('Session changed');
    }

    checkOwner();
    final random = Random.secure();
    final op =
        operation ??
        List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
    for (var attempt = 0; attempt < 6; attempt++) {
      checkOwner();
      final snapshot = await load(group);
      checkOwner();
      if (snapshot.home.operations.contains(op)) return snapshot;
      final next = snapshot.home.copy()..creditActivity(xp);
      mutate(next);
      next.remember(op);
      final c = await codec();
      checkOwner();
      if (c == null) throw E2ENoKeyError('pet_homes');
      final body = c.encode('pet_homes', group, group, {
        'group_id': group,
        'state': {'group': group, 'home': next.toJson()},
      });
      if (!isSealedValue(body['state'])) throw E2ENoKeyError('pet_homes');
      try {
        final raw = await pb.send<Map<String, dynamic>>(
          _path(group),
          method: 'POST',
          body: {
            'revision': snapshot.revision,
            'operation': op,
            'state': body['state'],
          },
        );
        checkOwner();
        return await _decode(group, raw);
      } on ClientException catch (error) {
        checkOwner();
        if (error.statusCode == 409) continue;
        // A dropped response may already have committed. Confirm before
        // reporting failure, without issuing the action again.
        if (error.statusCode == 0) {
          try {
            final confirmed = await load(group);
            checkOwner();
            if (confirmed.home.operations.contains(op)) return confirmed;
          } on Object {
            checkOwner();
          }
        }
        rethrow;
      }
    }
    throw const PetHomeBusy();
  }
}

class PetHomeBusy implements Exception {
  const PetHomeBusy();
}
