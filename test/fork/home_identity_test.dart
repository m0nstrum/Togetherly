@Tags(['fork-runtime'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/identity.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/widgets/home_layout_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Russian and English invites name the installed app and keep the instance link',
    () {
      const link = 'https://couple.example/invite/CODE#secret';
      for (final lang in [AppLanguage.ru, AppLanguage.en]) {
        LocaleService.instance.setLanguage(lang);
        expect(
          LocaleService.current.shareInviteText('CODE', link),
          contains(ForkIdentity.appName),
        );
        expect(
          LocaleService.current.shareInviteText('CODE', link),
          contains(link),
        );
        expect(
          LocaleService.current.joinMeLinkText(link),
          isNot(contains('Togetherly')),
        );
      }
    },
  );

  testWidgets('home settings hide the unavailable Wallet action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: HomeLayoutSettingsSection()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Wallet'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
