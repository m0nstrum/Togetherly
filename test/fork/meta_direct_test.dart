import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/fork/meta_direct.dart';

/// Разбор на устройстве совпадает с серверным: те же случаи, что в
/// server/internal/domain/linkpreview/linkpreview_test.go.
void main() {
  group('ForkLinkPreview.parse — как linkpreview.Parse на сервере', () {
    final cases = <String, (String, String, Map<String, dynamic>)>{
      'og-теги и цена с копейками': (
        '<meta property="og:title" content="Кружка &amp; блюдце"><meta content="/img/a.jpg" property="og:image">\n'
            '<meta property="product:price:amount" content="12 990,00"><meta property="product:price:currency" content="RUB">\n'
            '<meta property="og:site_name" content="Магазин">',
        'https://shop.example.org/p/1',
        {
          'title': 'Кружка & блюдце',
          'image': 'https://shop.example.org/img/a.jpg',
          'shop': 'Магазин',
          'price': 12990,
          'currency': '₽',
        },
      ),
      'title и JSON-LD': (
        '<title> Книга </title><script>{"price": "1299.5", "priceCurrency":"usd"}</script>\n'
            '<meta name="twitter:image" content="//cdn.example.org/b.png">',
        'https://www.books.example.org/x',
        {
          'title': 'Книга',
          'image': 'https://cdn.example.org/b.png',
          'shop': 'books.example.org',
          'price': 1299,
          'currency': r'$',
        },
      ),
      'рубль по знаку на странице': (
        '<title>Чайник</title><span>от 1 299 ₽</span><meta itemprop="price" content="от 1 299">',
        'https://t.example.org/',
        {
          'title': 'Чайник',
          'image': '',
          'shop': 't.example.org',
          'price': 1299,
          'currency': '₽',
        },
      ),
      'пусто': (
        '',
        'https://e.example.org/',
        {
          'title': '',
          'image': '',
          'shop': 'e.example.org',
          'price': 0,
          'currency': '',
        },
      ),
    };
    cases.forEach((name, c) {
      test(name, () => expect(ForkLinkPreview.parse(c.$1, c.$2), c.$3));
    });
  });

  test('fetch: ответ в форме /api/link/preview, ошибка — null', () async {
    final ok = MockClient(
      (req) async => http.Response(
        '<title>Вещь</title>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      ),
    );
    final r = await ForkLinkPreview.fetch('https://s.example.org/', client: ok);
    expect(r?['success'], isTrue);
    expect(r?['title'], 'Вещь');

    final bad = MockClient((req) async => http.Response('', 403));
    expect(
      await ForkLinkPreview.fetch('https://s.example.org/', client: bad),
      isNull,
    );
    expect(await ForkLinkPreview.fetch('javascript:alert(1)'), isNull);
  });

  test('fetch: короткая ссылка — итоговый адрес и точка места', () async {
    const full = 'https://www.google.com/maps/place/x/@55.7298,37.6011,17z';
    final c = MockClient((req) async {
      if (req.url.host == 'maps.app.goo.gl') {
        return http.Response('', 302, headers: {'location': full});
      }
      return http.Response(
        '<meta property="og:title" content="Парк">'
        '<meta property="place:location:latitude" content="55.7298">'
        '<meta property="place:location:longitude" content="37.6011">',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final r = await ForkLinkPreview.fetch(
      'https://maps.app.goo.gl/abc',
      client: c,
    );
    expect(r?['url'], full);
    expect(r?['lat'], 55.7298);
    expect(r?['lng'], 37.6011);
  });
}
