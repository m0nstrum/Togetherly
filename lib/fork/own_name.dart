/// Своё имя для подписи реплик, зова и записей звонка.
///
/// Имя в записи входа (`users.display_name`) лежит шифром личного ключа. Пока
/// ключ не открылся (холодный старт, фон), запись отдаёт пустоту, и партнёр
/// видел вместо имени «Гость». Локальный профиль хранит имя открытым — оно
/// и подставляется ([UserData] обновляет его при загрузке и правке).
library;

abstract final class ForkOwnName {
  static String _value = '';

  static String get value => _value;

  /// Шифр и замок не годятся в подпись — пропускаем.
  static bool usable(String v) {
    final t = v.trim();
    return t.isNotEmpty && !t.startsWith('e2e1.') && t != '🔒';
  }

  static set value(String v) {
    if (v.isEmpty || usable(v)) _value = v.trim();
  }
}
