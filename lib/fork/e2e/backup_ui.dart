/// Бэкап ключей и восстановление (docs/fork/E2E.md §7, решение §12.1).
library;

import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../widgets/settings_scaffold.dart';
import 'backup.dart';
import 'e2e_service.dart';
import 'fork_e2e.dart';
import 'password_policy.dart';

bool get _ru => const {
  'ru',
  'uk',
  'be',
}.contains(LocaleService.instance.language.code.toLowerCase());

String _t(String ru, String en) => _ru ? ru : en;

String problemText(PasswordProblem p) => switch (p) {
  PasswordProblem.tooShort => _t(
    'не короче 12 символов',
    'at least 12 characters',
  ),
  PasswordProblem.noLower => _t(
    'нужна строчная буква',
    'add a lowercase letter',
  ),
  PasswordProblem.noUpper => _t(
    'нужна заглавная буква',
    'add an uppercase letter',
  ),
  PasswordProblem.noDigit => _t('нужна цифра', 'add a digit'),
  PasswordProblem.noSymbol => _t(
    'нужен символ: !, #, - …',
    'add a symbol: !, #, - …',
  ),
  PasswordProblem.leaked => _t(
    'такой пароль (или его основа) есть в утечках — его подбирают первым',
    'this password (or its base) is in leaks — it is guessed first',
  ),
  PasswordProblem.personal => _t(
    'не используйте почту и имя',
    'don’t use your email or name',
  ),
  PasswordProblem.repeated => _t(
    'без повторов и рядов вроде 1234, aaaa',
    'no repeats or runs like 1234, aaaa',
  ),
  PasswordProblem.keyboard => _t(
    'без рядов клавиатуры вроде qwerty',
    'no keyboard runs like qwerty',
  ),
};

/// Строка настроек: включён ли бэкап ключей.
class ForkE2EBackupRow extends StatelessWidget {
  const ForkE2EBackupRow({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<E2EService?>(
    valueListenable: ForkE2E.service,
    builder: (context, svc, _) {
      if (svc == null) return const SizedBox.shrink();
      return ValueListenableBuilder<BackupMethod?>(
        valueListenable: svc.backupMethod,
        builder: (context, m, _) => SettingsRow(
          icon: Icons.key_rounded,
          title: _t('Бэкап ключей шифрования', 'Encryption key backup'),
          subtitle: switch (m) {
            BackupMethod.phrase => _t(
              'Включён: фраза из 24 слов',
              'On: 24-word phrase',
            ),
            BackupMethod.password => _t('Включён: пароль', 'On: password'),
            null => _t(
              'Выключен — потеряете телефон, потеряете переписку',
              'Off — lose your phone, lose your history',
            ),
          },
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ForkE2EBackupScreen(),
            ),
          ),
        ),
      );
    },
  );
}

/// Включение бэкапа: фраза (рекомендуем) или пароль.
class ForkE2EBackupScreen extends StatefulWidget {
  const ForkE2EBackupScreen({super.key});

  @override
  State<ForkE2EBackupScreen> createState() => _ForkE2EBackupScreenState();
}

class _ForkE2EBackupScreenState extends State<ForkE2EBackupScreen> {
  BackupMethod? _method;
  RecoveryPhrase? _phrase;
  bool _written = false;
  bool _busy = false;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  List<PasswordProblem> _problems = const [];

  E2EService get _svc => ForkE2E.service.value!;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _pickPhrase() async {
    final words = await ForkE2E.wordlist();
    setState(() {
      _method = BackupMethod.phrase;
      _phrase = RecoveryPhrase.generate(_svc.crypto, words);
    });
  }

  Future<void> _check() async {
    final leaked = await ForkE2E.leakedPasswords();
    if (!mounted) return;
    setState(
      () => _problems = PasswordPolicy.check(
        _pw.text,
        leaked: leaked,
        email: ForkE2E.email,
      ),
    );
  }

  Future<void> _save(String secret) async {
    setState(() => _busy = true);
    try {
      await _svc.enableBackup(_method!, secret);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('Бэкап ключей включён', 'Key backup is on'))),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('Не получилось: $e', 'Failed: $e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Бэкап ключей', 'Key backup'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: switch (_method) {
            null => [
              Text(
                _t(
                  'Переписка шифруется на телефоне, и ключи есть только у вас. Без бэкапа новый телефон их не получит — '
                      'история останется нечитаемой. Сервер хранит бэкап зашифрованным, расшифровать его без фразы '
                      'или пароля нельзя.',
                  'Your history is encrypted on the phone and only you have the keys. Without a backup a new phone '
                      'can’t get them. The server stores the backup encrypted; it can’t be opened without your phrase '
                      'or password.',
                ),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _pickPhrase,
                child: Text(
                  _t(
                    'Фраза из 24 слов (надёжнее)',
                    '24-word phrase (stronger)',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    setState(() => _method = BackupMethod.password),
                child: Text(_t('Пароль', 'Password')),
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Пароль удобнее, но сервер может перебирать его без ограничений — поэтому требования строгие.',
                  'A password is handier, but the server could guess it offline — so the rules are strict.',
                ),
                style: text.bodySmall,
              ),
            ],
            BackupMethod.phrase => [
              Text(
                _t(
                  'Запишите слова на бумаге по порядку. Мы покажем их один раз; без них ключи не восстановить.',
                  'Write the words down in order. We show them once; without them keys can’t be restored.',
                ),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (i, w) in _phrase!.words.indexed)
                    Chip(
                      label: Text(
                        '${i + 1}. $w',
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
              CheckboxListTile(
                value: _written,
                onChanged: (v) => setState(() => _written = v ?? false),
                title: Text(
                  _t('Я записал(а) фразу', 'I wrote the phrase down'),
                ),
              ),
              FilledButton(
                onPressed: _written && !_busy
                    ? () => _save(_phrase.toString())
                    : null,
                child: _busy
                    ? const _Spinner()
                    : Text(_t('Включить бэкап', 'Turn on backup')),
              ),
            ],
            BackupMethod.password => [
              TextField(
                controller: _pw,
                obscureText: true,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: _t('Пароль', 'Password'),
                ),
                onChanged: (_) => _check(),
              ),
              TextField(
                controller: _pw2,
                obscureText: true,
                decoration: InputDecoration(labelText: _t('Ещё раз', 'Repeat')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              for (final p in _problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${problemText(p)}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed:
                    !_busy &&
                        _pw.text.isNotEmpty &&
                        _problems.isEmpty &&
                        _pw.text == _pw2.text
                    ? () => _save(_pw.text)
                    : null,
                child: _busy
                    ? const _Spinner()
                    : Text(_t('Включить бэкап', 'Turn on backup')),
              ),
            ],
          },
        ),
      ),
    );
  }
}

/// Восстановление на новом телефоне: на сервере есть бэкап, локальных ключей
/// нет.
class ForkE2ERestoreScreen extends StatefulWidget {
  const ForkE2ERestoreScreen({super.key});

  @override
  State<ForkE2ERestoreScreen> createState() => _ForkE2ERestoreScreenState();
}

class _ForkE2ERestoreScreenState extends State<ForkE2ERestoreScreen> {
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;

  E2EService get _svc => ForkE2E.service.value!;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _svc.restore(_secret.text);
      if (mounted) Navigator.of(context).maybePop();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(
        () => _error = _t(
          'Не подошло — проверьте фразу или пароль',
          'Didn’t work — check the phrase or password',
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _fresh() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Начать без истории?', 'Start without history?')),
        content: Text(
          _t(
            'Старая зашифрованная переписка останется нечитаемой на этом телефоне, а партнёр увидит, что ваш ключ сменился.',
            'Old encrypted history stays unreadable on this phone, and your partner will see your key changed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('Начать заново', 'Start over')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _svc.startFresh();
      if (mounted) Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _svc.restoreMethod == BackupMethod.phrase;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Восстановить ключи', 'Restore keys'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              phrase
                  ? _t(
                      'Введите фразу из 24 слов. Достаточно первых четырёх букв каждого слова.',
                      'Enter your 24-word phrase. The first four letters of each word are enough.',
                    )
                  : _t(
                      'Введите пароль бэкапа ключей.',
                      'Enter your key backup password.',
                    ),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _secret,
              obscureText: !phrase,
              minLines: phrase ? 3 : 1,
              maxLines: phrase ? 5 : 1,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: phrase
                    ? _t('Фраза', 'Phrase')
                    : _t('Пароль', 'Password'),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _restore,
              child: _busy
                  ? const _Spinner()
                  : Text(_t('Восстановить', 'Restore')),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: _busy ? null : _fresh,
              child: Text(
                _t(
                  'Нет фразы или пароля — начать заново',
                  'No phrase or password — start over',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
