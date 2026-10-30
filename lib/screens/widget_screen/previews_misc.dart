import '../../widgets/storage_image.dart';
import 'package:flutter/material.dart';
import '../../theme/fonts.dart';
import '../../models/note_preview.dart';
import '../../utils/couple_days.dart';
import '../../models/pair_data.dart';
import '../../models/together_caption.dart';
import '../../models/timer_item.dart';
import '../../models/year_progress.dart';
import '../../models/user_data.dart';
import '../../services/locale_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/canvas_meta.dart';
import '../../models/mascot.dart';
import '../../models/mascot_anim.dart';
import '../../models/mascot_widget_data.dart';
import '../../services/catalog_service.dart';
import '../../services/offline/media_view_cache.dart';
import '../../services/mascot/mascot_art_source.dart';
import '../../services/mascot/mascot_widget_service.dart';
import '../../services/mascot_service.dart';
import '../../widgets/draw/canvas_preview.dart';
import '../../widgets/mascot/pixel_mascot_view.dart';
import '../../widgets/active_mascot_widget.dart' show buildMascotAssetImage;
import '../../services/timer_service.dart';
import '../../services/widget_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/profile_theme.dart';
import 'catalog.dart';
import 'preview_style.dart';
import 'previews_time.dart';

// Превью маскота, счётчика дней, фото-сетки, холста и заметки в каталоге
// виджетов. Данные экрана приходят параметрами.

/// Картинка непиксельного маскота: встроенного, каталожного или
/// нарисованного человеком. Порядок тот же, что на главной.
class MascotPicture extends StatelessWidget {
  const MascotPicture({super.key, required this.mascot});

  final Mascot mascot;

  @override
  Widget build(BuildContext context) {
    final asset = mascot.defaultAsset;
    if (asset != null && asset.isNotEmpty) {
      return buildMascotAssetImage(asset, fit: BoxFit.contain);
    }
    final catalogUrl = mascot.catalogUrl;
    if (catalogUrl != null && catalogUrl.isNotEmpty) {
      return CachedNetworkImage(
        cacheManager: OfflineImageCacheManager.instance,
        imageUrl: catalogUrl,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    final drawn = mascot.imageUrl;
    if (drawn != null && drawn.isNotEmpty) {
      return StorageImage(
        imageUrl: drawn,
        fit: BoxFit.contain,
        placeholder: (_, __) => const SizedBox.shrink(),
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Превью виджета маскота: НАСТОЯЩИЙ персонаж пары, а не образец.
///
/// Так же устроена заметка — в каталоге она показывает свой текст. Человек
/// выбирает размер по тому, что реально встанет на стол.
class CatalogMascotPreview extends StatelessWidget {
  const CatalogMascotPreview({
    super.key,
    required this.ps,
    required this.mascotService,
    required this.userData,
    required this.size,
  });

  final PreviewStyle ps;
  final MascotService mascotService;
  final UserData userData;
  final MascotPreviewSize size;

  @override
  Widget build(BuildContext context) {
    final aspect = switch (size) {
      MascotPreviewSize.strip => 424 / 92,
      MascotPreviewSize.small => 1.0,
      MascotPreviewSize.wide => 424 / 200,
      MascotPreviewSize.large => 1.0,
    };

    final mascotState = mascotService.state;
    final id = mascotState.activeMascotId ?? '';
    final mascot = mascotService.activeMascot;
    // Атлас есть только у пиксельных из каталога; у встроенных, каталожных
    // рисунков и нарисованных вручную его нет, и превью берёт их картинку.
    final anim = id.isEmpty ? null : CatalogService.instance.animById(id);

    if (mascot == null || (!mascot.hasImage && anim == null)) {
      return AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(
            color: ps.wr('surfaceContainer'),
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            LocaleService.current.mascotWidgetNoMascot,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Onest',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: ps.wr('onSurfaceVariant'),
            ),
          ),
        ),
      );
    }

    final streak = mascotService.activeStreak;
    final record = mascot.recordStreak;
    final sleep = userData.sleepOf(id);
    final data = MascotWidgetData(
      mascotId: id,
      name: mascot.localizedName,
      streakDays: streak,
      recordStreak: record > streak ? record : streak,
      sad: streak == 0 && (mascotState.streakLastOpenedDate ?? '').isNotEmpty,
      sleep: mascotSleepsInWidget(anim)
          ? MascotSleepWindow(from: sleep.from, to: sleep.to)
          : MascotSleepWindow.none,
    );
    final labels = buildMascotWidgetLabels(data);

    Widget figure(double side) => SizedBox(
      width: side,
      height: side,
      child: anim != null
          ? PixelMascotView(
              anim: anim,
              state: MascotAnimState.live,
              size: side,
              level: data.level,
              sleep: sleep,
            )
          : MascotPicture(mascot: mascot),
    );

    Widget chip(
      String text, {
      required Color bg,
      required Color ink,
      double fontSize = 10,
    }) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Onest',
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          color: ink,
        ),
      ),
    );

    Widget label(
      String text, {
      double fontSize = 10,
      FontWeight weight = FontWeight.w600,
      Color? color,
    }) => Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Onest',
        fontWeight: weight,
        fontSize: fontSize,
        color: color ?? ps.wr('onSurfaceVariant'),
      ),
    );

    Widget bar(double width) => Container(
      height: 6,
      decoration: BoxDecoration(
        color: ps.wr('trackOnContainer'),
        borderRadius: BorderRadius.circular(99),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: data.percent / 100,
        child: Container(
          decoration: BoxDecoration(
            color: ps.wr('primary'),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );

    final body = switch (size) {
      MascotPreviewSize.strip => Row(
        children: [
          figure(40),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(
                  data.name,
                  fontSize: 13,
                  weight: FontWeight.w800,
                  color: ps.wr('onSurface'),
                ),
                label('${labels.stage} · ${labels.next}'),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              label(
                '${data.streakDays}',
                fontSize: 20,
                weight: FontWeight.w800,
                color: ps.wr('onPrimaryContainer'),
              ),
              label(labels.streak, fontSize: 9),
            ],
          ),
        ],
      ),
      MascotPreviewSize.small => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: label(
                  data.name,
                  fontSize: 12,
                  weight: FontWeight.w800,
                  color: ps.wr('onSurface'),
                ),
              ),
              chip(
                labels.stage,
                bg: ps.wr('tertiaryContainer'),
                ink: ps.wr('onTertiaryContainer'),
              ),
            ],
          ),
          Expanded(child: Center(child: figure(64))),
          bar(double.infinity),
          const SizedBox(height: 4),
          label(labels.next, fontSize: 9),
        ],
      ),
      MascotPreviewSize.wide => Row(
        children: [
          Container(
            width: 96,
            decoration: BoxDecoration(
              color: ps.wr('primaryContainer'),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: figure(74),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(
                  data.name,
                  fontSize: 17,
                  weight: FontWeight.w800,
                  color: ps.wr('onSurface'),
                ),
                const SizedBox(height: 2),
                label(
                  '${labels.stage} · ${data.streakDays} ${labels.streak}',
                  fontSize: 11,
                ),
                const SizedBox(height: 10),
                bar(double.infinity),
                const SizedBox(height: 6),
                label(labels.next, fontSize: 10),
              ],
            ),
          ),
        ],
      ),
      MascotPreviewSize.large => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 59,
            child: Container(
              decoration: BoxDecoration(
                color: ps.wr('primaryContainer'),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ps.wr('trackOnContainer'),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.72,
                      alignment: Alignment.topCenter,
                      child: Center(child: figure(92)),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: chip(
                      '${data.name} · ${labels.stage}',
                      bg: ps.wr('surface'),
                      ink: ps.wr('onSurface'),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    top: 10,
                    child: chip(
                      labels.sleepDay,
                      bg: ps.wr('tertiaryContainer'),
                      ink: ps.wr('onTertiaryContainer'),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 26,
            child: Row(
              children: [
                Expanded(
                  child: MascotTile(
                    ps: ps,
                    value: '${data.streakDays}',
                    caption: labels.streak,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MascotTile(
                    ps: ps,
                    child: bar(double.infinity),
                    caption: labels.next,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MascotTile(
                    ps: ps,
                    value: '${data.recordStreak}',
                    caption: labels.record.split(' ').first,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    };

    return AspectRatio(
      aspectRatio: aspect,
      child: Container(
        padding: EdgeInsets.all(size == MascotPreviewSize.large ? 8 : 10),
        decoration: BoxDecoration(
          // Тот же фон, что у виджета на столе: карточка каталога сама
          // розоватая, и на surfaceContainer превью сливалось с ней.
          color: size == MascotPreviewSize.strip
              ? ps.wr('primaryContainer')
              : ps.wr('surface'),
          borderRadius: BorderRadius.circular(22),
        ),
        child: body,
      ),
    );
  }
}

/// Кружок-аватарка для превью счётчика дней.
class DaysPreviewAvatar extends StatelessWidget {
  const DaysPreviewAvatar({super.key, required this.t, required this.url});

  final AppTheme t;
  final String url;

  @override
  Widget build(BuildContext context) {
    // Кайма — это отступ, а не `Border`. У круглого `Container` рамка рисуется
    // ВНУТРЬ, а картинка внутри просилась во все 56 px: она не влезала в
    // оставшиеся 52 и обрезалась по краям — на превью аватар выглядел
    // подрезанным сбоку. Теперь картинка занимает ровно внутреннюю область.
    return Container(
      width: 56,
      height: 56,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, color: t.cardSurface),
      child: ClipOval(
        child: ColoredBox(
          color: t.primary.withValues(alpha: 0.1),
          child: StorageImage(
            imageUrl: url,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Icon(
              Icons.person_rounded,
              color: t.primary.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class DaysCounterPreview extends StatelessWidget {
  const DaysCounterPreview({
    super.key,
    required this.t,
    required this.daysPhotosEnabled,
    required this.pair,
    required this.timerService,
    required this.widgetTimer,
    required this.ws,
    required this.userData,
  });

  final AppTheme t;
  final bool daysPhotosEnabled;
  final PairData pair;
  final TimerService timerService;
  final TimerItem? widgetTimer;
  final WidgetService ws;
  final UserData userData;

  @override
  Widget build(BuildContext context) {
    final widgetTimer = this.widgetTimer;

    final s = LocaleService.current;
    // Берём тот же активный таймер, что и виджет на рабочем столе
    final timer = widgetTimer ?? timerService.systemTimer;
    final start = timer?.startDate ?? pair.startDate;
    final totalDays = timer != null
        ? timer.daysElapsed.abs()
        : (start != null ? calendarDaysBetween(start, DateTime.now()) : 0);
    final startLabel = start != null
        ? '${start.day.toString().padLeft(2, '0')}.${start.month.toString().padLeft(2, '0')}.${start.year}'
        : '';

    final myGender = userData.gender?.name ?? '';
    final partnerGender = ws.firstPartnerData?.gender.isNotEmpty == true
        ? ws.firstPartnerData!.gender
        : '';

    String imgName = 'widget_couple_mf';
    bool flipCouple = false;
    if (myGender == 'female' && partnerGender == 'female') {
      imgName = 'widget_couple_ff';
    } else if (myGender == 'male' && partnerGender == 'male') {
      imgName = 'widget_couple_mm';
    } else if (myGender == 'female' && partnerGender == 'male') {
      // User (female) on left → mirror the mf image horizontally
      flipCouple = true;
    }

    // Подпись считается тем же правилом, что и на самом виджете: годы
    // календарные, а до первой годовщины счёт идёт на месяцы.
    final yearsText = start != null
        ? togetherAlreadyCaption(YearProgress.between(start, DateTime.now()), s)
        : '';

    final myAvatar = userData.avatarUrl;
    final partnerAvatar = pair.partnerAvatarUrl;
    final showPhotos =
        daysPhotosEnabled && myAvatar.isNotEmpty && partnerAvatar.isNotEmpty;

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: t.cardSurface,
        border: Border.all(color: t.primary.withOpacity(0.15), width: 3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          if (showPhotos)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DaysPreviewAvatar(t: t, url: myAvatar),
                    Transform.translate(
                      offset: const Offset(-10, 0),
                      child: DaysPreviewAvatar(t: t, url: partnerAvatar),
                    ),
                  ],
                ),
              ),
            )
          else
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(21),
                ),
                child: Transform.scale(
                  scaleX: flipCouple ? -1.0 : 1.0,
                  child: Image.asset(
                    'assets/images/widget/$imgName.webp',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                yearsText,
                style: AppFonts.onest(
                  size: 12,
                  weight: 700,
                  color: t.primary.withOpacity(0.7),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$totalDays',
                  style: AppFonts.onest(
                    size: 36,
                    weight: 700,
                    height: 1.0,
                    color: t.primary,
                  ),
                ),
                Text(
                  LocaleService.current.daysCounterLabel,
                  style: AppFonts.onest(
                    size: 14,
                    weight: 700,
                    color: t.primary.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  startLabel,
                  style: AppFonts.onest(
                    size: 10,
                    weight: 700,
                    color: t.primary.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PhotoGridPlaceholder extends StatelessWidget {
  const PhotoGridPlaceholder({super.key, required this.t, required this.emoji});

  final AppTheme t;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: t.primary.withOpacity(0.07),
      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
    );
  }
}

class PhotoGridMockup extends StatelessWidget {
  const PhotoGridMockup({
    super.key,
    required this.t,
    required this.photoGridCount,
    required this.ws,
  });

  final AppTheme t;
  final int photoGridCount;
  final WidgetService ws;

  @override
  Widget build(BuildContext context) {
    // Превью показывает фото ПАРТНЁРА (то, что отображается на рабочем столе)
    final partnerUrls = ws.firstPartnerData?.photoGridUrls ?? [];
    final partnerCount = ws.firstPartnerData?.photoGridCount ?? 1;
    final slots = partnerUrls.isNotEmpty ? partnerCount : photoGridCount;

    Widget cell(int index) {
      if (index < partnerUrls.length && partnerUrls[index].isNotEmpty) {
        return StorageImage(
          imageUrl: partnerUrls[index],
          fit: BoxFit.cover,
          placeholder: (_, __) => PhotoGridPlaceholder(t: t, emoji: '⏳'),
          errorWidget: (_, __, ___) => PhotoGridPlaceholder(t: t, emoji: '📷'),
        );
      }
      return PhotoGridPlaceholder(t: t, emoji: '📷');
    }

    if (slots == 1) return cell(0);
    if (slots == 2) {
      return Row(
        children: [
          Expanded(child: cell(0)),
          const SizedBox(width: 2),
          Expanded(child: cell(1)),
        ],
      );
    }
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: cell(0)),
              const SizedBox(width: 2),
              Expanded(child: cell(1)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: cell(2)),
              const SizedBox(width: 2),
              Expanded(child: cell(3)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Превью: настоящий холст пары, тот же, что встанет на стол.
class CatalogCanvasPreview extends StatelessWidget {
  const CatalogCanvasPreview({
    super.key,
    required this.ps,
    required this.canvases,
    required this.pair,
    required this.userData,
    required this.aspect,
  });

  final PreviewStyle ps;
  final List<CanvasMeta> canvases;
  final PairData pair;
  final UserData userData;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    final meta = canvases.isEmpty ? null : canvases.first;
    if (meta == null) {
      return AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(
            color: ps.wr('surfaceContainer'),
            borderRadius: BorderRadius.circular(22),
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            LocaleService.current.canvasWidgetEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Onest',
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: ps.wr('onSurfaceVariant'),
            ),
          ),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: aspect,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CanvasPreview(
          meta: meta,
          uid: userData.uid,
          groupId: pair.pairId,
          background: Colors.white,
          placeholder: Container(color: ps.wr('surfaceContainer')),
        ),
      ),
    );
  }
}

/// Превью «Вместе» 2×2: фон primary #6750A4, стек аватаров и число 54/800.
/// Превью листика в каталоге. [paper] — бумажный стикер, иначе карточка M3.
class CatalogNotePreview extends StatelessWidget {
  const CatalogNotePreview({
    super.key,
    required this.noteText,
    required this.noteAuthor,
    required this.noteAt,
    required this.theme,
    required this.userData,
    this.compact = false,
    this.big = false,
    this.paper = false,
  });

  final String noteText;
  final String noteAuthor;
  final String noteAt;
  final AppTheme theme;
  final UserData userData;
  final bool compact;
  final bool big;
  final bool paper;

  @override
  Widget build(BuildContext context) {
    final cs = ProfileTheme.schemeFor(theme);
    const paperBg = Color(0xFFFFF3C4);
    const paperInk = Color(0xFF4A3D13);
    final bg = paper ? paperBg : cs.surfaceContainer;
    final ink = paper ? paperInk : cs.onSurface;
    final faded = paper ? const Color(0xFF8A7A45) : cs.onSurfaceVariant;

    // Настоящая заметка пары; пока её нет — образец, потому что пустой
    // листик в каталоге читается как сломанный виджет.
    final text = notePreviewText(
      noteText,
      demo: LocaleService.current.tgNoteDemo,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!paper) ...[
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.sticky_note_2_rounded,
                    size: 14,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  LocaleService.current.tgNoteTitle.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: faded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else ...[
            Center(
              child: Container(
                width: 46,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.14),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            text,
            maxLines: big ? 5 : 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 13 : 14,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: paper
                      ? Colors.black.withValues(alpha: 0.18)
                      : cs.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    noteAuthor.isEmpty ? userData.displayName : noteAuthor,
                    if (noteAt.isNotEmpty) noteAt,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: faded,
                  ),
                ),
              ),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: paper ? paperInk : cs.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.edit_rounded,
                  size: 14,
                  color: paper ? paperBg : cs.onPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
