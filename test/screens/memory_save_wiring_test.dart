// Сторож подключения сохранения к ленте воспоминаний.
//
// Лист воспоминания — приватный класс в part-файле, собрать его в тесте без
// PocketBase нельзя, поэтому проверяются исходники: старое скачивание не
// вернулось, меню не выходит молча, полный экран знает запись.
import 'package:flutter_test/flutter_test.dart';

import '../support/flat_source.dart';
import '../support/screen_source.dart';

String _read(String p) => flatSource(p);

void main() {
  final lane = flat(screenSource('lib/screens/memory_lane_screen.dart'));
  final detail = _read('lib/screens/memory_lane/detail.dart');
  final gallery = _read('lib/screens/memory_lane/gallery.dart');
  final all = '$lane\n$detail\n$gallery';

  test('старая кнопка скачивания не вернулась', () {
    // Она открывала браузер для каждого своего файла и брала только обложку.
    expect(all, isNot(contains(flat('_downloadMemoryMedia('))));
    expect(all, isNot(contains(flat('Gal.putImage('))));
    expect(all, isNot(contains(flat('Gal.putVideo('))));
    expect(all, isNot(contains(flat("url.contains('firebase')"))));
  });

  test('лист воспоминания сохраняет разделённой кнопкой через общий поток', () {
    expect(detail, contains(flat('SaveSplitButton(')));
    expect(detail, contains(flat('saveToGallery(')));
    expect(detail, contains(flat('showSaveOptionsSheet(')));
    expect(detail, contains(flat('showFramePicker(')));
  });

  test('меню «три точки» считает пункты и не выходит молча', () {
    expect(detail, contains(flat('memoryMenuActions(')));
    expect(
      detail,
      isNot(contains(flat('if (!widget.isOwner && !canSetPlace) return;'))),
    );
    // Кнопку без пунктов лист не показывает.
    expect(detail, contains(flat('_menuActions(memory).isNotEmpty')));
  });

  test('каждый полноэкранный просмотр ленты знает запись кадра', () {
    for (final src in [lane, detail, gallery]) {
      final calls = RegExp(r'(?<![\w])FullscreenGallery\(').allMatches(src);
      for (final c in calls) {
        final window = src.substring(
          c.start,
          (c.start + 260).clamp(0, src.length),
        );
        if (window.startsWith('FullscreenGallery({')) continue; // конструктор
        expect(
          window,
          contains(flat('memoryOf')),
          reason: 'FullscreenGallery без memoryOf: кадр не сохранить',
        );
      }
    }
  });

  test('лента подхватывает оборванную очередь и держит островок', () {
    expect(lane, contains(flat('MediaSaveQueue.instance.resume()')));
    expect(lane, contains(flat('SaveIsland(')));
    expect(gallery, contains(flat('SaveIsland(')));
  });

  test('выбор нескольких записей: вход из листа, выход кнопкой «Назад»', () {
    expect(lane, contains(flat("trKey('feedSelectMany')")));
    expect(lane, contains(flat('canPop: !_selecting')));
    expect(lane, contains(flat('_saveSelected')));
  });
}
