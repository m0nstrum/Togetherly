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
    final before = {for (final g in shown()) _id(g)};
    await load();
    for (final g in shown()) {
      final id = _id(g);
      if (id.isEmpty || before.contains(id) || _opened.contains(id)) continue;
      _opened.add(id);
      await open(g);
      return; // остальные новые — следующим событием, лист за листом
    }
  }

  static String _id(Map<String, dynamic> g) => (g['id'] ?? '').toString();
}
