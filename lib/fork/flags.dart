/// Переключатели поведения форка (docs/history/PLAN.md, S2).
///
/// Геттеры, а не `const`: с константой анализатор помечает код апстрима за
/// проверкой как мёртвый, и это шум в базовой линии предупреждений.
abstract final class ForkFlags {
  /// Собственная аналитика апстрима (`/api/stats/collect`) выключена:
  /// события не копятся и не отправляются. Вызовы в экранах остаются.
  static bool get analyticsDisabled => true;

  /// Всё бесплатно (решение 1): Togetherly+ открыт у всех, покупок нет.
  /// Заодно снимает рекламные развилки апстрима — они пропускают рекламу при
  /// открытом Плюсе.
  static bool get allFree => true;

  /// Каналы автора апстрима (Telegram-канал, бот жалоб, донаты) не
  /// показываются: форк не ведёт людей к чужой инфраструктуре.
  static bool get hideUpstreamChannels => true;

  /// Вход только по почте и паролю (решение 3): кнопок OAuth (Google,
  /// Яндекс, Apple) нет.
  static bool get emailOnlyAuth => true;

  /// Вход только с введённой почтой (UX_AUDIT A1). Апстрим при неверном
  /// пароле пробует тот же пароль на «опечаточных» доменах (`gmail.ru`,
  /// `gmail.con`…) и молча входит в первый подошедший — то есть в чужой
  /// аккаунт с тем же паролем, и заодно умножает попытки перебора. У своего
  /// сервера нет наследства из аккаунтов с опечатками, ради которых это
  /// делалось.
  static bool get strictLogin => true;

  /// Запросы к сторонним сайтам — через свой сервер (lib/fork/http_gateway.dart).
  static bool get metaGateway => true;

  /// Ключи чужих сервисов, зашитые автором апстрима (общий ключ poiskkino),
  /// не используются: фильмы ищет свой сервер, свой ключ — через
  /// `--dart-define`.
  static bool get noUpstreamKeys => true;

  /// The fork offers only complete Russian and English interfaces (PLAN 2.3).
  static bool get fullLanguageCatalog => false;

  /// No upstream GitHub/Play update checks in the fork (PLAN 1.9).
  static bool get upstreamUpdates => false;

  /// Из комнаты и ленты выходят с первого «назад» — кнопкой или жестом, как
  /// с любого другого экрана (просьба владельца 22.10). Апстрим просил второе
  /// нажатие с системной подсказкой «нажмите ещё раз».
  static bool get singleBackExit => true;
}
