import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/push/notif_tap.dart';
import 'package:love_app/services/deep_link_service.dart';

NotificationResponse tap(String? payload) => NotificationResponse(
  notificationResponseType: NotificationResponseType.selectedNotification,
  payload: payload,
);

void main() {
  tearDown(() => ForkNotifTap.other = null);

  test('loveapp links open the screen, other payloads go to their owner', () {
    final others = <String?>[];
    ForkNotifTap.other = others.add;
    ForkNotifTap.onResponse(tap('loveapp://watch'));
    expect(
      DeepLinkService().consumePendingWidgetAction(),
      Uri.parse('loveapp://watch'),
    );
    ForkNotifTap.onResponse(tap('memory123'));
    expect(DeepLinkService().consumePendingWidgetAction(), isNull);
    expect(others, ['memory123']);
  });

  test(
    'every service that initializes the shared plugin passes the router',
    () {
      // The plugin keeps only the callback of the last initialize() call.
      final offenders = <String>[];
      for (final f in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        final calls = RegExp(
          r'\.initialize\(\s*settings:[^;]*;',
        ).allMatches(src);
        for (final c in calls) {
          if (!c.group(0)!.contains('ForkNotifTap.onResponse'))
            offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    },
  );
}
