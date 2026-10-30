import '../../widgets/mood_image.dart';
import '../../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import '../../models/widget_data.dart';
import '../../models/mood_entry.dart';
import '../../theme/app_theme.dart';

// Части превью виджетов в каталоге: зависят только от темы.

class PairPreviewHalf extends StatelessWidget {
  const PairPreviewHalf({
    super.key,
    required this.data,
    required this.photoUrl,
    required this.panelColor,
    required this.isLeft,
  });

  final WidgetData data;
  final String photoUrl;
  final Color panelColor;
  final bool isLeft;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl.isNotEmpty;
    final textColor = hasPhoto ? Colors.white : const Color(0xCC000000);
    final subColor = hasPhoto
        ? Colors.white.withOpacity(0.85)
        : const Color(0x99000000);

    Widget panel() => ColoredBox(color: panelColor);

    return Stack(
      fit: StackFit.expand,
      children: [
        // Фон: фото (cover) или цветная панель
        if (hasPhoto)
          StorageImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => panel(),
            errorWidget: (_, __, ___) => panel(),
          )
        else
          panel(),
        // Лёгкое затемнение поверх фото
        if (hasPhoto) const ColoredBox(color: Color(0x1A000000)),
        // Центральный контент
        Padding(
          padding: const EdgeInsets.all(6),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (data.hasMood)
                  ClipOval(
                    child: MoodImage(
                      data.moodEmoji,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                    ),
                  ),
                if (data.hasStatus) ...[
                  const SizedBox(height: 4),
                  Text(
                    data.status,
                    textAlign: TextAlign.center,
                    style: AppFonts.onest(
                      size: 10,
                      weight: 600,
                      color: textColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (data.hasMessage) ...[
                  const SizedBox(height: 2),
                  Text(
                    data.message,
                    textAlign: TextAlign.center,
                    style: AppFonts.onest(size: 9, color: subColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (data.hasMusic) ...[
                  const SizedBox(height: 3),
                  Text(
                    '♪ ${data.musicTitle}',
                    textAlign: TextAlign.center,
                    style: AppFonts.onest(size: 8, color: subColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Аватар в нижнем углу (как в нативном виджете)
        if (data.avatarUrl.isNotEmpty)
          Positioned(
            bottom: 4,
            left: isLeft ? 4 : null,
            right: isLeft ? null : 4,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: ClipOval(
                child: StorageImage(
                  imageUrl: data.avatarUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      ColoredBox(color: Colors.white.withOpacity(0.4)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class LockMoodHalf extends StatelessWidget {
  const LockMoodHalf({
    super.key,
    required this.t,
    required this.entry,
    required this.name,
    required this.isLeft,
    required this.noMoodLabel,
  });

  final AppTheme t;
  final MoodEntry? entry;
  final String name;
  final bool isLeft;
  final String noMoodLabel;

  @override
  Widget build(BuildContext context) {
    final entry = this.entry;
    return Column(
      crossAxisAlignment: isLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          name,
          style: AppFonts.onest(
            size: 11,
            weight: 700,
            letterSpacing: 0.3,
            color: t.textMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (entry != null) ...[
          ClipOval(
            child: MoodImage(
              entry.imagePath,
              width: 48,
              height: 48,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            entry.localizedLabel,
            style: AppFonts.onest(size: 12, weight: 700, color: t.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ] else ...[
          const Text('😶', style: TextStyle(fontSize: 36)),
          const SizedBox(height: 4),
          Text(
            noMoodLabel,
            style: AppFonts.onest(size: 12, color: t.textMuted),
          ),
        ],
      ],
    );
  }
}

class SmallStatBox extends StatelessWidget {
  const SmallStatBox({
    super.key,
    required this.t,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.bg,
  });

  final AppTheme t;
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: t.cardSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppFonts.onest(size: 18, weight: 800, color: t.textPrimary),
          ),
          Text(
            label,
            style: AppFonts.onest(size: 9, weight: 600, color: t.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
