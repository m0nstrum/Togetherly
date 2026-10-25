import 'package:flutter/material.dart';

import '../../dict_strings.dart' show ruEn;
import '../../theme/fonts.dart';
import '../l10n/count_words.dart';
import 'wish_reminder_prefs.dart';
import 'wish_reminders.dart';

/// «Напоминания» вишлиста: каждый сам решает, какие получать и когда
/// (docs/WISHLIST.md). Настройки на телефоне, партнёру не видны.
class WishReminderSettingsScreen extends StatefulWidget {
  const WishReminderSettingsScreen({super.key, this.initial, this.onSaved});

  /// Для тестов: начальные настройки без чтения с диска.
  final WishReminderPrefs? initial;

  /// Для тестов: вместо записи на диск и пересчёта расписания.
  final ValueChanged<WishReminderPrefs>? onSaved;

  @override
  State<WishReminderSettingsScreen> createState() =>
      _WishReminderSettingsScreenState();
}

class _WishReminderSettingsScreenState
    extends State<WishReminderSettingsScreen> {
  WishReminderPrefs? _p;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _p = initial;
    } else {
      WishReminderPrefs.load().then((p) {
        if (mounted) setState(() => _p = p);
      });
    }
  }

  Future<void> _set(WishReminderPrefs next) async {
    setState(() => _p = next);
    final saved = widget.onSaved;
    if (saved != null) {
      saved(next);
      return;
    }
    await next.save();
    WishReminders.instance.schedule();
  }

  String _offsetLabel(WishOffset o) {
    if (o.amount == 0) return ruEn('в день срока', 'on the day');
    if (o.hours) {
      return ruEn(
        'за ${o.amount} ${forkRuCountWord(o.amount, 'час', 'часа', 'часов')}',
        '${o.amount} h before',
      );
    }
    return ruEn(
      'за ${o.amount} ${forkRuCountWord(o.amount, 'день', 'дня', 'дней')}',
      '${o.amount} d before',
    );
  }

  String _time(int h, int m) =>
      '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  Future<TimeOfDay?> _pickTime(int h, int m) => showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: h, minute: m),
  );

  Future<void> _addOffset(WishReminderPrefs p) async {
    final added = await showDialog<WishOffset>(
      context: context,
      builder: (_) => const _OffsetDialog(),
    );
    if (added == null || p.dueOffsets.contains(added)) return;
    await _set(p.copyWith(dueOffsets: [...p.dueOffsets, added]));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = _p;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ruEn('Напоминания', 'Reminders'),
          style: AppFonts.unbounded(size: 17, weight: 600),
        ),
      ),
      body: p == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(cs, ruEn('Срок «когда»', 'Due date')),
                SwitchListTile(
                  key: const Key('wish-rem-due'),
                  title: Text(
                    ruEn('Напоминать о сроке', 'Remind about due dates'),
                  ),
                  subtitle: Text(
                    ruEn(
                      'У желаний с датой или месяцем',
                      'For wishes with a date or month',
                    ),
                  ),
                  value: p.dueOn,
                  onChanged: (v) => _set(p.copyWith(dueOn: v)),
                ),
                if (p.dueOn) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in p.dueOffsets)
                          InputChip(
                            label: Text(_offsetLabel(o)),
                            onDeleted: () => _set(
                              p.copyWith(
                                dueOffsets: [
                                  for (final x in p.dueOffsets)
                                    if (x != o) x,
                                ],
                              ),
                            ),
                          ),
                        ActionChip(
                          key: const Key('wish-rem-add-offset'),
                          avatar: const Icon(Icons.add_rounded, size: 18),
                          label: Text(ruEn('Ещё', 'More')),
                          onPressed: () => _addOffset(p),
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(ruEn('Время срока', 'Time of the due date')),
                    subtitle: Text(
                      ruEn(
                        'От него считаются отметки; в это же время — подсказки',
                        'Reminders count back from it; hints come at this time',
                      ),
                    ),
                    trailing: Text(_time(p.dueHour, p.dueMinute)),
                    onTap: () async {
                      final t = await _pickTime(p.dueHour, p.dueMinute);
                      if (t != null) {
                        await _set(
                          p.copyWith(dueHour: t.hour, dueMinute: t.minute),
                        );
                      }
                    },
                  ),
                ],
                _header(cs, ruEn('Место', 'Place')),
                SwitchListTile(
                  key: const Key('wish-rem-place'),
                  title: Text(ruEn('Когда мы рядом', 'When we are nearby')),
                  subtitle: Text(
                    ruEn(
                      'Вы оба рядом с местом из вишлиста — нужна «Где мы» у обоих. '
                          'Не чаще раза в неделю на место',
                      'Both of you are near a place from the wishlist — needs '
                          'location sharing on both phones. At most weekly per place',
                    ),
                  ),
                  value: p.placeOn,
                  onChanged: (v) => _set(p.copyWith(placeOn: v)),
                ),
                if (p.placeOn)
                  ListTile(
                    title: Text(ruEn('Рядом — это', 'Nearby means')),
                    subtitle: Slider(
                      key: const Key('wish-rem-radius'),
                      value: p.placeRadius.toDouble().clamp(100, 2000),
                      min: 100,
                      max: 2000,
                      divisions: 19,
                      label: ruEn('${p.placeRadius} м', '${p.placeRadius} m'),
                      onChanged: (v) => setState(
                        () => _p = p.copyWith(placeRadius: v.round()),
                      ),
                      onChangeEnd: (v) =>
                          _set(p.copyWith(placeRadius: v.round())),
                    ),
                    trailing: Text(
                      ruEn('${p.placeRadius} м', '${p.placeRadius} m'),
                    ),
                  ),
                _header(cs, ruEn('Желание недели', 'Wish of the week')),
                SwitchListTile(
                  key: const Key('wish-rem-weekly'),
                  title: Text(ruEn('Желание недели', 'Wish of the week')),
                  subtitle: Text(
                    ruEn(
                      'Одно несбывшееся желание — одинаковое у вас обоих',
                      'One open wish — the same for both of you',
                    ),
                  ),
                  value: p.weeklyOn,
                  onChanged: (v) => _set(p.copyWith(weeklyOn: v)),
                ),
                if (p.weeklyOn)
                  ListTile(
                    title: Text(ruEn('Когда', 'When')),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (var d = 1; d <= 7; d++)
                            ChoiceChip(
                              label: Text(_weekday(d)),
                              selected: p.weeklyDay == d,
                              onSelected: (_) => _set(p.copyWith(weeklyDay: d)),
                            ),
                        ],
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final t = await _pickTime(p.weeklyHour, p.weeklyMinute);
                        if (t != null) {
                          await _set(
                            p.copyWith(
                              weeklyHour: t.hour,
                              weeklyMinute: t.minute,
                            ),
                          );
                        }
                      },
                      child: Text(_time(p.weeklyHour, p.weeklyMinute)),
                    ),
                  ),
                _header(cs, ruEn('Подарки', 'Gifts')),
                SwitchListTile(
                  key: const Key('wish-rem-gift'),
                  title: Text(ruEn('Подсказки к датам', 'Hints before dates')),
                  subtitle: Text(
                    ruEn(
                      'Перед днём рождения партнёра и годовщиной — тихо, только вам',
                      'Before your partner’s birthday and anniversaries — only to you',
                    ),
                  ),
                  value: p.giftOn,
                  onChanged: (v) => _set(p.copyWith(giftOn: v)),
                ),
                if (p.giftOn) ...[
                  ListTile(
                    title: Text(ruEn('Заранее', 'In advance')),
                    subtitle: Wrap(
                      spacing: 6,
                      children: [
                        for (final d in const [3, 7, 14, 30])
                          ChoiceChip(
                            label: Text(
                              ruEn(
                                '$d ${forkRuCountWord(d, 'день', 'дня', 'дней')}',
                                '$d days',
                              ),
                            ),
                            selected: p.giftLeadDays == d,
                            onSelected: (_) =>
                                _set(p.copyWith(giftLeadDays: d)),
                          ),
                      ],
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      ruEn('14 февраля и 8 марта', 'Feb 14 and Mar 8'),
                    ),
                    value: p.giftHolidays,
                    onChanged: (v) => _set(p.copyWith(giftHolidays: v)),
                  ),
                ],
                SwitchListTile(
                  key: const Key('wish-rem-reserve'),
                  title: Text(ruEn('Срок «Дарю»', '“I’m gifting” deadline')),
                  subtitle: Text(
                    ruEn(
                      'Накануне и в день срока подарка, который вы взяли',
                      'The day before and on the deadline of a gift you took',
                    ),
                  ),
                  value: p.reserveOn,
                  onChanged: (v) => _set(p.copyWith(reserveOn: v)),
                ),
              ],
            ),
    );
  }

  String _weekday(int d) => ruEn(
    const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][d - 1],
    const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d - 1],
  );

  Widget _header(ColorScheme cs, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: AppFonts.onest(size: 13, weight: 700, color: cs.primary),
    ),
  );
}

/// «Напомнить заранее»: N дней или N часов. Поле живёт вместе с диалогом —
/// снаружи его не убрать раньше, чем диалог доиграет закрытие.
class _OffsetDialog extends StatefulWidget {
  const _OffsetDialog();

  @override
  State<_OffsetDialog> createState() => _OffsetDialogState();
}

class _OffsetDialogState extends State<_OffsetDialog> {
  final TextEditingController _amount = TextEditingController(text: '3');
  bool _hours = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(ruEn('Напомнить заранее', 'Remind before')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('wish-offset-amount'),
            controller: _amount,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(labelText: ruEn('Сколько', 'How many')),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(ruEn('дней', 'days'))),
              ButtonSegment(value: true, label: Text(ruEn('часов', 'hours'))),
            ],
            selected: {_hours},
            onSelectionChanged: (v) => setState(() => _hours = v.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ruEn('Отмена', 'Cancel')),
        ),
        TextButton(
          key: const Key('wish-offset-ok'),
          onPressed: () {
            final n = int.tryParse(_amount.text.trim());
            if (n == null || n < 0 || n > (_hours ? 72 : 365)) return;
            Navigator.of(
              context,
            ).pop(_hours ? WishOffset.hours(n) : WishOffset.days(n));
          },
          child: Text(ruEn('Добавить', 'Add')),
        ),
      ],
    );
  }
}
