/// Точка входа E2E для приложения (PLAN S8).
///
/// Живёт только в главном изоляте: фоновый сервис уведомлений ключи не
/// трогает — два изолята, пишущие одну запись Keystore, затирали бы друг
/// другу ключи пары.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pocketbase/pocketbase.dart';

import 'package:http/http.dart' as http;

import '../../services/centrifugo_service.dart';
import '../../services/offline/local_store.dart';
import '../../services/offline/pb_id.dart';
import '../../services/pocketbase_service.dart';
import 'crypto.dart';
import 'e2e_service.dart';
import 'envelope.dart';
import 'http_client.dart';
import 'key_store.dart';
import 'media_proxy.dart';
import 'password_policy.dart';
import 'pb_backend.dart';
import 'record_codec.dart';

abstract final class ForkE2E {
  /// Сервис текущего пользователя; null — не вошли или libsodium не
  /// загрузилась (тогда приложение работает как без E2E).
  static final ValueNotifier<E2EService?> service = ValueNotifier(null);

  static Future<E2EService?>? _starting;
  static String _uid = '';
  static String _group = '';
  static final List<UnsubscribeFunc> _subs = [];
  static Future<void> _chain = Future.value();

  /// Фрагменты ссылок приглашения по коду, пока код не принят.
  static final Map<String, String> _pendingFragments = {};

  static Future<E2EService?> ensure(String uid) {
    if (uid.isEmpty) return Future.value(null);
    if (_uid == uid && _starting != null) return _starting!;
    _uid = uid;
    service.value = null;
    return _starting = () async {
      try {
        final c = await E2ECrypto.init();
        final s = E2EService(
          crypto: c,
          store: E2EKeyStore(
            c,
            const SecureStorageVault(),
            slot: 'fork_e2e_keys_v1_$uid',
          ),
          backend: PbE2EBackend(PocketBaseService().pb),
          uid: uid,
        );
        await s.start();
        if (_uid == uid) service.value = s;
        return s;
      } catch (e) {
        debugPrint('ForkE2E: не запустился — $e');
        _starting = null;
        return null;
      }
    }();
  }

  /// Активная пара на главном экране: синхронизация ключей сейчас и по
  /// каждому шагу обмена в канале пары.
  static Future<void> attach(String groupId, String uid) async {
    if (groupId.isEmpty ||
        (groupId == _group && _subs.isNotEmpty && _uid == uid)) {
      return;
    }
    await detach();
    _group = groupId;
    final s = await ensure(uid);
    if (s == null || _group != groupId) return;
    unawaited(sync(groupId).then((_) => migrateOwn(groupId, uid)));
    for (final col in const ['e2e_handshake', 'e2e_grants']) {
      try {
        _subs.add(
          await CentrifugoService.instance.subscribeDelta(
            'pair:$groupId',
            col,
            (e) {
              if (e.action == 'create') unawaited(sync(groupId));
            },
          ),
        );
      } catch (e) {
        debugPrint('ForkE2E: подписка $col — $e');
      }
    }
  }

  static Future<void> detach() async {
    _group = '';
    for (final u in _subs) {
      try {
        await u();
      } catch (_) {}
    }
    _subs.clear();
  }

  /// Синхронизации пары идут по одной: состояние ключей общее.
  static Future<PairE2EStatus?> sync(String groupId) {
    final s = service.value;
    if (s == null) return Future.value(null);
    final done = Completer<PairE2EStatus?>();
    _chain = _chain.then((_) async {
      try {
        final before = s.keys.pairKeys.length;
        final st = await s.syncGroup(groupId);
        if (s.keys.pairKeys.length != before) await unlockCache();
        done.complete(st);
      } catch (e) {
        debugPrint('ForkE2E: синхронизация $groupId — $e');
        done.complete(null);
      }
    });
    return done.future;
  }

  /// Выход из аккаунта.
  static Future<void> reset() async {
    await detach();
    _uid = '';
    _starting = null;
    service.value = null;
    _ro = null;
    _roUid = '';
  }

  // --- шифрование записей (S9) ---

  static Future<E2ECrypto>? _crypto;
  static Future<RecordCodec>? _ro;
  static RecordCodec? _roReady;
  static String _roUid = '';
  static DateTime _roAt = DateTime(0);
  static final Map<String, String> _groupHints = {};

  /// HTTP-клиент PocketBase с шифрованием полей.
  static http.Client httpClient() => E2EHttpClient(
    http.Client(),
    codec: codec,
    groupOf: _groupOf,
    newId: newPbId,
  );

  /// Кодек записей. Пока сервис не поднялся (старт приложения, фоновый
  /// изолят) — ключи только на чтение прямо из Keystore: так и очередь
  /// не уйдёт открытым текстом в первые секунды, и уведомление из фона
  /// покажет текст. null — не вошли.
  static Future<RecordCodec?> codec() async {
    final s = service.value;
    if (s != null) return RecordCodec(s.crypto, s);
    final uid = _currentUid();
    if (uid.isEmpty) return null;
    final fresh = DateTime.now().difference(_roAt) < const Duration(minutes: 1);
    if (_ro == null || _roUid != uid || !fresh) {
      _roUid = uid;
      _roAt = DateTime.now();
      _ro = _loadReadOnly(uid);
    }
    return _ro;
  }

  static Future<RecordCodec> _loadReadOnly(String uid) async {
    try {
      final c = await (_crypto ??= E2ECrypto.init());
      final keys = await E2EKeyStore(
        c,
        const SecureStorageVault(),
        slot: 'fork_e2e_keys_v1_$uid',
      ).load();
      return _roReady = keys == null
          ? RecordCodec.locked()
          : RecordCodec(c, keys);
    } catch (e) {
      debugPrint('ForkE2E: ключи на чтение — $e');
      _crypto = null;
      return _roReady = RecordCodec.locked();
    }
  }

  static String _currentUid() {
    try {
      return PocketBaseService().userId ?? '';
    } catch (_) {
      return '';
    }
  }

  static MediaProxy? _proxy;

  /// Адрес файла `media` для показа и плееров: через локальный прокси,
  /// который расшифровывает на лету (открытые файлы проходят как есть).
  static Future<String> mediaUrl(String url) async {
    try {
      return await (_proxy ??= MediaProxy(codec: codec)).wrap(url);
    } catch (e) {
      debugPrint('ForkE2E: прокси медиа — $e');
      return url;
    }
  }

  /// Заранее поднять ключи на чтение: дельты Centrifugo разбираются
  /// синхронно и ждать не могут.
  static void preload() => unawaited(codec());

  /// Расшифровка записи из дельты Centrifugo (синхронно).
  static Map<String, dynamic> decodeSync(
    String? collection,
    Map<String, dynamic> rec,
  ) {
    if (collection == null || !RecordCodec.covers(collection)) return rec;
    return _syncCodec().decode(collection, rec);
  }

  static RecordCodec _syncCodec() {
    final s = service.value;
    return s != null
        ? RecordCodec(s.crypto, s)
        : (_roReady ?? RecordCodec.locked());
  }

  static ChannelPlace _pointPlace(String channel, String uid, Object? at) =>
      ChannelPlace('loc:$channel', 'point:$uid', at is int ? at : 0);

  /// Живая точка геопозиции для канала `loc:<channel>`. Нет ключа пары —
  /// как есть.
  static Map<String, dynamic> sealPoint(
    String channel,
    Map<String, dynamic> msg,
  ) {
    final members = pairChannelMembers(channel);
    final codec = _syncCodec();
    final group = members == null ? null : codec.keys.groupWith(members);
    final key = group == null ? null : codec.keys.currentKey(group);
    final uid = '${msg['uid'] ?? ''}';
    if (key == null || uid.isEmpty) return msg;
    final at = msg['updatedAt'];
    final inner = Map<String, dynamic>.of(msg)
      ..remove('t')
      ..remove('uid');
    return {
      't': msg['t'],
      'uid': uid,
      'at': at,
      'e2e': codec.sealChannel(_pointPlace(channel, uid, at), inner, key),
    };
  }

  /// Обратное к [sealPoint]; открытая точка (старый клиент, нет ключа) —
  /// как есть, подделка — null.
  static Map<String, dynamic>? openPoint(
    String channel,
    Map<String, dynamic> msg,
  ) {
    final sealed = msg['e2e'];
    if (sealed is! String) return msg;
    final uid = '${msg['uid'] ?? ''}';
    final inner = _syncCodec().openChannel(
      _pointPlace(channel, uid, msg['at']),
      sealed,
    );
    if (inner == null) return null;
    return {...inner, 't': msg['t'], 'uid': uid};
  }

  static ChannelPlace _livePlace(String channel, String type) =>
      ChannelPlace(channel, type, 0);

  /// Эфемерные данные пары [groupId] для канала [channel] (живые штрихи):
  /// `{e2e: шифр}`, AAD — канал и [type] (автор, холст). Нет ключа — как есть.
  static Map<String, dynamic>? sealLive(
    String groupId,
    String channel,
    String type,
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final codec = _syncCodec();
    final key = codec.crypto == null ? null : codec.keys.currentKey(groupId);
    if (key == null) return data;
    return {
      e2ePartialKey: codec.sealChannel(_livePlace(channel, type), data, key),
    };
  }

  /// Обратное к [sealLive]: `ok == false` — подделка или нечем открыть,
  /// пакет не показываем.
  static ({bool ok, Map<String, dynamic>? data}) openLive(
    String channel,
    String type,
    Object? data,
  ) {
    if (data is! Map) return (ok: true, data: null);
    final sealed = data[e2ePartialKey];
    if (sealed is! String) {
      return (ok: true, data: Map<String, dynamic>.from(data));
    }
    final open = _syncCodec().openChannel(_livePlace(channel, type), sealed);
    return (ok: open != null, data: open);
  }

  /// Шифруются ли новые записи пары [groupId].
  static bool encrypts(String groupId) {
    final s = service.value;
    return s != null && s.currentKey(groupId) != null;
  }

  static Future<String?> _groupOf(
    String collection,
    String id,
    Map<String, dynamic> body,
  ) async {
    final hint = _groupHints[id];
    if (hint != null) return hint;
    final members = pairChannelMembers(body['channel']);
    if (members != null) return (await codec())?.keys.groupWith(members);
    final local = await LocalStore.instance.getRecord(collection, id);
    final g = local?.data['group_id'];
    if (g is String && g.isNotEmpty) return g;
    try {
      final r = await PocketBaseService().pb
          .collection(collection)
          .getOne(id, fields: 'group_id');
      return r.getStringValue('group_id');
    } catch (_) {
      return null;
    }
  }

  /// Пришёл новый ключ: открыть в кэше то, что раньше открыть было нечем.
  static Future<void> unlockCache() async {
    final codec = await ForkE2E.codec();
    if (codec == null) return;
    for (final col in e2eFields.keys) {
      try {
        for (final r in await LocalStore.instance.allRecords(col)) {
          final data = r.toJson();
          if (data[e2eLockedKey] == null) continue;
          final open = codec.retry(col, data);
          if (open != null) {
            await LocalStore.instance.upsertRaw(col, r.id, open);
          }
        }
      } catch (e) {
        debugPrint('ForkE2E: кэш $col — $e');
      }
    }
  }

  /// Коллекции пары, где своё старое перешифровывает сам автор: править
  /// чужое сервер не даёт (chat_guard.pb.js, правила цикла).
  /// Коллекция → поле автора.
  static const Map<String, String> migrated = {
    'chat_messages': 'user_uid',
    'cycle_entries': 'user_uid',
    'memories': 'author_uid',
    'memory_comments': 'author_uid',
    'wishes': 'author_uid',
    'wish_categories': 'author_uid',
    'mood_entries': 'user_uid',
    'custom_moods': 'author_uid',
    'love_tests': 'user_uid',
    'widget_data': 'user_uid',
    'canvas_catalogue': 'created_by',
  };

  /// Свои записи, сохранённые до E2E, перешифровать на сервере.
  static Future<int> migrateOwn(String groupId, String uid) async {
    var done = 0;
    if (uid.isEmpty) return 0;
    final pb = PocketBaseService().pb;
    for (final e in migrated.entries) {
      done += await _migrate(
        e.key,
        pb.filter(
          'group_id = {:g} && ${e.value} = {:u} && (${plaintextFilter(e.key)})',
          {'g': groupId, 'u': uid},
        ),
        groupId,
      );
    }
    // Запись пары правит любой участник.
    done += await _migrate(
      'groups',
      pb.filter('id = {:g} && (${plaintextFilter('groups')})', {'g': groupId}),
      groupId,
    );
    return done;
  }

  static Future<int> _migrate(String col, String filter, String groupId) async {
    if (!encrypts(groupId)) return 0;
    final fields = e2eFields[col]!;
    final pb = PocketBaseService().pb;
    final seen = <String>{};
    var done = 0;
    try {
      while (encrypts(groupId)) {
        final page = await pb
            .collection(col)
            .getList(perPage: 100, filter: filter, skipTotal: true);
        final fresh = page.items.where((r) => seen.add(r.id)).toList();
        if (fresh.isEmpty) break;
        for (final r in fresh) {
          // Поле, что не открылось, не трогаем: в нём заглушка, а не текст.
          final locked = r.data[e2eLockedKey];
          final body = <String, dynamic>{
            for (final f in fields.keys)
              if (r.data[f] != null &&
                  r.data[f] != '' &&
                  !(locked is Map && locked.containsKey(f)))
                f: r.data[f],
          };
          if (body.isEmpty) continue;
          _groupHints[r.id] = groupId;
          try {
            await pb.collection(col).update(r.id, body: body);
            done++;
          } finally {
            _groupHints.remove(r.id);
          }
        }
      }
    } catch (e) {
      debugPrint('ForkE2E: перешифровка $col $groupId — $e');
    }
    if (done > 0) debugPrint('ForkE2E: перешифровано $col: $done');
    return done;
  }

  // --- бэкап (§7) ---

  static List<String>? _wordlist;
  static LeakedPasswords? _leaked;

  /// Список слов BIP39 из ассетов.
  static Future<List<String>> wordlist() async => _wordlist ??=
      (await rootBundle.loadString('assets/fork/bip39_english.txt'))
          .split('\n')
          .map((w) => w.trim())
          .where((w) => w.isNotEmpty)
          .toList(growable: false);

  /// Словарь утёкших паролей из ассетов (фильтр Блума).
  static Future<LeakedPasswords?> leakedPasswords() async {
    final s = service.value;
    if (s == null) return null;
    if (_leaked != null) return _leaked;
    final data = await rootBundle.load('assets/fork/leaked_passwords.bloom');
    return _leaked = LeakedPasswords.parse(
      s.crypto,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  /// Почта входа — пароль бэкапа не должен её содержать.
  static String get email {
    try {
      return PocketBaseService().pb.authStore.record?.getStringValue('email') ??
          '';
    } catch (_) {
      return '';
    }
  }

  // --- приглашения (§6.2) ---

  /// Фрагмент для ссылки приглашения с кодом [code]; пусто — E2E не готов.
  static String inviteFragment(String code) {
    final s = service.value;
    if (s == null || code.isEmpty) return '';
    try {
      return s.inviteFragment(code);
    } catch (_) {
      return '';
    }
  }

  /// Ссылка или QR пришли с фрагментом: запомнить до приёма кода.
  static void rememberFragment(String code, String fragment) {
    if (code.isEmpty || fragment.isEmpty) return;
    _pendingFragments[code.toUpperCase()] = fragment;
  }

  /// Код принят, пара [groupId]. Если код пришёл ссылкой с секретом —
  /// подтверждение уйдёт при ближайшей синхронизации.
  static Future<void> accepted(String code, String groupId) async {
    final fragment = _pendingFragments.remove(code.toUpperCase());
    final s = service.value;
    if (fragment == null || s == null) return;
    await s.acceptedInvite(groupId, code.toUpperCase(), fragment);
    unawaited(sync(groupId));
  }
}
