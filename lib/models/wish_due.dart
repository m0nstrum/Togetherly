/// «Когда» у желания (docs/WISHLIST.md): точная дата, месяц или
/// «когда-нибудь». В записи — строка `2026-11-14`, `2026-11` или `someday`,
/// шифром ключа пары (поле `wishes.due`).
enum WishDueKind { none, date, month, someday }

class WishDue {
  const WishDue._(this.kind, this.year, this.month, this.day);

  static const WishDue none = WishDue._(WishDueKind.none, 0, 0, 0);
  static const WishDue someday = WishDue._(WishDueKind.someday, 0, 0, 0);

  factory WishDue.date(DateTime d) =>
      WishDue._(WishDueKind.date, d.year, d.month, d.day);

  factory WishDue.month(int year, int month) =>
      WishDue._(WishDueKind.month, year, month, 0);

  final WishDueKind kind;
  final int year;
  final int month;
  final int day;

  bool get isSet => kind != WishDueKind.none;

  /// День, к которому привязаны напоминания и календарь: у месяца — первое
  /// число. Null у «когда-нибудь» и пустого.
  DateTime? get anchor => switch (kind) {
        WishDueKind.date => DateTime(year, month, day),
        WishDueKind.month => DateTime(year, month),
        _ => null,
      };

  static final RegExp _dateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _monthRe = RegExp(r'^(\d{4})-(\d{2})$');

  /// Непонятная строка — «не задано»: запись от более новой сборки не должна
  /// ронять список.
  static WishDue parse(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return none;
    if (s == 'someday') return someday;
    final d = _dateRe.firstMatch(s);
    if (d != null) {
      final y = int.parse(d[1]!), m = int.parse(d[2]!), day = int.parse(d[3]!);
      final dt = DateTime(y, m, day);
      if (m < 1 || m > 12 || dt.month != m || dt.day != day) return none;
      return WishDue._(WishDueKind.date, y, m, day);
    }
    final mo = _monthRe.firstMatch(s);
    if (mo != null) {
      final y = int.parse(mo[1]!), m = int.parse(mo[2]!);
      if (m < 1 || m > 12) return none;
      return WishDue._(WishDueKind.month, y, m, 0);
    }
    return none;
  }

  String encode() {
    String two(int v) => v.toString().padLeft(2, '0');
    return switch (kind) {
      WishDueKind.none => '',
      WishDueKind.someday => 'someday',
      WishDueKind.month => '${year.toString().padLeft(4, '0')}-${two(month)}',
      WishDueKind.date =>
        '${year.toString().padLeft(4, '0')}-${two(month)}-${two(day)}',
    };
  }

  /// Срок прошёл: дата позади или месяц кончился.
  bool isPast(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (kind) {
      WishDueKind.date => DateTime(year, month, day).isBefore(today),
      WishDueKind.month => !DateTime(year, month + 1).isAfter(today),
      _ => false,
    };
  }

  /// Подпись на карточке: «14 ноября», «ноябрь 2026», «когда-нибудь».
  /// [genitive] и [nominative] — названия месяцев текущего языка.
  String label({
    required List<String> genitive,
    required List<String> nominative,
    required String somedayLabel,
    DateTime? now,
  }) {
    final thisYear = (now ?? DateTime.now()).year;
    return switch (kind) {
      WishDueKind.none => '',
      WishDueKind.someday => somedayLabel,
      WishDueKind.date => year == thisYear
          ? '$day ${genitive[month - 1]}'
          : '$day ${genitive[month - 1]} $year',
      WishDueKind.month => year == thisYear
          ? nominative[month - 1]
          : '${nominative[month - 1]} $year',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is WishDue &&
      other.kind == kind &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(kind, year, month, day);
}
