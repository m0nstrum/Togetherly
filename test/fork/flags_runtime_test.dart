@Tags(['fork-runtime'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/flags.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/models/help_items.dart';
import 'package:love_app/services/coin_store.dart';
import 'package:love_app/services/movie_search_service.dart';
import 'package:love_app/services/plus_service.dart';
import 'package:love_app/widgets/auth_widgets.dart';
import 'package:love_app/widgets/common/ad_banner.dart';

/// Поведение сборки форка. Запускается без env/test.json
/// (`flutter test --tags fork-runtime`), иначе флаги вернут поведение апстрима.
void main() {
  test('флаги форка включены', () {
    expect(ForkFlags.analyticsDisabled, isTrue);
    expect(ForkFlags.allFree, isTrue);
    expect(ForkFlags.hideUpstreamChannels, isTrue);
    expect(ForkFlags.emailOnlyAuth, isTrue);
    expect(ForkFlags.metaGateway, isTrue);
    expect(ForkFlags.noUpstreamKeys, isTrue);
  });

  testWidgets('кнопок входа через Google/Яндекс/Apple нет', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AuthSocialRow(label: 'x', onGoogle: () {}, onYandex: () {}),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AuthSocialRow)), Size.zero);
  });

  test('Плюс открыт у всех, купить и задонатить нельзя', () {
    expect(PlusService.instance.active, isTrue);
    expect(PlusService.canPurchase, isFalse);
    expect(kStore, 'fork');
    expect(kDonationsEnabled, isFalse);
    expect(kCoinsPurchasable, isFalse);
    expect(sharedCoinStore.isAvailable, isFalse);
  });

  test('в помощи нет покупки Плюса и Telegram автора', () {
    final ids = helpItems(plusInStore: true).map((i) => i.id).toList();
    expect(ids, isNot(contains('plusStore')));
    expect(ids, isNot(contains('plusSite')));
    expect(ids, isNot(contains('telegram')));
  });

  testWidgets('рекламный баннер не занимает места', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: AdBanner(height: 50)),
      ),
    );
    expect(tester.getSize(find.byType(AdBanner)), Size.zero);
  });

  test('фильмы не ищутся общим ключом poiskkino автора', () async {
    final hosts = <String>[];
    final client = MockClient((req) async {
      hosts.add(req.url.host);
      return http.Response('{}', 500);
    });
    expect(MovieSearchService.isConfigured, isFalse);
    // Без сессии на своём сервере запасной путь — ручной ввод, не poiskkino.
    await expectLater(
      MovieSearchService.searchWith(
        'матрица',
        base: 'https://pb.example.org',
        token: '',
        lang: 'ru',
        client: client,
      ),
      throwsA(
        isA<MovieSearchException>().having(
          (e) => e.notConfigured,
          'notConfigured',
          isTrue,
        ),
      ),
    );
    expect(hosts, isEmpty);
  });
}
