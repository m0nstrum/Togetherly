import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Отметка «за сколько до срока»: N дней или N часов.
@immutable
class WishOffset {
  const WishOffset.days(this.amount) : hours = false;
  const WishOffset.hours(this.amount) : hours = true;

  final int amount;

  /// Часы, а не дни.
  final bool hours;

  Duration get duration =>
      hours ? Duration(hours: amount) : Duration(days: amount);

  String encode() => hours ? '${amount}h' : '${amount}d';

  static WishOffset? parse(Object? raw) {
    final m = RegExp(r'^(\d{1,3})([dh])$').firstMatch('$raw');
    if (m == null) return null;
    final n = int.parse(m[1]!);
    return m[2] == 'h' ? WishOffset.hours(n) : WishOffset.days(n);
  }

  @override
  bool operator ==(Object other) =>
      other is WishOffset && other.amount == amount && other.hours == hours;

  @override
  int get hashCode => Object.hash(amount, hours);
}

/// Напоминания вишлиста — каждый настраивает себе сам (docs/WISHLIST.md):
/// какие получать и когда. Хранятся на телефоне: это личное, партнёру и
/// серверу знать незачем.
@immutable
class WishReminderPrefs {
  const WishReminderPrefs({
    this.dueOn = true,
    this.dueOffsets = const [WishOffset.days(1), WishOffset.days(0)],
    this.dueHour = 10,
    this.dueMinute = 0,
    this.placeOn = true,
    this.placeRadius = 500,
    this.weeklyOn = true,
    this.weeklyDay = DateTime.friday,
    this.weeklyHour = 18,
    this.weeklyMinute = 0,
    this.giftOn = true,
    this.giftLeadDays = 14,
    this.giftHolidays = true,
    this.reserveOn = true,
  });

  // ── срок «когда» ──
  final bool dueOn;

  /// За сколько до срока напоминать; 0 дней — в сам день.
  final List<WishOffset> dueOffsets;

  /// Во сколько считается срок: день срока в это время.
  final int dueHour;
  final int dueMinute;

  // ── место ──
  final bool placeOn;

  /// «Рядом», метров.
  final int placeRadius;

  // ── желание недели ──
  final bool weeklyOn;

  /// День недели: 1 — понедельник … 7 — воскресенье.
  final int weeklyDay;
  final int weeklyHour;
  final int weeklyMinute;

  // ── подсказки к датам ──
  final bool giftOn;

  /// За сколько дней до повода.
  final int giftLeadDays;

  /// 14 февраля и 8 марта — тоже поводы.
  final bool giftHolidays;

  // ── срок «Дарю» ──
  final bool reserveOn;

  WishReminderPrefs copyWith({
    bool? dueOn,
    List<WishOffset>? dueOffsets,
    int? dueHour,
    int? dueMinute,
    bool? placeOn,
    int? placeRadius,
    bool? weeklyOn,
    int? weeklyDay,
    int? weeklyHour,
    int? weeklyMinute,
    bool? giftOn,
    int? giftLeadDays,
    bool? giftHolidays,
    bool? reserveOn,
  }) => WishReminderPrefs(
    dueOn: dueOn ?? this.dueOn,
    dueOffsets: dueOffsets ?? this.dueOffsets,
    dueHour: dueHour ?? this.dueHour,
    dueMinute: dueMinute ?? this.dueMinute,
    placeOn: placeOn ?? this.placeOn,
    placeRadius: placeRadius ?? this.placeRadius,
    weeklyOn: weeklyOn ?? this.weeklyOn,
    weeklyDay: weeklyDay ?? this.weeklyDay,
    weeklyHour: weeklyHour ?? this.weeklyHour,
    weeklyMinute: weeklyMinute ?? this.weeklyMinute,
    giftOn: giftOn ?? this.giftOn,
    giftLeadDays: giftLeadDays ?? this.giftLeadDays,
    giftHolidays: giftHolidays ?? this.giftHolidays,
    reserveOn: reserveOn ?? this.reserveOn,
  );

  Map<String, dynamic> toJson() => {
    'dueOn': dueOn,
    'dueOffsets': [for (final o in dueOffsets) o.encode()],
    'dueHour': dueHour,
    'dueMinute': dueMinute,
    'placeOn': placeOn,
    'placeRadius': placeRadius,
    'weeklyOn': weeklyOn,
    'weeklyDay': weeklyDay,
    'weeklyHour': weeklyHour,
    'weeklyMinute': weeklyMinute,
    'giftOn': giftOn,
    'giftLeadDays': giftLeadDays,
    'giftHolidays': giftHolidays,
    'reserveOn': reserveOn,
  };

  /// Чего нет или что не читается — по умолчанию: запись от другой сборки
  /// не должна выключать напоминания целиком.
  factory WishReminderPrefs.fromJson(Map<String, dynamic> j) {
    const d = WishReminderPrefs();
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    int i(String k, int def, int min, int max) {
      final v = j[k];
      return v is int && v >= min && v <= max ? v : def;
    }

    final offsets = j['dueOffsets'] is List
        ? [for (final o in j['dueOffsets'] as List) ?WishOffset.parse(o)]
        : d.dueOffsets;
    return WishReminderPrefs(
      dueOn: b('dueOn', d.dueOn),
      dueOffsets: offsets,
      dueHour: i('dueHour', d.dueHour, 0, 23),
      dueMinute: i('dueMinute', d.dueMinute, 0, 59),
      placeOn: b('placeOn', d.placeOn),
      placeRadius: i('placeRadius', d.placeRadius, 50, 5000),
      weeklyOn: b('weeklyOn', d.weeklyOn),
      weeklyDay: i('weeklyDay', d.weeklyDay, 1, 7),
      weeklyHour: i('weeklyHour', d.weeklyHour, 0, 23),
      weeklyMinute: i('weeklyMinute', d.weeklyMinute, 0, 59),
      giftOn: b('giftOn', d.giftOn),
      giftLeadDays: i('giftLeadDays', d.giftLeadDays, 1, 90),
      giftHolidays: b('giftHolidays', d.giftHolidays),
      reserveOn: b('reserveOn', d.reserveOn),
    );
  }

  static const String prefsKey = 'fork_wish_reminders_v1';

  static Future<WishReminderPrefs> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null || raw.isEmpty) return const WishReminderPrefs();
      return WishReminderPrefs.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e) {
      debugPrint('WishReminderPrefs.load: $e');
      return const WishReminderPrefs();
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(toJson()));
  }
}
