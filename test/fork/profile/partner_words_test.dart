import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/fork/l10n/count_words.dart';
import 'package:love_app/fork/l10n/last_seen.dart';
import 'package:love_app/services/locale_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async => LocaleService.instance.setLanguage(AppLanguage.en));

  test(
    'Russian count forms include teen exceptions and English singulars',
    () async {
      await LocaleService.instance.setLanguage(AppLanguage.ru);
      expect([1, 2, 5, 11, 21, 22].map(forkDaysWord), [
        'день',
        'дня',
        'дней',
        'дней',
        'день',
        'дня',
      ]);
      expect([1, 2, 11, 21].map(forkMemoriesWord), [
        'воспоминание',
        'воспоминания',
        'воспоминаний',
        'воспоминание',
      ]);
      expect([1, 4, 14, 21].map(forkMessagesWord), [
        'сообщение',
        'сообщения',
        'сообщений',
        'сообщение',
      ]);
      await LocaleService.instance.setLanguage(AppLanguage.en);
      expect(forkDaysWord(1), 'day');
      expect(forkDaysWord(2), 'days');
      expect(forkMemoriesWord(1), 'memory');
      expect(forkMemoriesWord(21), 'memories');
      expect(forkMessagesWord(1), 'message');
    },
  );

  test('last visit uses known gender and an absolute local time', () async {
    await LocaleService.instance.setLanguage(AppLanguage.ru);
    final now = DateTime(2026, 10, 23, 13);
    final at = DateTime(2026, 10, 23, 12, 30).millisecondsSinceEpoch;
    expect(forkLastSeen(at, gender: 'female', now: now), 'заходила в 12:30');
    expect(forkLastSeen(at, gender: 'male', now: now), 'заходил в 12:30');
    expect(forkLastSeen(at, gender: '', now: now), 'заходил(а) в 12:30');
    expect(
      forkLastSeen(at, gender: 'female', entered: false, now: now),
      'была в 12:30',
    );
    expect(
      forkLastSeen(
        DateTime(2026, 10, 22, 12, 30).millisecondsSinceEpoch,
        gender: 'female',
        now: now,
      ),
      'заходила вчера в 12:30',
    );
    expect(forkLastSeen(null, gender: 'male', now: now), isEmpty);
  });
}
