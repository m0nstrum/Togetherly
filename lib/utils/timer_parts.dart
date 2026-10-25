/// Годы, месяцы, дни и время суток между двумя моментами — по календарю.
///
/// Одно правило на круглый и цифровой вид таймера на главной (BACKLOG D7):
/// разойдутся — круг и цифры покажут разное.
class TimerParts {
  const TimerParts({
    required this.years,
    required this.months,
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.totalDays,
  });

  static const zero = TimerParts(
    years: 0,
    months: 0,
    days: 0,
    hours: 0,
    minutes: 0,
    seconds: 0,
    totalDays: 0,
  );

  final int years;
  final int months;
  final int days;
  final int hours;
  final int minutes;
  final int seconds;

  /// Полных суток всего — «1234 дня вместе».
  final int totalDays;

  /// От [start] до [now]; у обратного отсчёта — от [now] до [start].
  factory TimerParts.of(DateTime start, DateTime now, {bool countdown = false}) {
    final from = countdown ? now : start;
    final to = countdown ? start : now;
    if (!to.isAfter(from)) return zero;

    // Целые месяцы — пока «from + N месяцев» не перешагнуло `to`. День
    // обрезается по длине месяца: 31 января + 1 месяц = 29 февраля. Прежний
    // счёт вычитанием давал тут −1 день (31.01 → 01.03).
    var total = (to.year - from.year) * 12 + to.month - from.month;
    var anchor = _addMonths(from, total);
    if (anchor.isAfter(to)) anchor = _addMonths(from, --total);
    // Дни — по календарю, а не по 24 часам: перевод часов их не сдвигает.
    var days = DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(anchor.year, anchor.month, anchor.day))
        .inDays;
    if (_timeOfDay(to) < _timeOfDay(anchor)) days--;
    final years = total ~/ 12;
    final months = total % 12;

    final diffMs = to.difference(from).inMilliseconds;
    return TimerParts(
      years: years,
      months: months,
      days: days,
      hours: (diffMs ~/ 3600000) % 24,
      minutes: (diffMs ~/ 60000) % 60,
      seconds: (diffMs ~/ 1000) % 60,
      totalDays: diffMs ~/ 86400000,
    );
  }

  static DateTime _addMonths(DateTime d, int n) {
    final m = d.month - 1 + n;
    final y = d.year + m ~/ 12;
    final month = m % 12 + 1;
    final last = DateTime(y, month + 1, 0).day;
    return DateTime(y, month, d.day > last ? last : d.day, d.hour, d.minute, d.second, d.millisecond);
  }

  static int _timeOfDay(DateTime d) =>
      ((d.hour * 60 + d.minute) * 60 + d.second) * 1000 + d.millisecond;

  /// «04:05:06».
  String get clock => [hours, minutes, seconds].map((v) => v.toString().padLeft(2, '0')).join(':');
}
