/// Бэкап ключей и восстановление (docs/E2E.md §7, решение §12.1).
library;

import '../secure_screen.dart';
import 'themed_route.dart';
import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../widgets/settings_scaffold.dart';
import 'backup.dart';
import 'e2e_service.dart';
import 'fork_e2e.dart';
import 'link_ui.dart';
import 'password_policy.dart';
import 'crypto.dart' show E2EVerifyError;
import '../ui/feedback.dart';

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

/// Строка настроек: бэкап ключей, а на новом телефоне — восстановление
/// (UX_AUDIT N1, A3).
class ForkE2EBackupRow extends StatelessWidget {
  const ForkE2EBackupRow({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<E2EService?>(
    valueListenable: ForkE2E.service,
    builder: (context, svc, _) {
      if (svc == null) {
        return SettingsRow(
          icon: Icons.key_rounded,
          title: _t('Ключи шифрования', 'Encryption keys'),
          subtitle: _t(
            'Ещё не готовы: появятся, когда приложение подключится к серверу',
            'Not ready yet: they appear once the app reaches the server',
          ),
        );
      }
      return ValueListenableBuilder<bool>(
        valueListenable: svc.needsRestore,
        builder: (context, restore, _) => restore
            ? SettingsRow(
                icon: Icons.restore_rounded,
                title: _t('Восстановить ключи', 'Restore keys'),
                // T3: без бэкапа ключи только на другом телефоне.
                subtitle: svc.restoreMethod == null
                    ? _t(
                        'Ключи на другом вашем телефоне — привяжите этот по QR, чтобы читать историю',
                        'Your keys are on your other phone — link this one by QR to read your history',
                      )
                    : _t(
                        'На сервере есть бэкап — введите фразу или пароль, чтобы читать историю',
                        'There is a backup on the server — enter your phrase or password to read your history',
                      ),
                onTap: () => Navigator.of(context).push(
                  forkE2ERoute<void>(context, const ForkE2ERestoreScreen()),
                ),
              )
            : ValueListenableBuilder<BackupMethod?>(
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
                    forkE2ERoute<void>(context, const ForkE2EBackupScreen()),
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

  /// Бэкап уже есть: сначала статус, а не настройка заново (UX_AUDIT N3).
  late bool _showStatus = _svc.backupMethod.value != null;

  /// Проверка записанной фразы: номера слов и ввод (UX_AUDIT A8).
  List<int>? _quiz;
  final List<TextEditingController> _quizIn = [];
  bool _busy = false;
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _showPassword = false;
  bool _showRepeat = false;
  List<PasswordProblem> _problems = const [];

  E2EService get _svc => ForkE2E.service.value!;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    for (final c in _quizIn) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _change() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Сменить фразу или пароль?', 'Change phrase or password?')),
        content: Text(
          _t(
            'Бэкап на сервере перезапишется. Старая фраза или пароль перестанут подходить — '
                'для восстановления понадобится только новая.',
            'The backup on the server will be replaced. The old phrase or password will stop working — '
                'only the new one will restore your keys.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('Отмена', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('Сменить', 'Change')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _showStatus = false);
  }

  /// Три случайных слова, которые человек вводит по памяти.
  void _startQuiz() {
    final picks = <int>{};
    final r = _svc.crypto.random(16);
    for (var i = 0; picks.length < 3 && i < r.length; i++) {
      picks.add(r[i] % 24);
    }
    for (var n = 0; picks.length < 3; n++) {
      picks.add(n);
    }
    for (final c in _quizIn) {
      c.dispose();
    }
    _quizIn
      ..clear()
      ..addAll([for (var i = 0; i < 3; i++) TextEditingController()]);
    setState(() => _quiz = picks.toList()..sort());
  }

  bool get _quizOk {
    final q = _quiz;
    final p = _phrase;
    if (q == null || p == null) return false;
    for (var i = 0; i < q.length; i++) {
      final typed = _quizIn[i].text.trim().toLowerCase();
      final want = p.words[q[i]];
      if (typed.length < 4 || !want.startsWith(typed)) return false;
    }
    return true;
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
        ForkNotice.error(
          context,
          e,
          what: _t('Бэкап не включился', 'Backup wasn’t turned on'),
          retry: () => _save(secret),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ForkSecureScreen(builder: _protectedBody);

  Widget _protectedBody(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Бэкап ключей', 'Key backup'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: switch (_method) {
            _ when _showStatus => [
              Text(
                switch (_svc.backupMethod.value) {
                  BackupMethod.password => _t(
                    'Бэкап ключей включён и защищён паролем.',
                    'Key backup is on, protected by a password.',
                  ),
                  _ => _t(
                    'Бэкап ключей включён и защищён фразой из 24 слов.',
                    'Key backup is on, protected by a 24-word phrase.',
                  ),
                },
                style: text.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _t(
                  'Новые ключи пары попадают в бэкап сами. Фразу или пароль нигде, кроме вашей памяти и бумаги, '
                      'не храним — потеряли их, смените, пока этот телефон с вами.',
                  'New pair keys are added to the backup automatically. We don’t store your phrase or password '
                      'anywhere — if you lost it, change it while you still have this phone.',
                ),
                style: text.bodyMedium,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _change,
                child: Text(_t('Сменить фразу или пароль', 'Change phrase or password')),
              ),
            ],
            _ when _quiz != null => [
              Text(
                _t(
                  'Проверим запись: введите слова под этими номерами (хватит первых четырёх букв).',
                  'Let’s check: type the words with these numbers (the first four letters are enough).',
                ),
                style: text.bodyLarge,
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < _quiz!.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: _quizIn[i],
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: _t('Слово №${_quiz![i] + 1}', 'Word #${_quiz![i] + 1}'),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _quizOk && !_busy ? () => _save(_phrase.toString()) : null,
                child: _busy
                    ? const _Spinner()
                    : Text(_t('Включить бэкап', 'Turn on backup')),
              ),
              TextButton(
                onPressed: _busy ? null : () => setState(() => _quiz = null),
                child: Text(_t('Показать фразу ещё раз', 'Show the phrase again')),
              ),
            ],
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
                  'Запишите слова на бумаге по порядку. Мы покажем их один раз; без них ключи не восстановить. '
                      'Не храните фразу в заметках, облаке или скриншоте.',
                  'Write the words down in order. We show them once; without them keys can’t be restored. '
                      'Don’t keep the phrase in notes, the cloud or a screenshot.',
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
                onPressed: _written && !_busy ? _startQuiz : null,
                child: Text(_t('Дальше: проверить запись', 'Next: check what you wrote')),
              ),
            ],
            BackupMethod.password => [
              TextField(
                controller: _pw,
                obscureText: !_showPassword,
                autocorrect: false, enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: _t('Пароль', 'Password'),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? _t('Скрыть пароль', 'Hide password') : _t('Показать пароль', 'Show password'),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility)),
                ),
                onChanged: (_) => _check(),
              ),
              TextField(
                controller: _pw2,
                obscureText: !_showRepeat,
                autocorrect: false, enableSuggestions: false,
                decoration: InputDecoration(labelText: _t('Ещё раз', 'Repeat'),
                  errorText: _pw2.text.isNotEmpty && _pw.text != _pw2.text
                      ? _t('Пароли не совпадают', 'Passwords don’t match') : null,
                  suffixIcon: IconButton(
                    tooltip: _showRepeat ? _t('Скрыть пароль', 'Hide password') : _t('Показать пароль', 'Show password'),
                    onPressed: () => setState(() => _showRepeat = !_showRepeat),
                    icon: Icon(_showRepeat ? Icons.visibility_off : Icons.visibility))),
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
  bool _showSecret = false;
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
      var secret = _secret.text;
      // Обещанный ввод по первым четырём буквам (UX_AUDIT A6): фразу
      // раскрываем до полных слов и проверяем контрольную сумму до Argon2.
      if (_svc.restoreMethod == BackupMethod.phrase) {
        secret = RecoveryPhrase.parse(secret, await ForkE2E.wordlist()).toString();
      }
      await _svc.restore(secret);
      if (mounted) Navigator.of(context).maybePop();
    } on FormatException catch (e) {
      setState(() => _error = _formatError(e));
    } on E2EVerifyError {
      setState(
        () => _error = _t(
          'Не подошло — проверьте фразу или пароль',
          'Didn’t work — check the phrase or password',
        ),
      );
    } catch (e) {
      // Сеть, сервер: фраза верная, просто повторить (UX_AUDIT A5).
      setState(() => _error = ForkFailure.of(e).text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatError(FormatException e) {
    final m = e.message;
    if (m.startsWith('нет такого слова')) {
      return _t(
        'Слово «${m.split(': ').last}» не из списка — проверьте написание',
        'The word “${m.split(': ').last}” isn’t in the list — check the spelling',
      );
    }
    if (m.contains('24')) {
      return _t('Во фразе должно быть 24 слова', 'The phrase must have 24 words');
    }
    return _t(
      'Во фразе ошибка: одно из слов не на своём месте или с опечаткой',
      'The phrase has a mistake: a word is misplaced or misspelled',
    );
  }

  Future<void> _fresh() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Начать без истории?', 'Start without history?')),
        content: Text(
          _t(
            'Старая зашифрованная переписка останется нечитаемой на этом телефоне, а партнёр увидит, что ваш ключ сменился. '
                'Новые ключи будут без бэкапа — сразу после этого предложим его включить.',
            'Old encrypted history stays unreadable on this phone, and your partner will see your key changed. '
                'The new keys will have no backup — we’ll offer to turn it on right after.',
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
      if (!mounted) return;
      // Новые ключи без бэкапа (UX_AUDIT A7) — сразу к нему.
      await Navigator.of(context).pushReplacement(
        forkE2ERoute<void>(context, const ForkE2EBackupScreen()),
      );
    } catch (e) {
      if (mounted) {
        ForkNotice.error(
          context,
          e,
          what: _t('Не получилось начать заново', 'Couldn’t start over'),
          retry: _fresh,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ForkSecureScreen(builder: _protectedBody);

  Widget _protectedBody(BuildContext context) {
    // T3: бэкапа нет, ключи на другом телефоне — только привязка или заново.
    if (_svc.restoreMethod == null) return _noBackupBody(context);
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
              obscureText: !phrase && !_showSecret,
              minLines: phrase ? 3 : 1,
              maxLines: phrase ? 5 : 1,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: phrase
                    ? _t('Фраза', 'Phrase')
                    : _t('Пароль', 'Password'),
                errorText: _error,
                suffixIcon: phrase ? null : IconButton(
                  tooltip: _showSecret ? _t('Скрыть пароль', 'Hide password') : _t('Показать пароль', 'Show password'),
                  onPressed: () => setState(() => _showSecret = !_showSecret),
                  icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility)),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _restore,
              child: _busy
                  ? const _Spinner()
                  : Text(_t('Восстановить', 'Restore')),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openLink,
              icon: const Icon(Icons.qr_code_rounded),
              label: Text(_t('Привязать с другого телефона', 'Link from another phone')),
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

  void _openLink() => Navigator.of(context).push(forkE2ELinkShowRoute(context));

  Widget _noBackupBody(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_t('Восстановить ключи', 'Restore keys'))),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _t(
              'Ключи шифрования этого аккаунта уже есть на другом вашем телефоне, а бэкапа на сервере нет. Привяжите этот телефон по QR — переписка откроется здесь.',
              'This account’s encryption keys are on your other phone, and there’s no backup on the server. Link this phone by QR to open your history here.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _openLink,
            icon: const Icon(Icons.qr_code_rounded),
            label: Text(_t('Привязать с другого телефона', 'Link from another phone')),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _busy ? null : _fresh,
            child: Text(
              _t('Другого телефона нет — начать заново', 'No other phone — start over'),
            ),
          ),
        ],
      ),
    ),
  );
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
