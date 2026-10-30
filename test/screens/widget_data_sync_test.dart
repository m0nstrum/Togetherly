import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/mood_entry.dart';
import 'package:love_app/screens/widget_screen/widget_data_sync.dart';

MoodEntry _entry(int score) {
  final option = MoodOption.registry.firstWhere(
    (o) => MoodOption.byId(o.id)?.score == score,
  );
  return MoodEntry(
    id: 'e$score',
    moodId: option.id,
    imagePath: option.imagePath,
    label: option.label,
    timestamp: DateTime(2026, 10, 28, 12),
  );
}

void main() {
  group('ключ привязки нового виджета', () {
    test('оба оформления заметки — один виджет', () {
      expect(WidgetDataSync.pinBindKey('note'), 'note');
      expect(WidgetDataSync.pinBindKey('note_paper'), 'note');
    });

    test('новые виджеты не перехватывают группу у «Таймера»', () {
      for (final type in [
        'together',
        'miss',
        'year_ring',
        'year_grid',
        'mascot',
        'canvas',
        'map',
        'pair',
      ]) {
        expect(WidgetDataSync.pinBindKey(type), type, reason: type);
      }
      expect(WidgetDataSync.pinBindKey('relationship_stats'), 'stats');
      expect(WidgetDataSync.pinBindKey('timer'), 'timer');
      expect(WidgetDataSync.pinBindKey('mood_tiles'), 'timer');
    });

    test('фото-виджетам и «Серии» привязка не нужна', () {
      expect(WidgetDataSync.pinBindKey(null), isNull);
      expect(WidgetDataSync.pinBindKey('photo_day_self'), isNull);
      expect(WidgetDataSync.pinBindKey('photo_day_partner'), isNull);
      expect(WidgetDataSync.pinBindKey('streak'), isNull);
    });
  });

  group('фото-виджет в группе', () {
    test('без пары — только виджеты без группы', () {
      expect(WidgetDataSync.photoDayInGroup('', null), isTrue);
      expect(WidgetDataSync.photoDayInGroup('', ''), isTrue);
      expect(WidgetDataSync.photoDayInGroup('', 'g1'), isFalse);
    });

    test('с парой — своя группа или ещё не привязанный', () {
      expect(WidgetDataSync.photoDayInGroup('g1', 'g1'), isTrue);
      expect(WidgetDataSync.photoDayInGroup('g1', null), isTrue);
      expect(WidgetDataSync.photoDayInGroup('g1', 'g2'), isFalse);
    });
  });

  group('неделя «Настроения»', () {
    test('столбик: нет отметки — -1, оценки 1..5 — от 20 до 100', () {
      expect(WidgetDataSync.moodBarPercent(null), -1);
      expect(WidgetDataSync.moodBarPercent(_entry(1)), 20);
      expect(WidgetDataSync.moodBarPercent(_entry(5)), 100);
    });

    test('семь дней от понедельника, совпадения считаются', () {
      // Среда, 28.10.2026: неделя с понедельника 26.10.
      final days = <DateTime>[];
      final w = WidgetDataSync.moodWeek(
        DateTime(2026, 10, 28, 15),
        mine: (day) {
          days.add(day);
          return day.day == 26 || day.day == 27 ? _entry(5) : null;
        },
        theirs: (day) => day.day == 26
            ? _entry(5)
            : day.day == 27
            ? _entry(1)
            : null,
      );
      expect(days.first, DateTime(2026, 10, 26));
      expect(days.last, DateTime(2026, 11, 1));
      expect(w.week, hasLength(7));
      expect(w.week[0], [100, 100]);
      expect(w.week[1], [100, 20]);
      expect(w.week[2], [-1, -1]);
      expect(w.matched, 1);
    });

    test('без пары столбик партнёра пустой', () {
      final w = WidgetDataSync.moodWeek(
        DateTime(2026, 10, 26),
        mine: (_) => _entry(5),
      );
      expect(w.week.every((d) => d[1] == -1), isTrue);
      expect(w.matched, 0);
    });
  });
}
