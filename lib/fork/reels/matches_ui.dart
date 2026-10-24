import 'dart:async';
import 'package:flutter/material.dart';
import '../../dict_strings.dart' show ruEn;
import '../../utils/safe_launch.dart';
import '../ui/feedback.dart';
import 'matches.dart';

class ForkReelsMatchesScreen extends StatefulWidget {
  const ForkReelsMatchesScreen({super.key, required this.groupId, this.load});
  final String groupId;
  final Future<List<ForkReelMatch>> Function()? load;
  @override
  State<ForkReelsMatchesScreen> createState() => _ForkReelsMatchesScreenState();
}

class _ForkReelsMatchesScreenState extends State<ForkReelsMatchesScreen> {
  List<ForkReelMatch> _items = [];
  bool _loading = false, _failed = false;
  final _deleting = <String>{};
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items =
          await (widget.load?.call() ??
              ForkReelsMatches.instance.list(widget.groupId));
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ForkReelMatch match) async {
    if (!await safeLaunchString(match.link!.url) && mounted) {
      ForkNotice.failure(
        context,
        ForkFailure.unknown,
        what: ruEn('Открыть ролик', 'Open clip'),
        retry: () => _open(match),
      );
    }
  }

  Future<void> _delete(ForkReelMatch match) async {
    if (_deleting.contains(match.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(ruEn('Удалить совпадение?', 'Delete this match?')),
        content: Text(
          ruEn(
            'Ролик исчезнет из списка у вас обоих.',
            'The clip will disappear from both partners’ lists.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ruEn('Отмена', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ruEn('Удалить', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(match.id));
    try {
      await ForkReelsMatches.instance.remove(match.id);
      if (mounted) {
        setState(() => _items.removeWhere((entry) => entry.id == match.id));
      }
    } catch (error) {
      if (mounted) ForkNotice.failure(context, ForkFailure.of(error));
    } finally {
      if (mounted) setState(() => _deleting.remove(match.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(ruEn('Совпадения в ленте', 'Reel matches'))),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            ruEn(
              'Ролики, на которые вы оба отреагировали одинаково.',
              'Clips you both reacted to in the same way.',
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_failed) ...[
            Text(
              ruEn(
                'Не удалось загрузить совпадения.',
                'Could not load matches.',
              ),
            ),
            TextButton(
              onPressed: _load,
              child: Text(ruEn('Повторить', 'Retry')),
            ),
          ],
          if (!_loading && !_failed && _items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                ruEn(
                  'Пока нет совпадений. Они появятся после общих реакций в ленте.',
                  'No matches yet. React together in the reel feed to save one.',
                ),
              ),
            ),
          for (final item in _items)
            Card(
              child: ListTile(
                isThreeLine: !item.locked,
                title: Text(
                  item.locked
                      ? ruEn('Ролик закрыт', 'Clip is locked')
                      : '${item.reaction} ${item.link!.platform}',
                ),
                subtitle: Text(
                  item.locked
                      ? ruEn(
                          'Нужны ключи пары с другого устройства или из бэкапа.',
                          'Pair keys from another device or a backup are required.',
                        )
                      : '${item.link!.url}\n${item.at == null ? '' : MaterialLocalizations.of(context).formatCompactDate(item.at!.toLocal())}',
                ),
                onTap: item.locked ? null : () => _open(item),
                trailing: item.locked
                    ? null
                    : IconButton(
                        tooltip: ruEn('Удалить совпадение', 'Delete match'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: _deleting.contains(item.id)
                            ? null
                            : () => _delete(item),
                      ),
              ),
            ),
        ],
      ),
    ),
  );
}
