import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/location_consent.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UX_AUDIT G1, G2, G12: показ геопозиции не переживает смену партнёра и
/// входа, а «Выключить» убирает точку у партнёра.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('согласие — только тому, кому дано', () async {
    await LocationConsent.remember('me', 'anna');
    expect(await LocationConsent.allows('me', 'anna'), isTrue);
    expect(await LocationConsent.allows('me', 'boris'), isFalse);
    expect(await LocationConsent.allows('other', 'anna'), isFalse);
  });

  test('снятое согласие и пустой партнёр', () async {
    await LocationConsent.remember('me', 'anna');
    await LocationConsent.remember('me', '');
    // Снято — значит, при новом включении привяжется заново.
    expect(await LocationConsent.allows('me', ''), isFalse);
  });

  test('включённое до обновления привязывается к текущему партнёру', () async {
    expect(await LocationConsent.allows('me', 'anna'), isTrue);
    expect(await LocationConsent.allows('me', 'boris'), isFalse);
  });

  test('сервис: согласие проверяется до старта, «Выключить» шлёт стоп', () {
    final src = File(
      'lib/services/live_location_service.dart',
    ).readAsStringSync();
    expect(src, contains('LocationConsent.allows(_uid, partnerUid)'));
    expect(src, contains("'t': 'stop'"));
    expect(src, contains("data['t'] == 'stop'"));
    expect(src, contains('setOngoing: true'));
  });
}
