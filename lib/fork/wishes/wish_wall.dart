import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/memory.dart';
import '../../models/symbol_catalog.dart';
import '../../models/wish.dart';
import '../../services/locale_service.dart';
import '../../theme/fonts.dart';
import '../../widgets/storage_image.dart';
import '../l10n/count_words.dart';
import 'wish_memory.dart';

/// Счётчики стены «Сбылось».
@immutable
class WishWallStats {
  const WishWallStats({
    required this.total,
    required this.thisYear,
    required this.together,
    required this.withMemory,
  });

  final int total;
  final int thisYear;

  /// Из тех, что хотели оба.
  final int together;

  /// С привязанным воспоминанием.
  final int withMemory;

  factory WishWallStats.of(Iterable<Wish> fulfilled, DateTime now) {
    var total = 0, year = 0, both = 0, mem = 0;
    for (final w in fulfilled) {
      if (!w.done) continue;
      total++;
      if (w.doneAt?.year == now.year) year++;
      if (w.wantedByBoth) both++;
      if (w.memoryId.isNotEmpty) mem++;
    }
    return WishWallStats(
      total: total,
      thisYear: year,
      together: both,
      withMemory: mem,
    );
  }
}

/// Стена «Сбылось» (docs/WISHLIST.md): сбывшееся пары плиткой — с датами,
/// фото вещи или привязанного воспоминания и счётчиками сверху.
class WishWallScreen extends StatelessWidget {
  const WishWallScreen({
    super.key,
    required this.fulfilled,
    this.memories = const {},
    this.onOpen,
  });

  /// Сбывшиеся, уже по порядку (Wish.fulfilled).
  final List<Wish> fulfilled;

  /// Воспоминания пары по id — для картинок привязанных.
  final Map<String, Memory> memories;

  /// Тап по плитке.
  final void Function(Wish wish)? onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stats = WishWallStats.of(fulfilled, DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ruEn('Сбылось', 'Came true'),
          style: AppFonts.unbounded(size: 17, weight: 600),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _stat(cs, stats.total, ruEn('всего', 'in total')),
                  _stat(cs, stats.thisYear, ruEn('в этом году', 'this year')),
                  _stat(cs, stats.together, ruEn('хотели оба', 'both wanted')),
                  _stat(
                    cs,
                    stats.withMemory,
                    ruEn('с воспоминанием', 'with a memory'),
                  ),
                ],
              ),
            ),
          ),
          if (fulfilled.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    ruEn(
                      'Здесь будет всё, что у вас сбылось.',
                      'Everything that comes true will be here.',
                    ),
                    textAlign: TextAlign.center,
                    style: AppFonts.onest(size: 15, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: .78,
                ),
                itemCount: fulfilled.length,
                itemBuilder: (_, i) => _tile(context, cs, fulfilled[i]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(ColorScheme cs, int n, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$n',
          style: AppFonts.unbounded(
            size: 20,
            weight: 700,
            color: cs.onSecondaryContainer,
          ),
        ),
        Text(
          label,
          style: AppFonts.onest(size: 12, color: cs.onSecondaryContainer),
        ),
      ],
    ),
  );

  Widget _tile(BuildContext context, ColorScheme cs, Wish w) {
    final memory = memories[w.memoryId];
    final image = w.image.isNotEmpty
        ? w.image
        : memory == null
        ? ''
        : wishMemoryImage(memory);
    final s = LocaleService.current;
    final date = w.doneAt == null
        ? ''
        : w.doneAt!.year == DateTime.now().year
        ? s.dayLogDate(w.doneAt!)
        : '${s.dayLogDate(w.doneAt!)} ${w.doneAt!.year}';
    return Material(
      key: Key('wish-wall-${w.id}'),
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen == null ? null : () => onOpen!(w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: image.isEmpty
                  ? Container(
                      color: cs.primaryContainer,
                      alignment: Alignment.center,
                      child: SymbolIcon(
                        w.iconName,
                        size: 40,
                        color: cs.onPrimaryContainer,
                      ),
                    )
                  : StorageImage(imageUrl: image, fit: BoxFit.cover),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    w.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppFonts.onest(
                      size: 14,
                      weight: 700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          date,
                          style: AppFonts.onest(
                            size: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (w.memoryId.isNotEmpty)
                        Icon(
                          Icons.photo_library_outlined,
                          size: 14,
                          color: cs.onSurfaceVariant,
                        ),
                      if (w.wantedByBoth)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.favorite_rounded,
                            size: 14,
                            color: cs.primary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «12 желаний сбылось» — подпись для кнопки стены.
String wishWallButtonLabel(int n) => ruEn(
  'Стена · $n ${forkRuCountWord(n, 'желание', 'желания', 'желаний')}',
  'Wall · $n ${n == 1 ? 'wish' : 'wishes'}',
);
