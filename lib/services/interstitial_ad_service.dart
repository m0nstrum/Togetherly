// fork: рекламы в форке нет (docs/history/PLAN.md, решение 1; TOUCHPOINTS.md).
// Заглушка с API апстрима: межстраничный ролик никогда не готов. При мёрже
// апстрима этот файл берём свой.

/// Межстраничный ролик. В форке не показывается.
class InterstitialAdService {
  InterstitialAdService({this.room = false});

  /// Ролик после комнаты совместного просмотра (в апстриме — свой блок).
  final bool room;

  bool get isReady => false;

  Future<void> load() async {}

  Future<bool> show({Duration timeout = const Duration(seconds: 60)}) async =>
      false;

  void dispose() {}
}
