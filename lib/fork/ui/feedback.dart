/// Общие кирпичики обратной связи (docs/history/UX_AUDIT.md, «Общий диагноз»).
///
/// Правило: действие отвечает «получилось» или «нет, вот почему», а экран
/// говорит человеку причину и даёт повторить. Никаких проглоченных ошибок,
/// `null` вместо причины и `Exception: …` на экране.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../system_settings.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../dict_strings.dart' show ruEn;
import '../e2e/record_codec.dart' show E2ENoKeyError;

/// Почему действие не удалось — так, как это различает человек.
enum ForkFailure {
  /// Нет связи или сервер молчит: обычно помогает повтор.
  network,

  /// Сессия кончилась: нужно войти заново.
  session,

  /// Ключи пары ещё не обменялись или не восстановлены.
  noKey,

  /// Access to the camera or photo library was denied.
  mediaPermission,

  /// Файл больше допустимого.
  tooLarge,

  /// Сервер отказал по правилам (чужое, запрещено).
  denied,

  /// Ошибка сервера или что-то неожиданное.
  unknown;

  /// Причина по пойманной ошибке.
  static ForkFailure of(Object error) {
    if (error is PlatformException &&
        const {
          'camera_access_denied',
          'camera_access_denied_without_prompt',
          'camera_access_restricted',
          'photo_access_denied',
          'photo_access_denied_without_prompt',
          'photo_access_restricted',
          'read_external_storage_denied',
          'access_denied',
          'PERMISSION_DENIED',
        }.contains(error.code)) {
      return mediaPermission;
    }
    if (error is ForkFailureError) return error.failure;
    if (error is E2ENoKeyError) return noKey;
    if (error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException ||
        error is HttpException) {
      return network;
    }
    if (error is ClientException) {
      final code = error.statusCode;
      if (code == 0) return network;
      if (code == 401) return session;
      if (code == 413 ||
          error.response.toString().contains('validation_file_size_limit')) {
        return tooLarge;
      }
      if (code == 403 || code == 404 || code == 400) return denied;
    }
    return unknown;
  }

  /// Текст для человека.
  String get text => switch (this) {
    network => ruEn(
      'Нет связи с сервером. Проверьте интернет и повторите.',
      'Can’t reach the server. Check your connection and try again.',
    ),
    session => ruEn(
      'Сессия завершилась — войдите заново.',
      'Your session ended — please sign in again.',
    ),
    noKey => ruEn(
      'Ключи шифрования ещё не готовы: дождитесь партнёра или восстановите ключи.',
      'Encryption keys aren’t ready yet: wait for your partner or restore your keys.',
    ),
    mediaPermission => ruEn(
      'Нет доступа к камере или галерее. Разрешите его в настройках телефона.',
      'Camera or photo access is denied. Allow it in your phone settings.',
    ),
    tooLarge => ruEn('Файл слишком большой.', 'The file is too large.'),
    denied => ruEn(
      'Сервер не принял это действие.',
      'The server refused this action.',
    ),
    unknown => ruEn(
      'Что-то пошло не так. Попробуйте ещё раз.',
      'Something went wrong. Please try again.',
    ),
  };

  /// Есть ли смысл в кнопке «Повторить».
  bool get retryable => this == network || this == unknown;
}

/// Ошибка с уже известной причиной — чтобы бросить её из сервиса.
class ForkFailureError implements Exception {
  const ForkFailureError(this.failure, [this.detail = '']);
  final ForkFailure failure;
  final String detail;

  @override
  String toString() => 'ForkFailureError(${failure.name}) $detail';
}

/// Итог действия: значение или причина отказа.
sealed class Outcome<T> {
  const Outcome();

  bool get ok => this is Done<T>;
  T? get value => switch (this) {
    Done<T>(:final value) => value,
    Failed<T>() => null,
  };
  ForkFailure? get failure => switch (this) {
    Done<T>() => null,
    Failed<T>(:final failure) => failure,
  };

  /// Выполнить [action] и поймать ошибку в причину.
  static Future<Outcome<T>> guard<T>(Future<T> Function() action) async {
    try {
      return Done(await action());
    } catch (e) {
      debugPrint('Outcome: $e');
      return Failed(ForkFailure.of(e), e);
    }
  }
}

final class Done<T> extends Outcome<T> {
  const Done(this.value);
  @override
  final T value;
}

final class Failed<T> extends Outcome<T> {
  const Failed(this.failure, [this.error]);
  @override
  final ForkFailure failure;
  final Object? error;
}

/// Сообщения человеку.
abstract final class ForkNotice {
  /// Сбой: причина и, если есть смысл, «Повторить».
  static void failure(
    BuildContext context,
    ForkFailure failure, {
    String? what,
    VoidCallback? retry,
  }) {
    final text = what == null ? failure.text : '$what. ${failure.text}';
    _show(
      context,
      text,
      error: true,
      action: failure == ForkFailure.mediaPermission
          ? SnackBarAction(
              label: ruEn('Открыть настройки', 'Open settings'),
              onPressed: () {
                unawaited(openSystemAppSettings());
              },
            )
          : retry != null && failure.retryable
          ? SnackBarAction(label: ruEn('Повторить', 'Retry'), onPressed: retry)
          : null,
    );
  }

  /// Сбой по пойманной ошибке.
  static void error(
    BuildContext context,
    Object error, {
    String? what,
    VoidCallback? retry,
  }) => failure(context, ForkFailure.of(error), what: what, retry: retry);

  /// Короткое сообщение о смене состояния («Партнёр вышел»).
  static void info(BuildContext context, String text) =>
      _show(context, text, error: false);

  static void _show(
    BuildContext context,
    String text, {
    required bool error,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final cs = Theme.of(context).colorScheme;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? cs.errorContainer : null,
          duration: Duration(seconds: action != null ? 6 : 4),
          action: action,
        ),
      );
  }
}

/// Тон плашки состояния.
enum ForkStatusTone { info, progress, warning, error }

/// Плашка состояния живого экрана: что происходит сейчас. Висит, пока
/// состояние не сменится, а не исчезает через пару секунд.
class ForkStatusBar extends StatelessWidget {
  const ForkStatusBar({
    super.key,
    required this.text,
    this.tone = ForkStatusTone.info,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.onClose,
  });

  final String text;
  final ForkStatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Касание по самой плашке (звонок — развернуть на весь экран).
  final VoidCallback? onTap;

  /// Крестик: плашку можно убрать, не делая действия.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      ForkStatusTone.error => (cs.errorContainer, cs.onErrorContainer),
      ForkStatusTone.warning => (cs.tertiaryContainer, cs.onTertiaryContainer),
      _ => (cs.secondaryContainer, cs.onSecondaryContainer),
    };
    return Semantics(
      liveRegion: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                if (tone == ForkStatusTone.progress)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else
                  Icon(
                    switch (tone) {
                      ForkStatusTone.error => Icons.error_outline_rounded,
                      ForkStatusTone.warning => Icons.warning_amber_rounded,
                      _ => Icons.info_outline_rounded,
                    },
                    size: 18,
                    color: fg,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: fg),
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  TextButton(
                    onPressed: onAction,
                    style: TextButton.styleFrom(foregroundColor: fg),
                    child: Text(actionLabel!),
                  ),
                if (onClose != null)
                  IconButton(
                    tooltip: ruEn('Закрыть', 'Close'),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 20, color: fg),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
