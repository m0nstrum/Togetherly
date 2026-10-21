import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож S1: в коде клиента нет адресов инфраструктуры апстрима.
///
/// Ловит новые хардкоды, которые приезжают с мёржами апстрима. Комментарии не
/// считаются: ссылки в них никуда не ходят, а правка чужих комментариев — лишние
/// конфликты. `ios/` не проверяем: по решению 2 (PLAN.md) iOS не собираем.
void main() {
  final patterns = <String, RegExp>{
    'домен апстрима': RegExp(r'togetherly\.(day|app)\b'),
    'duckdns': RegExp(r'duckdns'),
    'Firebase Hosting': RegExp(r'web\.app\b'),
    // IP как адрес: после схемы или @, либо целой строкой/значением
    // элемента. Голые числа (SVG-пути, версии в User-Agent) не трогаем.
    'IP-литерал': RegExp(
      r'''(?:://|@|['">])((?:\d{1,3}\.){3}\d{1,3})(?=[:/'"<]|$)''',
      multiLine: true,
    ),
  };

  // IP, которые адресом сервера не являются.
  const allowedIps = {'0.0.0.0', '127.0.0.1', '10.0.2.2', '255.255.255.255'};

  const roots = ['lib', 'android'];
  const exts = {
    '.dart',
    '.kt',
    '.java',
    '.kts',
    '.xml',
    '.gradle',
    '.properties',
    '.pro',
    '.json',
  };

  bool skipped(String path) =>
      path.contains('/build/') ||
      path.contains('/.gradle/') ||
      path.contains('/generated/') ||
      path.endsWith('local.properties') ||
      path.contains('GeneratedPluginRegistrant');

  String stripComments(String path, String src) {
    if (path.endsWith('.xml')) {
      return src.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    }
    var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    if (path.endsWith('.properties') || path.endsWith('.pro')) {
      s = s.replaceAll(RegExp(r'^\s*#.*$', multiLine: true), '');
    }
    // `//` комментарий, но не `https://`.
    return s.replaceAll(RegExp(r'''(?<![:'"\w])//.*$''', multiLine: true), '');
  }

  test('в lib/ и android/ нет адресов апстрима', () {
    final hits = <String>[];
    for (final root in roots) {
      for (final f in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        final path = f.path.replaceAll('\\', '/');
        if (skipped(path)) continue;
        if (!exts.any(path.endsWith)) continue;
        final lines = stripComments(path, f.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          for (final MapEntry(key: what, value: re) in patterns.entries) {
            for (final m in re.allMatches(lines[i])) {
              if (what == 'IP-литерал' && allowedIps.contains(m[1])) continue;
              final line = lines[i].trim();
              hits.add(
                '$path: $what: ${line.length > 160 ? line.substring(0, 160) : line}',
              );
            }
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Адреса — в lib/fork/config/endpoints.dart, см. docs/fork/TOUCHPOINTS.md',
    );
  });
}
