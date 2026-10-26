import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/wish.dart';
import '../../dict_strings.dart' show ruEn;
import '../../theme/app_theme.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';
import '../../utils/safe_launch.dart';
import '../app_sheet.dart';
import 'wish_due_picker.dart';

/// Открыть чужое желание целиком.
///
/// В списке описание сжато в одну строку, а править чужое нельзя, поэтому
/// нажатие на желание партнёра раньше не делало ничего: длинное желание было
/// не прочитать (отзыв из Play 02.09.2026).
Future<void> showWishDetailsSheet(
  BuildContext context, {
  required AppTheme theme,
  required Wish wish,
  required String authorName,
  bool alsoMine = false,
  Future<void> Function()? onAlso,
}) {
  // Схему снимаем до открытия: лист живёт в навигаторе и переживает экран.
  final scheme = ProfileTheme.themeFor(theme).colorScheme;
  return showAppSheet<void>(
    context,
    background: scheme.surfaceContainer,
    builder: (_) => Theme(
      data: ProfileTheme.data(scheme),
      child: WishDetailsSheet(
        wish: wish,
        authorName: authorName,
        alsoMine: alsoMine,
        onAlso: onAlso,
      ),
    ),
  );
}

class WishDetailsSheet extends StatefulWidget {
  const WishDetailsSheet({
    super.key,
    required this.wish,
    required this.authorName,
    this.alsoMine = false,
    this.onAlso,
  });

  final Wish wish;
  final String authorName;

  /// «Я тоже хочу» уже стоит.
  final bool alsoMine;

  /// Переключить «я тоже хочу». Null — кнопки нет (своё или сбывшееся).
  final Future<void> Function()? onAlso;

  @override
  State<WishDetailsSheet> createState() => _WishDetailsSheetState();
}

class _WishDetailsSheetState extends State<WishDetailsSheet> {
  late bool _also = widget.alsoMine;

  Wish get wish => widget.wish;
  String get authorName => widget.authorName;

  @override
  Widget build(BuildContext context) {
    final due = wishDueLabel(wish.due);
    final cs = Theme.of(context).colorScheme;
    final hasShopLine = wish.hasPrice || wish.shop.isNotEmpty;

    return SheetScaffold(
      title: wish.title,
      bottom: wish.url.isEmpty
          ? null
          : FilledButton.icon(
              key: const Key('wish-open-link'),
              onPressed: () async {
                final uri = Uri.tryParse(wish.url);
                if (uri == null) return;
                await safeLaunchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new_rounded, size: 20),
              label: Text(ruEn('Открыть ссылку', 'Open link')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (authorName.isNotEmpty)
              Text(
                authorName,
                style: AppFonts.onest(
                  size: 13.5,
                  weight: 600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (hasShopLine) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (wish.hasPrice)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        wish.priceLabel,
                        style: AppFonts.onest(
                          size: 13.5,
                          weight: 700,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  if (wish.shop.isNotEmpty)
                    Text(
                      wish.shop,
                      style: AppFonts.onest(
                        size: 13.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
            if (due.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    due,
                    style: AppFonts.onest(
                      size: 14,
                      weight: 600,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ],
            if (widget.onAlso != null && !wish.done) ...[
              const SizedBox(height: 12),
              FilterChip(
                key: const Key('wish-details-also'),
                selected: _also,
                showCheckmark: false,
                avatar: Icon(
                  _also
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 18,
                ),
                label: Text(ruEn('Я тоже хочу', 'I want it too')),
                onSelected: (_) async {
                  setState(() => _also = !_also);
                  await widget.onAlso!();
                },
              ),
            ],
            if (wish.note.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                wish.note,
                style: AppFonts.onest(
                  size: 16,
                  height: 1.45,
                  color: cs.onSurface,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
