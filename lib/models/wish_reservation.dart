import 'package:pocketbase/pocketbase.dart';

/// «Дарю»: кто-то из пары взял вещь из общего списка на себя.
///
/// Отметка живёт отдельной записью, а не полем желания. Правило чтения
/// `wishes` отдаёт запись целиком любому участнику группы, поэтому поле
/// внутри желания автор увидел бы в ту же секунду — и сюрприза не осталось бы.
/// У коллекции `wish_reservations` правило чтения `uid = @request.auth.id`:
/// записи просто не существует для всех, кроме того, кто дарит.
class WishReservation {
  const WishReservation({
    required this.id,
    required this.wishId,
    required this.uid,
    required this.createdAt,
    this.until,
  });

  final String id;

  /// Какое желание взято.
  final String wishId;

  /// Кто дарит. Он же единственный, кто видит эту запись.
  final String uid;

  final DateTime createdAt;

  /// Срок «Дарю» (docs/WISHLIST.md): к этому дню даритель обещал себе
  /// успеть. Null — без срока. Видит только дарящий.
  final DateTime? until;

  /// Срок прошёл: день срока позади.
  bool overdue(DateTime now) {
    final u = until;
    if (u == null) return false;
    return DateTime(u.year, u.month, u.day)
        .isBefore(DateTime(now.year, now.month, now.day));
  }

  WishReservation withUntil(DateTime? at) => WishReservation(
        id: id,
        wishId: wishId,
        uid: uid,
        createdAt: createdAt,
        until: at == null ? null : DateTime(at.year, at.month, at.day),
      );

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _date(Object? raw) {
    final text = (raw ?? '').toString();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  factory WishReservation.fromPb(RecordModel rec) => WishReservation(
        id: rec.id,
        wishId: rec.getStringValue('wish_id'),
        uid: rec.getStringValue('uid'),
        createdAt: _date(rec.getStringValue('created')) ?? DateTime.now(),
        until: _date(rec.getStringValue('until')),
      );

  factory WishReservation.fromMap(Map<String, dynamic> map) => WishReservation(
        id: (map['id'] ?? '') as String,
        wishId: (map['wish_id'] ?? '') as String,
        uid: (map['uid'] ?? '') as String,
        createdAt: _date(map['created']) ?? DateTime.now(),
        until: _date(map['until']),
      );

  Map<String, dynamic> toMap({required String groupId}) => {
        'id': id,
        'group_id': groupId,
        'wish_id': wishId,
        'uid': uid,
        'created': createdAt.toUtc().toIso8601String(),
        if (until != null) 'until': _day(until!),
      };
}

/// Какие вещи из списка уже взяты на себя.
///
/// Карточке нужен ответ на один вопрос, а не сами записи. Повторы схлопываются:
/// двойное нажатие в офлайне кладёт в очередь две записи на одну вещь.
Set<String> reservedWishIds(List<WishReservation> list) =>
    {for (final r in list) if (r.wishId.isNotEmpty) r.wishId};
