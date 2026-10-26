// fork: бэкап ключей и требования к паролю (docs/E2E.md §7).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/e2e/backup.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/password_policy.dart';

void main() {
  late E2ECrypto c;
  late List<String> words;
  late LeakedPasswords leaked;
  // В тестах Argon2id дешёвый: проверяется схема, а не стойкость.
  const fast = KdfParams(ops: 1, mem: 8 << 20);

  setUpAll(() async {
    c = await E2ECrypto.init();
    words = File('assets/fork/bip39_english.txt').readAsLinesSync();
    leaked = LeakedPasswords.parse(
      c,
      File('assets/fork/leaked_passwords.bloom').readAsBytesSync(),
    );
  });

  group('фраза BIP39', () {
    test('официальные тест-векторы', () {
      expect(
        RecoveryPhrase.fromEntropy(Uint8List(32), words).toString(),
        '${List.filled(23, 'abandon').join(' ')} art',
      );
      expect(
        RecoveryPhrase.fromEntropy(
          Uint8List.fromList(List.filled(32, 0x7f)),
          words,
        ).toString(),
        'legal winner thank year wave sausage worth useful legal winner thank year '
        'wave sausage worth useful legal winner thank year wave sausage worth title',
      );
    });

    test('ввод: регистр, пробелы, сокращения; ошибка ловится', () {
      final p = RecoveryPhrase.generate(c, words);
      final typed =
          '  ${p.words.map((w) => w.substring(0, w.length.clamp(0, 4)).toUpperCase()).join('   ')} ';
      expect(RecoveryPhrase.parse(typed, words).words, p.words);

      final broken = [...p.words];
      broken[5] = broken[5] == 'zoo' ? 'abandon' : 'zoo';
      expect(
        () => RecoveryPhrase.parse(broken.join(' '), words),
        throwsFormatException,
      );
      expect(
        () => RecoveryPhrase.parse('abandon abandon', words),
        throwsFormatException,
      );
      expect(
        () => RecoveryPhrase.parse(
          p.words.take(23).followedBy(['ыыы']).join(' '),
          words,
        ),
        throwsFormatException,
      );
    });
  });

  group('бэкап ключей', () {
    BackupContents contents() => BackupContents(
      accountSecret: c.signKeyPair().secretKey.extractBytes(),
      pairKeys: [
        PairKey('g1', 1, c.symmetricKey()),
        PairKey('g1', 2, c.symmetricKey()),
      ],
    );

    for (final method in BackupMethod.values) {
      test('${method.name}: туда и обратно, чужой секрет не подходит', () {
        final secret = method == BackupMethod.phrase
            ? RecoveryPhrase.generate(c, words).toString()
            : 'Ябл0ко-Кит-Велик';
        final what = contents();
        final data = KeyBackup.seal(
          c,
          user: 'u1',
          method: method,
          secret: secret,
          contents: what,
          params: fast,
        );

        final back = KeyBackup.open(
          c,
          user: 'u1',
          data: data,
          secret: method == BackupMethod.phrase
              ? ' ${secret.toUpperCase()} '
              : secret,
        );
        expect(back.accountSecret, what.accountSecret);
        expect([for (final k in back.pairKeys) k.keyId], ['g1:1', 'g1:2']);
        expect(
          back.pairKeys[1].key.extractBytes(),
          what.pairKeys[1].key.extractBytes(),
        );

        expect(
          () => KeyBackup.open(c, user: 'u1', data: data, secret: '${secret}x'),
          throwsA(isA<E2EVerifyError>()),
        );
        // Чужой бэкап, подложенный сервером под другого человека.
        expect(
          () => KeyBackup.open(c, user: 'u2', data: data, secret: secret),
          throwsA(isA<E2EVerifyError>()),
        );
      });
    }

    test('в данных бэкапа нет открытых ключей', () {
      final what = contents();
      final data = KeyBackup.seal(
        c,
        user: 'u1',
        method: BackupMethod.password,
        secret: 'Ябл0ко-Кит-Велик',
        contents: what,
        params: fast,
      );
      final text = data.toString();
      expect(text.contains(b64(what.accountSecret)), isFalse);
      expect(text.contains(b64(what.pairKeys[0].key.extractBytes())), isFalse);
    });

    test(
      'invalid KDF rejected by sync and async restoration before hashing',
      () async {
        final data = KeyBackup.seal(
          c,
          user: 'u1',
          method: BackupMethod.password,
          secret: 'x',
          contents: contents(),
          params: fast,
        );
        for (final patch in <Map<String, dynamic>>[
          {'ops': 0},
          {'ops': -1},
          {'ops': 5},
          {'ops': 1 << 40},
          {'ops': 1.5},
          {'ops': '3'},
          {'mem': 0},
          {'mem': -1},
          {'mem': (8 << 20) - 1},
          {'mem': (256 << 20) + 1},
          {'mem': 4 << 30},
          {'mem': 8.5},
          {'salt': ''},
          {'salt': 'a' * 100000},
          {'salt': 'not-base64!'},
          {'salt': null},
          {'alg': 'unknown'},
        ]) {
          final bad = {
            ...data,
            'kdf': {...(data['kdf'] as Map), ...patch},
          };
          expect(
            () => BackupKey.forData(c, bad, 'x'),
            throwsFormatException,
            reason: '$patch',
          );
          await expectLater(
            BackupKey.forDataAsync(c, bad, 'x'),
            throwsFormatException,
            reason: '$patch',
          );
        }
        final restored = await BackupKey.forDataAsync(c, data, 'x');
        expect(restored.params.ops, 1);
        restored.key.dispose();
      },
    );

    test('сервер не заставит Argon2id взять гигабайты', () {
      final data = KeyBackup.seal(
        c,
        user: 'u1',
        method: BackupMethod.password,
        secret: 'x',
        contents: contents(),
        params: fast,
      );
      final kdf = {...(data['kdf'] as Map), 'mem': 4 << 30};
      expect(
        () => KeyBackup.open(
          c,
          user: 'u1',
          data: {...data, 'kdf': kdf},
          secret: 'x',
        ),
        throwsFormatException,
      );
    });
  });

  group('пароль', () {
    List<PasswordProblem> check(
      String pw, {
      String email = '',
      String name = '',
    }) => PasswordPolicy.check(pw, leaked: leaked, email: email, name: name);

    test('словарь из Python читается в Dart теми же хэшами', () {
      for (final w in [
        'password',
        'iloveyou',
        'dragon',
        'monkey',
        'qwertyuiop123',
      ]) {
        expect(leaked.contains(w), isTrue, reason: w);
      }
    });

    test('сильный пароль проходит', () {
      expect(check('Ябл0ко-Кит-Велик'), isEmpty);
      expect(check('Tethered%Moss#82'), isEmpty);
    });

    test('утёкшая основа ловится сквозь регистр, цифры и leet', () {
      expect(check('P@ssw0rd2024!!'), contains(PasswordProblem.leaked));
      expect(check('Iloveyou!2024'), contains(PasswordProblem.leaked));
    });

    test('правила состава', () {
      expect(check('Ab1!'), contains(PasswordProblem.tooShort));
      expect(check('alllowercase#42x'), contains(PasswordProblem.noUpper));
      expect(check('ALLUPPERCASE#42X'), contains(PasswordProblem.noLower));
      expect(check('NoDigitsHere#xyz'), contains(PasswordProblem.noDigit));
      expect(check('NoSymbolsHere42x'), contains(PasswordProblem.noSymbol));
    });

    test('личное, повторы, клавиатура', () {
      expect(
        check('Mashenka#Moss82', email: 'mashenka@example.org'),
        contains(PasswordProblem.personal),
      );
      expect(
        check('Tethered#Moss82', name: 'Moss Petrov'),
        contains(PasswordProblem.personal),
      );
      expect(check('Teth9999#Moss!x'), contains(PasswordProblem.repeated));
      expect(check('Teth1234#Moss!x'), contains(PasswordProblem.repeated));
      expect(check('Qwer#Moss82Tet!'), contains(PasswordProblem.keyboard));
      expect(check('Йцук#Moss82Tet!'), contains(PasswordProblem.keyboard));
    });
  });
}
