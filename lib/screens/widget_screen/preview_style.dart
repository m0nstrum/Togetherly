import 'package:flutter/material.dart';

import '../../models/year_progress.dart';
import '../../services/locale_service.dart';
import '../../services/widget_theme_sync.dart';
import 'catalog.dart';

/// Общее для превью в каталоге виджетов: цвета по ролям темы, даты, подписи.
/// Зависит только от цветовой схемы и языка.
class PreviewStyle {
  const PreviewStyle(this.cs);

  final ColorScheme cs;

  /// Цвет виджета по роли активной темы.
  ///
  /// Тот же справочник ролей, что уходит в нативные виджеты
  /// (`WidgetThemeSync.rolesOf`), поэтому превью в каталоге и карточка на
  /// рабочем столе не расходятся ни в одной из двадцати тем.
  Color wr(String role) => WidgetThemeSync.rolesOf(cs)[role] ?? cs.primary;

  static const List<String> _monthsGenitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  static const List<String> _monthsGenitiveEn = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String formatDayMonth(DateTime d) =>
      switch (LocaleService.instance.language) {
        AppLanguage.ru => '${d.day} ${_monthsGenitive[d.month - 1]}',
        AppLanguage.zh => '${d.month}月${d.day}日',
        _ => '${_monthsGenitiveEn[d.month - 1]} ${d.day}',
      };

  /// Дата цифрами, как в подписи «с 30.09.2020».
  String formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Инициал для кружка-аватара: пусто заменяем сердечком, а не пустотой.
  String initialOf(String name) {
    final n = name.trim();
    return n.isEmpty ? '' : n.characters.first.toUpperCase();
  }

  /// Подпись пустого состояния: дата начала не задана, считать нечего.
  Widget emptyLabel(Color color) => Center(
    child: Text(
      LocaleService.current.tgYearNoStartDate,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color),
    ),
  );

  /// Сетка месяцев для превью «Календаря лет».
  ///
  /// Колонок всегда двенадцать, рядов — шесть на каждое прожитое шестилетие,
  /// как в нативном виджете. Точка мельчает, число колонок не меняется.
  Widget monthsGrid(
    YearProgress p, {
    required double dot,
    required double gap,
  }) {
    final rows = (p.monthsCompleted ~/ 72 + 1) * 6;
    final shrink = 6 / rows;
    return CustomPaint(
      size: Size(
        (12 * dot + 11 * gap) * shrink,
        (rows * dot + (rows - 1) * gap) * shrink,
      ),
      painter: MonthsGridPainter(
        filled: p.monthsCompleted,
        rows: rows,
        dot: dot * shrink,
        gap: gap * shrink,
        past: wr('primary'),
        current: wr('tertiary'),
        future: wr('trackOnSurface'),
      ),
    );
  }
}
