import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:love_app/fork/config/endpoints.dart';
import 'package:love_app/fork/http_gateway.dart';

void main() {
  final gateway = Uri.parse('https://pb.example.org/api/meta/fetch');
  const cfg = EndpointsConfig(
    pbUrl: 'https://pb.example.org',
    sentryDsn: 'https://key@crash.example.org/1',
    legacyHosts: 'old.example.org',
  );

  group('route', () {
    final direct = ForkHttpGateway.directHosts(cfg);

    test('свои хосты, Sentry и тайлы — напрямую', () {
      for (final u in [
        'https://pb.example.org/api/collections/x',
        'https://old.example.org/api/files/a',
        'https://crash.example.org/api/1/envelope/',
        'https://tiles.openfreemap.org/planet',
        'http://10.0.2.2:8090/api/health',
      ]) {
        expect(
          ForkHttpGateway.route(Uri.parse(u), gateway: gateway, direct: direct),
          isNull,
          reason: u,
        );
      }
    });

    test('чужие сайты — через gateway с исходным адресом в url', () {
      final via = ForkHttpGateway.route(
        Uri.parse('https://api.deezer.com/track/1?x=2'),
        gateway: gateway,
        direct: direct,
      );
      expect(via?.host, 'pb.example.org');
      expect(via?.path, '/api/meta/fetch');
      expect(via?.queryParameters['url'], 'https://api.deezer.com/track/1?x=2');
    });

    test('не http — не трогаем', () {
      expect(
        ForkHttpGateway.route(
          Uri.parse('data:text/plain,x'),
          gateway: gateway,
          direct: direct,
        ),
        isNull,
      );
    });
  });

  test('настоящий http.get к чужому сайту уходит на gateway', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String>[];
    server.listen((req) {
      seen.add('${req.method} ${req.uri}');
      req.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true}))
        ..close();
    });
    final gw = Uri.parse('http://127.0.0.1:${server.port}/api/meta/fetch');

    await HttpOverrides.runWithHttpOverrides(() async {
      final r = await http.get(Uri.parse('https://noembed.com/embed?url=a'));
      expect(r.statusCode, 200);
      // POST к чужому сайту не перехватывается (и тут уйдёт в никуда).
    }, ForkHttpGateway.overrides(gateway: gw, direct: {'127.0.0.1'}));

    await server.close(force: true);
    expect(seen, hasLength(1));
    expect(
      Uri.parse(seen.single.split(' ').last).queryParameters['url'],
      'https://noembed.com/embed?url=a',
    );
  });
}
