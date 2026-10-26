import 'wish.dart';

/// Шаг между соседними местами при перенумерации.
const double wishPosStep = 1024;

/// Новые места после перетаскивания карточки с [from] на [to] (индекс в
/// списке после вставки). Возвращает только изменившиеся: id → место.
///
/// Обычно меняется одна карточка — ей достаётся середина между соседями.
/// Если у соседей места нет (желания прежних сборок, новые) или зазор
/// кончился, список нумеруется заново: так порядок совпадёт у обоих.
Map<String, double> wishReorder(List<Wish> list, int from, int to) {
  if (from == to || from < 0 || from >= list.length) return const {};
  final order = List.of(list);
  final moved = order.removeAt(from);
  final at = to.clamp(0, order.length);
  order.insert(at, moved);

  final prev = at > 0 ? order[at - 1].pos : null;
  final next = at < order.length - 1 ? order[at + 1].pos : null;
  final hasPrev = at > 0, hasNext = at < order.length - 1;
  final allPlaced = order.every((w) => w.pos != null);
  if (allPlaced) {
    double? pos;
    if (!hasPrev && next != null) pos = next - wishPosStep;
    if (!hasNext && prev != null) pos = prev + wishPosStep;
    if (prev != null && next != null && next - prev > 1e-6) {
      pos = (prev + next) / 2;
    }
    if (pos != null) return {moved.id: pos};
  }

  final out = <String, double>{};
  for (var i = 0; i < order.length; i++) {
    final p = (i + 1) * wishPosStep;
    if (order[i].pos != p) out[order[i].id] = p;
  }
  return out;
}
