import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/memory.dart';
import '../../models/wish.dart';
import '../../services/locale_service.dart';
import '../../theme/fonts.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/storage_image.dart';

/// Подпись воспоминания в списке выбора: название, подпись или вид записи.
String wishMemoryLabel(Memory m) {
  final t = (m.title ?? '').trim();
  if (t.isNotEmpty) return t;
  final c = (m.caption ?? '').trim();
  if (c.isNotEmpty) return c;
  return ruEn('Воспоминание', 'Memory');
}

/// Картинка воспоминания для стены и списка: фото, обложка или постер.
String wishMemoryImage(Memory m) {
  for (final v in [
    m.imageUrl,
    ...?m.imageUrls,
    m.moviePosterUrl,
    m.bookCoverUrl,
    m.musicCoverUrl,
  ]) {
    if (v != null && v.isNotEmpty) return v;
  }
  return '';
}

/// Воспоминания-кандидаты: сначала те, что рядом с датой исполнения
/// (±7 дней), потом остальные — свежие сверху. Капсулы до открытия не
/// предлагаем: их содержимого ещё не видно.
List<Memory> wishMemoryCandidates(Wish wish, Iterable<Memory> all) {
  final at = wish.doneAt ?? DateTime.now();
  final list = [
    for (final m in all)
      if (!m.sealedNow()) m,
  ];
  int near(Memory m) => m.createdAt.difference(at).inDays.abs() <= 7 ? 0 : 1;
  list.sort((a, b) {
    final c = near(a).compareTo(near(b));
    return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
  });
  return list;
}

/// Выбрать воспоминание для сбывшегося желания. Null — передумали.
Future<String?> pickWishMemory(
  BuildContext context, {
  required Wish wish,
  required List<Memory> memories,
}) {
  final list = wishMemoryCandidates(wish, memories);
  return showModalSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final s = LocaleService.current;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * .75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  ruEn('Какое воспоминание?', 'Which memory?'),
                  style: AppFonts.unbounded(size: 17, weight: 600),
                ),
              ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text(
                    ruEn(
                      'Воспоминаний пока нет. Добавьте его в ленте — и '
                          'вернитесь привязать.',
                      'No memories yet. Add one in the feed and come back.',
                    ),
                    style: AppFonts.onest(
                      size: 14,
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final m = list[i];
                      final img = wishMemoryImage(m);
                      return ListTile(
                        key: Key('wish-memory-${m.id}'),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: img.isEmpty
                              ? Container(
                                  width: 44,
                                  height: 44,
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.photo_outlined,
                                    color: cs.onSurfaceVariant,
                                  ),
                                )
                              : StorageImage(
                                  imageUrl: img,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        title: Text(
                          wishMemoryLabel(m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(s.dayLogDate(m.createdAt)),
                        onTap: () => Navigator.of(ctx).pop(m.id),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
