/// Бэкап ключей (docs/fork/E2E.md §7): фраза восстановления или пароль.
///
/// На сервер (`e2e_backups`) уходят соль, параметры Argon2id и шифртекст.
/// Ни фразы, ни пароля, ни ключа бэкапа у сервера нет.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'crypto.dart';
import 'envelope.dart';

/// Фраза восстановления BIP39: 24 слова, 256 бит и 8 бит контрольной суммы.
/// Список слов — assets/fork/bip39_english.txt (официальный английский).
class RecoveryPhrase {
  RecoveryPhrase._(this.words);

  final List<String> words;

  @override
  String toString() => words.join(' ');

  static RecoveryPhrase generate(E2ECrypto c, List<String> wordlist) =>
      fromEntropy(c.random(32), wordlist);

  static RecoveryPhrase fromEntropy(Uint8List entropy, List<String> wordlist) {
    _checkList(wordlist);
    final bits = StringBuffer();
    for (final b in [...entropy, sha256.convert(entropy).bytes[0]]) {
      bits.write(b.toRadixString(2).padLeft(8, '0'));
    }
    final s = bits.toString();
    return RecoveryPhrase._([
      for (var i = 0; i < s.length; i += 11)
        wordlist[int.parse(s.substring(i, i + 11), radix: 2)],
    ]);
  }

  /// Разбор введённой фразы: регистр и лишние пробелы не важны, слово можно
  /// сократить до первых четырёх букв (так в BIP39 слова различимы).
  static RecoveryPhrase parse(String input, List<String> wordlist) {
    _checkList(wordlist);
    final typed = input.toLowerCase().trim().split(RegExp(r'\s+'));
    if (typed.length != 24) {
      throw const FormatException('во фразе должно быть 24 слова');
    }
    final words = <String>[];
    for (final w in typed) {
      final hit = wordlist
          .where((x) => x == w || (w.length >= 4 && x.startsWith(w)))
          .toList();
      if (hit.length != 1) throw FormatException('нет такого слова: $w');
      words.add(hit.single);
    }
    final bits = words
        .map((w) => wordlist.indexOf(w).toRadixString(2).padLeft(11, '0'))
        .join();
    final entropy = Uint8List.fromList([
      for (var i = 0; i < 256; i += 8)
        int.parse(bits.substring(i, i + 8), radix: 2),
    ]);
    if (int.parse(bits.substring(256), radix: 2) !=
        sha256.convert(entropy).bytes[0]) {
      throw const FormatException(
        'фраза с ошибкой: не сходится контрольная сумма',
      );
    }
    return RecoveryPhrase._(words);
  }

  static void _checkList(List<String> l) {
    if (l.length != 2048) {
      throw ArgumentError('список BIP39 — 2048 слов, а не ${l.length}');
    }
  }
}

enum BackupMethod { phrase, password }

/// Параметры Argon2id. По умолчанию — §7: MODERATE и 256 МиБ.
class KdfParams {
  const KdfParams({required this.ops, required this.mem});

  final int ops;
  final int mem;

  static KdfParams standard(E2ECrypto c) =>
      KdfParams(ops: c.pwhashOpsModerate, mem: 256 << 20);
}

/// Что лежит в бэкапе: ключ аккаунта и ключи всех пар всех эпох.
class BackupContents {
  BackupContents({required this.accountSecret, required this.pairKeys});

  /// Секрет Ed25519 ключа аккаунта (64 байта libsodium).
  final Uint8List accountSecret;
  final List<PairKey> pairKeys;
}

/// Ключ бэкапа с параметрами, из которых он выведен. Хранится на
/// устройстве, чтобы обновлять бэкап при каждом новом ключе пары без фразы
/// или пароля (их не храним).
class BackupKey {
  BackupKey({
    required this.method,
    required this.params,
    required this.salt,
    required this.key,
  });

  final BackupMethod method;
  final KdfParams params;
  final Uint8List salt;
  final SecureKey key;

  static String _normalize(BackupMethod method, String secret) =>
      method == BackupMethod.phrase
      ? secret.toLowerCase().trim().split(RegExp(r'\s+')).join(' ')
      : secret;

  /// Новый ключ из фразы или пароля (новая соль).
  static BackupKey derive(
    E2ECrypto c,
    BackupMethod method,
    String secret, {
    KdfParams? params,
  }) {
    final p = params ?? KdfParams.standard(c);
    final salt = c.random(c.pwhashSaltBytes);
    return BackupKey(
      method: method,
      params: p,
      salt: salt,
      key: c.pwhash(
        _normalize(method, secret),
        salt,
        opsLimit: p.ops,
        memLimit: p.mem,
      ),
    );
  }

  /// Ключ существующего бэкапа [data] из фразы или пароля.
  static BackupKey forData(
    E2ECrypto c,
    Map<String, dynamic> data,
    String secret,
  ) {
    if (data['v'] != 1) throw FormatException('бэкап: версия ${data['v']}');
    final method = BackupMethod.values.byName(data['method'] as String);
    final kdf = (data['kdf'] as Map).cast<String, dynamic>();
    if (kdf['alg'] != 'argon2id13') {
      throw FormatException('бэкап: ${kdf['alg']}');
    }
    // Параметры пришли с сервера: не даём ему заставить телефон съесть
    // гигабайты памяти.
    if ((kdf['mem'] as int) > 1 << 30) {
      throw const FormatException('бэкап: слишком много памяти для Argon2id');
    }
    final params = KdfParams(ops: kdf['ops'] as int, mem: kdf['mem'] as int);
    final salt = unb64(kdf['salt'] as String);
    return BackupKey(
      method: method,
      params: params,
      salt: salt,
      key: c.pwhash(
        _normalize(method, secret),
        salt,
        opsLimit: params.ops,
        memLimit: params.mem,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'ops': params.ops,
    'mem': params.mem,
    'salt': b64(salt),
    'key': b64(key.extractBytes()),
  };

  static BackupKey fromJson(E2ECrypto c, Map<String, dynamic> j) => BackupKey(
    method: BackupMethod.values.byName(j['method'] as String),
    params: KdfParams(ops: j['ops'] as int, mem: j['mem'] as int),
    salt: unb64(j['salt'] as String),
    key: c.keyFromBytes(unb64(j['key'] as String)),
  );
}

abstract final class KeyBackup {
  static Uint8List _aad(String user) =>
      frame([utf8Bytes('tethered-backup-v1'), utf8Bytes(user)]);

  /// Запись `e2e_backups.data` под готовым ключом.
  static Map<String, dynamic> sealWith(
    E2ECrypto c, {
    required String user,
    required BackupKey key,
    required BackupContents contents,
  }) {
    final plain = utf8Bytes(
      jsonEncode({
        'account': b64(contents.accountSecret),
        'pairs': [
          for (final k in contents.pairKeys)
            {
              'group': k.groupId,
              'epoch': k.epoch,
              'key': b64(k.key.extractBytes()),
            },
        ],
      }),
    );
    final nonce = c.random(c.aeadNonceBytes);
    return {
      'v': 1,
      'method': key.method.name,
      'kdf': {
        'alg': 'argon2id13',
        'ops': key.params.ops,
        'mem': key.params.mem,
        'salt': b64(key.salt),
      },
      'nonce': b64(nonce),
      'ct': b64(c.aeadEncrypt(plain, nonce, key.key, _aad(user))),
    };
  }

  /// Запись `e2e_backups.data` из фразы или пароля.
  static Map<String, dynamic> seal(
    E2ECrypto c, {
    required String user,
    required BackupMethod method,
    required String secret,
    required BackupContents contents,
    KdfParams? params,
  }) {
    final key = BackupKey.derive(c, method, secret, params: params);
    try {
      return sealWith(c, user: user, key: key, contents: contents);
    } finally {
      key.key.dispose();
    }
  }

  /// Открыть бэкап ключом. Чужой ключ — [E2EVerifyError].
  static BackupContents openWith(
    E2ECrypto c, {
    required String user,
    required Map<String, dynamic> data,
    required BackupKey key,
  }) {
    final plain = c.aeadDecrypt(
      unb64(data['ct'] as String),
      unb64(data['nonce'] as String),
      key.key,
      _aad(user),
    );
    final j = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
    return BackupContents(
      accountSecret: unb64(j['account'] as String),
      pairKeys: [
        for (final p in (j['pairs'] as List).cast<Map<String, dynamic>>())
          PairKey(
            p['group'] as String,
            p['epoch'] as int,
            c.keyFromBytes(unb64(p['key'] as String)),
          ),
      ],
    );
  }

  /// Открыть бэкап фразой или паролем. Неверные — [E2EVerifyError].
  static BackupContents open(
    E2ECrypto c, {
    required String user,
    required Map<String, dynamic> data,
    required String secret,
  }) {
    final key = BackupKey.forData(c, data, secret);
    try {
      return openWith(c, user: user, data: data, key: key);
    } finally {
      key.key.dispose();
    }
  }
}
