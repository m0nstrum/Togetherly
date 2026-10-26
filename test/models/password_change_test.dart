import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/models/password_change.dart';

void main() {
  group('смена пароля: что проверяем до сервера', () {
    test('всё заполнено верно', () {
      expect(
        passwordChangeProblem(
          current: 'StaryiParol1',
          fresh: 'NovyiParol123',
          repeat: 'NovyiParol123',
        ),
        isNull,
      );
    });

    test('без текущего пароля не отправляем', () {
      expect(
        passwordChangeProblem(
          current: '',
          fresh: 'NovyiParol123',
          repeat: 'NovyiParol123',
        ),
        PasswordChangeProblem.noCurrent,
      );
    });

    test('короче минимума форка (12) — отказ, ровно 12 — можно', () {
      expect(
        passwordChangeProblem(
          current: 'StaryiParol1',
          fresh: 'korot',
          repeat: 'korot',
        ),
        PasswordChangeProblem.tooShort,
      );
      // fork (A15): 8–11 символов раньше проходили, теперь нет.
      expect(
        passwordChangeProblem(
          current: 'StaryiParol1',
          fresh: 'Dlina11char',
          repeat: 'Dlina11char',
        ),
        PasswordChangeProblem.tooShort,
      );
      expect(
        passwordChangeProblem(
          current: 'StaryiParol1',
          fresh: 'Dlina12chars',
          repeat: 'Dlina12chars',
        ),
        isNull,
      );
    });

    test('повтор не совпал', () {
      expect(
        passwordChangeProblem(
          current: 'StaryiParol1',
          fresh: 'NovyiParol123',
          repeat: 'NovyiParol124',
        ),
        PasswordChangeProblem.mismatch,
      );
    });

    test('новый пароль равен старому — сервер примет молча, мы нет', () {
      expect(
        passwordChangeProblem(
          current: 'StaryiParol1',
          fresh: 'StaryiParol1',
          repeat: 'StaryiParol1',
        ),
        PasswordChangeProblem.same,
      );
    });

    test('пустой текущий важнее короткого нового: правим по порядку полей', () {
      expect(
        passwordChangeProblem(current: '', fresh: 'kor', repeat: 'kor'),
        PasswordChangeProblem.noCurrent,
      );
    });
  });
}
