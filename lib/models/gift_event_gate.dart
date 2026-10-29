/// Очередь реакций на события подарков (RT-7).
///
/// Сервер на один подарок шлёт create и сразу следом update (фото, звук,
/// отметки). Раньше каждое событие запускало свой обработчик параллельно:
/// оба запоминали длину списка «до», оба перечитывали входящие, оба видели,
/// что список вырос, — и один и тот же подарок открывался дважды, лист поверх
/// листа. К тому же сравнение по длине пропускало подарок, если в тот же миг
/// другой ушёл из списка.
///
/// Теперь проходы идут по одному: событие во время прохода лишь просит ещё
/// один (сколько бы их ни пришло — один). Новый подарок узнаётся по id, а
/// уже открытый автоматически второй раз не открывается.
class GiftEventGate {
  GiftEventGate({required this.load, required this.open, required this.shown});

  /// Перечитать входящие (обновляет то, что отдаёт [shown]).
  final Future<void> Function() load;

  /// Показать подарок; завершается, когда человек ответил.
  final Future<void> Function(Map<String, dynamic> gift) open;

  /// Входящие, которые сборка умеет показать, новые первыми.
  final List<Map<String, dynamic>> Function() shown;

  final Set<String> _opened = {};

  /// Подарки, известные очереди на конец её прошлого прохода, — без тех, что
  /// она нашла новыми, но ещё не открыла. Базу берём отсюда, а не из
  /// текущего списка: [open] сам перечитывает входящие после ответа, и
  /// подарок, пришедший во время показа листа, иначе попадал бы в базу и не
  /// открывался никогда.
  Set<String>? _known;
  Future<void>? _running;
  bool _again = false;

  /// Пришло событие подарков: перечитать и открыть новый, если он есть.
  Future<void> onEvent() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _drain();
    _running = run;
    return run;
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        await _pass();
      } while (_again);
    } finally {
      _running = null;
    }
  }

  Future<void> _pass() async {
    final before = _known ?? {for (final g in shown()) _id(g)};
    await load();
    final loaded = {for (final g in shown()) _id(g)};
    final fresh = [
      for (final g in shown())
        if (_id(g).isNotEmpty &&
            !before.contains(_id(g)) &&
            !_opened.contains(_id(g)))
          g,
    ];
    // Новые, кроме открываемого сейчас, остаются новыми и для следующего
    // прохода: лист за листом, а не поверх.
    _known = loaded.difference({for (final g in fresh.skip(1)) _id(g)});
    if (fresh.isEmpty) return;
    if (fresh.length > 1) _again = true;
    _opened.add(_id(fresh.first));
    await open(fresh.first);
  }

  static String _id(Map<String, dynamic> g) => (g['id'] ?? '').toString();
}
