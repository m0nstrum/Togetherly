import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/identity.dart';
import 'package:love_app/utils/invite_code.dart';

void main() {
  group('ForkIdentity', () {
    test('ссылка приглашения на схеме форка', () {
      expect(ForkIdentity.inviteDeepLink('HQ792S'), 'tethered://invite/HQ792S');
      expect(ForkIdentity.inviteDeepLink('  '), isEmpty);
    });

    test('код из ссылки форка разбирается общим нормализатором', () {
      expect(
        normalizeInviteCode(ForkIdentity.inviteDeepLink('AB2C3D')),
        'AB2C3D',
      );
    });

    // Схема и applicationId живут в двух местах: Dart и Gradle. Тест ловит
    // рассинхрон, который иначе всплыл бы только на телефоне.
    test('совпадает с Gradle', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('"appScheme" to "${ForkIdentity.inviteScheme}"'));
      expect(gradle, contains('"appLabel" to "${ForkIdentity.appName}"'));
      expect(gradle, contains('applicationId = forkApplicationId'));
    });

    test('манифест не регистрирует схему апстрима наружу', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(manifest, isNot(contains('android:scheme="loveapp"')));
      expect(manifest, isNot(contains('android:label="Togetherly"')));
    });
  });
}
