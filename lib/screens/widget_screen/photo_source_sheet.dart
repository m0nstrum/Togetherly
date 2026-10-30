import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PHOTO SOURCE SHEET
// ══════════════════════════════════════════════════════════════════════════════

/// Маркер листа выбора: человек нажал «Живое фото», а не выбрал источник снимка.
const String kPickLiveVideo = 'live-video';

/// Маркер: человек хочет вернуть виджету обычную фотографию.
const String kDropLiveVideo = 'live-video-off';

class PhotoSourceSheet extends StatelessWidget {
  final AppTheme theme;

  /// Стоит ли сейчас живое фото — от этого зависит, показывать ли «убрать».
  final bool liveActive;

  const PhotoSourceSheet({
    super.key,
    required this.theme,
    this.liveActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            LocaleService.current.chooseSource,
            style: AppFonts.onest(
              size: 18,
              weight: 800,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.camera_alt_rounded,
                  label: LocaleService.current.camera,
                  source: ImageSource.camera,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _sourceButton(
                  context,
                  icon: Icons.photo_library_rounded,
                  label: LocaleService.current.gallery,
                  source: ImageSource.gallery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Живое фото: короткое видео или гифка вместо снимка. Кадры из файла
          // делает сервер, здесь человек просто выбирает его в галерее.
          _liveButton(context),
          if (liveActive) ...[
            const SizedBox(height: 8),
            _dropLiveButton(context),
          ],
        ],
      ),
    );
  }

  /// «Живое фото» отдаёт не источник, а признак: дальше вызывающий сам берёт
  /// файл из галереи (`pickMedia`) и отправляет его на подготовку кадров.
  Widget _liveButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, kPickLiveVideo),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primary.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(
              Icons.motion_photos_on_rounded,
              size: 30,
              color: theme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              ruEn(
                'Живое фото — видео или гифка',
                'Live photo — a video or a GIF',
              ),
              style: AppFonts.onest(
                size: 13,
                weight: 600,
                color: theme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Выход из живого фото. Отдельная строка нужна потому, что снимок его больше
  /// не вытесняет молча: раскадровка лежит своими ключами, и без явного сброса
  /// виджет оставался с видео навсегда.
  Widget _dropLiveButton(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, kDropLiveVideo),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: theme.textSecondary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.motion_photos_off_rounded,
              size: 20,
              color: theme.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              ruEn('Убрать живое фото', 'Remove the live photo'),
              style: AppFonts.onest(
                size: 13,
                weight: 600,
                color: theme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.primary.withOpacity(0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: theme.primary),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppFonts.onest(
                size: 13,
                weight: 600,
                color: theme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
