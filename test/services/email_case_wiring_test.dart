import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Почта без учёта регистра при сбросе пароля (18.09.2026): штатный
/// `request-password-reset` ищет адрес с точностью до буквы, поэтому
/// приложение зовёт свой маршрут. Сервер стерегут Go-тесты
/// (server/internal/handler/email_test.go).
void main() {
  test('Приложение просит сброс через свой маршрут', () {
    final auth = File('lib/services/pb_auth_service.dart').readAsStringSync();
    expect(auth, contains("'/api/auth/password-reset'"));
  });
}
