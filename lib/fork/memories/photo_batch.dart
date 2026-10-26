/// Заливка набора фото в воспоминание без молчаливых потерь
/// (docs/history/UX_AUDIT.md, D1/D6): если часть не залилась, человеку говорят
/// «загружено N из M» и дают повторить или не сохранять запись.
library;

import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/upload_failure.dart';
import '../../services/locale_service.dart';

/// Заливка одного файла по пути; возвращает ссылку или причину отказа.
typedef PhotoUploader = Future<UploadOutcome> Function(String path, int index);

/// Запись не сохраняем: человек отказался или причина уже названа.
/// Форма, поймав её, остаётся открытой с введённым.
class MemorySaveAborted implements Exception {
  const MemorySaveAborted();

  @override
  String toString() => 'MemorySaveAborted';
}

/// Итог заливки набора: ссылки по местам исходных путей.
class PhotoBatch {
  PhotoBatch._(this.paths, this._refs, this.failure);

  final List<String> paths;
  final List<String?> _refs;

  /// Причина первого отказа последнего прохода.
  final UploadFailure? failure;

  int get total => paths.length;
  int get uploaded => _refs.where((r) => r != null).length;
  bool get complete => uploaded == total;

  /// Ссылки в порядке исходных путей, без пропусков.
  List<String> get urls => [for (final r in _refs) ?r];

  static Future<PhotoBatch> upload(
    List<String> paths,
    PhotoUploader uploader,
  ) => _run(paths, List<String?>.filled(paths.length, null), uploader);

  /// Залить только то, что не залилось.
  Future<PhotoBatch> retryFailed(PhotoUploader uploader) =>
      _run(paths, List<String?>.of(_refs), uploader);

  static Future<PhotoBatch> _run(
    List<String> paths,
    List<String?> refs,
    PhotoUploader uploader,
  ) async {
    UploadFailure? failure;
    for (var i = 0; i < paths.length; i++) {
      if (refs[i] != null) continue;
      final outcome = await uploader(paths[i], i);
      refs[i] = outcome.ref;
      if (outcome.ref == null)
        failure ??= outcome.failure ?? UploadFailure.other;
    }
    return PhotoBatch._(paths, refs, failure);
  }
}

/// Залить [paths]; пока не залито всё, спрашивать «повторить или не
/// сохранять». `null` — человек отказался (запись сохранять нельзя).
Future<List<String>?> uploadPhotosConfirmed(
  BuildContext context,
  List<String> paths,
  PhotoUploader uploader, {
  void Function()? beforeAsk,
}) async {
  var batch = await PhotoBatch.upload(paths, uploader);
  while (!batch.complete) {
    beforeAsk?.call();
    if (!context.mounted) return null;
    final retry = await _askRetry(context, batch);
    if (retry != true) return null;
    batch = await batch.retryFailed(uploader);
  }
  return batch.urls;
}

Future<bool?> _askRetry(BuildContext context, PhotoBatch batch) {
  final reason = uploadFailureText(
    batch.failure ?? UploadFailure.other,
    LocaleService.current,
    video: false,
  );
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(
        ruEn(
          'Загружено ${batch.uploaded} из ${batch.total} фото',
          'Uploaded ${batch.uploaded} of ${batch.total} photos',
        ),
      ),
      content: Text(
        '$reason\n\n${ruEn('Запись не сохранится без остальных фото. Повторить заливку или не сохранять запись? Введённое останется в форме.', 'The memory won’t be saved without the rest. Retry the upload or don’t save? What you typed stays in the form.')}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ruEn('Не сохранять', 'Don’t save')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ruEn('Повторить', 'Retry')),
        ),
      ],
    ),
  );
}
