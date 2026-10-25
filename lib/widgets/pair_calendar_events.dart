import 'package:flutter/material.dart';

import '../dict_strings.dart' show ruEn;
import '../fork/l10n/count_words.dart';
import '../models/pair_calendar.dart';

/// Значок события в клетке календаря и в строке листа дня (D8).
String pairEventEmoji(PairEvent e) => switch (e.kind) {
  PairEventKind.memory => '📸',
  PairEventKind.capsule => '⏳',
  PairEventKind.anniversary => '💞',
  PairEventKind.celebration => '🎉',
  PairEventKind.firstKiss => '💋',
  PairEventKind.birthday => '🎂',
  PairEventKind.wish => '✨',
};

String _years(int n) => ruEn(
  '$n ${forkRuCountWord(n, 'год', 'года', 'лет')}',
  '$n ${n == 1 ? 'year' : 'years'}',
);

/// Подпись события; [nameOf] — имя участника по uid.
String pairEventTitle(PairEvent e, String Function(String uid) nameOf) {
  switch (e.kind) {
    case PairEventKind.memory:
      final m = e.memory!;
      final t = (m.title ?? '').trim();
      final c = (m.caption ?? '').trim();
      if (m.sealedNow()) return ruEn('Капсула времени', 'Time capsule');
      return t.isNotEmpty
          ? t
          : (c.isNotEmpty ? c : ruEn('Воспоминание', 'Memory'));
    case PairEventKind.capsule:
      return ruEn('Открывается капсула времени', 'A time capsule opens');
    case PairEventKind.anniversary:
      return ruEn(
        'Вместе ${_years(e.years)}',
        'Together for ${_years(e.years)}',
      );
    case PairEventKind.celebration:
      return ruEn(
        'Годовщина · ${_years(e.years)}',
        'Anniversary · ${_years(e.years)}',
      );
    case PairEventKind.firstKiss:
      return ruEn(
        'Первый поцелуй — ${_years(e.years)}',
        'First kiss — ${_years(e.years)}',
      );
    case PairEventKind.birthday:
      final who = nameOf(e.uid).trim();
      return who.isEmpty
          ? ruEn('День рождения', 'Birthday')
          : ruEn('День рождения: $who', '$who’s birthday');
    case PairEventKind.wish:
      return ruEn('Хотим: ${e.wish!.title}', 'We want: ${e.wish!.title}');
  }
}

/// Раздел «В этот день» листа дня: праздники и записи.
class PairDayEvents extends StatelessWidget {
  const PairDayEvents({
    super.key,
    required this.events,
    required this.nameOf,
    required this.scheme,
  });

  final List<PairEvent> events;
  final String Function(String uid) nameOf;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                ruEn('В этот день', 'On this day'),
                style: TextStyle(
                  fontFamily: 'Onest',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final e in events)
              ListTile(
                dense: true,
                leading: Text(
                  pairEventEmoji(e),
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text(
                  pairEventTitle(e, nameOf),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: e.special ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
