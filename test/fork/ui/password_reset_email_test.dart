import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ui/password_reset_email.dart';
import 'package:love_app/screens/login_screen.dart';
import 'package:love_app/models/user_data.dart';
import 'package:love_app/services/locale_service.dart';
import 'package:love_app/theme/app_theme.dart';
import 'package:love_app/theme/theme_scope.dart';

void main() {
  testWidgets(
    'reset recipient is editable, validated and only returned after confirmation',
    (t) async {
      String? recipient;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  recipient = await forkPasswordResetEmail(
                    ctx,
                    initial: 'old@example.org',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(recipient, isNull);
      expect(find.text('old@example.org'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'wrong');
      await t.tap(find.textContaining(RegExp('Отправить письмо|Send email')));
      await t.pumpAndSettle();
      expect(recipient, isNull);
      expect(find.text(LocaleService.current.invalidEmail), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'new@example.org');
      await t.tap(find.textContaining(RegExp('Отправить письмо|Send email')));
      await t.pumpAndSettle();
      expect(recipient, 'new@example.org');
    },
  );

  testWidgets(
    'forgot password has a full touch target and opens input when email is empty',
    (t) async {
      await t.pumpWidget(
        ThemeScope(
          theme: AppThemes.pink,
          child: MaterialApp(home: LoginScreen(userData: UserData())),
        ),
      );
      await t.pumpAndSettle();
      final reset = find.widgetWithText(
        TextButton,
        LocaleService.current.forgotPassword,
      );
      await t.ensureVisible(reset);
      expect(t.getSize(reset).height, greaterThanOrEqualTo(48));
      await t.tap(reset);
      await t.pumpAndSettle();
      expect(find.byType(TextFormField), findsOneWidget);
      await t.tap(find.text(LocaleService.current.cancel));
      await t.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
    },
  );
}
