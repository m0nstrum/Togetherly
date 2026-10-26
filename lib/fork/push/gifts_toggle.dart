/// Тумблер уведомлений о подарках (UX_AUDIT G11): `PbPushService` давно
/// учитывает `notif_gifts`, а выключателя на экране не было.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dict_strings.dart' show ruEn;
import '../../widgets/settings_scaffold.dart';

class ForkGiftsNotifRow extends StatefulWidget {
  const ForkGiftsNotifRow({super.key});

  static const prefsKey = 'notif_gifts';

  @override
  State<ForkGiftsNotifRow> createState() => _ForkGiftsNotifRowState();
}

class _ForkGiftsNotifRowState extends State<ForkGiftsNotifRow> {
  bool _on = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted)
        setState(() => _on = p.getBool(ForkGiftsNotifRow.prefsKey) ?? true);
    }, onError: (_) {}); // тихо: без настроек остаётся «включено»
  }

  Future<void> _set(bool v) async {
    setState(() => _on = v);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(ForkGiftsNotifRow.prefsKey, v);
    } catch (e) {
      debugPrint('ForkGiftsNotifRow: $e');
    }
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: Icons.card_giftcard_rounded,
    title: ruEn('Подарки', 'Gifts'),
    subtitle: ruEn(
      'Когда партнёр что-то дарит',
      'When your partner sends a gift',
    ),
    trailing: Switch(value: _on, onChanged: _set),
    onTap: () => _set(!_on),
  );
}
