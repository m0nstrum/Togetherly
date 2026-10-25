// fork (D1): скрипт скорости в кадре TikTok (lib/fork/reels/tiktok_rate.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/reels/tiktok_rate.dart';

void main() {
  test('скрипт слушает только свою страницу и ставит только 1 или 2', () async {
    final script = forkTikTokRateScript('example.org');
    expect(script, contains('"https://example.org"'));
    final node = await Process.run('node', ['-e', _harness(script)]);
    expect(node.exitCode, 0, reason: '${node.stdout}${node.stderr}');
    expect('${node.stdout}'.trim(), '2,2,1,1');
  }, skip: _hasNode ? false : 'нет node');

  test('имя хоста не ломает строку скрипта', () {
    expect(forkTikTokRateScript('a"b.org'), contains(r'"https://a\"b.org"'));
  });
}

final bool _hasNode = () {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } catch (_) {
    return false;
  }
}();

/// Кадр TikTok в node: окно, документ с одним роликом, события.
String _harness(String script) =>
    '''
const vm = require('vm');
const handlers = {}; const docHandlers = {};
const video = { tagName: 'VIDEO', playbackRate: 1 };
const window = { top: {}, addEventListener: (t, f) => { handlers[t] = f; } };
const document = {
  getElementsByTagName: () => [video],
  addEventListener: (t, f) => { docHandlers[t] = f; },
};
vm.runInNewContext(${_js(script)}, { window, document, location: { hostname: 'www.tiktok.com' }, Number });
const out = [];
handlers.message({ origin: 'https://example.org', data: { 'x-fork-rate': 2 } }); out.push(video.playbackRate);
handlers.message({ origin: 'https://evil.example', data: { 'x-fork-rate': 1 } }); out.push(video.playbackRate);
video.playbackRate = 1; docHandlers.ratechange({ target: video });
handlers.message({ origin: 'https://example.org', data: { 'x-fork-rate': 16 } });
handlers.message({ origin: 'https://example.org', data: { 'x-fork-rate': 1 } }); out.push(video.playbackRate);
docHandlers.play({ target: video }); out.push(video.playbackRate);
console.log(out.join(','));
''';

String _js(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
