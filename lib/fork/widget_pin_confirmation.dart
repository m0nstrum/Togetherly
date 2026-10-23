import 'package:home_widget/home_widget.dart';

/// A pin request only opens the launcher's dialog. Confirm a new installed ID.
class ForkWidgetPinConfirmation {
  ForkWidgetPinConfirmation({required this.installed, required this.confirmed});

  final Future<List<HomeWidgetInfo>> Function() installed;
  final Future<void> Function() confirmed;
  final Map<String, Set<int>> _pending = {};
  bool _checking = false;
  bool get pending => _pending.isNotEmpty;

  Future<void> request(
    String className,
    Future<void> Function() requestPin,
  ) async {
    final before = await installed();
    _pending[className] = {
      for (final w in before)
        if (w.androidWidgetId != null) w.androidWidgetId!,
    };
    try {
      await requestPin();
    } catch (_) {
      _pending.remove(className);
      rethrow;
    }
  }

  Future<void> check() async {
    if (_checking || !pending) return;
    _checking = true;
    try {
      final widgets = await installed();
      final added = <String>[];
      for (final entry in _pending.entries) {
        if (widgets.any(
          (w) =>
              w.androidClassName == entry.key &&
              w.androidWidgetId != null &&
              !entry.value.contains(w.androidWidgetId),
        )) {
          added.add(entry.key);
        }
      }
      for (final name in added) {
        _pending.remove(name);
        await confirmed();
      }
    } finally {
      _checking = false;
    }
  }
}
