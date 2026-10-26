import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/features/pet_home/pet_home_model.dart';
import 'package:love_app/features/pet_home/pet_dialogue.dart';

void main() {
  test('care and credit are permanent; repeat furniture is free', () {
    final home = PetHome();
    home.furnish('cottage');
    expect(home.balance, 10);
    home.furnish('cottage');
    expect(home.balance, 10);
    home.careFor(PetCare.feed, 'a', 1);
    home.careFor(PetCare.feed, 'b', 9999999999999);
    expect(home.balance, 15);
    expect(home.care['feed'], 2);
    home.creditActivity(150);
    expect(home.balance, 30);
    home.creditActivity(150);
    home.creditActivity(50);
    expect(home.balance, 30);
    final restored = PetHome.fromJson(home.toJson());
    expect(restored.toJson(), home.toJson());
    expect(restored.owned, contains('cottage'));
    expect(restored.lastActor, 'b');
  });

  test(
    'purchase fails without mutating state; shared slots can be removed',
    () {
      final home = PetHome(balance: 0);
      expect(() => home.furnish('cottage'), throwsA(isA<PetNotEnoughCozy>()));
      expect(home.owned, isNot(contains('cottage')));
      expect(home.equipped.containsKey(PetSlot.bed), false);
      home.equipped.remove(PetSlot.seat);
      expect(home.copy().equipped.containsKey(PetSlot.seat), false);
    },
  );

  test('invalid or future schema never silently resets a paid home', () {
    expect(() => PetHome.fromJson({'v': 2}), throwsFormatException);
    final map = PetHome().toJson();
    map['equipped'] = {'bed': 'sofa', 'rug': 'nonexistent'};
    expect(PetHome.fromJson(map).equipped, isEmpty);
    final home = PetHome();
    for (var i = 0; i < 200; i++) {
      home.remember('$i');
    }
    expect(home.operations.length, 128);
    expect(home.operations.first, '72');
  });

  test(
    'roles are explicit, names are not declined or recursively replaced',
    () {
      expect(const PetRole('mom').address('Аня', false), 'Мама');
      expect(const PetRole('dad').address('X', true), 'Dad');
      expect(
        const PetRole('name').address('Звёздочка_99', false),
        'Звёздочка_99',
      );
      expect(const PetRole('custom', 'Мур').address('X', false), 'Мур');
    },
  );

  test('112 RU/EN lines cover every event, shuffle without repetition', () {
    final dialogue = PetDialogue(random: Random(17));
    expect(
      petLines.values.fold<int>(0, (n, v) => n + v.length),
      greaterThanOrEqualTo(112),
    );
    for (final event in petLines.keys) {
      final seen = <String>{};
      for (var i = 0; i < petLines[event]!.length; i++) {
        final line = dialogue.next(event, english: false, me: 'Мама');
        expect(line, isNot(contains('{me}')));
        expect(seen.add(line), true);
      }
      for (final line in petLines[event]!) {
        expect(line.split('|').length, 2);
        expect(line.split('|').every((part) => part.isNotEmpty), true);
      }
    }
  });
}
