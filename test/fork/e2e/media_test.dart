// fork: шифрование файлов медиа и локальный прокси (PLAN S9).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_app/fork/e2e/crypto.dart';
import 'package:love_app/fork/e2e/envelope.dart';
import 'package:love_app/fork/e2e/http_client.dart';
import 'package:love_app/fork/e2e/media_cipher.dart';
import 'package:love_app/fork/e2e/media_proxy.dart';
import 'package:love_app/fork/e2e/record_codec.dart';
import 'package:pocketbase/pocketbase.dart';

const _gid = 'pairaaaaaaaaaaa';

class _Keys implements E2EKeyring {
  final Map<String, PairKey> byId = {};
  void add(PairKey k) => byId[k.keyId] = k;
  @override
  PairKey? keyFor(String keyId) => byId[keyId];
  @override
  PairKey? currentKey(String groupId) =>
      byId.values.where((k) => k.groupId == groupId).lastOrNull;
  @override
  String? groupWith(Set<String> members) => null;
}

Uint8List _bytes(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + 3) & 0xff));

/// Сервер файлов как у PocketBase: `/api/files/media/<id>/<имя>`, Range.
class _FileServer {
  final Map<String, Uint8List> files = {};
  final List<String?> ranges = [];
  late HttpServer _s;

  Future<void> start() async {
    _s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _s.listen((req) async {
      final f = files[req.uri.path];
      final res = req.response;
      if (f == null) {
        res.statusCode = 404;
        await res.close();
        return;
      }
      final range = req.headers.value('range');
      ranges.add(range);
      final r = parseRange(range, f.length);
      if (range != null && r == null) {
        res.statusCode = 416;
        await res.close();
        return;
      }
      final (a, b) = r ?? (0, f.length - 1);
      res.statusCode = r == null ? 200 : 206;
      res.headers.set('accept-ranges', 'bytes');
      res.headers.contentType = ContentType.parse('image/jpeg');
      if (r != null) {
        res.headers.set('content-range', 'bytes $a-$b/${f.length}');
      }
      res.contentLength = b - a + 1;
      if (req.method != 'HEAD') res.add(Uint8List.sublistView(f, a, b + 1));
      await res.close();
    });
  }

  String url(String path) => 'http://127.0.0.1:${_s.port}$path?token=t';

  Future<void> stop() => _s.close(force: true);
}

void main() {
  late E2ECrypto c;
  late _Keys keys;
  late PairKey key;
  setUpAll(() async => c = await E2ECrypto.init());
  setUp(() {
    key = PairKey(_gid, 1, c.symmetricKey());
    keys = _Keys()..add(key);
  });

  group('формат файла', () {
    test('туда и обратно на границах блоков', () {
      final cipher = MediaCipher(c);
      for (final n in [1, 15, 16, 17, 64, 100]) {
        final plain = _bytes(n);
        final enc = cipher.encrypt(plain, key, 'rec1', chunk: 16);
        final h = parseMediaHeader(enc);
        expect(h.length, n);
        expect(enc.length, h.encryptedLength);
        expect(cipher.decryptAll(enc, keys, 'rec1'), plain, reason: '$n');
      }
    });

    test('чужая запись, обрезка, перестановка блоков — не открывается', () {
      final cipher = MediaCipher(c);
      final enc = cipher.encrypt(_bytes(48), key, 'rec1', chunk: 16);
      expect(
        () => cipher.decryptAll(enc, keys, 'rec2'),
        throwsA(isA<E2EVerifyError>()),
      );
      final h = parseMediaHeader(enc);
      final (s0, l0) = h.chunkRange(0);
      final (s1, _) = h.chunkRange(1);
      final swapped = Uint8List.fromList(enc)
        ..setRange(s0, s0 + l0, enc.sublist(s1, s1 + l0))
        ..setRange(s1, s1 + l0, enc.sublist(s0, s0 + l0));
      expect(
        () => cipher.decryptAll(swapped, keys, 'rec1'),
        throwsA(isA<E2EVerifyError>()),
      );
      final cut = Uint8List.sublistView(enc, 0, h.chunkRange(2).$1);
      expect(
        () => cipher.decryptAll(cut, keys, 'rec1'),
        throwsA(isA<E2EVerifyError>()),
      );
    });

    test('открытый файл узнаётся по первым байтам', () {
      expect(
        () =>
            parseMediaHeader(Uint8List.fromList(utf8.encode('\xff\xd8 jpeg'))),
        throwsA(isA<NotEncrypted>()),
      );
      expect(
        () => parseMediaHeader(Uint8List.fromList(mediaMagic.sublist(0, 4))),
        throwsA(isA<NeedMoreBytes>()),
      );
    });

    test('Range разбирается как у сервера', () {
      expect(parseRange('bytes=0-', 10), (0, 9));
      expect(parseRange('bytes=2-4', 10), (2, 4));
      expect(parseRange('bytes=-3', 10), (7, 9));
      expect(parseRange('bytes=5-100', 10), (5, 9));
      expect(parseRange('bytes=10-', 10), isNull);
      expect(parseRange('bytes=0-1,4-5', 10), isNull);
      expect(parseRange(null, 10), isNull);
    });
  });

  group('прокси', () {
    late _FileServer server;
    late MediaProxy proxy;
    final client = HttpClient();

    setUp(() async {
      server = _FileServer();
      await server.start();
      proxy = MediaProxy(codec: () async => RecordCodec(c, keys));
    });
    tearDown(() async {
      await proxy.close();
      await server.stop();
    });

    Future<(int, Map<String, String>, Uint8List)> get(
      String url, {
      String? range,
      String method = 'GET',
    }) async {
      final r = await client.openUrl(method, Uri.parse(url));
      if (range != null) r.headers.set('range', range);
      final res = await r.close();
      final body = BytesBuilder();
      await res.forEach(body.add);
      final h = <String, String>{};
      res.headers.forEach((k, v) => h[k] = v.join(','));
      return (res.statusCode, h, body.toBytes());
    }

    test('шифрованный файл: целиком, середина, хвост, HEAD', () async {
      final plain = _bytes(200000);
      server.files['/api/files/media/rec1/photo.mp4'] = MediaCipher(
        c,
      ).encrypt(plain, key, 'rec1', mime: 'video/mp4');
      final url = await proxy.wrap(
        server.url('/api/files/media/rec1/photo.mp4'),
      );
      expect(url, startsWith('http://127.0.0.1:'));
      expect(url, contains('/photo.mp4?'));

      final (s1, h1, b1) = await get(url);
      expect(s1, 200);
      expect(h1['content-type'], 'video/mp4');
      expect(b1, plain);

      final (s2, h2, b2) = await get(url, range: 'bytes=65530-131080');
      expect(s2, 206);
      expect(h2['content-range'], 'bytes 65530-131080/200000');
      expect(b2, plain.sublist(65530, 131081));
      // С сервера ушли только нужные блоки, а не весь файл.
      expect(server.ranges.last, isNot('bytes=0-'));

      final (s3, _, b3) = await get(url, range: 'bytes=-10');
      expect(s3, 206);
      expect(b3, plain.sublist(199990));

      final (s4, h4, b4) = await get(url, method: 'HEAD');
      expect(s4, 200);
      expect(h4['content-length'], '200000');
      expect(b4, isEmpty);
    });

    test('открытый файл проходит как есть, с диапазоном', () async {
      final plain = _bytes(3000);
      server.files['/api/files/media/old/a.jpg'] = plain;
      final url = await proxy.wrap(server.url('/api/files/media/old/a.jpg'));
      expect((await get(url)).$3, plain);
      final (s, _, b) = await get(url, range: 'bytes=10-19');
      expect(s, 206);
      expect(b, plain.sublist(10, 20));
    });

    test('чужой секрет и нет ключа — 404; не media — адрес как есть', () async {
      server.files['/api/files/media/rec2/x.jpg'] = MediaCipher(
        c,
      ).encrypt(_bytes(10), PairKey(_gid, 9, c.symmetricKey()), 'rec2');
      final url = await proxy.wrap(server.url('/api/files/media/rec2/x.jpg'));
      expect((await get(url)).$1, 404);
      final forged = url.replaceFirst(
        RegExp(r'127\.0\.0\.1:\d+/[^/]+'),
        '${Uri.parse(url).host}:${Uri.parse(url).port}/wrong',
      );
      expect((await get(forged)).$1, 404);
      final other = server.url('/api/files/users/u1/a.jpg');
      expect(await proxy.wrap(other), other);
    });
  });

  group('загрузка', () {
    test('файл пары уходит шифром, аватар — открытым', () async {
      final sent = <String, Uint8List>{};
      final pb = PocketBase(
        'http://pb',
        httpClientFactory: () => E2EHttpClient(
          MockClient.streaming((req, body) async {
            final bytes = await body.toBytes();
            final kind =
                utf8.decode(bytes, allowMalformed: true).contains('avatar')
                ? 'avatar'
                : 'memory';
            sent[kind] = bytes;
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(jsonEncode({'id': 'x', 'file': 'a.jpg'})),
              ),
              200,
            );
          }),
          codec: () async => RecordCodec(c, keys),
          newId: () => 'mediaid00000001',
        ),
      );
      final plain = utf8.encode('JPEG-ОТКРЫТЫЕ-БАЙТЫ' * 10);
      await pb
          .collection('media')
          .create(
            body: {'group_id': _gid, 'kind': 'memory'},
            files: [
              http.MultipartFile.fromBytes('file', plain, filename: 'a.jpg'),
            ],
          );
      await pb
          .collection('media')
          .create(
            body: {'group_id': 'useraaaaaaaaaa', 'kind': 'avatar'},
            files: [
              http.MultipartFile.fromBytes('file', plain, filename: 'a.jpg'),
            ],
          );
      final mem = utf8.decode(sent['memory']!, allowMalformed: true);
      expect(mem, contains('mediaid00000001'));
      expect(mem, isNot(contains('ОТКРЫТЫЕ')));
      expect(mem, contains('TTHE2EF1'));
      expect(
        utf8.decode(sent['avatar']!, allowMalformed: true),
        contains('ОТКРЫТЫЕ'),
      );
    });
  });
}
