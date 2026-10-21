import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/flags.dart';
import 'package:love_app/services/analytics_service.dart';

void main() {
  test('аналитика апстрима выключена и ничего не шлёт', () async {
    expect(ForkFlags.analyticsDisabled, isTrue);
    final a = AnalyticsService.instance;
    a.logScreen('home', ms: 10);
    a.logAction('tap');
    // Без сети и без PocketBase: flush обязан вернуться сразу, не трогая http.
    await a.flush();
  });
}
