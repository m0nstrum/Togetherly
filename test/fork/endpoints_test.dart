import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/config/endpoints.dart';

void main() {
  group('EndpointsConfig', () {
    test('пустой конфиг не проходит проверку', () {
      const c = EndpointsConfig(pbUrl: '');
      expect(c.problems(), contains('PB_URL не задан'));
      expect(c.ensureValid, throwsStateError);
    });

    test('неверные адреса видны в проверке', () {
      const c = EndpointsConfig(
        pbUrl: 'pb.example.org',
        centrifugoWs: 'https://pb.example.org/ws',
        gamesUrl: 'ftp://games',
      );
      final p = c.problems().join('\n');
      expect(p, contains('PB_URL'));
      expect(p, contains('CENTRIFUGO_WS'));
      expect(p, contains('GAMES_URL'));
    });

    test('минимальный конфиг: всё выводится из PB_URL', () {
      const c = EndpointsConfig(pbUrl: 'https://pb.example.org/');
      expect(c.problems(), isEmpty);
      expect(c.site, 'https://pb.example.org');
      expect(c.siteHost, 'pb.example.org');
      expect(c.centrifugoUrl, 'wss://pb.example.org/connection/websocket');
      expect(c.inviteLink('AB2C3D'), 'https://pb.example.org/invite/AB2C3D');
      expect(c.inviteLink(' '), isEmpty);
      expect(c.privacyPolicyUrl, 'https://pb.example.org/privacy-policy');
      expect(c.termsUrl, 'https://pb.example.org/terms');
      expect(c.ownHosts, ['pb.example.org']);
      expect(c.gamesUrl, isEmpty);
      expect(c.reelsProxyUrl, isEmpty);
    });

    test('http PB даёт ws Centrifugo (локальная разработка)', () {
      const c = EndpointsConfig(pbUrl: 'http://10.0.2.2:8090');
      expect(c.centrifugoUrl, 'ws://10.0.2.2:8090/connection/websocket');
    });

    test('отдельный сайт и легаси-хосты', () {
      const c = EndpointsConfig(
        pbUrl: 'https://api.example.org',
        siteUrl: 'https://example.org',
        legacyHosts: ' Old.Example.org , ,old2.example.org',
        centrifugoWs: 'wss://rt.example.org/connection/websocket',
      );
      expect(c.problems(), isEmpty);
      expect(c.inviteLink('X1Y2Z3'), 'https://example.org/invite/X1Y2Z3');
      expect(c.siteHost, 'example.org');
      expect(c.centrifugoUrl, 'wss://rt.example.org/connection/websocket');
      expect(c.ownHosts, [
        'api.example.org',
        'example.org',
        'old.example.org',
        'old2.example.org',
      ]);
    });

    test('openfreemap — единственный дефолт', () {
      const c = EndpointsConfig(pbUrl: 'https://pb.example.org');
      expect(c.mapTileJsonUrl, EndpointsConfig.openFreeMapTileJson);
      expect(c.sentryDsn, isEmpty);
    });
  });
}
