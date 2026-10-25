import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/utils/map_link.dart';

/// «Поделиться → Tethered» ссылкой на карты (docs/WISHLIST.md).
void main() {
  void point(String url, double lat, double lng, [String name = '']) {
    final p = mapPointFromUrl(url);
    expect(p, isNotNull, reason: url);
    expect(p!.lat, closeTo(lat, 1e-6), reason: url);
    expect(p.lng, closeTo(lng, 1e-6), reason: url);
    if (name.isNotEmpty) expect(p.name, name, reason: url);
  }

  test('Яндекс: метка точнее центра; долгота первой', () {
    point(
      'https://yandex.ru/maps/?ll=37.60,55.73&pt=37.6011,55.7298&z=17',
      55.7298,
      37.6011,
    );
    point(
      'https://yandex.ru/maps/213/moscow/?ll=37.617635%2C55.755814&z=10',
      55.755814,
      37.617635,
    );
  });

  test('Google: точка места, центр карты, q=', () {
    point(
      'https://www.google.com/maps/place/Gorky+Park/@55.73,37.60,15z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d55.7298!4d37.6011',
      55.7298,
      37.6011,
      'Gorky Park',
    );
    point('https://www.google.com/maps/@55.7558,37.6173,14z', 55.7558, 37.6173);
    point('https://maps.google.com/?q=55.7298,37.6011', 55.7298, 37.6011);
  });

  test('2ГИС, OSM, Apple, geo:', () {
    point('https://2gis.ru/moscow?m=37.6011%2C55.7298%2F16', 55.7298, 37.6011);
    point(
      'https://www.openstreetmap.org/?mlat=55.7298&mlon=37.6011#map=16/55.7298/37.6011',
      55.7298,
      37.6011,
    );
    point(
      'https://www.openstreetmap.org/#map=16/55.7298/37.6011',
      55.7298,
      37.6011,
    );
    point(
      'https://maps.apple.com/?ll=55.7298,37.6011&q=Park',
      55.7298,
      37.6011,
    );
    point(
      'geo:0,0?q=55.7298,37.6011(Парк Горького)',
      55.7298,
      37.6011,
      'Парк Горького',
    );
    point('geo:55.7298,37.6011', 55.7298, 37.6011);
  });

  test('не карты и короткие ссылки — без точки', () {
    for (final url in [
      'https://www.wildberries.ru/catalog/1/detail.aspx',
      'https://maps.app.goo.gl/abc',
      'https://yandex.ru/maps/-/CDabc',
      'https://yandex.ru/maps/?ll=999,999',
      '',
    ]) {
      expect(mapPointFromUrl(url), isNull, reason: url);
    }
  });
}
