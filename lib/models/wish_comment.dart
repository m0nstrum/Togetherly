import 'package:pocketbase/pocketbase.dart';

/// Комментарий к желанию «Хочу с тобой» (docs/WISHLIST.md): «давай в
/// пятницу?», «вот в этом размере». Текст — шифр ключа пары; править и
/// удалять может только тот, кто написал.
class WishComment {
  const WishComment({
    required this.id,
    required this.wishId,
    required this.authorUid,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String wishId;
  final String authorUid;
  final String text;
  final DateTime createdAt;

  static DateTime? _date(Object? raw) {
    final s = (raw ?? '').toString();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  factory WishComment.fromPb(RecordModel rec) =>
      WishComment.fromMap({...rec.data, 'id': rec.id});

  factory WishComment.fromMap(Map<String, dynamic> map) => WishComment(
    id: (map['id'] ?? '').toString(),
    wishId: (map['wish_id'] ?? '').toString(),
    authorUid: (map['author_uid'] ?? '').toString(),
    text: (map['text'] ?? '').toString(),
    createdAt: _date(map['created']) ?? DateTime.now(),
  );

  Map<String, dynamic> toMap({required String groupId}) => {
    'id': id,
    'group_id': groupId,
    'wish_id': wishId,
    'author_uid': authorUid,
    'text': text,
    'created': createdAt.toUtc().toIso8601String(),
  };
}

/// Сколько комментариев у каждого желания — цифра на карточке.
Map<String, int> wishCommentCounts(Iterable<WishComment> all) {
  final out = <String, int>{};
  for (final c in all) {
    if (c.wishId.isEmpty) continue;
    out[c.wishId] = (out[c.wishId] ?? 0) + 1;
  }
  return out;
}
