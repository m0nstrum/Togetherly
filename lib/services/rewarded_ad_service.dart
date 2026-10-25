// fork: рекламы нет (docs/history/PLAN.md, решение 1). Заглушка с API
// апстрима: ролик никогда не готов. Её ещё зовут сундук, подарки и пробы тем —
// уходит вместе с этими развилками (docs/ROADMAP.md, этап 0, пункт 4).

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
