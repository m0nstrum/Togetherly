// fork: рекламы в форке нет (docs/history/PLAN.md, решение 1; TOUCHPOINTS.md).
// Реализация апстрима на SDK Яндекса заменена заглушкой с тем же API: ролик
// никогда не готов и не показывается. Экраны, где реклама была платой за
// функцию, пропускают её сами — Togetherly+ в форке открыт у всех
// (ForkFlags.allFree). При мёрже апстрима этот файл берём свой.

/// Rewarded-видео. В форке всегда «не готово».
class RewardedAdService {
  RewardedAdService({this.chest = false});

  /// Ролик сундука недели (в апстриме — свой рекламный блок).
  final bool chest;

  bool get isReady => false;
  bool get lastShowWasYandex => false;
  int? get lastServerCoins => null;
  bool get lastRewardGranted => false;
  bool get lastRateLimited => false;
  bool get lastGrantTimedOut => false;
  int get lastSecondsAway => 0;

  Future<void> load() async {}

  /// Ролик не показывается, награды нет.
  Future<bool> show({required String uid, String? chestOpenId}) async => false;

  void dispose() {}
}
