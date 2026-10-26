/// Согласие на показ геопозиции — конкретному партнёру (UX_AUDIT G1).
///
/// У апстрима флаг «показывать» один на телефон: пара распалась, сменился
/// вход, появился новый партнёр — и точка уходит ему без нового согласия.
/// Здесь рядом с флагом лежит, кому он был дан (`<мой uid>|<uid партнёра>`).
/// Другой человек или другой вход — согласие снимается.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract final class LocationConsent {
  static const prefsKey = 'fork_live_location_consent';

  static String _who(String me, String partner) => '$me|$partner';

  /// Запомнить, кому дано согласие; пустой [partner] — снять.
  static Future<void> remember(String me, String partner) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (me.isEmpty || partner.isEmpty) {
        await prefs.remove(prefsKey);
      } else {
        await prefs.setString(prefsKey, _who(me, partner));
      }
    } catch (
      _
    ) {} // тихо: без настроек согласие просто не сохранится — шеринг не включится сам
  }

  /// Можно ли слать точку [partner] от [me]. Согласие без адресата (включено
  /// до этой версии) привязывается к текущему партнёру.
  static Future<bool> allows(String me, String partner) async {
    if (me.isEmpty || partner.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefsKey);
      if (saved == null || saved.isEmpty) {
        await prefs.setString(prefsKey, _who(me, partner));
        return true;
      }
      return saved == _who(me, partner);
    } catch (_) {
      return false;
    }
  }
}
