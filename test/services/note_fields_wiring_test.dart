import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Поле, которого нет в одном из мест связки, теряется МОЛЧА — PocketBase
/// отвечает на неизвестное поле успехом, просто выбрасывая его.
/// В этом проекте так уже терялись ссылки желаний, заметка виджета и обложка
/// роликов, поэтому у фигурок связка проверяется тестом.
void main() {
  const noteFields = [
    'note_url',
    'note_ms',
    'note_shape',
    'note_thumb',
    'note_seen_at',
    'note_hearts',
  ];

  test('поля фигурки объявлены в схеме коллекции', () {
    final raw = File('pocketbase/collections_schema.json').readAsStringSync();
    final decoded = jsonDecode(raw);
    final list = decoded is List
        ? decoded
        : (decoded['collections'] as List? ?? const []);
    final chat = list.firstWhere((c) => c['name'] == 'chat_messages');
    final fields = (chat['fields'] ?? chat['schema']) as List;
    final names = fields.map((f) => f['name']).toSet();
    for (final f in noteFields) {
      expect(names, contains(f), reason: 'нет в collections_schema.json: $f');
    }
  });

  test('отправка кладёт поля фигурки в тело запроса', () {
    final src = File('lib/services/pb_data_service.dart').readAsStringSync();
    // Тело собирает chatBody: и прямая отправка, и повтор из очереди берут
    // поля оттуда. Раньше тест смотрел внутрь chatSend и после рефакторинга
    // стерёг пустое место.
    final body = src
        .split('Map<String, dynamic> chatBody(')[1]
        .split('return body;')[0];
    for (final f in ['note_url', 'note_ms', 'note_shape', 'note_thumb']) {
      expect(body, contains("'$f'"), reason: 'chatSend не шлёт $f');
    }
  });

  test('смотрящему открыты только отметка просмотра и сердечки', () {
    final guard = File(
      'server/internal/infrastructure/pocketbase/authorship.go',
    ).readAsStringSync();
    final chat = guard.split('"chat_messages":')[1].split('}},')[0];
    expect(chat, contains('"note_seen_at": true'));
    expect(chat, contains('"note_hearts": true'));
    // Ссылку на файл и форму чужой правит только автор.
    expect(chat, isNot(contains('note_url')));
    expect(chat, isNot(contains('note_shape')));
  });

  test('сохранение в галерею берёт сам файл фигурки через прокси', () {
    // Файл зашифрован ключом пары: серверного экспорта в форке нет.
    final client = File(
      'lib/services/note_export_service.dart',
    ).readAsStringSync();
    expect(client, contains('resolveUrlAuthed(noteUrl)'));
    expect(client, isNot(contains('/api/note/export')));
    final viewer = File(
      'lib/screens/chat/note_viewer_screen.dart',
    ).readAsStringSync();
    expect(viewer, contains('saveToGallery(_msg.id, _note.url)'));
  });

  test('форма для экспорта берётся из того же профиля, что и в приложении', () {
    final shapes =
        jsonDecode(File('tools/note_shapes.json').readAsStringSync())
            as Map<String, dynamic>;
    final dart = File('lib/widgets/chat/note_shapes.dart').readAsStringSync();
    for (final id in shapes.keys) {
      expect(dart, contains("id: '$id'"), reason: 'формы разошлись: $id');
    }
    expect(shapes.length, 10);
  });

  test('модель читает все поля из записи', () {
    final src = File('lib/models/chat_msg.dart').readAsStringSync();
    for (final f in noteFields) {
      expect(src, contains("m['$f']"), reason: 'ChatMsg.fromPb не читает $f');
    }
  });
}
