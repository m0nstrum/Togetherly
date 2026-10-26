import 'dart:convert';
import 'dart:io';

/// Поля коллекции в схеме сервера форка после всех миграций — снимок
/// `server/internal/migrations/testdata/fields.json` (его сверяет Go-тест
/// TestFieldsSnapshot). PocketBase молча выбрасывает поле, которого нет в
/// схеме: ответ 200, запись без поля.
Set<String> forkFields(String collection) {
  final raw = File(
    'server/internal/migrations/testdata/fields.json',
  ).readAsStringSync();
  final all = jsonDecode(raw) as Map<String, dynamic>;
  final fields = all[collection] as List?;
  if (fields == null) throw StateError('нет коллекции $collection в схеме');
  return fields.cast<String>().toSet();
}
