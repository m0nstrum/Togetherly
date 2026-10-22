/// Главная по умолчанию в форке (просьба владельца 22.10: «главный экран
/// кажется слегка перегруженным»).
///
/// Сундук и задания дня — механика монет; в форке монеты бесплатные, и эти
/// блоки только удлиняли главную. Они спрятаны, пока человек сам не включит
/// их в «Настроить главную»; настроенная раньше раскладка не трогается.
library;

import '../models/home_layout.dart';

abstract final class ForkHome {
  static const HomeLayout layout = HomeLayout(
    hiddenBlocks: {HomeBlock.chest, HomeBlock.tasks},
  );

  /// Раскладка совпадает с главной форка по умолчанию — «Сбросить» не нужен.
  static bool isDefault(HomeLayout l) =>
      l.toJson().toString() == layout.toJson().toString();
}
