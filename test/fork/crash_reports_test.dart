import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/crash_reports.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  tearDown(() => ForkCrashReports.consent.value = null);

  group('ForkCrashReports', () {
    test('без согласия событие не уходит', () {
      ForkCrashReports.consent.value = null;
      expect(ForkCrashReports.beforeSend(SentryEvent()), isNull);
      ForkCrashReports.consent.value = false;
      expect(ForkCrashReports.beforeSend(SentryEvent()), isNull);
    });

    test('с согласием уходит, но без человека и его данных', () {
      ForkCrashReports.consent.value = true;
      final e = SentryEvent(
        user: SentryUser(id: 'u123', email: 'a@b.c'),
        message: SentryMessage(
          'open https://x.org/api/files/m/1/a.jpg?token=SECRET at 55.751244, 37.618423',
        ),
        exceptions: [
          SentryException(
            type: 'ClientException',
            value: 'Bearer abc.def.ghi failed for me@mail.ru',
          ),
        ],
        breadcrumbs: [
          Breadcrumb(
            message: 'Привет, любимая',
            category: 'ui',
            data: {'lat': 55.75},
          ),
        ],
        contexts: Contexts(device: SentryDevice(model: 'Pixel'))
          ..['picker'] = {'error': 'x'},
      );
      final out = ForkCrashReports.beforeSend(e)!;
      expect(out.user, isNull);
      expect(out.message!.formatted, isNot(contains('SECRET')));
      expect(out.message!.formatted, isNot(contains('55.751244')));
      expect(out.message!.formatted, contains('token=[redacted]'));
      expect(out.exceptions!.single.value, isNot(contains('abc.def.ghi')));
      expect(out.exceptions!.single.value, isNot(contains('me@mail.ru')));
      final crumb = out.breadcrumbs!.single;
      expect(crumb.message, isNull);
      expect(crumb.data, anyOf(isNull, isEmpty));
      expect(crumb.category, 'ui');
      expect(out.contexts.device?.model, 'Pixel');
      expect(out.contexts['picker'], isNull);
    });

    test('JWT вырезается', () {
      expect(
        ForkCrashReports.scrubText(
          't=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig_part-1',
        ),
        isNot(contains('eyJ')),
      );
    });
  });
}
