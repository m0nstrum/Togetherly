import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:love_app/fork/config/endpoints.dart';
import 'package:love_app/fork/http_gateway.dart';
import 'package:love_app/fork/meta_direct.dart';

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

  test('«напрямую с устройства» — gateway не трогается', () async {
    Future<(HttpServer, List<String>)> serve() async {
      final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String>[];
      srv.listen((req) {
        seen.add(req.uri.path);
        req.response
          ..write('ok')
          ..close();
      });
      return (srv, seen);
    }

    final (gwSrv, gwSeen) = await serve();
    final (site, siteSeen) = await serve();
    final gw = Uri.parse('http://127.0.0.1:${gwSrv.port}/api/meta/fetch');
    ForkMetaDirect.enabled.value = true;
    addTearDown(() => ForkMetaDirect.enabled.value = false);

    await HttpOverrides.runWithHttpOverrides(() async {
      // localhost не в списке прямых: без настройки ушёл бы на gateway.
      final r = await http.get(Uri.parse('http://localhost:${site.port}/page'));
      expect(r.body, 'ok');
    }, ForkHttpGateway.overrides(gateway: gw, direct: {'127.0.0.1'}));

    await gwSrv.close(force: true);
    await site.close(force: true);
    expect(gwSeen, isEmpty);
    expect(siteSeen, ['/page']);
  });

  test(
    'followRedirects=false: сервер не проходит редирект за клиента',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final modes = <String?>[];
      server.listen((req) {
        modes.add(req.headers.value('X-Meta-Redirect'));
        req.response
          ..statusCode = HttpStatus.found
          ..headers.set('Location', 'https://www.deezer.com/track/7')
          ..close();
      });
      final gw = Uri.parse('http://127.0.0.1:${server.port}/api/meta/fetch');

      String? location;
      await HttpOverrides.runWithHttpOverrides(() async {
        // Как music_meta_service раскрывает link.deezer.com.
        final c = HttpClient();
        final req = await c.getUrl(Uri.parse('https://link.deezer.com/s/abc'));
        req.followRedirects = false;
        final resp = await req.close();
        location = resp.headers.value('location');
        c.close();
      }, ForkHttpGateway.overrides(gateway: gw, direct: {'127.0.0.1'}));

      await server.close(force: true);
      expect(modes, ['manual']);
      expect(location, 'https://www.deezer.com/track/7');
    },
  );
}
