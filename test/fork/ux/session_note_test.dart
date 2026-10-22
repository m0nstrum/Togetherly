import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ui/session_note.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> open(WidgetTester t) async {
    ForkSessionNote.debugReset();
    await t.pumpWidget(const MaterialApp(
      home: ForkSessionNote(child: Scaffold(body: Text('login'))),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('сервер отозвал вход — экран входа говорит почему (UX A13)',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await ForkSessionEnd.revoked();
    await open(t);
    expect(find.text(ForkSessionEnd.text(revoked: true)), findsOneWidget);
    await t.tap(find.byType(FilledButton));
    await t.pumpAndSettle();
    expect(find.text('login'), findsOneWidget);
    expect(await ForkSessionEnd.take(), isFalse, reason: 'причина снята');
  });

  testWidgets('без отзыва — «вход устарел», один раз за запуск', (t) async {
    SharedPreferences.setMockInitialValues({});
    await open(t);
    expect(find.text(ForkSessionEnd.text(revoked: false)), findsOneWidget);
    await t.tap(find.byType(FilledButton));
    await t.pumpAndSettle();
    await t.pumpWidget(const MaterialApp(
      home: ForkSessionNote(child: Scaffold(body: Text('again'))),
    ));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
