import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Аудит B-7: порядок холодного старта в `main()`.
///
/// Очистка первой установки идёт до любых сервисов, иначе они успевают
/// прочитать или записать то, что тут же стирается. Крашрепорты — сразу за
/// ней, чтобы сбои старта сервисов попадали в трекер; opt-in при этом прежний.
void main() {
  test('первая установка чистится до сервисов, Sentry — раньше них', () {
    final source = File('lib/main.dart').readAsStringSync();
    final mainStart = source.indexOf('void main() async {');
    expect(mainStart, isNot(-1));
    final body = source.substring(
      mainStart,
      source.indexOf('runApp(', mainStart),
    );

    int at(String s) {
      final i = body.indexOf(s);
      expect(i, isNot(-1), reason: '$s нет в main()');
      return i;
    }

    final clear = at('await prefs.clear();');
    final forget = at('PocketBaseService.forgetStoredSession()');
    final sentry = at('SentryFlutter.init(');
    final consent = at('ForkCrashReports.load()');
    expect(forget, lessThan(clear));
    expect(clear, lessThan(consent), reason: 'согласие — из чистых настроек');
    expect(consent, lessThan(sentry));
    for (final service in [
      'PocketBaseService().init()',
      'LocalStore.instance.init()',
      'LocalStore.instance.ensureOwner(',
      'ForkE2E.ensure(',
      'OutboxService.instance.init()',
      'MediaCache.instance.init()',
    ]) {
      expect(clear, lessThan(at(service)), reason: 'очистка после $service');
      expect(sentry, lessThan(at(service)), reason: 'Sentry после $service');
    }
    // opt-in и чистка событий остаются.
    expect(body, contains('ForkCrashReports.configure(options'));
  });
}
