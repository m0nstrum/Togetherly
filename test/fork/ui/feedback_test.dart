import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:love_app/fork/ui/feedback.dart';

void main() {
  group('ForkFailure.of', () {
    test('сеть', () {
      expect(ForkFailure.of(const SocketException('x')), ForkFailure.network);
      expect(ForkFailure.of(TimeoutException('x')), ForkFailure.network);
      expect(
        ForkFailure.of(ClientException(statusCode: 0)),
        ForkFailure.network,
      );
    });
    test('permission errors have a safe explanation', () {
      final error = PlatformException(
        code: 'photo_access_denied',
        message: 'internal native details',
      );
      expect(ForkFailure.of(error), ForkFailure.mediaPermission);
      expect(ForkFailure.of(error).text, isNot(contains('internal')));
    });
    test('ответы сервера', () {
      expect(
        ForkFailure.of(ClientException(statusCode: 401)),
        ForkFailure.session,
      );
      expect(
        ForkFailure.of(ClientException(statusCode: 413)),
        ForkFailure.tooLarge,
      );
      expect(
        ForkFailure.of(ClientException(statusCode: 403)),
        ForkFailure.denied,
      );
      expect(
        ForkFailure.of(ClientException(statusCode: 500)),
        ForkFailure.unknown,
      );
    });
    test('нет ключа и уже известная причина', () {
      expect(ForkFailure.of(E2ENoKeyError('chat_messages')), ForkFailure.noKey);
      expect(
        ForkFailure.of(const ForkFailureError(ForkFailure.denied)),
        ForkFailure.denied,
      );
    });
    test('текст без сырого исключения, повтор — только где поможет', () {
      for (final f in ForkFailure.values) {
        expect(f.text, isNot(contains('Exception')));
      }
      expect(ForkFailure.network.retryable, isTrue);
      expect(ForkFailure.session.retryable, isFalse);
    });
  });

  test('Outcome.guard', () async {
    final ok = await Outcome.guard(() async => 7);
    expect(ok.ok, isTrue);
    expect(ok.value, 7);
    final bad = await Outcome.guard<int>(
      () async => throw ClientException(statusCode: 401),
    );
    expect(bad.ok, isFalse);
    expect(bad.failure, ForkFailure.session);
  });

  testWidgets('ForkNotice: причина и «Повторить»', (t) async {
    var retried = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => ForkNotice.failure(
                c,
                ForkFailure.network,
                what: 'Фото не загрузилось',
                retry: () => retried++,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.textContaining('Фото не загрузилось'), findsOneWidget);
    await t.tap(find.text('Retry'));
    await t.pump();
    expect(retried, 1);
  });
}
