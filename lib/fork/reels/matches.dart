/// Persistent mutual reactions. Clip identifiers and reactions are sealed by PB's E2E client.
library;

import '../e2e/crypto.dart' show utf8Bytes;
import 'package:pocketbase/pocketbase.dart';
import '../../models/reel_link.dart';
import '../../services/pocketbase_service.dart';
import '../e2e/fork_e2e.dart';
import '../e2e/record_codec.dart';

const forkReelReactions = {'❤️', '😂', '😮', '😢', '🔥', '👍'};

class ForkReelMatch {
  ForkReelMatch(this.id, this.link, this.reaction, this.at);
  final String id;
  final ReelLink? link;
  final String reaction;
  final DateTime? at;
  bool get locked => link == null;
  factory ForkReelMatch.fromRecord(RecordModel record) {
    final state = record.data['state'];
    if (state is! Map) return ForkReelMatch(record.id, null, '', null);
    final clip = state['clip'], reaction = state['reaction'], at = state['at'];
    final link = clip is String ? ReelLink.parse(clip) : null;
    DateTime? time;
    if (at is int && at > 0 && at < 8640000000000000) {
      time = DateTime.fromMillisecondsSinceEpoch(at);
    }
    return ForkReelMatch(
      record.id,
      link,
      forkReelReactions.contains(reaction) ? reaction as String : '',
      time,
    );
  }
}

class ForkReelsMatches {
  ForkReelsMatches({required this.pb, required this.codec, required this.uid});
  final PocketBase pb;
  final Future<RecordCodec?> Function() codec;
  final String Function() uid;
  static const collection = 'fork_reels_matches';
  static final instance = ForkReelsMatches(
    pb: PocketBaseService().pb,
    codec: ForkE2E.codec,
    uid: () => PocketBaseService().userId ?? '',
  );

  Future<List<ForkReelMatch>> list(String group) async {
    final records = await pb
        .collection(collection)
        .getFullList(
          filter: pb.filter('group_id = {:group}', {'group': group}),
          sort: '-created',
        );
    return records.map(ForkReelMatch.fromRecord).toList();
  }

  Future<void> save(String group, String clip, String reaction) async {
    final link = ReelLink.parse(clip);
    final me = uid();
    if (group.isEmpty ||
        me.isEmpty ||
        link == null ||
        !forkReelReactions.contains(reaction)) {
      throw ArgumentError('Invalid reel match');
    }
    final c = await codec();
    final key = c?.keys.currentKey(group);
    if (c?.crypto == null || key == null) {
      throw StateError('Pair key unavailable');
    }
    // Scan all decrypted pages so a pair-key rotation does not duplicate a clip.
    if ((await list(group)).any((match) => match.link?.key == link.key)) return;
    final tag = c!.crypto!
        .hash(utf8Bytes('reels-match-v1/$group/${link.key}'), key: key.key)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    try {
      await pb
          .collection(collection)
          .create(
            body: {
              'group_id': group,
              'author_uid': me,
              'match_tag': tag,
              'state': {
                'clip': link.key,
                'reaction': reaction,
                'at': DateTime.now().millisecondsSinceEpoch,
              },
            },
          );
    } on ClientException catch (error) {
      // Both phones may save simultaneously. A unique-index rejection succeeds
      // only if the other phone's authenticated record is actually readable.
      if (error.statusCode != 400 ||
          !(await list(group)).any((match) => match.link?.key == link.key)) {
        rethrow;
      }
    }
  }

  Future<void> remove(String id) => pb.collection(collection).delete(id);
}
