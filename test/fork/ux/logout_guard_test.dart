import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/ui/logout_guard.dart';

void main() {
  test('без очереди — текст как есть, с очередью — предупреждение', () {
    expect(ForkLogoutGuard.message('Выйти?', pendingOverride: 0), 'Выйти?');
    final m = ForkLogoutGuard.message('Выйти?', pendingOverride: 3);
    expect(m, startsWith('Выйти?'));
    expect(m, contains('3'));
  });
}
