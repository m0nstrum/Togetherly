/// Пароль аккаунта по тем же правилам, что пароль бэкапа ключей
/// (password_policy.dart): 12 символов, все классы, без утечек, почты, имени,
/// повторов и рядов клавиатуры. Регистрация и смена пароля.
library;

import 'package:flutter/material.dart';

import 'backup_ui.dart' show problemText;
import 'fork_e2e.dart';
import 'password_policy.dart';

abstract final class ForkAccountPassword {
  /// Пустой список — пароль годится.
  static Future<List<PasswordProblem>> problems(
    String pw, {
    String email = '',
    String name = '',
  }) async => PasswordPolicy.check(
    pw,
    leaked: await ForkE2E.leakedPasswords(),
    email: email,
    name: name,
  );

  /// Текст для снекбара: что не так, через запятую.
  static String describe(List<PasswordProblem> p) =>
      p.map(problemText).join(', ');
}

/// Индикаторы под полем пароля: базовые правила строками [row] (как у
/// апстрима), остальное — красным списком.
class ForkPasswordChecks extends StatefulWidget {
  const ForkPasswordChecks({
    super.key,
    required this.password,
    required this.row,
    this.email = '',
    this.name = '',
  });

  final String password;
  final String email;
  final String name;
  final Widget Function(String label, bool passed) row;

  @override
  State<ForkPasswordChecks> createState() => _ForkPasswordChecksState();
}

class _ForkPasswordChecksState extends State<ForkPasswordChecks> {
  LeakedPasswords? _leaked;

  static const _base = [
    PasswordProblem.tooShort,
    PasswordProblem.noLower,
    PasswordProblem.noUpper,
    PasswordProblem.noDigit,
    PasswordProblem.noSymbol,
  ];

  @override
  void initState() {
    super.initState();
    ForkE2E.leakedPasswords().then((l) {
      if (mounted && l != null) setState(() => _leaked = l);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = PasswordPolicy.check(
      widget.password,
      leaked: _leaked,
      email: widget.email,
      name: widget.name,
    );
    final extra = widget.password.isEmpty
        ? const <PasswordProblem>[]
        : p.where((x) => !_base.contains(x)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final b in _base) widget.row(problemText(b), !p.contains(b)),
          ],
        ),
        for (final x in extra)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '• ${problemText(x)}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}
