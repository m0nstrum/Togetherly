import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/wish.dart';
import '../../services/offline/local_store.dart';
import '../../services/pb_data_service.dart';
import 'wish_place_check.dart';
import 'wish_reminder_prefs.dart';
import 'wish_reminders.dart';

/// «Вы оба рядом с местом из вишлиста» (docs/WISHLIST.md).
///
/// Зовётся на каждую свою точку «Где мы» (LiveLocationService). Сначала
/// дешёвая проверка — есть ли место рядом со мной; только тогда спрашиваем
/// последнюю точку партнёра. Её телефон делает то же самое, поэтому
/// напоминание приходит обоим. Не чаще раза в неделю на место.
class WishPlaces {
  WishPlaces._();
  static final WishPlaces instance = WishPlaces._();

  static const String _lastKey = 'fork_wish_place_notified_v1';

  List<Wish> _places = const [];
  DateTime _placesAt = DateTime(0);
  DateTime _partnerAskedAt = DateTime(0);
  bool _busy = false;

  /// Список желаний поменялся — места перечитать при следующей точке.
  void invalidate() => _placesAt = DateTime(0);

  Future<List<Wish>> _loadPlaces() async {
    final now = DateTime.now();
    if (now.difference(_placesAt) < const Duration(minutes: 10)) {
      return _places;
    }
    final recs = await LocalStore.instance.allRecords('wishes');
    _places = [
      for (final r in recs)
        if (Wish.fromPb(r) case final w when w.place != null && !w.done) w,
    ];
    _placesAt = now;
    return _places;
  }

  Future<void> onMyFix({
    required String channel,
    required String myUid,
    required double lat,
    required double lng,
    double accuracy = 0,
  }) async {
    if (_busy || myUid.isEmpty || !channel.startsWith('pair_')) return;
    _busy = true;
    try {
      final prefs = await WishReminderPrefs.load();
      if (!prefs.placeOn) return;
      final places = await _loadPlaces();
      if (places.isEmpty) return;
      final now = DateTime.now();
      final me = GeoFix(lat, lng, now, accuracy: accuracy);
      final radius = prefs.placeRadius.toDouble();
      if (!anyWishPlaceNear(places, me, radius)) return;
      // Точку партнёра спрашиваем не чаще раза в три минуты: стоять у места
      // можно долго, а точки идут каждые несколько секунд.
      if (now.difference(_partnerAskedAt) < const Duration(minutes: 3)) return;
      _partnerAskedAt = now;
      final ids = channel.substring(5).split('_');
      final partnerUid = ids.firstWhere((u) => u != myUid, orElse: () => '');
      if (partnerUid.isEmpty) return;
      final point = await PbDataService().getLivePoint(channel, partnerUid);
      final partner = _fix(point);
      final store = await SharedPreferences.getInstance();
      final last = _readLast(store);
      final hits = wishPlacesTogether(
        wishes: places,
        me: me,
        partner: partner,
        now: now,
        radius: radius,
        lastNotified: last,
      );
      for (final w in hits) {
        last[w.id] = now;
        final where = w.place!.name.isEmpty ? '' : ' (${w.place!.name})';
        await WishReminders.instance.showNow(
          key: 'place|${w.id}',
          title: ruEn(
            'Вы оба рядом: ${w.title}',
            'You’re both nearby: ${w.title}',
          ),
          body: ruEn(
            'Вы хотели сюда сходить$where — может, сейчас?',
            'You wanted to go here$where — maybe now?',
          ),
        );
      }
      if (hits.isNotEmpty) {
        await store.setString(
          _lastKey,
          jsonEncode({
            for (final e in last.entries)
              if (now.difference(e.value) < wishPlaceCooldown)
                e.key: e.value.millisecondsSinceEpoch,
          }),
        );
      }
    } catch (e) {
      debugPrint('WishPlaces: проверка места — $e');
    } finally {
      _busy = false;
    }
  }

  static GeoFix? _fix(Map<String, dynamic>? p) {
    if (p == null) return null;
    final lat = (p['lat'] as num?)?.toDouble();
    final lng = (p['lng'] as num?)?.toDouble();
    final at = (p['updatedAt'] as num?)?.toInt();
    if (lat == null || lng == null || at == null) return null;
    return GeoFix(
      lat,
      lng,
      DateTime.fromMillisecondsSinceEpoch(at),
      accuracy: (p['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }

  static Map<String, DateTime> _readLast(SharedPreferences store) {
    try {
      final m = jsonDecode(store.getString(_lastKey) ?? '{}') as Map;
      return {
        for (final e in m.entries)
          if (e.value is int)
            '${e.key}': DateTime.fromMillisecondsSinceEpoch(e.value as int),
      };
    } on Object {
      return {};
    }
  }
}
