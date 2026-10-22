import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/watch/room_picker.dart';
import 'package:love_app/services/watch_history_service.dart';
import 'package:love_app/services/watch_videos_service.dart';

void main() {
  test('какие ссылки комната включит', () {
    for (final ok in [
      'https://youtu.be/abc',
      'смотри https://www.youtube.com/watch?v=abc вот',
      'youtu.be/abc',
      'https://vk.com/video-1_2',
      'https://rutube.ru/video/abc/',
      'https://disk.yandex.ru/i/x',
      'https://drive.google.com/file/d/1/view',
      'https://example.com/film.mp4',
    ]) {
      expect(forkRoomPlayable(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'привет', 'https://example.com/page', 'https://ivi.ru/watch/1']) {
      expect(forkRoomPlayable(bad), isFalse, reason: bad);
    }
    expect(forkRoomLinkOf('смотри https://youtu.be/abc вот'), 'https://youtu.be/abc');
  });

  testWidgets('ссылка из буфера — одной кнопкой; плохая — объясняем', (tester) async {
    ForkRoomPick? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async {
              got = await showModalBottomSheet<ForkRoomPick>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => SizedBox(
                  height: 600,
                  child: ForkRoomPicker(
                    groupId: 'g1',
                    clipboard: () async => 'глянь https://youtu.be/xyz',
                    recent: () async => [
                      const WatchEntry(id: 'r1', url: 'https://youtu.be/old', kind: 'youtube', title: 'Старое', thumb: '', seconds: 0),
                      const WatchEntry(id: 'r2', url: 'file://a.mp4', kind: 'file', title: 'Свой файл', thumb: '', seconds: 0),
                    ],
                    uploaded: () async => const <WatchVideo>[],
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('https://youtu.be/xyz'), findsOneWidget);
    expect(find.text('Старое'), findsOneWidget);
    expect(find.text('Свой файл'), findsNothing, reason: 'свой файл ссылкой не открыть');

    await tester.enterText(find.byType(TextField), 'просто текст');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pump();
    expect(find.textContaining(RegExp('не откроет|can’t open')), findsOneWidget);

    await tester.tap(find.text('https://youtu.be/xyz'));
    await tester.pumpAndSettle();
    expect(got?.url, 'https://youtu.be/xyz');
  });
}
