import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/wishes/wish_place_check.dart';
import 'package:love_app/fork/wishes/wish_place_picker.dart';
import 'package:love_app/models/wish.dart';
import 'package:love_app/models/wish_place.dart';
import 'package:love_app/services/pb_data_service.dart';
import 'package:love_app/theme/app_theme.dart';

/// «Место» в вишлисте и «вы оба рядом» (docs/WISHLIST.md).
void main() {
  const park = WishPlace(lat: 55.7298, lng: 37.6011, name: 'Парк Горького');
  final now = DateTime(2026, 10, 25, 15);

  Wish w(String id, {WishPlace? place = park, bool done = false}) => Wish(
    id: id,
    title: id,
    authorUid: 'a',
    place: place,
    done: done,
    createdAt: DateTime(2026),
  );

  // ~300 м к северу от парка.
  GeoFix near(DateTime at) => GeoFix(55.7325, 37.6011, at, accuracy: 20);
  GeoFix far(DateTime at) => GeoFix(55.80, 37.70, at, accuracy: 20);

  test('точка: запись, мусор, расстояние', () {
    expect(WishPlace.parse(park.encode()), park);
    for (final raw in [
      '',
      'x',
      '{"lat":0,"lng":0}',
      '{"lat":91,"lng":1}',
      null,
    ]) {
      expect(WishPlace.parse(raw), isNull, reason: '$raw');
    }
    expect(park.metersTo(55.7325, 37.6011), closeTo(300, 10));
    final back = Wish.fromMap(w('1').toMap(groupId: 'g'));
    expect(back.place, park);
    expect(w('1').copyWith(noPlace: true).place, isNull);
    final body = PbDataService.wishUpsertBody(
      'g',
      w('1', place: null).toMap(groupId: 'g'),
    );
    expect(body['place'], '', reason: 'снятая точка стирается и на сервере');
  });

  test('оба рядом — да; один, давно или далеко — нет', () {
    List<String> hits({
      GeoFix? partner,
      Map<String, DateTime> last = const {},
      double radius = 500,
    }) => wishPlacesTogether(
      wishes: [w('park'), w('done', done: true), w('nowhere', place: null)],
      me: near(now),
      partner: partner,
      now: now,
      radius: radius,
      lastNotified: last,
    ).map((x) => x.id).toList();

    expect(hits(partner: near(now.subtract(const Duration(minutes: 5)))), [
      'park',
    ]);
    expect(hits(partner: null), isEmpty);
    expect(hits(partner: far(now)), isEmpty);
    expect(
      hits(partner: near(now.subtract(const Duration(minutes: 30)))),
      isEmpty,
      reason: 'точка партнёра устарела',
    );
    expect(hits(partner: near(now), radius: 150), isEmpty);
    expect(
      hits(
        partner: near(now),
        last: {'park': now.subtract(const Duration(days: 3))},
      ),
      isEmpty,
      reason: 'не чаще раза в неделю',
    );
    expect(
      hits(
        partner: near(now),
        last: {'park': now.subtract(const Duration(days: 8))},
      ),
      ['park'],
    );
    expect(anyWishPlaceNear([w('park')], far(now), 500), isFalse);
    expect(anyWishPlaceNear([w('park')], near(now), 500), isTrue);
  });

  testWidgets('карта: тап ставит метку, «Готово» отдаёт точку', (tester) async {
    WishPlace? got;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                got = await Navigator.of(ctx).push<WishPlace>(
                  MaterialPageRoute(
                    builder: (_) => WishPlacePicker(
                      theme: AppThemes.all.first,
                      initial: park,
                      tiles: const SizedBox.expand(),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('wish-place-name')), 'Вход');
    await tester.tap(find.byKey(const Key('wish-place-done')));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.lat, park.lat);
    expect(got!.name, 'Вход');
  });
}
