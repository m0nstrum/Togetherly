// D8: общий календарь пары — события по дням.
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/memory.dart';
import 'package:love_app/models/pair_calendar.dart';

Memory _mem(String id, DateTime at, {DateTime? openAt}) => Memory(
  id: id,
  groupId: 'g',
  authorUid: 'a',
  authorName: '',
  authorAvatar: '',
  type: MemoryType.photo,
  createdAt: at,
  sealed: openAt != null,
  openAt: openAt,
);

void main() {
  test('записи, капсулы и ежегодные даты в диапазоне', () {
    final events = pairCalendarEvents(
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 12, 31),
      memories: [
        _mem('m1', DateTime(2026, 3, 8, 21)),
        _mem('m2', DateTime(2025, 3, 8), openAt: DateTime(2026, 3, 8, 9)),
      ],
      startDate: DateTime(2020, 2, 29),
      anniversaryDate: DateTime(2022, 6, 1),
      firstKissDate: DateTime(2020, 3, 1),
      birthdays: {'b': DateTime(1999, 10, 25)},
    );
    final march8 = events['2026-03-08']!;
    expect(march8.map((e) => e.kind), [
      PairEventKind.capsule,
      PairEventKind.memory,
    ], reason: 'праздник выше записи');
    final feb28 = events['2026-02-28']!.single;
    expect(
      feb28.kind,
      PairEventKind.anniversary,
      reason: '29.02 в невисокосный год — 28-го',
    );
    expect(feb28.years, 6);
    expect(events['2026-06-01']!.single.kind, PairEventKind.celebration);
    expect(events['2026-03-01']!.single.kind, PairEventKind.firstKiss);
    final bday = events['2026-10-25']!.single;
    expect(
      [bday.kind, bday.uid, bday.years],
      [PairEventKind.birthday, 'b', 27],
    );
    expect(events.containsKey('2025-03-08'), isFalse, reason: 'вне диапазона');
  });

  test('годовщина в дату начала не дублируется, в год начала её нет', () {
    final events = pairCalendarEvents(
      from: DateTime(2020, 1, 1),
      to: DateTime(2021, 12, 31),
      startDate: DateTime(2020, 5, 5),
      anniversaryDate: DateTime(2020, 5, 5),
    );
    expect(events.keys, ['2021-05-05']);
    expect(events['2021-05-05']!.single.kind, PairEventKind.anniversary);
  });
}
