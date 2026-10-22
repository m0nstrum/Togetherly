import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/identity.dart';
import 'package:love_app/fork/own_name.dart';

/// applicationId форка свой, а классы Android живут в пакете апстрима:
/// каждое имя виджета должно уходить в home_widget полным, иначе
/// «No Widget found» (жалоба владельца 22.10: «добавить на главный экран»).
void main() {
  test('у каждого androidName есть qualifiedAndroidName', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('androidName:') ||
            lines[i].contains('qualifiedAndroidName')) {
          continue;
        }
        final next = i + 1 < lines.length ? lines[i + 1] : '';
        if (!next.contains('qualifiedAndroidName')) bad.add('${f.path}:${i + 1}');
      }
    }
    expect(bad, isEmpty);
  });

  test('полное имя — пакет Kotlin-кода, а не applicationId', () {
    final ns = RegExp(r'namespace = "([^"]+)"')
        .firstMatch(File('android/app/build.gradle.kts').readAsStringSync())!
        .group(1)!;
    expect(ForkIdentity.widgetClass('LoveWidgetProvider'),
        '$ns.LoveWidgetProvider');
  });

  test('алиасы иконок собираются от пакета Kotlin-кода', () {
    final src = File(
            'android/app/src/main/kotlin/com/togetherly/love/MainActivity.kt')
        .readAsStringSync();
    expect(src, isNot(contains(r'"$packageName$suffix"')));
  });

  test('своё имя: шифр и замок не подпись', () {
    ForkOwnName.value = 'Аня';
    expect(ForkOwnName.value, 'Аня');
    ForkOwnName.value = 'e2e1.k.n.ct';
    expect(ForkOwnName.value, 'Аня', reason: 'шифр не затирает имя');
    expect(ForkOwnName.usable('🔒'), isFalse);
    ForkOwnName.value = '';
    expect(ForkOwnName.value, isEmpty);
  });

  test('канал комнаты шлёт вход и выход зрителей', () {
    final cfg = jsonDecode(File('deploy/centrifugo/config.json').readAsStringSync());
    final watch = (cfg['channel']['namespaces'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((n) => n['name'] == 'watch');
    expect(watch['presence'], isTrue);
    expect(watch['join_leave'], isTrue,
        reason: 'без него страница не узнаёт, что партнёр вышел');
    expect(watch['force_push_join_leave'], isTrue);
  });

  test('вошедший по зову не зовёт в ответ', () {
    final src =
        File('lib/screens/together/watch_room_screen.dart').readAsStringSync();
    final i = src.indexOf('Future<void> _inviteUnlessJoining()');
    final body = src.substring(i, src.indexOf('\n  }\n', i));
    expect(body.indexOf('ReelsInvite.active'),
        lessThan(body.indexOf('ReelsInvite.send')));
  });
}
