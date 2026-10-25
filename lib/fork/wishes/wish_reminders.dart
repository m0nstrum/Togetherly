import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../../models/pair_data.dart';
import '../../models/wish.dart';
import '../../services/pocketbase_service.dart';
import '../../services/wish_repository.dart';
import '../../utils/notification_permission.dart';
import '../push/notif_tap.dart';
import 'wish_reminder_plan.dart';
import 'wish_reminder_prefs.dart';

/// Ставит напоминания вишлиста системным будильником (docs/WISHLIST.md).
///
/// Расписание считается заново целиком (planWishReminders): при старте
/// приложения, при изменениях списка и после правки настроек. Что стояло
/// раньше и в новом расчёте нет — снимается; id стабильны по ключу.
class WishReminders {
  WishReminders._();
  static final WishReminders instance = WishReminders._();

  static const String _channelId = 'wish_reminders';
  static const String _idsKey = 'fork_wish_reminder_ids_v1';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  Timer? _debounce;
  Future<void>? _running;

  Future<void> _init() async {
    if (_ready) return;
    tz.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: ForkNotifTap.onResponse,
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        'Хочу с тобой',
        description: 'Сроки желаний, желание недели, подсказки к датам',
        importance: Importance.defaultImportance,
      ),
    );
    _ready = true;
  }

  /// Пара, для которой считали в последний раз: экран желаний пары не
  /// знает, а пересчитать после правки ему нужно.
  _PairSnapshot? _pair;

  /// Главная сообщает пару (старт, смена пары) — и пересчитываем.
  void updatePair(PairData pair) {
    final next = _PairSnapshot(
      paired: pair.isPaired,
      groupId: pair.pairId,
      partnerUid: pair.partnerUid,
      partnerName: pair.partnerDisplayName,
      partnerBirthday: pair.memberBirthdays[pair.partnerUid],
      startDate: pair.startDate,
      anniversaryDate: pair.anniversaryDate,
    );
    // Пара уведомляет часто (статусы, аватары) — пересчёт только по делу.
    if (next == _pair) return;
    _pair = next;
    schedule();
  }

  /// Пересчитать чуть погодя: правки списка идут пачками.
  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      unawaited(syncFromStores());
    });
  }

  /// Собрать всё нужное (желания, свои «Дарю», настройки) и переставить
  /// расписание. Пары ещё не знаем — ничего не трогаем.
  Future<void> syncFromStores() {
    return _running ??= _syncFromStores().whenComplete(() => _running = null);
  }

  Future<void> _syncFromStores() async {
    try {
      final pair = _pair;
      if (pair == null) return;
      final groupId = pair.groupId;
      final myUid = PocketBaseService().userId ?? '';
      if (!pair.paired || groupId.isEmpty || myUid.isEmpty) {
        await apply(const []);
        return;
      }
      final repo = WishRepository.instance;
      final wishes = await repo.load(groupId);
      final reservations = await repo.loadReservations(groupId);
      final prefs = await WishReminderPrefs.load();
      final plan = planWishReminders(
        now: DateTime.now(),
        prefs: prefs,
        groupId: groupId,
        myUid: myUid,
        partnerUid: pair.partnerUid,
        partnerName: pair.partnerName,
        wishes: wishes,
        reservations: [
          for (final r in reservations)
            if (r.uid == myUid) r,
        ],
        partnerBirthday: pair.partnerBirthday,
        startDate: pair.startDate,
        anniversaryDate: pair.anniversaryDate,
      );
      await apply(plan);
    } catch (e) {
      debugPrint('WishReminders: расписание не обновилось — $e');
    }
  }

  /// Поставить ровно [plan]: лишнее снять, новое добавить.
  Future<void> apply(List<WishReminder> plan) async {
    final prefs = await SharedPreferences.getInstance();
    final before = <int>{
      for (final v in (jsonDecode(prefs.getString(_idsKey) ?? '[]') as List))
        if (v is int) v,
    };
    final next = {for (final r in plan) r.notificationId};
    if (before.isEmpty && plan.isEmpty) return;
    await _init();
    for (final id in before.difference(next)) {
      await _plugin.cancel(id: id);
    }
    if (plan.isNotEmpty) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await requestNotificationPermissionSafely(android);
      if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    }
    for (final r in plan) {
      try {
        await _plugin.zonedSchedule(
          id: r.notificationId,
          title: r.title,
          body: r.body,
          scheduledDate: tz.TZDateTime.from(r.at, tz.local),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Хочу с тобой',
              channelDescription:
                  'Сроки желаний, желание недели, подсказки к датам',
              icon: '@drawable/ic_notification',
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: 'loveapp://wishes',
          // Неточный режим: точное время не важно, а точный будильник
          // требует отдельного разрешения на Android 13+.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('WishReminders: ${r.key} не поставлено — $e');
      }
    }
    await prefs.setString(_idsKey, jsonEncode(next.toList()));
  }

  /// Пригодится экрану: желание недели сейчас.
  static Wish? currentWeekly(List<Wish> wishes, String groupId) =>
      weeklyWish(wishes, groupId, isoWeekKey(DateTime.now()));
}

class _PairSnapshot {
  const _PairSnapshot({
    required this.paired,
    required this.groupId,
    required this.partnerUid,
    required this.partnerName,
    this.partnerBirthday,
    this.startDate,
    this.anniversaryDate,
  });

  final bool paired;
  final String groupId;
  final String partnerUid;
  final String partnerName;
  final DateTime? partnerBirthday;
  final DateTime? startDate;
  final DateTime? anniversaryDate;

  @override
  bool operator ==(Object other) =>
      other is _PairSnapshot &&
      other.paired == paired &&
      other.groupId == groupId &&
      other.partnerUid == partnerUid &&
      other.partnerName == partnerName &&
      other.partnerBirthday == partnerBirthday &&
      other.startDate == startDate &&
      other.anniversaryDate == anniversaryDate;

  @override
  int get hashCode => Object.hash(
    paired,
    groupId,
    partnerUid,
    partnerName,
    partnerBirthday,
    startDate,
    anniversaryDate,
  );
}
