import '../../dict_strings.dart' show ruEn;

String forkLastSeen(int? milliseconds, {required String gender, bool entered = true, DateTime? now}) {
  if (milliseconds == null || milliseconds <= 0 || milliseconds > 8640000000000000) return '';
  final seen = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final yesterday = DateTime(current.year, current.month, current.day - 1);
  final day = DateTime(seen.year, seen.month, seen.day);
  final verb = entered
      ? switch (gender) { 'female' => 'заходила', 'male' => 'заходил', _ => 'заходил(а)' }
      : switch (gender) { 'female' => 'была', 'male' => 'был', _ => 'был(а)' };
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(seen.hour)}:${two(seen.minute)}';
  if (day == today) return ruEn('$verb в $time', 'last seen at $time');
  if (day == yesterday) return ruEn('$verb вчера в $time', 'last seen yesterday at $time');
  final year = seen.year == current.year ? '' : '.${seen.year}';
  final date = '${two(seen.day)}.${two(seen.month)}$year';
  return ruEn('$verb $date в $time', 'last seen $date at $time');
}
