/// Идентичность форка Tethered.
///
/// Должна совпадать с `forkManifestPlaceholders` в
/// `android/app/build.gradle.kts`: схема оттуда регистрируется в манифесте, а
/// отсюда попадает в ссылки, которые клиент выдаёт и разбирает.
abstract final class ForkIdentity {
  static const String appName = 'Tethered';

  /// Схема приглашений: `tethered://invite/CODE`.
  ///
  /// Схема апстрима `loveapp://` остаётся внутренней схемой виджетов (их
  /// интенты явные), а наружу форк её не регистрирует, чтобы не спорить за
  /// ссылки с приложением апстрима на том же телефоне.
  static const String inviteScheme = 'tethered';

  /// Прямой deep link приглашения (для QR). Пустой код — пустая строка.
  static String inviteDeepLink(String inviteCode) =>
      inviteCode.trim().isEmpty ? '' : '$inviteScheme://invite/$inviteCode';
}
