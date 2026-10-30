import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/widget_panels.dart';

/// Что раскрыто в каталоге виджетов и какой размер выбран в карточках.
///
/// Живёт в prefs (`WidgetPanels`, `WidgetSizeChoice`), поэтому переживает
/// уход с экрана и перезапуск — до 12.09.2026 набор сбрасывался к умолчаниям
/// при каждом заходе.
class WidgetCatalogPanels extends ChangeNotifier {
  WidgetCatalogPanels({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  Set<String> _expanded = {...WidgetPanels.byDefault};

  /// Выбранный размер в карточке каталога, ключ — `widgetType`.
  final Map<String, int> _sizes = {};

  /// Человек уже сворачивал что-то в этот заход. Нужен против гонки: чтение
  /// prefs асинхронное, и ответ, пришедший после первого нажатия, затёр бы
  /// свежее решение прежним набором.
  bool _touched = false;
  bool _disposed = false;

  bool isExpanded(String key) => _expanded.contains(key);

  /// Выбранный вариант размера; `null` — не выбирали.
  int? sizeOf(String widgetType) => _sizes[widgetType];

  /// Свернуть или раскрыть и тут же запомнить решение.
  void toggle(String key) {
    _touched = true;
    if (!_expanded.remove(key)) _expanded.add(key);
    notifyListeners();
    unawaited(_savePanels());
  }

  /// Раскрыть без запоминания: карточка, открытая тапом по виджету рабочего
  /// стола, — не решение человека о каталоге.
  void open(String key) {
    _expanded.add(key);
    notifyListeners();
  }

  void chooseSize(String widgetType, int index) {
    _sizes[widgetType] = index;
    notifyListeners();
    unawaited(_saveSizes());
  }

  Future<void> load() async {
    final prefs = await _prefs();
    final saved = WidgetPanels.restore(
      prefs.getStringList(WidgetPanels.prefsKey),
    );
    final sizes = WidgetSizeChoice.restore(
      prefs.getStringList(WidgetSizeChoice.prefsKey),
    );
    if (_disposed || _touched) return;
    // Выбранный размер — то же самое решение человека, что и раскрытие:
    // выбрал «4×4», ушёл на главную, вернулся — размер обязан остаться.
    // `putIfAbsent`, а не `addAll`: чтение асинхронное, и тот, кто успел
    // ткнуть размер до ответа prefs, не должен получить прежний обратно.
    sizes.forEach((k, v) => _sizes.putIfAbsent(k, () => v));
    // Карточку, раскрытую тапом по виджету рабочего стола, не закрываем:
    // человек пришёл сюда именно ради неё.
    _expanded = {
      ..._expanded.intersection({WidgetPanels.pairWidget}),
      ...saved,
    };
    notifyListeners();
  }

  Future<void> _savePanels() async {
    final prefs = await _prefs();
    await prefs.setStringList(
      WidgetPanels.prefsKey,
      WidgetPanels.store(_expanded),
    );
  }

  Future<void> _saveSizes() async {
    final prefs = await _prefs();
    await prefs.setStringList(
      WidgetSizeChoice.prefsKey,
      WidgetSizeChoice.store(_sizes),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
