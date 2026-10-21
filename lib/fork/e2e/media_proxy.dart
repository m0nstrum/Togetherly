/// Локальный прокси для шифрованных файлов медиа (PLAN S9).
///
/// Плееры видео и звука, загрузчики картинок и виджеты получают от
/// `PbMediaService.resolveUrlAuthed` адрес и качают по нему сами — вставить
/// расшифровку между ними и сетью негде. Поэтому адрес файла `media` ведёт
/// сюда: `http://127.0.0.1:<порт>/<секрет>/m/<имя>?u=<адрес на сервере>`.
/// Прокси качает с сервера нужные блоки (HTTP Range — перемотка работает) и
/// отдаёт открытые байты. Открытые файлы (до E2E, аватары) проходят как есть.
///
/// Слушает только петлевой адрес, а случайный секрет в пути не даёт другим
/// приложениям телефона забрать расшифрованное.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'crypto.dart';
import 'envelope.dart';
import 'media_cipher.dart';
import 'record_codec.dart';

class MediaProxy {
  MediaProxy({
    required Future<RecordCodec?> Function() codec,
    HttpClient Function()? client,
  }) : _codec = codec,
       _client = (client ?? HttpClient.new)();

  final Future<RecordCodec?> Function() _codec;
  final HttpClient _client;
  final String _secret = _randomSecret();

  Future<HttpServer>? _server;
  final Map<String, Future<MediaHeader?>> _headers = {};

  static final _mediaPath = RegExp(r'^/api/files/media/([^/]+)/([^/]+)$');

  static String _randomSecret() {
    final r = Random.secure();
    return List.generate(
      24,
      (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)],
    ).join();
  }

  /// Адрес прокси для файла `media` на сервере; прочие адреса — как есть.
  Future<String> wrap(String url) async {
    final u = Uri.tryParse(url);
    final m = u == null ? null : _mediaPath.firstMatch(u.path);
    if (m == null) return url;
    final server = await (_server ??= _bind());
    return Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      pathSegments: [_secret, 'm', m.group(2)!],
      queryParameters: {'u': url},
    ).toString();
  }

  Future<HttpServer> _bind() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    s.listen((req) => unawaited(_handle(req)));
    return s;
  }

  Future<void> close() async {
    final s = await _server;
    _server = null;
    await s?.close(force: true);
    _client.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    var started = false;
    try {
      final seg = req.uri.pathSegments;
      final target = Uri.tryParse(req.uri.queryParameters['u'] ?? '');
      final m = target == null ? null : _mediaPath.firstMatch(target.path);
      if (seg.isEmpty || seg.first != _secret || m == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      if (req.method != 'GET' && req.method != 'HEAD') {
        res.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final head = await _header(target!);
      if (head == null) {
        started = true;
        await _pipe(req, target);
        return;
      }
      final codec = await _codec();
      final c = codec?.crypto;
      final key = codec?.keys.keyFor(head.keyId);
      if (c == null || key == null) {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      // Диапазон, который не разобрать, игнорируем и отдаём файл целиком
      // (так можно по RFC 9110).
      final range = parseRange(req.headers.value('range'), head.length);
      final (start, end) = range ?? (0, head.length - 1);
      res
        ..statusCode = range == null ? HttpStatus.ok : HttpStatus.partialContent
        ..headers.contentType = ContentType.parse(head.mime)
        ..headers.set('accept-ranges', 'bytes')
        ..contentLength = head.length == 0 ? 0 : end - start + 1;
      if (range != null) {
        res.headers.set('content-range', 'bytes $start-$end/${head.length}');
      }
      if (req.method == 'HEAD' || head.length == 0) return;
      started = true;
      await _stream(res, target, m.group(1)!, head, c, key, start, end);
    } catch (e) {
      debugPrint('MediaProxy: $e');
      if (!started) {
        try {
          res.statusCode = HttpStatus.badGateway;
        } catch (_) {}
      }
    } finally {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _stream(
    HttpResponse res,
    Uri target,
    String recordId,
    MediaHeader head,
    E2ECrypto c,
    PairKey key,
    int start,
    int end,
  ) async {
    final first = start ~/ head.chunk;
    final last = end ~/ head.chunk;
    final (from, _) = head.chunkRange(first);
    final (lastStart, lastLen) = head.chunkRange(last);
    final up = await _get(target, from, lastStart + lastLen - 1);
    if (up.statusCode != HttpStatus.partialContent &&
        up.statusCode != HttpStatus.ok) {
      await up.drain<void>();
      throw HttpException('сервер ответил ${up.statusCode}');
    }
    // Сервер мог проигнорировать Range и отдать файл целиком.
    var skip = up.statusCode == HttpStatus.ok ? from : 0;
    final cipher = MediaCipher(c);
    final fk = cipher.fileKey(key, recordId);
    try {
      final buf = BytesBuilder(copy: false);
      var i = first;
      var need = head.chunkRange(i).$2;
      await for (final data in up) {
        var bytes = data;
        if (skip > 0) {
          if (bytes.length <= skip) {
            skip -= bytes.length;
            continue;
          }
          bytes = bytes.sublist(skip);
          skip = 0;
        }
        buf.add(bytes);
        while (i <= last && buf.length >= need) {
          final all = buf.takeBytes();
          final plain = cipher.decryptChunk(
            head,
            fk,
            recordId,
            i,
            Uint8List.sublistView(all, 0, need),
          );
          if (all.length > need) buf.add(Uint8List.sublistView(all, need));
          final off = i * head.chunk;
          final a = max(start - off, 0);
          final b = min(end - off + 1, plain.length);
          res.add(Uint8List.sublistView(plain, a, b));
          i++;
          if (i <= last) need = head.chunkRange(i).$2;
        }
        if (i > last) break;
      }
      if (i <= last) throw const HttpException('файл оборвался');
    } finally {
      fk.dispose();
    }
  }

  /// Заголовок шифрованного файла; null — файл открытый.
  Future<MediaHeader?> _header(Uri target) {
    final k = target.path;
    final cached = _headers[k];
    if (cached != null) return cached;
    final f = _fetchHeader(target);
    _headers[k] = f;
    f.catchError((Object _) {
      _headers.remove(k);
      return null;
    });
    return f;
  }

  Future<MediaHeader?> _fetchHeader(Uri target) async {
    var want = MediaCipher.probeBytes;
    for (var attempt = 0; attempt < 3; attempt++) {
      final head = await _prefix(target, want);
      if (head == null) return null;
      try {
        return parseMediaHeader(head);
      } on NotEncrypted {
        return null;
      } on NeedMoreBytes catch (e) {
        if (head.length < want) return null; // файл короче — не наш формат
        want = e.bytes;
      }
    }
    throw const FormatException('файл: заголовок не читается');
  }

  /// Первые [n] байт файла; null — файла нет или он пустой.
  Future<Uint8List?> _prefix(Uri target, int n) async {
    final up = await _get(target, 0, n - 1);
    if (up.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      await up.drain<void>();
      return Uint8List(0);
    }
    if (up.statusCode != HttpStatus.ok &&
        up.statusCode != HttpStatus.partialContent) {
      await up.drain<void>();
      throw HttpException('сервер ответил ${up.statusCode}');
    }
    final out = BytesBuilder(copy: false);
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = up.listen(
      (d) {
        out.add(d);
        if (out.length >= n && !done.isCompleted) {
          done.complete();
          unawaited(sub.cancel());
        }
      },
      onError: (Object e) {
        if (!done.isCompleted) done.completeError(e);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    await done.future;
    final all = out.toBytes();
    return all.length > n ? Uint8List.sublistView(all, 0, n) : all;
  }

  Future<HttpClientResponse> _get(Uri target, int from, int to) async {
    final r = await _client.getUrl(target);
    r.headers.set('range', 'bytes=$from-$to');
    return r.close();
  }

  /// Открытый файл: запрос как есть, ответ как есть.
  Future<void> _pipe(HttpRequest req, Uri target) async {
    final r = await _client.openUrl(req.method, target);
    final range = req.headers.value('range');
    if (range != null) r.headers.set('range', range);
    final up = await r.close();
    final res = req.response..statusCode = up.statusCode;
    for (final h in const [
      'content-type',
      'content-range',
      'accept-ranges',
      'content-length',
    ]) {
      final v = up.headers.value(h);
      if (v != null) res.headers.set(h, v);
    }
    await res.addStream(up);
  }
}

/// Диапазон `Range: bytes=a-b` для файла длиной [length], включительно.
/// null — заголовка нет или он нам не по силам (несколько диапазонов).
(int, int)? parseRange(String? header, int length) {
  if (header == null || length <= 0) return null;
  final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (m == null) return null;
  final a = m.group(1)!, b = m.group(2)!;
  if (a.isEmpty && b.isEmpty) return null;
  if (a.isEmpty) {
    final n = int.parse(b);
    if (n == 0) return null;
    return (max(length - n, 0), length - 1);
  }
  final start = int.parse(a);
  final end = b.isEmpty ? length - 1 : min(int.parse(b), length - 1);
  if (start > end || start >= length) return null;
  return (start, end);
}
