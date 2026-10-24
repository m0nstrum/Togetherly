// Волна 2 UX, настройки (UX_AUDIT.md: N1, N6, N8, N9, N10, N14, N15).
//
// Прогон с env/test.json (там SUPPORT_EMAIL задан, флаги форка выключены);
// поведение форка с пустым адресом и allFree — в settings_runtime_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/fork_e2e.dart';
import 'package:love_app/screens/settings_screen.dart';
import 'package:love_app/widgets/settings_scaffold.dart';
import 'package:love_app/services/locale_service.dart';

Widget _app() => MaterialApp(
  home: SettingsScreen(
    scheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63)),
    accountEmail: 'sasha@example.com',
    onAppearance: () {},
    onNotifications: () {},
    onLanguage: () {},
    onCoinShop: () {},
    onPrivacyPolicy: () {},
    onExport: () {},
    onTerms: () {},
    onSupport: () {},
    onOfficial: () {},
    onDrawTools: () {},
    onAbout: () {},
    onHelp: () {},
    onChangePassword: () {},
    onLogout: () {},
    onDeleteAccount: () {},
    onTelegramChannel: () {},
    onBugBot: () {},
    lockScreenMood: false,
    onLockScreenMoodChanged: (_) {},
    sideActionIsArrow: true,
    onToggleSideAction: () {},
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 15000);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

double _y(WidgetTester tester, Pattern text) =>
    tester.getTopLeft(find.textContaining(text).first).dy;

void main() {
  testWidgets('coins belong to account, help to about, reset is not in settings', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    String group(IconData icon) => tester.widget<SettingsCollapsible>(
      find.ancestor(of: find.byIcon(icon), matching: find.byType(SettingsCollapsible)),
    ).prefsKey;
    expect(group(Icons.monetization_on_rounded), 'account');
    expect(group(Icons.help_rounded), 'about');
    expect(find.textContaining(RegExp('Версия и лицензии|Version & licenses')), findsOneWidget);
    expect(find.text(LocaleService.current.resetMissYouCount), findsNothing);
  });

  testWidgets('N8: «Аккаунт» выше данных, удаление — последним и отдельно', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pump();

    final account = _y(tester, RegExp('^(АККАУНТ|ACCOUNT)\$'));
    final data = _y(tester, RegExp('^(ДАННЫЕ|DATA)\$'));
    final about = _y(tester, RegExp('^(О ПРИЛОЖЕНИИ|ABOUT)'));
    final delete = _y(tester, RegExp('Удалить аккаунт|Delete account'));
    expect(account < data, isTrue, reason: 'аккаунт поднят');
    expect(delete > about, isTrue, reason: 'удаление внизу, после «О приложении»');
  });

  testWidgets('N10: заголовок секции не повторяет заголовок её строки', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    // «Оформление» было и заголовком секции, и названием единственной строки.
    expect(find.text('ОФОРМЛЕНИЕ'), findsNothing);
    expect(find.text('УВЕДОМЛЕНИЯ'), findsNothing);
    expect(find.text('МАГАЗИН МОНЕТ'), findsNothing);
  });

  testWidgets('N10: рисование и боковая кнопка не в «уведомлениях»', (
    tester,
  ) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    final tools = _y(tester, RegExp('^(РИСОВАНИЕ И ГЛАВНАЯ|DRAWING & HOME)\$'));
    final draw = _y(tester, RegExp(r'^(Панель рисования|Drawing panel)$'));
    final phone = _y(tester, RegExp('^(ТЕЛЕФОН И ЭКРАН БЛОКИРОВКИ|PHONE & LOCK)'));
    expect(draw > tools, isTrue);
    expect(tools > phone, isTrue);
  });

  testWidgets('N1: без сервиса шифрования секции «Шифрование» нет', (
    tester,
  ) async {
    _tall(tester);
    ForkE2E.service.value = null;
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.text('ШИФРОВАНИЕ'), findsNothing);
    expect(find.text('ENCRYPTION'), findsNothing);
  });

  testWidgets('N6: адрес поддержки задан — строка есть', (tester) async {
    _tall(tester);
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(find.text(SettingsScreen.supportEmail), findsOneWidget);
  });
}
