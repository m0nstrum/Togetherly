/// Проверка полей смены пароля — до похода на сервер.
///
/// Человек, который уже вошёл, меняет пароль сам: вводит текущий и новый.
/// Письмо ему ни к чему, оно нужно только тому, кто пароль забыл или входил
/// через Google и Apple, — там пароля нет вовсе.
///
/// Сервер проверяет то же самое (`oldPassword` обязателен, минимум восемь
/// символов), но его отказ приходит по-английски и общей формулировкой, а
/// человеку нужно знать, какое из трёх полей поправить.
library;

import '../fork/e2e/password_policy.dart' show PasswordPolicy; // fork

/// Что не так с введённым. `null` — всё в порядке, можно отправлять.
PasswordChangeProblem? passwordChangeProblem({
  required String current,
  required String fresh,
  required String repeat,
}) {
  if (current.isEmpty) return PasswordChangeProblem.noCurrent;
  // fork (A15): минимум один на весь форк — тот же, что у ForkAccountPassword.
  if (fresh.runes.length < PasswordPolicy.minLength) return PasswordChangeProblem.tooShort;
  if (fresh != repeat) return PasswordChangeProblem.mismatch;
  // Пароль, равный прежнему, сервер примет молча — и человек решит, что смена
  // не сработала. Отвечаем сразу.
  if (fresh == current) return PasswordChangeProblem.same;
  return null;
}

enum PasswordChangeProblem { noCurrent, tooShort, mismatch, same }
