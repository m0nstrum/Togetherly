import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../models/wish_due.dart';
import '../../services/locale_service.dart';
import '../../theme/fonts.dart';
import '../../theme/profile_theme.dart';

/// Подпись срока на текущем языке: «14 ноября», «ноябрь 2026»,
/// «когда-нибудь». Пусто — срока нет.
String wishDueLabel(WishDue due, {DateTime? now}) {
  final s = LocaleService.current;
  return due.label(
    genitive: s.cycleMonthsGenitive,
    nominative: [for (final m in s.cycleMonthNames) m.toLowerCase()],
    somedayLabel: ruEn('когда-нибудь', 'someday'),
    now: now,
  );
}

/// «Когда» в форме желания: без срока, дата, месяц или «когда-нибудь».
///
/// Чипы, а не одно поле даты: у половины желаний срока нет вовсе, а
/// «весной» или «когда-нибудь» точной датой не скажешь.
class WishDuePicker extends StatelessWidget {
  const WishDuePicker({
    super.key,
    required this.value,
    required this.scheme,
    required this.ru,
    required this.onChanged,
  });

  final WishDue value;
  final ColorScheme scheme;
  final bool ru;
  final ValueChanged<WishDue> onChanged;

  String _tr(String r, String e) => ru ? r : ruEn(r, e);

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = value.kind == WishDueKind.date ? value.anchor! : today;
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: _tr('Когда', 'When'),
      builder: (ctx, child) =>
          Theme(data: ProfileTheme.data(scheme), child: child!),
    );
    if (picked != null) onChanged(WishDue.date(picked));
  }

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showDialog<WishDue>(
      context: context,
      builder: (_) => Theme(
        data: ProfileTheme.data(scheme),
        child: _MonthDialog(
          initial: value.kind == WishDueKind.month ? value : null,
          ru: ru,
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final chips = <(WishDueKind, String, IconData)>[
      (WishDueKind.none, _tr('Без срока', 'No date'), Icons.block_rounded),
      (
        WishDueKind.date,
        value.kind == WishDueKind.date
            ? wishDueLabel(value)
            : _tr('Дата', 'Date'),
        Icons.event_rounded,
      ),
      (
        WishDueKind.month,
        value.kind == WishDueKind.month
            ? wishDueLabel(value)
            : _tr('Месяц', 'Month'),
        Icons.calendar_month_rounded,
      ),
      (
        WishDueKind.someday,
        _tr('Когда-нибудь', 'Someday'),
        Icons.all_inclusive_rounded,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            _tr('Когда', 'When'),
            style: AppFonts.onest(size: 12, weight: 600, color: scheme.primary),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (kind, label, icon) in chips)
              ChoiceChip(
                key: Key('wish-due-${kind.name}'),
                selected: value.kind == kind,
                showCheckmark: false,
                avatar: Icon(icon, size: 16),
                label: Text(label),
                labelStyle: AppFonts.onest(
                  size: 13.5,
                  weight: 600,
                  color: value.kind == kind
                      ? scheme.onSecondaryContainer
                      : scheme.onSurfaceVariant,
                ),
                selectedColor: scheme.secondaryContainer,
                backgroundColor: scheme.surfaceContainerHigh,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                onSelected: (_) => switch (kind) {
                  WishDueKind.none => onChanged(WishDue.none),
                  WishDueKind.someday => onChanged(WishDue.someday),
                  WishDueKind.date => _pickDate(context),
                  WishDueKind.month => _pickMonth(context),
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// Год стрелками и сетка из двенадцати месяцев. Прошедшие месяцы погашены:
/// срок в прошлом не ставят.
class _MonthDialog extends StatefulWidget {
  const _MonthDialog({required this.initial, required this.ru});

  final WishDue? initial;
  final bool ru;

  @override
  State<_MonthDialog> createState() => _MonthDialogState();
}

class _MonthDialogState extends State<_MonthDialog> {
  final DateTime _now = DateTime.now();
  late int _year = widget.initial?.year ?? _now.year;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final names = LocaleService.current.cycleMonthNames;
    return AlertDialog(
      title: Row(
        children: [
          IconButton(
            tooltip: widget.ru ? 'Раньше' : 'Earlier',
            onPressed: _year > _now.year ? () => setState(() => _year--) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(
              '$_year',
              textAlign: TextAlign.center,
              style: AppFonts.unbounded(size: 18, weight: 600),
            ),
          ),
          IconButton(
            tooltip: widget.ru ? 'Позже' : 'Later',
            onPressed: _year < _now.year + 10
                ? () => setState(() => _year++)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: GridView.count(
          shrinkWrap: true,
          crossAxisCount: 3,
          childAspectRatio: 2.2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [for (var m = 1; m <= 12; m++) _cell(cs, m, names[m - 1])],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.ru ? 'Отмена' : 'Cancel'),
        ),
      ],
    );
  }

  Widget _cell(ColorScheme cs, int m, String name) {
    final past = _year == _now.year && m < _now.month;
    final selected =
        widget.initial?.year == _year && widget.initial?.month == m;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('wish-month-$m'),
        onTap: past
            ? null
            : () => Navigator.of(context).pop(WishDue.month(_year, m)),
        child: Center(
          child: Text(
            name.length > 4 ? name.substring(0, 3) : name,
            style: AppFonts.onest(
              size: 14,
              weight: 600,
              color: selected
                  ? cs.onPrimary
                  : past
                  ? cs.onSurface.withValues(alpha: .38)
                  : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
