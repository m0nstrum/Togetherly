/// Шифрование файлов медиа (PLAN S9, docs/fork/E2E.md §8).
///
/// Файл режется на блоки по [MediaCipher.defaultChunk] байт, каждый блок —
/// XChaCha20-Poly1305 со своим номером в nonce. Блоки независимы, поэтому
/// плеер может перематывать: прокси качает с сервера только нужный диапазон
/// (HTTP Range) и расшифровывает его.
///
/// ```
/// "TTHE2EF1" | u16 длина заголовка | заголовок (JSON) | блок 0 | блок 1 | …
/// ```
///
/// Заголовок: `k` — key_id ключа пары, `n` — 16 случайных байт nonce, `c` —
/// размер блока, `l` — длина открытого файла, `m` — тип содержимого.
///
/// Ключ файла выводится из ключа пары и id записи `media`: файл из одной
/// записи не открыть под видом другой. AAD блока — id записи, заголовок
/// целиком, номер блока и признак последнего: сервер не обрежет файл, не
/// переставит блоки и не подменит тип.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'crypto.dart';
import 'envelope.dart';
import 'record_codec.dart';

/// Виды файлов `media`, что остаются открытыми: их разбирает сервер (кадры
/// живого фото для виджета, `widget_anim.pb.js`). Аватар и баннер шифруются
/// личным ключом, партнёру уходит копия под ключом пары (ForkProfile);
/// ролики — ключом пары, играют через локальный прокси.
const Set<String> plainMediaKinds = {'widget_anim'};

/// Тип содержимого по имени файла — прокси отдаёт его плееру.
String mimeFromName(String? name) {
  final dot = (name ?? '').lastIndexOf('.');
  final ext = dot < 0 ? '' : name!.substring(dot + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'heic' => 'image/heic',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'm4a' => 'audio/mp4',
    'aac' => 'audio/aac',
    'mp3' => 'audio/mpeg',
    'ogg' || 'opus' => 'audio/ogg',
    'wav' => 'audio/wav',
    'json' => 'application/json',
    _ => 'application/octet-stream',
  };
}

const List<int> mediaMagic = [0x54, 0x54, 0x48, 0x45, 0x32, 0x45, 0x46, 0x31];
const int _tagBytes = 16;

class MediaHeader {
  MediaHeader({
    required this.keyId,
    required this.nonce,
    required this.chunk,
    required this.length,
    required this.mime,
    required this.raw,
  });

  final String keyId;
  final Uint8List nonce;
  final int chunk;

  /// Длина открытого файла.
  final int length;
  final String mime;

  /// Байты заголовка (JSON) — входят в AAD.
  final Uint8List raw;

  /// Сколько байт до первого блока.
  int get size => mediaMagic.length + 2 + raw.length;

  int get chunks => length == 0 ? 0 : (length + chunk - 1) ~/ chunk;

  /// Длина шифрованного файла.
  int get encryptedLength => size + length + chunks * _tagBytes;

  /// Где в шифрованном файле лежит блок [i] и сколько в нём байт.
  (int start, int len) chunkRange(int i) {
    final plain = math.min(chunk, length - i * chunk);
    return (size + i * (chunk + _tagBytes), plain + _tagBytes);
  }
}

/// Начало файла не похоже на шифрованное — файл открытый (старый, аватар).
class NotEncrypted implements Exception {
  const NotEncrypted();
}

/// Чтобы разобрать заголовок, нужно столько байт с начала файла.
class NeedMoreBytes implements Exception {
  const NeedMoreBytes(this.bytes);
  final int bytes;
}

/// Заголовок шифрованного файла по его первым байтам.
MediaHeader parseMediaHeader(Uint8List head) {
  for (var i = 0; i < mediaMagic.length; i++) {
    if (i >= head.length) throw NeedMoreBytes(mediaMagic.length + 2);
    if (head[i] != mediaMagic[i]) throw const NotEncrypted();
  }
  if (head.length < mediaMagic.length + 2) {
    throw NeedMoreBytes(mediaMagic.length + 2);
  }
  final len = (head[mediaMagic.length] << 8) | head[mediaMagic.length + 1];
  final end = mediaMagic.length + 2 + len;
  if (head.length < end) throw NeedMoreBytes(end);
  final raw = Uint8List.fromList(head.sublist(mediaMagic.length + 2, end));
  final j = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  final chunk = j['c'] as int;
  final length = j['l'] as int;
  if (chunk <= 0 || length < 0) {
    throw const FormatException('файл: битый заголовок');
  }
  return MediaHeader(
    keyId: j['k'] as String,
    nonce: unb64(j['n'] as String),
    chunk: chunk,
    length: length,
    mime: (j['m'] as String?) ?? 'application/octet-stream',
    raw: raw,
  );
}

class MediaCipher {
  MediaCipher(this._c);

  final E2ECrypto _c;

  static const int defaultChunk = 64 * 1024;

  /// Сколько байт качать с начала файла, чтобы почти наверняка хватило на
  /// заголовок.
  static const int probeBytes = 512;

  SecureKey fileKey(PairKey key, String recordId) => _c.keyFromBytes(
    _c.hash(
      frame([utf8Bytes('tethered-file-key-v1'), utf8Bytes(recordId)]),
      key: key.key,
    ),
  );

  Uint8List encrypt(
    Uint8List plain,
    PairKey key,
    String recordId, {
    String mime = 'application/octet-stream',
    int chunk = defaultChunk,
  }) {
    final raw = utf8Bytes(
      jsonEncode({
        'k': key.keyId,
        'n': b64(_c.random(16)),
        'c': chunk,
        'l': plain.length,
        'm': mime,
      }),
    );
    final prefix = _prefix(raw);
    final h = parseMediaHeader(prefix);
    final fk = fileKey(key, recordId);
    try {
      final out = BytesBuilder(copy: false)..add(prefix);
      for (var i = 0; i < h.chunks; i++) {
        final from = i * chunk;
        final to = math.min(from + chunk, plain.length);
        out.add(
          _c.aeadEncrypt(
            Uint8List.sublistView(plain, from, to),
            _nonce(h, i),
            fk,
            _aad(h, recordId, i),
          ),
        );
      }
      return out.toBytes();
    } finally {
      fk.dispose();
    }
  }

  /// Блок [i]; бросает [E2EVerifyError], если блок подменён.
  Uint8List decryptChunk(
    MediaHeader h,
    SecureKey fk,
    String recordId,
    int i,
    Uint8List ct,
  ) => _c.aeadDecrypt(ct, _nonce(h, i), fk, _aad(h, recordId, i));

  /// Весь файл разом. null — открыть нечем; [NotEncrypted] — файл открытый.
  Uint8List? decryptAll(Uint8List data, E2EKeyring keys, String recordId) {
    final h = parseMediaHeader(data);
    final key = keys.keyFor(h.keyId);
    if (key == null) return null;
    if (data.length != h.encryptedLength) {
      throw E2EVerifyError('файл: длина не сходится');
    }
    final fk = fileKey(key, recordId);
    try {
      final out = BytesBuilder(copy: false);
      for (var i = 0; i < h.chunks; i++) {
        final (start, len) = h.chunkRange(i);
        out.add(
          decryptChunk(
            h,
            fk,
            recordId,
            i,
            Uint8List.sublistView(data, start, start + len),
          ),
        );
      }
      return out.toBytes();
    } finally {
      fk.dispose();
    }
  }

  static Uint8List _prefix(Uint8List raw) {
    if (raw.length > 0xffff) throw const FormatException('файл: заголовок');
    return Uint8List.fromList([
      ...mediaMagic,
      raw.length >> 8,
      raw.length & 0xff,
      ...raw,
    ]);
  }

  static Uint8List _nonce(MediaHeader h, int i) {
    final n = Uint8List(24)..setAll(0, h.nonce);
    ByteData.sublistView(n).setUint64(16, i);
    return n;
  }

  static Uint8List _aad(MediaHeader h, String recordId, int i) {
    final idx = Uint8List(8);
    ByteData.sublistView(idx).setUint64(0, i);
    return frame([
      utf8Bytes('tethered-file-v1'),
      utf8Bytes(recordId),
      h.raw,
      idx,
      Uint8List.fromList([i == h.chunks - 1 ? 1 : 0]),
    ]);
  }
}
