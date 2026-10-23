// fork: пароль аккаунта по правилам пароля бэкапа (account_password.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/account_password.dart';
import 'package:love_app/fork/e2e/password_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('слабые пароли регистрации не проходят, сильный проходит', () async {
    // Прежние правила апстрима (8 символов, заглавная, знак) пускали их.
    expect(
      await ForkAccountPassword.problems('Parol_123'),
      contains(PasswordProblem.tooShort),
    );
    expect(
      await ForkAccountPassword.problems('P@ssw0rd2024!'),
      contains(PasswordProblem.leaked),
    );
    expect(
      await ForkAccountPassword.problems(
        'Vlad-Moscow-71x',
        email: 'vlad@x.org',
      ),
      contains(PasswordProblem.personal),
    );
    expect(
      await ForkAccountPassword.problems('Qwerty-Lamp-91'),
      contains(PasswordProblem.keyboard),
    );
    expect(await ForkAccountPassword.problems('Kettle-Moss-82-Orbit'), isEmpty);
  });

  test('generated passwords are unique and satisfy the full policy', () async {
    final generated = <String>{};
    for (var i = 0; i < 8; i++) {
      final password = await ForkAccountPassword.generate(email: 'alice@example.org', name: 'Alice');
      expect(password.length, 24);
      expect(await ForkAccountPassword.problems(password, email: 'alice@example.org', name: 'Alice'), isEmpty);
      generated.add(password);
    }
    expect(generated, hasLength(8));
  });

  testWidgets('индикаторы: базовые строки и утечка красным', (tester) async {
    final rows = <String, bool>{};
    Widget row(String label, bool ok) {
      rows[label] = ok;
      return Text(label);
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ForkPasswordChecks(password: 'P@ssw0rd2024!', row: row),
          ),
        ),
      );
      await ForkAccountPassword.problems('x');
    });
    await tester.pump();

    expect(rows, hasLength(5));
    expect(rows.values, everyElement(isTrue));
    expect(find.textContaining('•'), findsOneWidget);
  });
}
