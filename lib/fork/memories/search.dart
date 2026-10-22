/// Поиск по ленте воспоминаний (docs/fork/UX_AUDIT.md, D10): кроме названия,
/// подписи, места и автора ищем по песням, книгам и фильмам.
library;

import '../../models/memory.dart';

/// Текстовые поля записи, по которым ищет строка поиска.
List<String?> memorySearchFields(Memory m) => [
  m.title,
  m.caption,
  m.locationName,
  m.authorName,
  // песни
  m.musicTitle,
  m.musicArtist,
  // книги
  m.bookAuthor,
  m.bookPublisher,
  m.bookYear,
  // фильмы и сериалы
  m.movieOriginalTitle,
  m.movieGenres,
  m.movieCountry,
  m.movieYear,
];

/// Подходит ли запись под [query] (уже в нижнем регистре и без пробелов по
/// краям). Пустой запрос пропускает всё.
bool memoryMatchesQuery(Memory m, String query) {
  if (query.isEmpty) return true;
  for (final field in memorySearchFields(m)) {
    if ((field ?? '').toLowerCase().contains(query)) return true;
  }
  return false;
}
