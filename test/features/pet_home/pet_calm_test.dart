import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:love_app/models/mascot.dart';
import 'package:love_app/models/mascot_widget_data.dart';
import 'package:love_app/services/mascot_inactivity_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('absence leaves the pet happy and keeps its historical growth', () {
    final pet = Mascot(
      id: 'drawing',
      name: 'Pet',
      createdBy: 'alice',
      createdAt: DateTime(2020),
      recordStreak: 7,
    );
    final home = GroupMascotState(
      activeMascotId: 'drawing',
      streakLastOpenedDate: '2020-01-01',
      mascotStreaks: const {
        'drawing': {'s': 1, 'd': '2020-01-01', 'best': 30},
      },
    );
    expect(home.activeStreak, 0);
    expect(home.moodState, MascotMoodState.happy);
    expect(home.growthFor(pet), 30);
    final data = MascotWidgetData(
      mascotId: 'drawing',
      name: 'Pet',
      streakDays: 0,
      recordStreak: 30,
      sad: false,
      sleep: MascotSleepWindow.none,
    );
    expect(data.stage, MascotStage.adult);
    expect(data.atlasLevel, 3);
    expect(data.percent, 100);
  });
  test(
    'upgrade cancels old reminder without scheduling or permission request',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      final methods = <MethodCall>[];
      const channel = MethodChannel(
        'dexterous.com/flutter/local_notifications',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = MascotInactivityNotificationService.instance;
      await service.init();
      await service.scheduleReminderAfterOneDay();
      expect(methods.where((call) => call.method == 'cancel'), isNotEmpty);
      expect(
        methods.any((call) => call.method.toLowerCase().contains('schedule')),
        false,
      );
      expect(
        methods.any((call) => call.method.toLowerCase().contains('permission')),
        false,
      );
    },
  );
}
