import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Сторож A14e (аудит CI-4): каждое `uses:` в workflows закреплено полным
/// SHA с комментарием версии — тег можно перевесить, коммит нет.
/// Обновляет их Dependabot (`.github/dependabot.yml`).
void main() {
  test('uses: в .github/workflows — только по SHA', () {
    final pinned = RegExp(r'uses:\s*[\w.\-/]+@[0-9a-f]{40} # v\d');
    final offenders = <String>[];
    for (final f in Directory('.github/workflows').listSync()) {
      if (f is! File || !RegExp(r'\.ya?ml$').hasMatch(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (!l.contains('uses:') || l.trimLeft().startsWith('#')) continue;
        // Локальные actions (`./…`) не пиннятся.
        if (l.contains('uses: ./')) continue;
        if (!pinned.hasMatch(l)) {
          offenders.add('${f.path.replaceAll('\\', '/')}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: 'action без SHA');
  });

  test('Dependabot следит за pub, gomod и actions', () {
    final src = File('.github/dependabot.yml').readAsStringSync();
    for (final eco in ['pub', 'gomod', 'github-actions']) {
      expect(src, contains('package-ecosystem: $eco'));
    }
  });

  test('релиз не печатает значения release.local.json (CI-6)', () {
    final src = File('.github/workflows/fork-release.yml').readAsStringSync();
    expect(src, isNot(contains('cat env/release.local.json')));
  });
}
