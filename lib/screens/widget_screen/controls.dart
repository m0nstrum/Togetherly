import 'dart:io';
import 'package:flutter/material.dart';
import 'catalog.dart';
import '../../theme/fonts.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../models/ios_widget_gaps.dart';

// Элементы карточек экрана виджетов: зависят только от темы и строк.

class CatalogGlassCard extends StatelessWidget {
  const CatalogGlassCard({super.key, required this.cs, required this.child});

  final ColorScheme cs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // M3 Expressive как на Подключении: тональный контейнер, крупный радиус,
    // плоско (без рамки и тени) — глубина передаётся тоном.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: child,
    );
  }
}

class EditBadge extends StatelessWidget {
  const EditBadge({super.key, required this.t});

  final AppTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.primaryLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_rounded, size: 12, color: t.primary),
          const SizedBox(width: 4),
          Text(
            LocaleService.current.editBtn,
            style: AppFonts.onest(size: 11, weight: 700, color: t.primary),
          ),
        ],
      ),
    );
  }
}

class SettingDivider extends StatelessWidget {
  const SettingDivider({super.key, required this.t});

  final AppTheme t;

  @override
  Widget build(BuildContext context) {
    return Divider(color: t.divider, height: 8, thickness: 1);
  }
}

class SettingToggle extends StatelessWidget {
  const SettingToggle({
    super.key,
    required this.t,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final AppTheme t;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppFonts.onest(
                    size: 13,
                    weight: 600,
                    color: t.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppFonts.onest(size: 11, color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 28,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeColor: t.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

/// Слот содержимого виджета: настроение, статус, сообщение, фото, музыка.
///
/// Заполненный — сплошная карточка со значением, пустой — та же карточка
/// пунктиром: сразу видно, что место свободно. Раньше все слоты были
/// одинаковыми строками с разделителями, и «пусто» отличалось только
/// кнопкой «+ Добавить» разной ширины.
class SlotRow extends StatelessWidget {
  const SlotRow({
    super.key,
    required this.cs,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.value,
    this.valueColor,
    this.trailing,
    this.subtitle,
    required this.onTap,
    this.onClear,
  });

  final ColorScheme cs;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final String? subtitle;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final valueColor = this.valueColor;
    final trailing = this.trailing;
    final subtitle = this.subtitle;
    final onClear = this.onClear;
    final hasValue = value != null;
    final radius = BorderRadius.circular(22);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: hasValue ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        // Форму задаёт только shape: Material не принимает его вместе с
        // borderRadius и валит сборку экрана ассертом.
        shape: hasValue
            ? RoundedRectangleBorder(borderRadius: radius)
            : RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: cs.outlineVariant),
              ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasValue
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: hasValue
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppFonts.onest(
                          size: hasValue ? 11.5 : 14.5,
                          weight: hasValue ? 500 : 600,
                          color: hasValue ? cs.onSurfaceVariant : cs.onSurface,
                        ),
                      ),
                      if (hasValue) ...[
                        const SizedBox(height: 1),
                        Text(
                          value,
                          style: AppFonts.onest(
                            size: 14.5,
                            weight: 600,
                            color: valueColor ?? cs.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: AppFonts.onest(
                            size: 11,
                            weight: 500,
                            height: 1.25,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
                if (onClear != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: ruEn('Очистить', 'Clear'),
                    onPressed: onClear,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                if (!hasValue) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 16,
                          color: cs.onSecondaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          LocaleService.current.addBtn,
                          style: AppFonts.onest(
                            size: 12.5,
                            weight: 600,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Слот половины партнёра — та же карточка, что и своя, но правку заменяет
/// просмотр: чужое содержимое мы не меняем, а вот раскрыть его целиком нужно.
///
/// [onOpen] задан там, где содержимое в строку не помещается: письмо, статус,
/// снимок, песня. Пока его не было, строка молчала на нажатие, и длинное
/// сообщение обрывалось многоточием навсегда.
class ReadonlySlot extends StatelessWidget {
  const ReadonlySlot({
    super.key,
    required this.cs,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.value,
    this.valueColor,
    this.trailing,
    this.onOpen,
  });

  final ColorScheme cs;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final valueColor = this.valueColor;
    final trailing = this.trailing;
    final onOpen = this.onOpen;
    final hasValue = value != null;
    final canOpen = hasValue && onOpen != null;
    final radius = BorderRadius.circular(22);

    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: hasValue
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: hasValue ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppFonts.onest(
                    size: hasValue ? 11.5 : 14.5,
                    weight: hasValue ? 500 : 600,
                    color: hasValue ? cs.onSurfaceVariant : cs.onSurface,
                  ),
                ),
                if (hasValue) ...[
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: AppFonts.onest(
                      size: 14.5,
                      weight: 600,
                      color: valueColor ?? cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          // Шеврон — единственный признак, что строку можно раскрыть.
          if (canOpen) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: cs.onSurfaceVariant,
            ),
          ],
          if (!hasValue)
            Text(
              '—',
              style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: hasValue ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        // Форму задаёт только shape: Material не принимает его вместе с
        // borderRadius и валит сборку экрана ассертом.
        shape: hasValue
            ? RoundedRectangleBorder(borderRadius: radius)
            : RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: cs.outlineVariant),
              ),
        child: canOpen ? InkWell(onTap: onOpen, child: row) : row,
      ),
    );
  }
}

class RotationRadio extends StatelessWidget {
  const RotationRadio({
    super.key,
    required this.t,
    required this.title,
    required this.value,
    required this.groupValue,
    required this.onChanged,
  });

  final AppTheme t;
  final String title;
  final String value;
  final String groupValue;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? t.primary.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: isSelected ? t.primary : t.divider,
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? t.primary : t.textMuted,
              size: 18,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style:
                    AppFonts.onest(
                      size: 12,
                      color: isSelected ? t.primary : t.textSecondary,
                    ).copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Сегменты выбора размера: «2×2 · 4×2 · 4×4». Каждый размер — отдельный
/// провайдер, поэтому выбор меняет и превью, и то, что уйдёт на рабочий стол.
class SizePicker extends StatelessWidget {
  const SizePicker({
    super.key,
    required this.cs,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  final ColorScheme cs;
  final List<WidgetSizeOption> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  // Высота минимальная, а не жёсткая: при системном шрифте
                  // 1.3 метка «4×2» с подписью не влезала в 36 точек, и
                  // каждая пилюля рисовала полосу «BOTTOM OVERFLOWED BY 3.0
                  // PIXELS» — а таких рядов в каталоге полтора десятка.
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        options[i].label,
                        style: TextStyle(
                          fontFamily: 'Onest',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          fontVariations: const [FontVariation('wght', 700)],
                          color: i == selected
                              ? cs.onPrimary
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      if (options[i].hint != null)
                        Text(
                          options[i].hint!,
                          style: TextStyle(
                            fontFamily: 'Onest',
                            fontSize: 9.5,
                            height: 1.1,
                            color:
                                (i == selected
                                        ? cs.onPrimary
                                        : cs.onSurfaceVariant)
                                    .withValues(alpha: 0.75),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class NotPairedBanner extends StatelessWidget {
  const NotPairedBanner({super.key, required this.t});

  final AppTheme t;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.cardSurface.withOpacity(0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.primary.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: t.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.timer_rounded,
              size: 30,
              color: t.primary.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            LocaleService.current.soloTimerBannerTitle,
            textAlign: TextAlign.center,
            style: AppFonts.onest(size: 16, weight: 700, color: t.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            LocaleService.current.soloTimerBannerSubtitle,
            textAlign: TextAlign.center,
            style: AppFonts.onest(size: 13, height: 1.5, color: t.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Полоса для iPhone на iOS 15 и 16: у них расширения виджетов нет вовсе.
///
/// Оно собрано с минимальной версией 17 — ветку `if #available` внутри
/// `WidgetBundle` держать нельзя, она роняет расширение целиком и уносит из
/// галереи ВСЕ виджеты (разбор 17.08.2026). На старых системах человек
/// открывает каталог, ставит виджет по инструкции и не находит Togetherly в
/// системном списке: «с обновлением виджет пропал» (iPhone 7 Plus,
/// 19.08.2026). Пусть каталог скажет это сам, а не оставляет искать поломку
/// в своём телефоне.
class IosWidgetsUnavailable extends StatelessWidget {
  const IosWidgetsUnavailable({super.key, required this.cs});

  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS ||
        iosWidgetsSupported(Platform.operatingSystemVersion)) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: cs.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              LocaleService.current.iosWidgetsNeedIos17,
              style: AppFonts.onest(
                size: 13,
                height: 1.35,
                color: cs.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
