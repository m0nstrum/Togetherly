@Tags(['fork-runtime'])
library;

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/utils/relationship_tips.dart';
import 'package:love_app/widgets/tips_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saved unsupported language migrates to English', () async {
    SharedPreferences.setMockInitialValues({'app_language': 'de'});
    await LocaleService.instance.init();
    expect(LocaleService.instance.language, AppLanguage.en);
    expect(
      (await SharedPreferences.getInstance()).getString('app_language'),
      'en',
    );
  });
  test(
    'selection and device detection expose only complete translations',
    () async {
      expect(LocaleService.availableLanguages, [
        AppLanguage.ru,
        AppLanguage.en,
      ]);
      expect(LocaleService.supportedLocales, [
        const ui.Locale('ru'),
        const ui.Locale('en'),
      ]);
      expect(LocaleService.detect(const ui.Locale('ru', 'RU')), AppLanguage.ru);
      for (final language in AppLanguage.values.where(
        (l) => l != AppLanguage.ru && l != AppLanguage.en,
      )) {
        expect(LocaleService.detect(language.locale), AppLanguage.en);
        await LocaleService.instance.setLanguage(language);
        expect(LocaleService.instance.language, AppLanguage.en);
      }
    },
  );
  testWidgets('English tip action has no Russian label', (tester) async {
    await LocaleService.instance.setLanguage(AppLanguage.en);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TipsCard(
            tips: const [
              RelationshipTip(
                id: 'chat',
                title: 'Title',
                body: 'Body',
                weight: 1,
                action: 'chat',
              ),
            ],
            onAction: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Write'), findsOneWidget);
    expect(find.text('Написать'), findsNothing);
  });
}
