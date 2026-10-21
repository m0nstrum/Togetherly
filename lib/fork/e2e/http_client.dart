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

/// Пара записи, когда в теле нет `group_id`: по телу (канал геопозиции),
/// кэшу или серверу.
typedef GroupLookup =
    Future<String?> Function(
      String collection,
      String id,
      Map<String, dynamic> body,
    );

class E2EHttpClient extends http.BaseClient {
  E2EHttpClient(
    this._inner, {
    required Future<RecordCodec?> Function() codec,
    GroupLookup? groupOf,
    String Function()? newId,
  }) : _codec = codec,
       _groupOf = groupOf,
       _newId = newId;

  final http.Client _inner;
  final Future<RecordCodec?> Function() _codec;
  final GroupLookup? _groupOf;
  final String Function()? _newId;

  static final _path = RegExp(
    r'/api/collections/([^/]+)/records(?:/([^/]+))?$',
  );

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
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
    if ((request is pb.MultipartRequest || request is http.MultipartRequest) &&
        request.method == 'POST' &&
        col == 'media' &&
        m.group(2) == null) {
      req = await _encodeMedia(request, codec);
    } else if (request is http.Request &&
        (request.method == 'POST' || request.method == 'PATCH') &&
        request.body.isNotEmpty) {
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
    var body = decoded;
    var id = pathId ?? (body['id'] is String ? body['id'] as String : '');
    if (id.isEmpty && request.method == 'POST') {
      // AAD привязан к id: без него шифровать не к чему. PocketBase берёт
      // id клиента, так что даём его сами.
      final gen = _newId;
      if (gen == null) return request;
      id = gen();
      body = {...body, 'id': id};
    }
    var group = body['group_id'] is String ? body['group_id'] as String : '';
    if (group.isEmpty && _groupOf != null) {
      group = await _groupOf(col, id, body) ?? '';
    }
    if (group.isEmpty) return request;
    final enc = codec.encode(col, id, group, body);
    if (identical(enc, body)) return request;
    final copy = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..body = jsonEncode(enc);
    return copy;
  }

  /// Файл в `media` шифруется ключом пары; id записи даём сами — от него
  /// выводится ключ файла. PocketBase кладёт поля формы JSON-ом в
  /// `@jsonPayload` своего `MultipartRequest`.
  Future<http.BaseRequest> _encodeMedia(
    http.BaseRequest request,
    RecordCodec codec,
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
    final group = '${fields['group_id'] ?? ''}';
    final kind = '${fields['kind'] ?? ''}';
    final c = codec.crypto;
    final key = group.isEmpty ? null : codec.keys.currentKey(group);
    if (c == null || key == null || plainMediaKinds.contains(kind)) {
      return request;
    }
    var id = '${fields['id'] ?? ''}';
    if (id.isEmpty) {
      final gen = _newId;
      if (gen == null) return request;
      id = gen();
    }
    fields['id'] = id;
    final cipher = MediaCipher(c);
    final enc = <http.MultipartFile>[
      for (final f in files)
        http.MultipartFile.fromBytes(
          f.field,
          cipher.encrypt(
            await f.finalize().toBytes(),
            key,
            id,
            mime: mimeFromName(f.filename),
          ),
          filename: f.filename,
        ),
    ];
    final http.BaseRequest copy;
    if (request is pb.MultipartRequest) {
      copy = pb.MultipartRequest(request.method, request.url)
        ..fields['@jsonPayload'] = [jsonEncode(fields)]
        ..files.addAll(enc);
    } else {
      copy = http.MultipartRequest(request.method, request.url)
        ..fields.addAll({for (final e in fields.entries) e.key: '${e.value}'})
        ..files.addAll(enc);
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
