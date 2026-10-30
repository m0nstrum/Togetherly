import 'package:flutter/material.dart';
import '../../models/widget_panels.dart';

/// Сетка месяцев для превью каталога: точка — месяц, ряд — год.
/// Повторяет `WidgetImages.monthsGrid` на нативной стороне.
class MonthsGridPainter extends CustomPainter {
  const MonthsGridPainter({
    required this.filled,
    required this.rows,
    required this.dot,
    required this.gap,
    required this.past,
    required this.current,
    required this.future,
  });

  final int filled;
  final int rows;
  final double dot;
  final double gap;
  final Color past;
  final Color current;
  final Color future;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final r = dot / 2;
    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < 12; col++) {
        final i = row * 12 + col;
        paint.color = i < filled
            ? past
            : i == filled
            ? current
            : future;
        canvas.drawCircle(
          Offset(col * (dot + gap) + r, row * (dot + gap) + r),
          r,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MonthsGridPainter old) =>
      old.filled != filled ||
      old.rows != rows ||
      old.dot != dot ||
      old.past != past ||
      old.current != current ||
      old.future != future;
}

/// Один размер виджета в карточке каталога.
///
/// В Android каждый размер — свой `AppWidgetProvider`, общего «виджета с
/// выбором размера» не бывает. Поэтому размер выбирается до установки:
/// выбранный вариант определяет и превью, и того провайдера, что уйдёт на
/// рабочий стол.
class WidgetSizeOption {
  const WidgetSizeOption({
    required this.label,
    required this.qualifiedName,
    required this.previewBuilder,
    this.hint,
  });

  /// Метка сегмента, например «4×2».
  final String label;

  /// Подпись под меткой: чем этот размер отличается.
  final String? hint;

  final String qualifiedName;

  /// Построитель превью. Именно функция: карточка собирала превью всех трёх
  /// размеров разом, а показывала одно — на раскрытии раздела это стоило
  /// заметной паузы.
  final Widget Function() previewBuilder;
}

/// Карточка каталога: в каком разделе стоит и как строится.
///
/// Строится лениво — свёрнутый раздел не должен собирать превью.
class CatalogCard {
  const CatalogCard(this.section, this.build, {this.count = 1});

  /// Ключ раздела из [WidgetPanels].
  final String section;
  final Widget Function() build;

  /// Сколько виджетов стоит за карточкой: у сетки мелких плиток их два, и
  /// бейдж раздела обязан считать виджеты, а не карточки.
  final int count;
}

/// Сворачивающийся раздел каталога виджетов.
///
/// Заголовок с иконкой и счётчиком, содержимое раскрывается анимацией. Нужен,
/// чтобы прежние виджеты не заслоняли новый каталог: их список длинный, а
/// смотреть в первую очередь надо новые.
class CollapsibleWidgetSection extends StatelessWidget {
  const CollapsibleWidgetSection({
    super.key,
    required this.cs,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.expanded,
    required this.onToggle,
    required this.itemsBuilder,
    required this.count,
  });

  final ColorScheme cs;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;

  /// Содержимое строится лениво — только когда раздел раскрыт.
  ///
  /// Раньше сюда приходил готовый список, и все карточки со всеми превью
  /// строились на каждый build, даже у свёрнутого раздела. Раскрытие после
  /// этого перестраивало полтора десятка превью разом, и приложение заметно
  /// подвисало.
  final List<Widget> Function() itemsBuilder;

  /// Число в бейдже. Считается без построения виджетов: карточки, без
  /// разделительных отступов и рекламы.
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, size: 20, color: cs.onSecondaryContainer),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Unbounded',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation('wght', 700)],
                            letterSpacing: -0.3,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          alignment: Alignment.topCenter,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: itemsBuilder(),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// Размеры превью маскота в каталоге: те же четыре, что и на столе.
enum MascotPreviewSize { strip, small, wide, large }
