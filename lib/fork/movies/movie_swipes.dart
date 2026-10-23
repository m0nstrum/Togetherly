import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../dict_strings.dart' show ruEn;
import '../../services/movie_search_service.dart';
import '../../utils/safe_launch.dart';
import '../ui/feedback.dart';
import 'movie_choices.dart';

class ForkMovieSwipesScreen extends StatefulWidget {
  const ForkMovieSwipesScreen({
    super.key,
    required this.groupId,
    required this.myUid,
    required this.partnerUid,
    this.repository,
    this.search,
  });
  final String groupId, myUid, partnerUid;
  final ForkMovieRepository? repository;
  final Future<List<MovieResult>> Function(String)? search;
  @override
  State<ForkMovieSwipesScreen> createState() => _ForkMovieSwipesScreenState();
}

class _ForkMovieSwipesScreenState extends State<ForkMovieSwipesScreen> {
  late final repo = widget.repository ?? ForkMovieChoices.instance;
  final _query = TextEditingController();
  StreamSubscription<void>? _events;
  List<ForkMovieChoice?> _rows = [];
  List<MovieResult> _results = [];
  Future<void>? _refreshing;
  bool _again = false, _loading = false, _failed = false, _busy = false;
  bool _searching = false, _searchFailed = false, _searched = false;
  final _adding = <String>{};
  ForkMovieCard? _undo;
  double _drag = 0;
  int _writeRevision = 0;
  bool _readOnce = false;
  Set<String> _knownMatches = {};
  ForkMoviePicks get _picks => ForkMoviePicks(
    _rows.whereType<ForkMovieChoice>().toList(),
    widget.myUid,
    widget.partnerUid,
  );
  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _events = repo
        .watch(widget.groupId)
        .listen(
          (_) => unawaited(_refresh()),
          onError: (Object _) {
            if (mounted) setState(() => _failed = true);
          },
        );
  }

  @override
  void dispose() {
    unawaited(_events?.cancel());
    _query.dispose();
    super.dispose();
  }

  Future<void> _refresh() {
    if (_refreshing != null) {
      _again = true;
      return _refreshing!;
    }
    final future = _read();
    _refreshing = future;
    unawaited(
      future.then((_) {
        if (identical(_refreshing, future)) _refreshing = null;
      }),
    );
    return future;
  }

  Future<void> _read() async {
    if (!mounted) return;
    setState(() => _loading = true);
    do {
      _again = false;
      try {
        final revision = _writeRevision;
        final rows = await repo.list(widget.groupId);
        if (revision != _writeRevision) {
          _again = true;
          continue;
        }
        if (mounted) {
          setState(() {
            _rows = rows;
            _failed = false;
          });
          _announceMatches();
        }
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
    } while (_again && mounted);
    if (mounted) setState(() => _loading = false);
  }

  void _accept(ForkMovieChoice saved) {
    _writeRevision++;
    setState(() {
      _rows.removeWhere(
        (choice) =>
            choice?.id == saved.id ||
            (choice?.author == saved.author &&
                choice?.movie.key == saved.movie.key),
      );
      _rows.insert(0, saved);
      _drag = 0;
    });
    _announceMatches();
  }

  void _announceMatches() {
    final matches = _picks.matches;
    final fresh = matches
        .where((movie) => !_knownMatches.contains(movie.key))
        .toList();
    _knownMatches = matches.map((movie) => movie.key).toSet();
    if (_readOnce && fresh.isNotEmpty) {
      unawaited(HapticFeedback.mediumImpact().catchError((Object _) {}));
      ForkNotice.info(
        context,
        ruEn(
          'Совпало: ${fresh.first.title}',
          'It’s a match: ${fresh.first.title}',
        ),
      );
    }
    _readOnce = true;
  }

  Future<void> _vote(ForkMovieCard movie, bool? value) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _drag = 0;
    });
    try {
      final saved = await repo.vote(widget.groupId, movie, value);
      if (!mounted) return;
      _accept(saved);
      setState(() => _undo = value == null ? null : movie);
    } catch (error) {
      if (mounted) {
        ForkNotice.error(context, error, retry: () => _vote(movie, value));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _propose(MovieResult result) async {
    final movie = ForkMovieCard.fromResult(result);
    if (_adding.contains(movie.key)) return;
    setState(() => _adding.add(movie.key));
    try {
      final saved = await repo.propose(widget.groupId, movie);
      if (mounted) {
        _accept(saved);
        ForkNotice.info(context, ruEn('В общей колоде', 'In your shared deck'));
      }
    } catch (error) {
      if (mounted) {
        ForkNotice.error(context, error, retry: () => _propose(result));
      }
    } finally {
      if (mounted) setState(() => _adding.remove(movie.key));
    }
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (_searching || query.length < 2) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchFailed = false;
      _searched = false;
      _results = [];
    });
    try {
      final results = await (widget.search ?? MovieSearchService.search)(query);
      if (mounted && _query.text.trim() == query) {
        setState(() {
          _results = results;
          _searched = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searchFailed = true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _info(ForkMovieCard movie) async {
    if (!await safeLaunchString(movie.info) && mounted) {
      ForkNotice.failure(context, ForkFailure.unknown);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight: (MediaQuery.textScalerOf(context).scale(20) * 2.4 + 12)
            .clamp(56, double.infinity),
        title: Text(
          ruEn('Что посмотрим?', 'What shall we watch?'),
          maxLines: 2,
        ),
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(
              key: const ValueKey('movies-deck-tab'),
              text: ruEn('Выбор', 'Swipe'),
            ),
            Tab(
              key: const ValueKey('movies-search-tab'),
              text: ruEn('Добавить', 'Add films'),
            ),
            Tab(
              text: ruEn(
                'Совпало · ${_picks.matches.length}',
                'Matches · ${_picks.matches.length}',
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: TabBarView(children: [_deck(), _find(), _matches()])),
        ],
      ),
    ),
  );
  Widget _status() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_failed)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              ruEn(
                'Не удалось обновить колоду.',
                'Could not refresh the deck.',
              ),
            ),
            TextButton(
              onPressed: _refresh,
              child: Text(ruEn('Повторить', 'Retry')),
            ),
          ],
        ),
      if (_rows.any((row) => row == null))
        Text(
          ruEn(
            'Часть карточек закрыта. Нужны ключи пары с другого устройства или из бэкапа.',
            'Some cards are locked. Pair keys from another device or a backup are required.',
          ),
        ),
    ],
  );
  Widget _deck() {
    final pending = _picks.pending;
    final movie = pending.isEmpty ? null : pending.first;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _status(),
            Text(
              ruEn(
                'Вправо — хочу смотреть, влево — не сейчас. Выбор увидите в совпадениях, когда он общий.',
                'Swipe right to watch, left for not now. Two yes votes appear in Matches.',
              ),
            ),
            const SizedBox(height: 12),
            if (movie == null && !_loading && !_failed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  _picks.all.isEmpty
                      ? ruEn(
                          'Добавьте фильмы в общую колоду на вкладке «Добавить».',
                          'Add films to your shared deck in the Add films tab.',
                        )
                      : ruEn(
                          'Вы оценили все карточки. Общие «да» будут на вкладке «Совпало».',
                          'You rated every card. Mutual yes votes appear in Matches.',
                        ),
                ),
              ),
            if (movie != null) ...[
              GestureDetector(
                key: ValueKey(movie.key),
                onHorizontalDragUpdate: _busy
                    ? null
                    : (event) => setState(() => _drag += event.delta.dx),
                onHorizontalDragCancel: () => setState(() => _drag = 0),
                onHorizontalDragEnd: _busy
                    ? null
                    : (_) {
                        if (_drag.abs() >= 70) {
                          unawaited(_vote(movie, _drag > 0));
                        } else {
                          setState(() => _drag = 0);
                        }
                      },
                child: Transform.translate(
                  offset: Offset(_drag.clamp(-70, 70), 0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (movie.poster != null)
                            SizedBox(
                              height: 180,
                              child: Image.network(
                                movie.poster!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.movie_outlined, size: 64),
                              ),
                            ),
                          Text(
                            movie.title,
                            key: const ValueKey('movie-card-title'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (movie.original.isNotEmpty &&
                              movie.original != movie.title)
                            Text(movie.original),
                          Text(
                            [
                              movie.year,
                              movie.genres,
                            ].where((value) => value.isNotEmpty).join(' · '),
                          ),
                          if (movie.description.isNotEmpty)
                            Text(
                              movie.description,
                              maxLines: 8,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (movie.info != null)
                            TextButton(
                              onPressed: () => _info(movie),
                              child: Text(ruEn('О фильме', 'About the film')),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('movie-no'),
                    onPressed: _busy ? null : () => _vote(movie, false),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(ruEn('Не сейчас', 'Not now')),
                  ),
                  FilledButton.icon(
                    key: const ValueKey('movie-yes'),
                    onPressed: _busy ? null : () => _vote(movie, true),
                    icon: const Icon(Icons.favorite_rounded),
                    label: Text(ruEn('Хочу смотреть', 'Want to watch')),
                  ),
                ],
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            TextButton.icon(
              key: const ValueKey('movie-undo'),
              onPressed: _busy || _undo == null
                  ? null
                  : () => _vote(_undo!, null),
              icon: const Icon(Icons.undo_rounded),
              label: Text(ruEn('Отменить последний выбор', 'Undo last choice')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _find() => ListView(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _status(),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: ruEn(
              'Название фильма или сериала',
              'Film or series title',
            ),
            suffixIcon: IconButton(
              tooltip: ruEn('Найти', 'Search'),
              onPressed: _searching ? null : _search,
              icon: const Icon(Icons.search_rounded),
            ),
          ),
        ),
      ),
      if (_searching) const LinearProgressIndicator(),
      if (_searchFailed)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                ruEn(
                  'Поиск недоступен. Проверьте связь и попробуйте позже.',
                  'Search is unavailable. Check your connection and try later.',
                ),
              ),
              TextButton(
                onPressed: _search,
                child: Text(ruEn('Повторить', 'Retry')),
              ),
            ],
          ),
        ),
      if (_searched && _results.isEmpty)
        Text(ruEn('Ничего не найдено', 'No films found')),
      ...[
        for (final result in _results)
          ListTile(
            title: Text(result.title),
            subtitle: Text(result.year ?? ''),
            trailing: IconButton(
              tooltip: ruEn('Добавить в общую колоду', 'Add to shared deck'),
              onPressed: _adding.contains(ForkMovieCard.fromResult(result).key)
                  ? null
                  : () => _propose(result),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
      ],
    ],
  );
  Widget _matches() => RefreshIndicator(
    onRefresh: _refresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _status(),
        if (_picks.matches.isEmpty && !_loading && !_failed)
          Text(
            ruEn(
              'Пока нет общих «Хочу смотреть». Выбирайте фильмы независимо друг от друга.',
              'No mutual yes votes yet. Choose films independently.',
            ),
          ),
        for (final movie in _picks.matches)
          Card(
            child: ListTile(
              leading: const Icon(Icons.favorite_rounded),
              title: Text(movie.title),
              subtitle: Text(movie.year),
              onTap: movie.info == null ? null : () => _info(movie),
            ),
          ),
      ],
    ),
  );
}
