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

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request &&
        request.method == 'POST' &&
        _routes.containsKey(request.url.path)) {
      final codec = await _codec();
      return _inner.send(
        codec == null ? request : _routes[request.url.path]!(request, codec),
      );
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
      if (gen == null) return null;
      id = gen();
      body = {...body, 'id': id};
    }
    if (id.isEmpty) return _noKey(col, body);
    var group = e2eGroupOf(col, id, body) ?? '';
    final needContext =
        group.isEmpty ||
        (method == 'PATCH' && RecordCodec.covers(col)) ||
        e2eRecordKey(col, {...body, 'id': id}) == null;
    final ctx = needContext && _context != null
        ? await _context(col, id, body)
        : null;
    if (group.isEmpty) group = '${ctx?['group_id'] ?? ''}';
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
        col == 'media' && !plainMediaKinds.contains('${fields['kind'] ?? ''}');
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
            filename: f.filename,
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
