import 'dart:convert';

import 'package:http/http.dart' as http;

import 'pocketbase_service.dart';
import '../fork/config/endpoints.dart'; // fork

/// Комната совместного просмотра.
///
/// Код комнаты выдаёт сервер по связи пары, а не придумывает клиент: оба
/// устройства спрашивают его сами и молча оказываются в одной комнате. Тот же
/// код зовёт партнёра в браузер — на сайте комната ровно та же.
class WatchRoomService {
  WatchRoomService._();

  static final Map<String, String> _cache = {};

  /// Сколько букв имени доезжает до комнаты. Длиннее в строке сообщения всё
  /// равно не помещается, а адрес раздувает.
  static const int maxNameLength = 32;

  /// Сайт с играми для пары — «Правда или действие» и прочее на одном
  /// телефоне. Живёт отдельной статикой на первом сервере, кода комнаты не
  /// спрашивает: играют вдвоём с одного экрана, а не по сети.
  /// fork: из конфига; пусто — плитка игр скрыта.
  static String get gamesUrl => Endpoints.current.gamesUrl;

  /// Адрес комнаты на сайте для кода [room].
  ///
  /// [src] — ссылка на ролик, который надо включить сразу после входа. Комната
  /// применит её, когда поднимется канал, и объявит партнёру. Ссылку для
  /// партнёра (копирование, «поделиться») берём без [src] — там свой выбор.
  ///
  /// [name] — как подписывать свои сообщения в чате комнаты. Без него страница
  /// подставляет «Гость» обоим, и человек не понимает, кто с ним смотрит
  /// (жалоба тестера: «партнёр отображается как гость»).
  ///
  /// [build] и [nativeWindow] — метки для замера касаний (`b`, `nb`): из какой
  /// сборки открыли комнату и каким окном. До 12.10.2026 страница сборку не
  /// знала, и проверить выпуск замером было нечем.
  static String siteUrl(
    String room, {
    String? src,
    String? name,
    bool reels = false,
    String? feed,
    int build = 0,
    bool nativeWindow = false,
  }) {
    // Совместная лента — своя страница (/watch/reels/) в том же канале пары,
    // что и комната (05.10.2026). Сборки постарше открывают её прежним
    // адресом комнаты с `?reels=1`, и страница комнаты уводит их туда.
    // `feed` — площадка своей ленты (shorts, tiktok, rutube, vk, dzen).
    final base = 'https://$siteHost/watch/${reels ? 'reels' : 'room'}/';
    final query = <String, String>{};
    if (reels && feed != null && feed.isNotEmpty) query['feed'] = feed;
    if (src != null && src.isNotEmpty) query['src'] = src;
    final trimmed = (name ?? '').trim();
    if (trimmed.isNotEmpty) {
      query['name'] = trimmed.length > maxNameLength
          ? trimmed.substring(0, maxNameLength)
          : trimmed;
    }
    if (build > 0) query['b'] = '$build';
    if (nativeWindow) query['nb'] = '1';
    if (query.isEmpty) return '$base#$room';
    final encoded = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$base?$encoded#$room';
  }

  /// fork (C3): page identity only. The PocketBase token stays in Dart.
  static String authScript({String? name}) {
    final data = jsonEncode({'name': (name ?? '').trim()});
    return '(function(){'
        "if(location.protocol!=='https:'||location.hostname!=='$siteHost'||window.top!==window)return;"
        'window.__togetherlyChrome=1;'
        'window.__forkWatchIdentity=$data;'
        '})();';
  }

  static String get siteHost => Endpoints.current.siteHost;

  /// Room-scoped connection/subscription tickets, never the account token.
  /// The native screen supplies its fixed room, not one chosen by JavaScript.
  static Future<Map<String, dynamic>> ticket(String room, String guest) async {
    final result = await PocketBaseService.instance.pb
        .send<Map<String, dynamic>>(
          '/api/watch/token',
          method: 'POST',
          body: {
            'room': room,
            'guest': RegExp(r'^g[a-z0-9]{14}$').hasMatch(guest) ? guest : '',
          },
        );
    return result;
  }

  /// Код комнаты пары. Пустая строка означает отказ сервера — вызывающий
  /// показывает ошибку и не открывает просмотр.
  static Future<String> roomCode(String groupId) async {
    if (groupId.isEmpty) return '';
    final cached = _cache[groupId];
    if (cached != null) return cached;

    final pb = PocketBaseService.instance.pb;
    final token = pb.authStore.token;
    if (token.isEmpty) return '';

    try {
      final res = await http
          .post(
            Uri.parse('${PocketBaseService.baseUrl}/api/watch/room'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': token,
            },
            body: jsonEncode({'groupId': groupId}),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final room = (data['room'] ?? '').toString();
      if (room.isNotEmpty) _cache[groupId] = room;
      return room;
    } catch (_) {
      return '';
    }
  }
}
