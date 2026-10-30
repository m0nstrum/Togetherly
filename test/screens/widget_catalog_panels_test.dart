// Раскрытые разделы и выбранные размеры каталога виджетов (A12-1: логика
// вынесена из экрана в WidgetCatalogPanels). Набор — привычка человека и
// живёт в prefs: уход с экрана и перезапуск его не сбрасывают.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:love_app/models/widget_panels.dart';
import 'package:love_app/screens/widget_screen/catalog_panels.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('первый заход — умолчания', () async {
    final p = WidgetCatalogPanels();
    await p.load();
    for (final key in WidgetPanels.known) {
      expect(
        p.isExpanded(key),
        WidgetPanels.byDefault.contains(key),
        reason: key,
      );
    }
    expect(p.sizeOf('mood'), isNull);
  });

  test('переключение и размер переживают новый экран', () async {
    final first = WidgetCatalogPanels();
    await first.load();
    first.toggle(WidgetPanels.sectionPair); // свернул открытый
    first.toggle(WidgetPanels.photoGrid); // раскрыл закрытый
    first.chooseSize('mood', 2);
    await pumpEventQueue();
    first.dispose();

    final second = WidgetCatalogPanels();
    await second.load();
    expect(second.isExpanded(WidgetPanels.sectionPair), isFalse);
    expect(second.isExpanded(WidgetPanels.photoGrid), isTrue);
    expect(second.isExpanded(WidgetPanels.photoDay), isTrue);
    expect(second.sizeOf('mood'), 2);
  });

  test('ответ prefs после первого нажатия не затирает решение', () async {
    SharedPreferences.setMockInitialValues({
      WidgetPanels.prefsKey: [WidgetPanels.sectionTime],
      WidgetSizeChoice.prefsKey: ['mood:1'],
    });
    final prefs = Completer<SharedPreferences>();
    final p = WidgetCatalogPanels(prefs: () => prefs.future);
    final loading = p.load();
    p.toggle(WidgetPanels.photoDay); // свернул до ответа
    prefs.complete(await SharedPreferences.getInstance());
    await loading;
    expect(p.isExpanded(WidgetPanels.photoDay), isFalse);
    expect(p.isExpanded(WidgetPanels.sectionPair), isTrue, reason: 'умолчание');
    expect(
      p.isExpanded(WidgetPanels.sectionTime),
      isFalse,
      reason: 'сохранённый набор не наложился поверх нажатия',
    );
  });

  test('выбранный до ответа prefs размер не возвращается к прежнему', () async {
    SharedPreferences.setMockInitialValues({
      WidgetSizeChoice.prefsKey: ['mood:1', 'note:2'],
    });
    final prefs = Completer<SharedPreferences>();
    final p = WidgetCatalogPanels(prefs: () => prefs.future);
    final loading = p.load();
    p.chooseSize('mood', 0);
    prefs.complete(await SharedPreferences.getInstance());
    await loading;
    expect(p.sizeOf('mood'), 0);
    expect(p.sizeOf('note'), 2, reason: 'остальное подтянулось');
  });

  test(
    'карточка, раскрытая тапом по виджету, при чтении не закрывается',
    () async {
      SharedPreferences.setMockInitialValues({
        WidgetPanels.prefsKey: <String>[],
      });
      final prefs = Completer<SharedPreferences>();
      final p = WidgetCatalogPanels(prefs: () => prefs.future);
      final loading = p.load();
      p.open(WidgetPanels.pairWidget);
      prefs.complete(await SharedPreferences.getInstance());
      await loading;
      expect(p.isExpanded(WidgetPanels.pairWidget), isTrue);
      expect(
        p.isExpanded(WidgetPanels.photoDay),
        isFalse,
        reason: 'всё свёрнуто',
      );

      // Раскрытие тапом — не решение о каталоге и в prefs не пишется.
      await pumpEventQueue();
      final again = WidgetCatalogPanels();
      await again.load();
      expect(again.isExpanded(WidgetPanels.pairWidget), isFalse);
    },
  );

  test('экран ушёл до ответа prefs — без уведомлений', () async {
    final prefs = Completer<SharedPreferences>();
    final p = WidgetCatalogPanels(prefs: () => prefs.future);
    var notified = 0;
    p.addListener(() => notified++);
    final loading = p.load();
    p.dispose();
    prefs.complete(await SharedPreferences.getInstance());
    await loading;
    expect(notified, 0);
  });

  test('нажатие перерисовывает экран сразу', () {
    final p = WidgetCatalogPanels();
    var notified = 0;
    p.addListener(() => notified++);
    p.toggle(WidgetPanels.sectionMood);
    p.chooseSize('mood', 1);
    p.open(WidgetPanels.pairWidget);
    expect(notified, 3);
  });
}
