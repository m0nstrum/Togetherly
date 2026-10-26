import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/catalog_service.dart';
import '../../services/mascot_service.dart';
import '../../services/offline/media_view_cache.dart';
import '../../models/mascot_anim.dart';
import '../../models/mascot_sleep.dart';
import '../../widgets/active_mascot_widget.dart' show buildMascotAssetImage;
import '../../widgets/mascot/pixel_mascot_view.dart';
import '../../widgets/storage_image.dart';

/// Reuses the actual chosen art, including drawings, uploads and pixel atlases.
class PetPortrait extends StatelessWidget {
  const PetPortrait({super.key, required this.service, required this.sleepOf});
  final MascotService service;
  final SleepWindow Function(String) sleepOf;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final mascot = service.activeMascot;
      if (mascot == null) {
        return const Icon(
          Icons.add_photo_alternate_outlined,
          size: 56,
          color: Color(0xFF563F2E),
        );
      }
      final asset = service.resolvedAssetForMood(mascot);
      if (asset != null) {
        return buildMascotAssetImage(asset, fit: BoxFit.contain);
      }
      final anim = CatalogService.instance.animById(mascot.id);
      if (anim != null) {
        return LayoutBuilder(
          builder: (context, c) => PixelMascotView(
            anim: anim,
            state: MascotAnimState.live,
            level: MascotAnim.levelForStreak(service.activeStreak),
            sleep: sleepOf(mascot.id),
            size: c.biggest.shortestSide,
          ),
        );
      }
      Widget waiting(BuildContext c, String url) =>
          const Center(child: Icon(Icons.pets_outlined));
      Widget failed(BuildContext c, String url, dynamic e) =>
          const Icon(Icons.pets_outlined);
      if (mascot.catalogUrl != null) {
        return CachedNetworkImage(
          imageUrl: mascot.catalogUrl!,
          cacheManager: OfflineImageCacheManager.instance,
          fit: BoxFit.contain,
          placeholder: waiting,
          errorWidget: failed,
        );
      }
      if (mascot.imageUrl != null) {
        return StorageImage(
          imageUrl: mascot.imageUrl!,
          fit: BoxFit.contain,
          placeholder: waiting,
          errorWidget: failed,
        );
      }
      return const Icon(Icons.pets_outlined, size: 56);
    },
  );
}
