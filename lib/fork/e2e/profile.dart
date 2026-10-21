/// Профиль для партнёра шифром ключа пары (docs/fork/E2E.md, «шифровать всё»).
///
/// Свой профиль в `users` зашифрован личным ключом — партнёр его не
/// откроет, а серверный `/api/user/card` отдаёт только шифр. Поэтому каждый
/// сам кладёт в запись пары то, что партнёр видит: имя, аватар, день
/// рождения (словари `member_*`) и карточку (`member_cards`: баннер, пол,
/// сон маскота). Файлы аватара и баннера лежат под личным ключом — в паре
/// нужна копия под ключом пары; откуда она снята, помнит карточка (`*_src`).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../services/offline/local_store.dart';
import '../../services/pb_media_service.dart';
import '../../services/pocketbase_service.dart';
import 'fork_e2e.dart';
import 'record_codec.dart';

abstract final class ForkProfile {
  static Future<void>? _running;

  /// Положить свой профиль в пару [groupId]; только то, что изменилось.
  static Future<void> publish(String groupId) =>
      _running ??= _publish(groupId).whenComplete(() => _running = null);

  static Future<void> _publish(String groupId) async {
    final s = ForkE2E.service.value;
    if (s == null || s.currentKey(groupId) == null) return;
    final uid = s.uid;
    try {
      final pb = PocketBaseService().pb;
      final me = (await pb.collection('users').getOne(uid)).data;
      final g = (await pb.collection('groups').getOne(groupId)).data;
      Map<String, dynamic> map(String f) =>
          g[f] is Map ? Map<String, dynamic>.from(g[f] as Map) : const {};
      final old = map('member_cards')[uid];
      final prev = old is Map
          ? Map<String, dynamic>.from(old)
          : const <String, dynamic>{};

      final name = _str(me['display_name']).isNotEmpty
          ? _str(me['display_name'])
          : _str(me['name']);
      final avatar = await _pairCopy(
        _str(me['avatar_url']),
        prev,
        'avatar',
        groupId,
        uid,
      );
      final banner = await _pairCopy(
        _str(me['banner_url']),
        prev,
        'banner',
        groupId,
        uid,
      );
      final birth = _str(me['birth_date']);
      final card = <String, dynamic>{
        'display_name': name,
        'avatar_url': avatar,
        'avatar_src': _str(me['avatar_url']),
        'banner_url': banner,
        'banner_src': _str(me['banner_url']),
        'gender': _str(me['gender']),
        'birth_date': birth,
        'mascot_sleep': me['mascot_sleep'],
      };

      Future<void> put(String field, Object? value) => pb.send(
        '/api/group/patch-map',
        method: 'POST',
        body: {'groupId': groupId, 'field': field, 'uid': uid, 'value': value},
      );
      if (name.isNotEmpty && map('member_names')[uid] != name) {
        await put('member_names', name);
      }
      if (avatar.isNotEmpty && map('member_avatars')[uid] != avatar) {
        await put('member_avatars', avatar);
      }
      if (birth.isNotEmpty && map('member_birthdays')[uid] != birth) {
        await put('member_birthdays', birth);
      }
      if (jsonEncode(prev) != jsonEncode(card)) await put('member_cards', card);
    } catch (e) {
      debugPrint('ForkProfile: профиль в пару $groupId — $e');
    }
  }

  static String _str(Object? v) => v is String ? v : '';

  /// Копия своего файла [ref] под ключом пары. Уже снята с того же
  /// файла — берём из карточки [prev].
  static Future<String> _pairCopy(
    String ref,
    Map<String, dynamic> prev,
    String kind,
    String groupId,
    String uid,
  ) async {
    if (ref.isEmpty || !PbMediaService().isPbRef(ref)) return ref;
    if (prev['${kind}_src'] == ref && _str(prev['${kind}_url']).isNotEmpty) {
      return _str(prev['${kind}_url']);
    }
    final url = await PbMediaService().resolveUrlAuthed(ref);
    if (url == null) return '';
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return '';
    final name = Uri.parse(ref).pathSegments.last;
    final dot = name.lastIndexOf('.');
    return await PbMediaService().uploadBytes(
          res.bodyBytes,
          '$kind${dot < 0 ? '' : name.substring(dot)}',
          uid: uid,
          groupId: groupId,
          kind: kind,
        ) ??
        '';
  }

  /// Карточка партнёра [uid] из записи пары поверх ответа `/api/user/card`
  /// ([card], ключи как у `loadPartnerCard`). Шифр личного ключа партнёра из
  /// ответа сервера не показываем.
  static Future<Map<String, dynamic>> partnerCard(
    String uid,
    Map<String, dynamic> card,
  ) async {
    final out = {
      for (final e in card.entries)
        e.key: isSealedValue(e.value) ? null : e.value,
    };
    try {
      final codec = await ForkE2E.codec();
      final me = PocketBaseService().userId ?? '';
      final groupId = codec?.keys.groupWith({me, uid});
      if (groupId == null) return out;
      final local = await LocalStore.instance.getRecord('groups', groupId);
      final g =
          local?.toJson() ??
          (await PocketBaseService().pb.collection('groups').getOne(groupId))
              .toJson();
      final cards = g['member_cards'];
      final c = cards is Map ? cards[uid] : null;
      if (c is! Map) return out;
      return {
        ...out,
        'displayName': c['display_name'],
        'avatarUrl': c['avatar_url'],
        'bannerUrl': c['banner_url'],
        'gender': c['gender'],
        'birthDate': c['birth_date'],
        'mascotSleep': c['mascot_sleep'],
      };
    } catch (e) {
      debugPrint('ForkProfile: карточка партнёра — $e');
      return out;
    }
  }
}
