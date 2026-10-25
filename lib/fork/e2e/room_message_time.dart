/// Local time, with a date for earlier days. Missing timestamps stay missing.
String forkRoomMessageTime(int milliseconds, {DateTime? now}) {
  if (milliseconds <= 0 || milliseconds > 8640000000000000) return '';
  final at = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  final today = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(at.hour)}:${two(at.minute)}';
  if (at.year == today.year && at.month == today.month && at.day == today.day)
    return time;
  final year = at.year == today.year ? '' : '.${at.year}';
  return '${two(at.day)}.${two(at.month)}$year $time';
}
