/// Выбор видео прямо из комнаты (комната как в Rave, 22.10).
///
/// Раньше в комнате было одно поле ссылки внизу страницы и «Включить»: что
/// туда вставлять и откуда взять ролик, не объяснялось, а недавнее и свои
/// ролики жили на другом экране — до них надо было выйти из комнаты. Теперь
/// кнопка «Выбрать видео» открывает лист: ссылка из буфера одной кнопкой,
/// поле со списком площадок, недавнее пары, свои ролики и файл с телефона.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard;

import '../../dict_strings.dart' show ruEn;
import '../../services/watch_history_service.dart';
import '../../services/watch_videos_service.dart';
import '../../widgets/app_sheet.dart';

/// Что выбрали: ссылку или «свой файл» (его выбирают на странице — окно
/// выбора файла открывается только из касания по ней самой).
@immutable
class ForkRoomPick {
  const ForkRoomPick.url(this.url) : file = false;
  const ForkRoomPick.file() : url = '', file = true;

  final String url;
  final bool file;
}

/// Похожа ли строка на ссылку, которую комната включит. Список площадок —
/// как в `parseSource` страницы (room.js); строже не нужно: окончательный
/// ответ всё равно даёт страница.
bool forkRoomPlayable(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return false;
  final m = RegExp(
    r'(https?://\S+)|((?:[a-z0-9-]+\.)+[a-z]{2,}/\S*)',
    caseSensitive: false,
  ).firstMatch(s);
  if (m == null) return false;
  final link = m.group(1) ?? 'https://${m.group(2)}';
  final uri = Uri.tryParse(link);
  if (uri == null || uri.host.isEmpty) return false;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  bool ends(String d) => host == d || host.endsWith('.$d');
  if (ends('youtu.be') || ends('youtube.com') || ends('vimeo.com')) return true;
  if (ends('vk.com') || ends('vkvideo.ru') || ends('rutube.ru')) return true;
  if (ends('disk.yandex.ru') || ends('disk.yandex.com') || host == 'yadi.sk')
    return true;
  if (ends('dropbox.com') || host == 'mega.nz' || host == 'mega.io')
    return true;
  if (host == 'drive.google.com') return true;
  return RegExp(
    r'\.(mp4|m4v|webm|ogv|ogg|mov)$',
    caseSensitive: false,
  ).hasMatch(uri.path);
}

/// Первая ссылка из текста — то, что уйдёт странице.
String forkRoomLinkOf(String raw) {
  final m = RegExp(
    r'https?://\S+',
    caseSensitive: false,
  ).firstMatch(raw.trim());
  return m?.group(0) ?? raw.trim();
}

const String forkRoomSources =
    'YouTube · VK Видео · Rutube · Vimeo · Яндекс Диск · Google Диск · Dropbox · MEGA';

Future<ForkRoomPick?> showForkRoomPicker(
  BuildContext context, {
  required String groupId,
  String initial = '',
}) => showAppSheet<ForkRoomPick>(
  context,
  expand: true,
  builder: (_) => ForkRoomPicker(groupId: groupId, initial: initial),
);

class ForkRoomPicker extends StatefulWidget {
  const ForkRoomPicker({
    super.key,
    required this.groupId,
    this.initial = '',
    @visibleForTesting this.recent,
    @visibleForTesting this.uploaded,
    @visibleForTesting this.clipboard,
  });

  final String groupId;
  final String initial;

  /// Подмена источников в тестах.
  final Future<List<WatchEntry>> Function()? recent;
  final Future<List<WatchVideo>> Function()? uploaded;
  final Future<String> Function()? clipboard;

  @override
  State<ForkRoomPicker> createState() => _ForkRoomPickerState();
}

class _ForkRoomPickerState extends State<ForkRoomPicker> {
  late final TextEditingController _link = TextEditingController(
    text: widget.initial,
  );
  String _clip = '';
  bool _bad = false;
  List<WatchEntry> _recent = const [];
  List<WatchVideo> _mine = const [];
  bool _loading = true;
  bool _recentFailed = false;
  bool _mineFailed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _recentFailed = false;
      _mineFailed = false;
    });
    final clip = _readClip();
    final recent = _guard(
      widget.recent ?? () => WatchHistoryService.recent(widget.groupId),
      () => _recentFailed = true,
    );
    final mine = _guard(
      widget.uploaded ?? () => WatchVideosService.uploaded(widget.groupId),
      () => _mineFailed = true,
    );
    final c = await clip;
    final r = await recent;
    final m = await mine;
    if (!mounted) return;
    setState(() {
      _clip = forkRoomPlayable(c) ? forkRoomLinkOf(c) : '';
      // Свой файл ссылкой не открыть, а защищённые ролики играют только
      // отдельным плеером — в комнату их не включить.
      _recent = r
          .where((e) => !e.url.startsWith('file://') && forkRoomPlayable(e.url))
          .toList();
      _mine = m
          .where((v) => !v.appOnly && WatchVideosService.playsInRoom(v.url))
          .toList();
      _loading = false;
    });
  }

  Future<String> _readClip() async {
    try {
      if (widget.clipboard != null) return await widget.clipboard!();
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      return d?.text ?? '';
    } catch (_) {
      return ''; // тихо: буфер недоступен — просто нет подсказки
    }
  }

  Future<List<T>> _guard<T>(
    Future<List<T>> Function() f,
    VoidCallback failed,
  ) async {
    try {
      return await f();
    } catch (_) {
      failed();
      return const [];
    }
  }

  Widget _listError(String title) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(
      ruEn('Не удалось загрузить список', 'Could not load the list'),
    ),
    trailing: TextButton(
      onPressed: _load,
      child: Text(ruEn('Повторить', 'Retry')),
    ),
  );

  void _submit() {
    final text = _link.text.trim();
    if (!forkRoomPlayable(text)) {
      setState(() => _bad = true);
      return;
    }
    Navigator.of(context).pop(ForkRoomPick.url(forkRoomLinkOf(text)));
  }

  void _pick(String url) => Navigator.of(context).pop(ForkRoomPick.url(url));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SheetScaffold(
      title: ruEn('Что смотрим?', 'What are we watching?'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          if (_clip.isNotEmpty) ...[
            Card(
              margin: EdgeInsets.zero,
              color: cs.primaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.content_paste_rounded,
                  color: cs.onPrimaryContainer,
                ),
                title: Text(
                  ruEn('Включить ссылку из буфера', 'Play the copied link'),
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  _clip,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onPrimaryContainer.withValues(alpha: .8),
                  ),
                ),
                onTap: () => _pick(_clip),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            autocorrect: false,
            onChanged: (_) {
              if (_bad) setState(() => _bad = false);
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: ruEn('Ссылка на видео', 'Video link'),
              hintText: 'https://youtu.be/…',
              helperText: _bad ? null : forkRoomSources,
              helperMaxLines: 2,
              errorText: _bad
                  ? ruEn(
                      'Такую ссылку комната не откроет. Подходят: $forkRoomSources и прямые ссылки на файл',
                      'The room can’t open this link. Works with: $forkRoomSources and direct file links',
                    )
                  : null,
              errorMaxLines: 3,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: ruEn('Включить', 'Play'),
                icon: const Icon(Icons.play_arrow_rounded),
                onPressed: _submit,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: cs.secondaryContainer,
              child: Icon(
                Icons.folder_open_rounded,
                color: cs.onSecondaryContainer,
              ),
            ),
            title: Text(ruEn('Файл с телефона', 'A file from your phone')),
            subtitle: Text(
              ruEn(
                'Играет у вас; партнёр откроет такой же файл у себя',
                'Plays on your phone; your partner opens the same file',
              ),
            ),
            onTap: () => Navigator.of(context).pop(const ForkRoomPick.file()),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && _mineFailed)
            _listError(ruEn('Ваши ролики', 'Your videos')),
          if (!_loading && _recentFailed)
            _listError(ruEn('Недавнее', 'Recent')),
          if (_mine.isNotEmpty) ...[
            _Head(ruEn('Ваши ролики', 'Your videos'), tt),
            for (final v in _mine)
              _Row(
                title: v.title.isEmpty
                    ? ruEn('Без названия', 'Untitled')
                    : v.title,
                thumb: v.thumbUrl,
                icon: Icons.video_library_rounded,
                onTap: () => _pick(v.url),
              ),
          ],
          if (_recent.isNotEmpty) ...[
            _Head(ruEn('Недавнее', 'Recent'), tt),
            for (final e in _recent)
              _Row(
                title: e.title.isEmpty ? e.url : e.title,
                subtitle: e.title.isEmpty
                    ? ''
                    : (Uri.tryParse(e.url)?.host ?? ''),
                thumb: e.thumb,
                icon: Icons.history_rounded,
                onTap: () => _pick(e.url),
              ),
          ],
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text, this.tt);
  final String text;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 6),
    child: Text(text, style: tt.titleSmall),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle = '',
    this.thumb = '',
  });

  final String title;
  final String subtitle;
  final String thumb;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, color: cs.onSurfaceVariant),
    );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 72,
          height: 44,
          child: thumb.startsWith('http')
              ? Image.network(
                  thumb,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.play_circle_outline_rounded),
    );
  }
}
