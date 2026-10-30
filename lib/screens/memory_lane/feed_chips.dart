import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/movie_search_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';

// Мелкие элементы ленты воспоминаний (A12-2): бывшие построители экрана,
// зависящие только от темы и своих параметров. Тела прежние.

/// Круглая кнопка шапки: тональный контейнер 48, как у блоков M3.
class RoundBarButton extends StatelessWidget {
  const RoundBarButton({
    super.key,
    required this.theme,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background,
    this.foreground,
  });

  final AppTheme theme;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final tooltip = this.tooltip;
    final t = theme;
    final btn = Material(
      color: background ?? t.cardSurface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, size: 22, color: foreground ?? t.textPrimary),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip, child: btn);
  }
}

/// Чип фильтра: один вид на все — иконка и подпись, выбранный залит
/// акцентом. Прежний круглый значок «Избранное» выбивался из ряда.
class FeedFilterTag extends StatelessWidget {
  const FeedFilterTag({
    super.key,
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final AppTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final t = theme;
    final bg = selected ? t.fillColor : t.cardSurface;
    final fg = selected
        ? AppThemes.onColor(t.fillColor, mode: t.brightness)
        : t.textPrimary;
    final iconColor = selected ? fg : t.textSecondary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: EdgeInsets.only(left: icon == null ? 14 : 11, right: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AppFonts.onest(size: 14, weight: 600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeedBadgeChip extends StatelessWidget {
  const FeedBadgeChip(this.label, this.icon, {super.key, required this.theme});

  final AppTheme theme;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final primary = theme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Чип в шапке карточки: сколько кадров внутри записи.
class FrameCountChip extends StatelessWidget {
  const FrameCountChip(this.count, {super.key, required this.theme});

  final AppTheme theme;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 8, right: 10),
      decoration: BoxDecoration(
        color: t.bgGradient[0],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.photo_library_rounded, size: 16, color: t.textSecondary),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: AppFonts.onest(
              size: 12.5,
              weight: 700,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class PinIconBox extends StatelessWidget {
  const PinIconBox({super.key, required this.theme});

  final AppTheme theme;

  @override
  Widget build(BuildContext context) {
    final primary = theme.primary;
    return Container(
      color: primary.withOpacity(0.10),
      alignment: Alignment.center,
      child: Icon(Icons.location_on_rounded, color: primary, size: 22),
    );
  }
}

class BookChip extends StatelessWidget {
  const BookChip(this.icon, this.label, this.accent, {super.key});

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: accent),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MovieKindChip extends StatelessWidget {
  const MovieKindChip(this.kind, this.isRu, {super.key, required this.theme});

  final AppTheme theme;
  final String? kind;
  final bool isRu;

  @override
  Widget build(BuildContext context) {
    final primary = theme.primary;
    final label = movieKindLabel(kind, isRu: isRu);
    final isSeries = kind != null && kind != 'movie' && kind != 'cartoon';
    final color = isSeries ? const Color(0xFF8B5CF6) : primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class KpChip extends StatelessWidget {
  const KpChip(this.rating, {super.key, required this.theme});

  final AppTheme theme;
  final String rating;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 11, color: cs.onTertiaryContainer),
          const SizedBox(width: 4),
          Text(
            LocaleService.current.kpRating(rating),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: cs.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
