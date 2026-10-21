/// Выход не теряет написанное молча (UX_AUDIT A4).
///
/// Очередь отправки при выходе очищается намеренно: иначе чужие правки ушли
/// бы под следующим входом. Но человек должен знать, что теряет.
library;

import '../../dict_strings.dart' show ruEn;
import '../../services/offline/outbox_service.dart';

abstract final class ForkLogoutGuard {
  /// Сколько ещё не ушло на сервер.
  static int get pending => OutboxService.instance.pendingCount.value;

  /// Текст подтверждения выхода: [base] плюс предупреждение, если в очереди
  /// что-то есть.
  static String message(String base, {int? pendingOverride}) {
    final n = pendingOverride ?? pending;
    if (n <= 0) return base;
    return '$base\n\n${ruEn(
      'Ещё не отправлено: $n. Подключитесь к интернету и дождитесь отправки — после выхода это пропадёт.',
      'Not sent yet: $n. Get online and wait for it to go through — it will be lost after you sign out.',
    )}';
  }
}
