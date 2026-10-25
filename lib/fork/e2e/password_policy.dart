/// Требования к паролю бэкапа ключей (docs/E2E.md §7, решение §12.1).
///
/// Сервер может перебирать пароль офлайн, поэтому проверка жёсткая и целиком
/// на устройстве — словарь утечек лежит в APK фильтром Блума
/// (tool/fork/gen_password_bloom.py), в сеть ничего не уходит.
library;

import 'dart:typed_data';

import 'crypto.dart';

enum PasswordProblem {
  tooShort,
  noLower,
  noUpper,
  noDigit,
  noSymbol,

  /// Сам пароль или его основа (`P@ssw0rd2024!` → `password`) есть среди
  /// утёкших.
  leaked,

  /// Содержит почту или имя.
  personal,

  /// `aaaa`, `1234`, `abcd`.
  repeated,

  /// Ряд клавиатуры: `qwerty`, `йцукен`, `asdf`.
  keyboard,
}

/// Фильтр Блума утёкших паролей. Формат — в gen_password_bloom.py.
class LeakedPasswords {
  LeakedPasswords._(this._c, this._k, this._m, this._bits);

  final E2ECrypto _c;
  final int _k;
  final int _m;
  final Uint8List _bits;

  static LeakedPasswords parse(E2ECrypto c, Uint8List data) {
    if (data.length < 10 ||
        String.fromCharCodes(data.sublist(0, 4)) != 'TBLM' ||
        data[4] != 1) {
      throw const FormatException('словарь утечек: не тот формат');
    }
    final m = ByteData.sublistView(data, 6, 10).getUint32(0);
    final bits = Uint8List.sublistView(data, 10);
    if (bits.length * 8 != m) {
      throw const FormatException('словарь утечек: обрезан');
    }
    return LeakedPasswords._(c, data[5], m, bits);
  }

  bool contains(String word) {
    final h = ByteData.sublistView(_c.hash(utf8Bytes(word), outLen: 16));
    final h1 = h.getUint32(0);
    final h2 = h.getUint32(4) | 1;
    for (var i = 0; i < _k; i++) {
      final idx = (h1 + i * h2) % _m;
      if (_bits[idx >> 3] & (1 << (idx & 7)) == 0) return false;
    }
    return true;
  }
}

abstract final class PasswordPolicy {
  static const int minLength = 12;

  static const Map<String, String> _leet = {
    '@': 'a',
    '4': 'a',
    '3': 'e',
    '1': 'i',
    '!': 'i',
    '0': 'o',
    r'$': 's',
    '5': 's',
    '7': 't',
  };

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _lower = RegExp(r'\p{Ll}', unicode: true);
  static final RegExp _upper = RegExp(r'\p{Lu}', unicode: true);
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _symbol = RegExp(r'[^\p{L}\d]', unicode: true);

  static const List<String> _rows = [
    'qwertyuiop',
    'asdfghjkl',
    'zxcvbnm',
    'йцукенгшщзхъ',
    'фывапролджэ',
    'ячсмитьбю',
    '1234567890',
    'abcdefghijklmnopqrstuvwxyz',
    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя',
  ];

  /// Формы, которые ищутся в словаре. Совпадает с forms() генератора.
  static Set<String> forms(String pw) {
    final low = pw.toLowerCase();
    final out = <String>{};
    if (low.length >= minLength) out.add(low);
    var i = 0, j = low.length;
    while (i < j && !_letter.hasMatch(low[i])) {
      i++;
    }
    while (j > i && !_letter.hasMatch(low[j - 1])) {
      j--;
    }
    final base = low
        .substring(i, j)
        .split('')
        .map((ch) => _leet[ch] ?? ch)
        .join();
    if (base.length >= 4) out.add(base);
    return out;
  }

  /// Пустой список — пароль годится.
  static List<PasswordProblem> check(
    String pw, {
    LeakedPasswords? leaked,
    String email = '',
    String name = '',
  }) {
    final p = <PasswordProblem>[];
    if (pw.runes.length < minLength) p.add(PasswordProblem.tooShort);
    if (!_lower.hasMatch(pw)) p.add(PasswordProblem.noLower);
    if (!_upper.hasMatch(pw)) p.add(PasswordProblem.noUpper);
    if (!_digit.hasMatch(pw)) p.add(PasswordProblem.noDigit);
    if (!_symbol.hasMatch(pw)) p.add(PasswordProblem.noSymbol);
    if (leaked != null && forms(pw).any(leaked.contains)) {
      p.add(PasswordProblem.leaked);
    }

    final low = pw.toLowerCase();
    final local = email.split('@').first.toLowerCase();
    final personal = [
      if (local.length >= 3) local,
      for (final part in name.toLowerCase().split(RegExp(r'\s+')))
        if (part.length >= 3) part,
    ];
    if (personal.any(low.contains)) p.add(PasswordProblem.personal);

    if (RegExp(r'(.)\1\1\1').hasMatch(low) ||
        _hasRun(low, 4, digitsAndAlphabetOnly: true)) {
      p.add(PasswordProblem.repeated);
    }
    if (_hasRun(low, 4, digitsAndAlphabetOnly: false)) {
      p.add(PasswordProblem.keyboard);
    }
    return p;
  }

  /// Есть ли подстрока длины [n] из ряда (вперёд или назад). Ряды цифр и
  /// алфавита — «повтор», ряды клавиатуры — «клавиатура».
  static bool _hasRun(String s, int n, {required bool digitsAndAlphabetOnly}) {
    final rows = digitsAndAlphabetOnly ? _rows.sublist(6) : _rows.sublist(0, 6);
    for (final row in rows) {
      for (final r in [row, row.split('').reversed.join()]) {
        for (var i = 0; i + n <= r.length; i++) {
          if (s.contains(r.substring(i, i + n))) return true;
        }
      }
    }
    return false;
  }
}
