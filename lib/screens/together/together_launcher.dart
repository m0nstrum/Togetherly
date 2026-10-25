import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../main.dart';
import '../../models/reels_source.dart';
import '../../models/room_window.dart';
import '../../services/locale_service.dart';
import '../../services/pocketbase_service.dart';
import '../../services/room_window_flag.dart';
import '../../services/watch_room_service.dart';
import '../../services/watch_videos_service.dart';
import 'watch_player_screen.dart';
import 'watch_room_screen.dart';
import '../../widgets/unfold/unfold_touch.dart';

/// Вход в совместный просмотр.
///
/// Комната одна на пару: её код выдаёт сервер, поэтому ни хоста, ни приглашений
/// больше нет — оба просто заходят. Внутри работает тот же движок, что на сайте
/// (Centrifugo), а прежняя синхронизация на Firebase RTDB убрана вместе с
/// экраном `watch_together_screen.dart`.
class TogetherLauncher {
  /// Открыть комнату пары. [videoUrl] — ссылка из карточки воспоминания,
  /// её подставят в комнату сразу после открытия.
  static Future<void> open(
    BuildContext context, {
    required String pairId,
    String? videoUrl,
    bool reels = false,
    ReelsSource reelsSource = ReelsSource.shorts,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final s = LocaleService.current;

    final room = await WatchRoomService.roomCode(pairId);
    if (room.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.error), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (!context.mounted) return;

    final navigator = LoveApp.rootNavigatorKey.currentState;
    if (navigator == null) return;

    // Файл воспоминания вкладке комнаты не отдать: там анонимный гость без
    // нашей сессии и без файлового токена. Раньше такую ссылку всё равно
    // клали в `?src=`, и оба смотрели на вечный спиннер — жалоба «видео не
    // прогружается, переносит в такое окно». Играем сами.
    final hasVideo = videoUrl != null && videoUrl.isNotEmpty;
    if (hasVideo && !WatchVideosService.playsInRoom(videoUrl)) {
      final player = MaterialPageRoute<void>(
        builder: (_) => WatchPlayerScreen(
          room: room,
          pairId: pairId,
          url: videoUrl,
        ),
      );
      await navigator.push(player);
      return;
    }

    // Комната — встроенный браузер, и на iPhone он уже терял касания после
    // чужих движений поверх себя. Растить его из кнопки под масштабом не
    // рискуем: комната открывается прежним переходом платформы.
    UnfoldTouch.forget();
    final build = await _buildNumber();
    // На iPhone доле людей (её задаёт сервер) комната открывается нативным
    // окном: встроенный браузер терял там касания у каждого четвёртого.
    final nativeWindow = roomOpensNatively(
      ios: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS,
      reels: reels,
      share: RoomWindowFlag.share,
      uid: PocketBaseService().userId ?? '',
    );
    final screen = MaterialPageRoute<void>(
      builder: (_) => WatchRoomScreen(
        room: room,
        pairId: pairId,
        videoUrl: videoUrl,
        reels: reels,
        reelsSource: reelsSource,
        nativeWindow: nativeWindow,
        build: build,
      ),
    );
    await navigator.push(screen);
  }

  /// Номер сборки для метки в адресе комнаты. Ноль, если узнать не вышло:
  /// метки тогда просто нет.
  static Future<int> _buildNumber() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return int.tryParse(info.buildNumber.trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Старое имя точки входа: ленту воспоминаний переучивать не нужно.
  static Future<void> hostVideo(
    BuildContext context, {
    required String pairId,
    required String partnerUid,
    required String videoUrl,
  }) =>
      open(context, pairId: pairId, videoUrl: videoUrl);
}
