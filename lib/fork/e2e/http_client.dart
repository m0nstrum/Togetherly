/// HTTP-клиент PocketBase с шифрованием полей (PLAN S9).
///
/// Единая точка для REST: тело create/update шифруется перед отправкой,
/// записи в ответе расшифровываются до того, как их увидит SDK. Остальной
/// код приложения (очередь, кэш, экраны) работает с открытым текстом и про
/// E2E не знает.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
// MultipartRequest SDK не экспортирует, а шлёт именно его.
// ignore: implementation_imports
import 'package:pocketbase/src/multipart_request.dart' as pb;

import 'media_cipher.dart';
import 'record_codec.dart';

/// Что известно о записи помимо тела запроса: `group_id`, `user_uid`,
/// `e2e_locked` — из кэша или с сервера. Для канала геопозиции пару
/// находит по составу канала. null — ничего не известно.
typedef ContextLookup =
    Future<Map<String, dynamic>?> Function(
      String collection,
      String id,
      Map<String, dynamic> body,
    );

class E2EHttpClient extends http.BaseClient {
  E2EHttpClient(
    this._inner, {
    required Future<RecordCodec?> Function() codec,
    ContextLookup? context,
    String Function()? newId,
  }) : _codec = codec,
       _context = context,
       _newId = newId;

  final http.Client _inner;
  final Future<RecordCodec?> Function() _codec;
  final ContextLookup? _context;
  final String Function()? _newId;

  static final _path = RegExp(
    r'/api/collections/([^/]+)/records(?:/([^/]+))?$',
  );

  /// Ответы входа несут запись профиля (`record`) — её тоже открываем.
  static final _authPath = RegExp(
    r'/api/collections/users/auth-(?:refresh|with-password|with-oauth2|with-otp)$',
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request &&
        request.method == 'POST' &&
        (_routes.containsKey(request.url.path) ||
            _giftRoutes.containsKey(request.url.path))) {
      final codec = await _codec();
      if (codec == null) return _inner.send(request);
      final route = _routes[request.url.path];
      return _inner.send(
        route != null
            ? route(request, codec)
            : await _encodeGift(request, codec, _giftRoutes[request.url.path]!),
      );
    }
    if (_authPath.hasMatch(request.url.path)) {
      return _decodeAuth(request);
    }
    final m = _path.firstMatch(request.url.path);
    final col = m?.group(1);
    if (m == null ||
        col == null ||
        !(RecordCodec.covers(col) || col == 'media')) {
      return _inner.send(request);
    }
    final codec = await _codec();
    if (codec == null) return _inner.send(request);

    var req = request;
    final write = request.method == 'POST' || request.method == 'PATCH';
    if (write &&
        (request is pb.MultipartRequest || request is http.MultipartRequest)) {
      req = await _encodeMultipart(request, codec, col, m.group(2));
    } else if (write && request is http.Request && request.body.isNotEmpty) {
      req = await _encodeRequest(request, codec, col, m.group(2));
    }

    final resp = await _inner.send(req);
    if (req.method == 'DELETE' || resp.statusCode >= 400) return resp;
    final bytes = await resp.stream.toBytes();
    var out = bytes;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      out = utf8.encode(jsonEncode(codec.decodeResponse(col, json)));
    } on FormatException {
      // Не JSON — отдаём как есть.
    }
    final headers = Map.of(resp.headers)..remove('content-length');
    return http.StreamedResponse(
      Stream.value(out),
      resp.statusCode,
      contentLength: out.length,
      request: resp.request,
      headers: headers,
      isRedirect: resp.isRedirect,
      persistentConnection: resp.persistentConnection,
      reasonPhrase: resp.reasonPhrase,
    );
  }

  Future<http.StreamedResponse> _decodeAuth(http.BaseRequest request) async {
    final resp = await _inner.send(request);
    if (resp.statusCode >= 400) return resp;
    final codec = await _codec();
    if (codec == null) return resp;
    final bytes = await resp.stream.toBytes();
    var out = bytes;
    try {
      final json = jsonDecode(utf8.decode(bytes));
      final rec = json is Map<String, dynamic> ? json['record'] : null;
      if (rec is Map<String, dynamic>) {
        out = utf8.encode(
          jsonEncode({...json, 'record': codec.decode('users', rec)}),
        );
      }
    } on FormatException {
      // Не JSON — отдаём как есть.
    }
    return http.StreamedResponse(
      Stream.value(out),
      resp.statusCode,
      contentLength: out.length,
      request: resp.request,
      headers: Map.of(resp.headers)..remove('content-length'),
      isRedirect: resp.isRedirect,
      persistentConnection: resp.persistentConnection,
      reasonPhrase: resp.reasonPhrase,
    );
  }

  Future<http.Request> _encodeRequest(
    http.Request request,
    RecordCodec codec,
    String col,
    String? pathId,
  ) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(request.body);
    } on FormatException {
      return request;
    }
    if (decoded is! Map<String, dynamic>) return request;
    final enc = await _encodeBody(codec, col, request.method, pathId, decoded);
    return enc == null ? request : _copy(request, enc.body);
  }

  /// Шифрует тело записи. null — шифровать нечего или нечем (пара без ключа).
  Future<({String id, String group, Map<String, dynamic> body})?> _encodeBody(
    RecordCodec codec,
    String col,
    String method,
    String? pathId,
    Map<String, dynamic> decoded,
  ) async {
    if (!RecordCodec.covers(col) && col != 'media') return null;
    var body = decoded;
    var id = pathId ?? (body['id'] is String ? body['id'] as String : '');
    if (id.isEmpty && method == 'POST') {
      // AAD привязан к id: без него шифровать не к чему. PocketBase берёт
      // id клиента, так что даём его сами.
      final gen = _newId;
      if (gen == null) return _noKey(col, body);
      id = gen();
      body = {...body, 'id': id};
    }
    if (id.isEmpty) return _noKey(col, body);
    var group = e2eGroupOf(col, id, body) ?? '';
    // Файл без пары (аватар, баннер) — личным ключом владельца.
    if (group.isEmpty && col == 'media' && body['uid'] is String) {
      group = body['uid'] as String;
    }
    final sticker = stickerOp(col, body);
    final needContext =
        sticker ||
        group.isEmpty ||
        (method == 'PATCH' && RecordCodec.covers(col)) ||
        e2eRecordKey(col, {...body, 'id': id}) == null;
    final ctx = needContext && _context != null
        ? await _context(col, id, body)
        : null;
    if (group.isEmpty) group = '${ctx?['group_id'] ?? ''}';
    if (sticker) body = applySticker(body, ctx);
    if (group.isEmpty) return _noKey(col, body);
    final locked = ctx?[e2eLockedKey];
    if (locked is Map<String, dynamic>) {
      body = codec.restoreLocked(col, body, locked);
    }
    if (!RecordCodec.covers(col)) {
      return (id: id, group: group, body: body);
    }
    final enc = codec.encode(col, id, group, body, context: ctx);
    if (identical(enc, body) && identical(body, decoded)) return null;
    return (id: id, group: group, body: enc);
  }

  /// Наклейка на воспоминание: апстрим шлёт `{sticker_put}`/`{sticker_del}`,
  /// а кладёт её в `data.stickers` сервер. Сервер форка `data` не читает —
  /// наклейку кладём сами и шлём правку всего `data` шифром.
  /// Имя файла для сервера: `<поле>.<расширение>`.
  static String neutralFileName(String field, String? name) {
    final n = name ?? '';
    final dot = n.lastIndexOf('.');
    final ext = dot < 0 ? '' : n.substring(dot).toLowerCase();
    final safe = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(ext) ? ext : '';
    return '${field.isEmpty ? 'file' : field}$safe';
  }

  static bool stickerOp(String col, Map<String, dynamic> body) =>
      col == 'memories' &&
      (body.containsKey('sticker_put') || body.containsKey('sticker_del'));

  /// Тело правки `data` с наклейкой из [body] поверх записи [ctx].
  /// Записи не знаем — [E2ENoKeyError]: открытой наклейка не уйдёт.
  static Map<String, dynamic> applySticker(
    Map<String, dynamic> body,
    Map<String, dynamic>? ctx,
  ) {
    final cur = ctx?['data'];
    if (cur is! Map) throw E2ENoKeyError('memories');
    final data = Map<String, dynamic>.from(cur)..remove(e2ePartialKey);
    final stickers = Map<String, dynamic>.from(
      data['stickers'] is Map ? data['stickers'] as Map : const {},
    );
    final put = body['sticker_put'];
    if (put is Map && put['id'] != null) stickers['${put['id']}'] = put;
    final del = body['sticker_del'];
    if (del != null) stickers.remove('$del');
    return {
      for (final e in body.entries)
        if (e.key != 'sticker_put' && e.key != 'sticker_del') e.key: e.value,
      'data': {...data, 'stickers': stickers},
    };
  }

  /// Пару записи не узнать — шифровать нечем. Открытое содержимое не
  /// уходит: [E2ENoKeyError].
  static Null _noKey(String col, Map<String, dynamic> body) {
    if (RecordCodec.hasPlainContent(col, body)) throw E2ENoKeyError(col);
    return null;
  }

  /// Маршруты сервера, которые сами пишут в записи то, что прислал клиент.
  static final Map<String, http.Request Function(http.Request, RecordCodec)>
  _routes = {
    '/api/group/miss-you': _encodeMissYou,
    '/api/group/patch-map': _encodePatchMap,
  };

  /// Подарки: поля тела → поле записи `gifts`. Запись заводит сервер, но id
  /// у неё клиентский (`giftId`, у сундука — `openId`): к нему и привязан
  /// шифр, как у обычной записи.
  static const Map<String, ({String idKey, Map<String, String> fields})>
  _giftRoutes = {
    '/api/gifts/send': (
      idKey: 'giftId',
      fields: {
        'note': 'note',
        'date': 'date',
        'place': 'place',
        'photo': 'photo',
        'sound': 'sound',
        'soundMeta': 'sound_meta',
      },
    ),
    '/api/gifts/react': (idKey: 'giftId', fields: {'reply': 'reply'}),
    '/api/chest/give': (idKey: 'openId', fields: {'note': 'note'}),
  };

  Future<http.Request> _encodeGift(
    http.Request request,
    RecordCodec codec,
    ({String idKey, Map<String, String> fields}) route,
  ) async {
    final body = _jsonBody(request);
    if (body == null) return request;
    final plain = {
      for (final e in route.fields.entries)
        if (body[e.key] is String &&
            (body[e.key] as String).isNotEmpty &&
            !isSealedValue(body[e.key]))
          e.key: body[e.key] as String,
    };
    if (plain.isEmpty) return request;
    final id = '${body[route.idKey] ?? ''}';
    var group = '${body['groupId'] ?? ''}';
    if (group.isEmpty && id.isNotEmpty && _context != null) {
      final ctx = await _context('gifts', id, const {});
      group = '${ctx?['group_id'] ?? ''}';
    }
    final key = id.isEmpty || group.isEmpty || codec.crypto == null
        ? null
        : codec.keys.currentKey(group);
    if (key == null) throw E2ENoKeyError('gifts');
    return _copy(request, {
      ...body,
      for (final e in plain.entries)
        e.key: codec.sealField('gifts', id, route.fields[e.key]!, e.value, key),
    });
  }

  static Map<String, dynamic>? _jsonBody(http.Request r) {
    try {
      final b = jsonDecode(r.body);
      return b is Map<String, dynamic> ? b : null;
    } on FormatException {
      return null;
    }
  }

  /// Правка словаря группы по одному участнику: значение — отдельный шифр
  /// (`SealedField.mapValues`).
  static http.Request _encodePatchMap(http.Request request, RecordCodec codec) {
    final body = _jsonBody(request);
    if (body == null) return request;
    final group = body['groupId'], field = body['field'], uid = body['uid'];
    final value = body['value'];
    if (group is! String || field is! String || uid is! String) return request;
    final spec = e2eFields['groups']?[field];
    if (spec?.kind != SealKind.mapValues ||
        value == null ||
        isSealedValue(value)) {
      return request;
    }
    final key = codec.crypto == null ? null : codec.keys.currentKey(group);
    if (key == null) throw E2ENoKeyError('groups');
    final sealed = codec.sealField(
      'groups',
      group,
      '$field/$uid',
      jsonEncode(value),
      key,
    );
    return _copy(request, {...body, 'value': sealed});
  }

  /// «Скучаю» с текстом: сервер разложит его по записям сам, шифр привязан
  /// к паре и автору (`e2eRecordKey`).
  static http.Request _encodeMissYou(http.Request request, RecordCodec codec) {
    final body = _jsonBody(request);
    if (body == null) return request;
    final text = body['text'], group = body['groupId'], uid = body['uid'];
    if (text is! String || text.isEmpty || isSealedValue(text)) return request;
    final key = group is! String || uid is! String || codec.crypto == null
        ? null
        : codec.keys.currentKey(group);
    if (key == null || group is! String || uid is! String) {
      throw E2ENoKeyError('miss_you');
    }
    final sealed = codec.sealField(
      'miss_you',
      '$group/$uid',
      'text',
      text,
      key,
    );
    return _copy(request, {...body, 'text': sealed});
  }

  static http.Request _copy(http.Request r, Map<String, dynamic> body) =>
      http.Request(r.method, r.url)
        ..headers.addAll(r.headers)
        ..followRedirects = r.followRedirects
        ..maxRedirects = r.maxRedirects
        ..persistentConnection = r.persistentConnection
        ..body = jsonEncode(body);

  /// Запись с файлами: PocketBase кладёт поля формы JSON-ом в `@jsonPayload`
  /// своего `MultipartRequest`. Поля шифруются как обычно; файл в `media`
  /// шифруется ключом пары (id записи даём сами — от него выводится ключ
  /// файла). Файлы других коллекций (картинка своего настроения) — как есть.
  Future<http.BaseRequest> _encodeMultipart(
    http.BaseRequest request,
    RecordCodec codec,
    String col,
    String? pathId,
  ) async {
    final Map<String, dynamic> fields;
    final List<http.MultipartFile> files;
    if (request is pb.MultipartRequest) {
      final raw = request.fields['@jsonPayload'];
      final Object? j = raw == null || raw.isEmpty
          ? null
          : jsonDecode(raw.first);
      fields = j is Map<String, dynamic> ? Map.of(j) : <String, dynamic>{};
      files = request.files;
    } else {
      final r = request as http.MultipartRequest;
      fields = Map<String, dynamic>.of(r.fields);
      files = r.files;
    }
    final enc = await _encodeBody(codec, col, request.method, pathId, fields);
    final c = codec.crypto;
    final key = enc == null || c == null
        ? null
        : codec.keys.currentKey(enc.group);
    final sealFiles =
        (col == 'media' &&
            !plainMediaKinds.contains('${fields['kind'] ?? ''}')) ||
        col == 'watch_videos';
    // Файл пары без ключа открытым не уходит.
    if (sealFiles && files.isNotEmpty && key == null) {
      throw E2ENoKeyError('media');
    }
    if (enc == null) return request;
    var outFiles = files;
    if (sealFiles && c != null && key != null) {
      final cipher = MediaCipher(c);
      outFiles = [
        for (final f in files)
          http.MultipartFile.fromBytes(
            f.field,
            cipher.encrypt(
              await f.finalize().toBytes(),
              key,
              enc.id,
              mime: mimeFromName(f.filename),
            ),
            // Имя файла видно серверу: своё имя с телефона (IMG_…, название
            // ролика) не отдаём — только поле и расширение.
            filename: neutralFileName(f.field, f.filename),
          ),
      ];
    } else if (col == 'media') {
      // Файл не шифруется — и id менять незачем.
      return request;
    }
    final http.BaseRequest copy;
    if (request is pb.MultipartRequest) {
      copy = pb.MultipartRequest(request.method, request.url)
        ..fields['@jsonPayload'] = [jsonEncode(enc.body)]
        ..files.addAll(outFiles);
    } else {
      copy = http.MultipartRequest(request.method, request.url)
        ..fields.addAll({for (final e in enc.body.entries) e.key: '${e.value}'})
        ..files.addAll(outFiles);
    }
    copy
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
    return copy;
  }

  @override
  void close() => _inner.close();
}
