// fork: прокси роликов «Смотрим вместе» (PLAN S11).
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch_proxy.dart';

void main() {
  test('выключен или ответ кривой — прокси нет', () {
    expect(WatchProxyInfo.fromJson({'enabled': false}), isNull);
    expect(WatchProxyInfo.fromJson({'enabled': true, 'url': ''}), isNull);
    expect(WatchProxyInfo.fromJson(null), isNull);
  });

  test('через прокси — только площадки из списка сервера', () {
    final p = WatchProxyInfo.fromJson({
      'enabled': true,
      'url': 'https://pair.example.org:8443',
      'hosts': ['.youtube.com', 'jnn-pa.googleapis.com'],
    })!;
    expect(p.url.host, 'pair.example.org');
    expect(p.url.port, 8443);
    expect(p.rules, ['youtube.com', '*.youtube.com', 'jnn-pa.googleapis.com']);
  });
}
