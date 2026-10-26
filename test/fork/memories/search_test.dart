import 'package:flutter_test/flutter_test.dart';
import 'package:love_app/fork/memories/search.dart';
import 'package:love_app/models/memory.dart';

Memory _m(
  MemoryType type, {
  String? musicArtist,
  String? bookAuthor,
  String? movieGenres,
  String? title,
}) => Memory(
  id: '1',
  groupId: 'g',
  authorUid: 'u',
  authorName: 'Аня',
  type: type,
  createdAt: DateTime(2026),
  title: title,
  musicArtist: musicArtist,
  bookAuthor: bookAuthor,
  movieGenres: movieGenres,
);

void main() {
  test('находит песню по исполнителю', () {
    expect(
      memoryMatchesQuery(_m(MemoryType.music, musicArtist: 'Земфира'), 'земф'),
      isTrue,
    );
  });
  test('находит книгу по автору', () {
    expect(
      memoryMatchesQuery(_m(MemoryType.book, bookAuthor: 'Булгаков'), 'булг'),
      isTrue,
    );
  });
  test('находит фильм по жанру', () {
    expect(
      memoryMatchesQuery(
        _m(MemoryType.movie, movieGenres: 'драма, мелодрама'),
        'мелодр',
      ),
      isTrue,
    );
  });
  test('пустой запрос пропускает всё, чужой — нет', () {
    final m = _m(MemoryType.text, title: 'Пикник');
    expect(memoryMatchesQuery(m, ''), isTrue);
    expect(memoryMatchesQuery(m, 'кино'), isFalse);
  });
}
