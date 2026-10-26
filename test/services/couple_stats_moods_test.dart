// T2: разбивка настроений в статистике пары считается на телефоне — на
// сервере mood_id зашифрован.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/services/couple_stats_service.dart';

MoodEntry _m(String id, DateTime at) => MoodEntry(
  id: 'x',
  moodId: id,
  imagePath: '',
  label: '',
  timestamp: at,
  authorDate: at,
);

void main() {
  final now = DateTime(2026, 10, 25, 12);

  test('по дням за 90 дней, новые сверху; любимые — за всё время', () {
    final json = moodStatsJson({
      'a': [
        _m('happy', now),
        _m('happy', now.subtract(const Duration(hours: 1))),
        _m('sad', now.subtract(const Duration(days: 3))),
        _m('sad', now.subtract(const Duration(days: 200))),
        _m('sad', now.subtract(const Duration(days: 201))),
      ],
      'b': [
        _m('e2e1.k.n.ct', now),
        _m('calm', now.subtract(const Duration(days: 1))),
      ],
    }, now);

    final stats = CoupleStats.fromJson({'mood': json});
    expect(stats.moodDaily.first.day, DateTime(2026, 10, 25));
    expect(stats.moodDaily.first.count, 2);
    expect(stats.moodDaily.map((p) => p.moodId), ['happy', 'calm', 'sad']);
    expect(
      stats.moodDaily.any((p) => p.moodId.startsWith('e2e1.')),
      isFalse,
      reason: 'шифр — не настроение',
    );
    final topA = stats.moodTop.where((p) => p.uid == 'a').toList();
    expect(topA.first.moodId, 'sad');
    expect(topA.first.count, 3);
  });
}
