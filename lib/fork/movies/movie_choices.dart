/// Shared movie deck with one encrypted, independently writable vote per person.
library;

import 'dart:async';
import 'dart:convert';
import 'package:pocketbase/pocketbase.dart';
import '../../services/centrifugo_service.dart';
import '../../services/movie_search_service.dart';
import '../../services/pocketbase_service.dart';
import '../e2e/crypto.dart' show utf8Bytes;
import '../e2e/e2e_service.dart' show PairE2EStatus;
import '../e2e/fork_e2e.dart';
import '../e2e/record_codec.dart';

String? _text(Object? value, int max) =>
    value is String && value.trim().isNotEmpty
    ? String.fromCharCodes(value.trim().runes.take(max))
    : null;
String? _https(Object? value, {bool info = false}) {
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return null;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (info && !{'kinopoisk.ru', 'imdb.com', 'wikidata.org'}.contains(host)) {
    return null;
  }
  return info
      ? Uri.https(host, uri.path.replaceFirst(RegExp(r'/+$'), '')).toString()
      : uri.toString().split('#').first;
}

class ForkMovieCard {
  ForkMovieCard._(Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  String get title => data['title'] as String;
  String get original => data['original'] as String? ?? '';
  String get year => data['year'] as String? ?? '';
  String get description => data['description'] as String? ?? '';
  String get genres => data['genres'] as String? ?? '';
  String? get poster => data['poster'] as String?;
  String? get info => data['info'] as String?;
  String get key {
    final id = data['id'] as int;
    if (id > 0) return 'kp:$id';
    if (info != null) return 'url:$info';
    return 'title:${jsonEncode([title.toLowerCase(), year, data['kind']])}';
  }

  factory ForkMovieCard.fromResult(MovieResult result) =>
      ForkMovieCard.fromJson({
        'id': result.id,
        'title': result.title,
        'original': result.originalTitle,
        'year': result.year,
        'kind': result.kind,
        'genres': result.genres,
        'poster': result.posterUrl,
        'info': result.infoUrl,
        'description': result.description,
      })!;
  static ForkMovieCard? fromJson(Object? value) {
    if (value is! Map) return null;
    final title = _text(value['title'], 300), id = value['id'];
    if (title == null || id is! int || id < 0) return null;
    return ForkMovieCard._({
      'id': id,
      'title': title,
      'kind': _text(value['kind'], 30) ?? 'movie',
      'original': _text(value['original'], 300),
      'year': _text(value['year'], 30),
      'genres': _text(value['genres'], 300),
      'description': _text(value['description'], 3000),
      'poster': _https(value['poster']),
      'info': _https(value['info'], info: true),
    });
  }
}

class ForkMovieChoice {
  const ForkMovieChoice({
    required this.id,
    required this.author,
    required this.tag,
    required this.movie,
    required this.vote,
    this.created,
  });
  final String id, author, tag;
  final ForkMovieCard movie;
  final bool? vote;
  final DateTime? created;
  static ForkMovieChoice? parse(RecordModel record) {
    final state = record.data['state'];
    final author = record.data['author_uid'], group = record.data['group_id'];
    if (author is! String ||
        author.isEmpty ||
        group is! String ||
        group.isEmpty) {
      return null;
    }
    if (state is! Map ||
        state['by'] != record.data['author_uid'] ||
        state['group'] != record.data['group_id']) {
      return null;
    }
    final movie = ForkMovieCard.fromJson(state['movie']);
    if (movie == null ||
        state['key'] != movie.key ||
        state['vote'] is! int ||
        !{0, 1, 2}.contains(state['vote'])) {
      return null;
    }
    return ForkMovieChoice(
      id: record.id,
      author: record.getStringValue('author_uid'),
      tag: record.getStringValue('movie_tag'),
      movie: movie,
      vote: state['vote'] == 0 ? null : state['vote'] == 1,
      created: DateTime.tryParse(record.getStringValue('created')),
    );
  }
}

class ForkMoviePicks {
  ForkMoviePicks(List<ForkMovieChoice> choices, this.me, this.partner) {
    for (final choice in choices) {
      if (choice.author != me && choice.author != partner) continue;
      final key = choice.movie.key;
      movies.putIfAbsent(key, () => choice.movie);
      // The repository returns newest updates first; preserve that decision.
      votes
          .putIfAbsent(key, () => {})
          .putIfAbsent(choice.author, () => choice.vote);
      final at = choice.created?.millisecondsSinceEpoch ?? 0;
      if (!first.containsKey(key) || at < first[key]!) first[key] = at;
    }
  }
  final String me, partner;
  final movies = <String, ForkMovieCard>{};
  final votes = <String, Map<String, bool?>>{};
  final first = <String, int>{};
  List<ForkMovieCard> get all => movies.values.toList()
    ..sort(
      (a, b) => (first[a.key] ?? 0).compareTo(first[b.key] ?? 0) != 0
          ? (first[a.key] ?? 0).compareTo(first[b.key] ?? 0)
          : a.key.compareTo(b.key),
    );
  List<ForkMovieCard> get pending =>
      all.where((movie) => votes[movie.key]?[me] == null).toList();
  List<ForkMovieCard> get matches => all
      .where(
        (movie) =>
            votes[movie.key]?[me] == true && votes[movie.key]?[partner] == true,
      )
      .toList();
}

abstract interface class ForkMovieRepository {
  Future<List<ForkMovieChoice?>> list(String group);
  Future<ForkMovieChoice> propose(String group, ForkMovieCard movie);
  Future<ForkMovieChoice> vote(String group, ForkMovieCard movie, bool? value);
  Stream<void> watch(String group);
}

class ForkMovieChoices implements ForkMovieRepository {
  ForkMovieChoices({
    required this.pb,
    required this.codec,
    required this.uid,
    required this.canWrite,
  });
  final PocketBase pb;
  final Future<RecordCodec?> Function() codec;
  final String Function() uid;
  final bool Function(String) canWrite;
  static const collection = 'fork_movie_choices';
  static final instance = ForkMovieChoices(
    pb: PocketBaseService().pb,
    codec: ForkE2E.codec,
    uid: () => PocketBaseService().userId ?? '',
    canWrite: (group) => {
      PairE2EStatus.verified,
      PairE2EStatus.unverified,
    }.contains(ForkE2E.service.value?.status.value[group]),
  );

  @override
  Future<List<ForkMovieChoice?>> list(String group) async =>
      (await pb
              .collection(collection)
              .getFullList(
                filter: pb.filter('group_id = {:group}', {'group': group}),
                sort: '-updated',
              ))
          .map(ForkMovieChoice.parse)
          .toList();
  @override
  Future<ForkMovieChoice> propose(String group, ForkMovieCard movie) =>
      _write(group, movie, null, proposing: true);
  @override
  Future<ForkMovieChoice> vote(
    String group,
    ForkMovieCard movie,
    bool? value,
  ) => _write(group, movie, value);
  Future<ForkMovieChoice> _write(
    String group,
    ForkMovieCard movie,
    bool? value, {
    bool proposing = false,
  }) async {
    final me = uid();
    final c = await codec();
    final key = c?.keys.currentKey(group);
    if (me.isEmpty || !canWrite(group) || c?.crypto == null || key == null) {
      throw E2ENoKeyError(collection);
    }
    final choices = await list(group);
    ForkMovieChoice? mine;
    for (final choice in choices) {
      if (choice?.author == me && choice?.movie.key == movie.key) {
        mine = choice;
        break;
      }
    }
    if (uid() != me || !canWrite(group)) throw StateError('Session changed');
    if (proposing && mine != null) return mine;
    final tag =
        mine?.tag ??
        c!.crypto!
            .hash(
              utf8Bytes('movie-choice-v1/$group/${movie.key}'),
              key: key.key,
            )
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
    Map<String, dynamic> body(String tag) => {
      'group_id': group,
      'author_uid': me,
      'movie_tag': tag,
      'state': {
        'by': me,
        'group': group,
        'key': movie.key,
        'movie': movie.data,
        // One digit in every state: ciphertext length must not reveal no vs yes.
        'vote': value == null
            ? 0
            : value
            ? 1
            : 2,
      },
    };
    RecordModel saved;
    if (mine != null) {
      saved = await pb
          .collection(collection)
          .update(mine.id, body: body(mine.tag));
    } else {
      try {
        saved = await pb.collection(collection).create(body: body(tag));
      } on ClientException catch (error) {
        if (error.statusCode != 400) rethrow;
        final existing = (await list(group))
            .whereType<ForkMovieChoice>()
            .where(
              (choice) => choice.author == me && choice.movie.key == movie.key,
            )
            .toList();
        if (existing.isEmpty) rethrow;
        if (proposing) return existing.first;
        if (uid() != me || !canWrite(group)) {
          throw StateError('Session changed');
        }
        saved = await pb
            .collection(collection)
            .update(existing.first.id, body: body(existing.first.tag));
      }
    }
    return ForkMovieChoice.parse(saved) ??
        (throw StateError('Unreadable choice response'));
  }

  @override
  Stream<void> watch(String group) async* {
    final events = StreamController<void>();
    final unsub = await CentrifugoService.instance.subscribeDelta(
      'pair:$group',
      collection,
      (_) => events.add(null),
    );
    final reconnect = CentrifugoService.instance.reconnected.listen(
      (_) => events.add(null),
    );
    try {
      yield* events.stream;
    } finally {
      await unsub();
      await reconnect.cancel();
      await events.close();
    }
  }
}
