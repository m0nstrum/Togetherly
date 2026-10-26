import '../fork/identity.dart'; // fork (PLAN 2.1)
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'pb_media_service.dart';

/// Чем закончилось сохранение фигурки — экрану нужно сказать разное.
///
/// Отказы разведены не для красоты: «сервер не собрал файл» и «галерея не
/// приняла» чинятся в разных местах, а человек, у которого не вышло, называет
/// ровно то, что увидел на экране.
enum NoteExportResult { saved, noAccess, serverFailed, saveFailed }

/// Отказ вместе с кодом ответа сервера: без кода жалоба «не сохраняется»
/// стоит вечера разбирательств.
class NoteExportOutcome {
  final NoteExportResult result;
  final int? status;

  /// Короткая причина от галереи (`accessDenied`, `notEnoughSpace`,
  /// `unexpected`). Человек читает её с экрана и называет — без этого разбор
  /// чужого телефона идёт вслепую.
  final String? reason;
  const NoteExportOutcome(this.result, {this.status, this.reason});
}

/// Сохранение фигурки в галерею телефона.
///
/// У апстрима файл собирал сервер (ffmpeg: квадрат, маска формы, подпись). В
/// форке файл фигурки зашифрован ключом пары, и серверу его не прочесть,
/// поэтому в галерею уходит сам ролик фигурки — расшифрованный локальным
/// прокси, без маски.
class NoteExportService {
  const NoteExportService._();

  /// Файл фигурки — несколько мегабайт через медленную сеть.
  static const Duration _timeout = Duration(seconds: 90);

  static Future<NoteExportOutcome> saveToGallery(
    String messageId,
    String noteUrl,
  ) async {
    if (messageId.isEmpty || noteUrl.isEmpty) {
      return const NoteExportOutcome(NoteExportResult.saveFailed);
    }
    final src = await PbMediaService.instance.resolveUrlAuthed(noteUrl);
    if (src == null || src.isEmpty) {
      return const NoteExportOutcome(NoteExportResult.serverFailed);
    }

    File? temp;
    var bytes = 0;
    try {
      final res = await http.get(Uri.parse(src)).timeout(_timeout);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
        debugPrint('NoteExport: ${res.statusCode}');
        return NoteExportOutcome(
          NoteExportResult.serverFailed,
          status: res.statusCode,
        );
      }

      bytes = res.bodyBytes.length;
      final dir = await getTemporaryDirectory();
      temp = File('${dir.path}/togetherly_$messageId.mp4');
      // flush обязателен: галерея читает файл СРАЗУ после нас, и без сброса
      // на диск ей достаётся пустой или обрезанный ролик.
      await temp.writeAsBytes(res.bodyBytes, flush: true);

      // Доступ спрашиваем ПЕРЕД записью в галерею: отказ — это не сбой, а
      // ответ человека, и говорить про него надо иначе.
      if (!await Gal.hasAccess(toAlbum: true)) {
        if (!await Gal.requestAccess(toAlbum: true)) {
          return const NoteExportOutcome(NoteExportResult.noAccess);
        }
      }
      await Gal.putVideo(temp.path, album: ForkIdentity.appName);
      return const NoteExportOutcome(NoteExportResult.saved);
    } on GalException catch (e, st) {
      debugPrint('NoteExport gal: ${e.type}');
      if (e.type != GalExceptionType.accessDenied) {
        // Отказ галереи прилетает только с чужих телефонов и только словами
        // «не сохраняется». Пусть приезжает сам, с типом и размером файла.
        unawaited(
          Sentry.captureException(
            e,
            stackTrace: st,
            withScope: (s) {
              s.level = SentryLevel.warning;
              s.setContexts('note_export', {
                'gal': e.type.name,
                'bytes': bytes,
                'message': messageId,
              });
            },
          ),
        );
      }
      return NoteExportOutcome(
        e.type == GalExceptionType.accessDenied
            ? NoteExportResult.noAccess
            : NoteExportResult.saveFailed,
        reason: e.type.name,
      );
    } catch (e, st) {
      debugPrint('NoteExport failed: $e');
      unawaited(
        Sentry.captureException(
          e,
          stackTrace: st,
          withScope: (s) {
            s.level = SentryLevel.warning;
            s.setContexts('note_export', {
              'bytes': bytes,
              'message': messageId,
            });
          },
        ),
      );
      return NoteExportOutcome(
        NoteExportResult.saveFailed,
        reason: e.runtimeType.toString(),
      );
    } finally {
      // Копия в галерее уже своя, временный файл держать незачем.
      try {
        if (temp != null && await temp.exists()) await temp.delete();
      } catch (_) {
        /* уберёт система */
      }
    }
  }
}
