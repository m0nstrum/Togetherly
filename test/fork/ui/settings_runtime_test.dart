@Tags(['fork-runtime'])
library;

// Настройки в сборке форка: без `env/test.json`, поэтому SUPPORT_EMAIL пуст, а
// ForkFlags.allFree включён (UX_AUDIT.md: N6, N9).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/screens/settings_screen.dart';

void main() {
  testWidgets('N6/N9: нет адреса поддержки и Плюса — нет и строк', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 15000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
          accountEmail: 'a@example.com',
          onAppearance: () {},
          onNotifications: () {},
          onLanguage: () {},
          onCoinShop: () {},
          onPrivacyPolicy: () {},
          onExport: () {},
          onResetMissYou: () {},
          onTerms: () {},
          onSupport: () {},
          onOfficial: () {},
          onDrawTools: () {},
          onAbout: () {},
          onChangePassword: () {},
          onLogout: () {},
          onDeleteAccount: () {},
          onTelegramChannel: () {},
          onBugBot: () {},
          lockScreenMood: false,
          onLockScreenMoodChanged: (_) {},
          sideActionIsArrow: true,
          onToggleSideAction: () {},
          plusVisible: true,
        ),
      ),
    );
    await tester.pump();
    expect(SettingsScreen.supportEmail, isEmpty);
    expect(find.textContaining(RegExp('Поддержка|Support')), findsNothing);
    expect(find.textContaining('Togetherly+'), findsNothing);
  });
}
