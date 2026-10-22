/// Тексты и расчёты «Смотрим» (docs/fork/UX_AUDIT.md, V3, V12).
library;

import '../../dict_strings.dart' show ruEn;
import '../../services/watch_videos_service.dart';

/// Срок хранения своих роликов (V12): когда пропадёт и сколько осталось.
abstract final class ForkVideoExpiry {
  /// Дата удаления; null — срок неизвестен (ролик не из «Смотрим»).
  static DateTime? expiresAt(DateTime? created) =>
      created?.add(WatchVideosService.lifetime);

  /// Дней до удаления, не меньше нуля.
  static int daysLeft(DateTime? created, DateTime now) {
    final end = expiresAt(created);
    if (end == null) return -1;
    final left = end.difference(now);
    if (left.isNegative) return 0;
    return (left.inHours / 24).ceil();
  }

  static String _date(DateTime d) {
    const ru = [
      'янв',
      'фев',
      'мар',
      'апр',
      'мая',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    const en = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return ruEn('${d.day} ${ru[d.month - 1]}', '${en[d.month - 1]} ${d.day}');
  }

  /// Подпись на плитке: «Удалится 12 ноя» либо «Удалится завтра».
  static String tileLabel(DateTime? created, DateTime now) {
    final end = expiresAt(created);
    if (end == null) return '';
    final days = daysLeft(created, now);
    if (days <= 0) return ruEn('Удалится сегодня', 'Deletes today');
    if (days == 1) return ruEn('Удалится завтра', 'Deletes tomorrow');
    return ruEn('Удалится ${_date(end)}', 'Deletes ${_date(end)}');
  }

  /// Пояснение у плитки загрузки.
  static String uploadHint() {
    final d = WatchVideosService.lifetime.inDays;
    return ruEn(
      'Хранится $d дней, потом удаляется',
      'Kept for $d days, then deleted',
    );
  }
}

/// «Загружаю N МБ…» (V3).
String forkUploadingText(int bytes) {
  final mb = (bytes / (1024 * 1024))
      .clamp(0.1, 100000)
      .toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0);
  return ruEn('Загружаю $mb МБ…', 'Uploading $mb MB…');
}
