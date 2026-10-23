import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:love_app/screens/miss_you_screen.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';

void main() {
  testWidgets('counter reset asks, respects cancellation, and checks server result', (t) async {
    SharedPreferences.setMockInitialValues({});
    var calls = 0;
    var saved = false;
    await t.pumpWidget(MaterialApp(home: MissYouScreen(theme: AppThemes.pink,
      groupId: '', myUid: 'me', partnerUid: '', partnerName: '',
      resetCount: () async { calls++; return saved; },
    )));
    Future<void> frame() async { await t.pump(); await t.pump(const Duration(milliseconds: 500)); }
    await frame();
    Future<void> request() async {
      await t.tap(find.byType(PopupMenuButton<String>));
      await frame();
      await t.tap(find.text(LocaleService.current.resetMissYouCount));
      await frame();
    }
    await request();
    await t.tap(find.text(LocaleService.current.cancel));
    await frame();
    expect(calls, 0);
    await request();
    await t.tap(find.text(LocaleService.current.reset));
    await frame();
    expect(calls, 1);
    expect(find.textContaining(RegExp('Ваш счётчик сброшен|Your counter was reset')), findsNothing);
    saved = true;
    await request();
    await t.tap(find.text(LocaleService.current.reset));
    await frame();
    expect(calls, 2);
    expect(find.textContaining(RegExp('Ваш счётчик сброшен|Your counter was reset')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
