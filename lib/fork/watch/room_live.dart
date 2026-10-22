/// Что происходит в комнате — словами (комната как в Rave, 22.10).
///
/// Страница комнаты в приложении — только окно видео. О каждом действии она
/// сообщает мостом `forkRoom` (pocketbase/pb_public/watch/room/room.js,
/// `forkReport`), а здесь события становятся состоянием для полосы «что
/// играет» и строками в ленте чата: «Аня — пауза на 12:34». Раньше кадр
/// просто замирал или менялся, и было не понять, кто и что сделал.
library;

import 'package:flutter/foundation.dart';

import '../../dict_strings.dart' show ruEn;

/// Строка-событие в ленте чата.
@immutable
class ForkRoomLine {
  const ForkRoomLine({
    required this.at,
    required this.text,
    required this.kind,
    this.mine = false,
  });

  /// Когда, мс от эпохи — по нему строки встают между репликами.
  final int at;
  final String text;

  /// play, pause, seek, source, here, gone, countdown.
  final String kind;
  final bool mine;
}

class ForkRoomLive extends ChangeNotifier {
  ForkRoomLive({required this.partnerName, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// Имя партнёра на момент события (пара может догрузиться позже).
  final String Function() partnerName;
  final DateTime Function() _now;

  /// Сколько людей в канале комнаты (вместе со мной).
  int viewers = 1;
  bool get partnerHere => viewers > 1;

  /// Что играет: площадка ('YouTube', 'Ваш файл'), название, кто включил.
  String kind = '';
  String label = '';
  String title = '';
  String url = '';
  bool get hasVideo => kind.isNotEmpty;

  bool playing = false;

  /// Последняя позиция из события, секунды.
  double at = 0;

  /// Плеер без управления (Google Диск, MEGA): нужны кнопки отсчёта.
  bool manual = false;

  /// Связи нет: offline или lost.
  bool offline = false;

  /// Спокойная строка статуса страницы: «Играет: YouTube».
  String status = '';

  /// Сказать вслух (отказ ссылки, промах перемотки) — экран покажет и
  /// обнулит; [noticeSeq] растёт с каждым новым.
  String notice = '';
  int noticeSeq = 0;

  /// Страница просит открыть выбор видео (кнопка в пустом окне).
  int pickSeq = 0;

  /// Плеер просит полный экран.
  int fullscreenSeq = 0;

  final List<ForkRoomLine> lines = [];
  static const int linesLimit = 80;

  String get _partner {
    final n = partnerName().trim();
    return n.isEmpty ? ruEn('Партнёр', 'Partner') : n;
  }

  /// Одно событие страницы.
  void handle(Map<String, dynamic> e) {
    final t = '${e['t'] ?? ''}';
    switch (t) {
      case 'viewers':
        final n = (e['n'] as num?)?.toInt() ?? 1;
        viewers = n < 1 ? 1 : n;
      case 'presence':
        final here = e['here'] == true;
        _line(
          here ? 'here' : 'gone',
          here
              ? ruEn('$_partner в комнате', '$_partner joined')
              : ruEn('$_partner вышел(а) из комнаты', '$_partner left the room'),
        );
      case 'source':
        _source(e);
      case 'title':
        title = '${e['title'] ?? ''}'.trim();
      case 'act':
        _act(e);
      case 'status':
        final text = '${e['text'] ?? ''}'.trim();
        if (e['loud'] == true) {
          if (text.isNotEmpty) {
            notice = text;
            noticeSeq++;
          }
        } else {
          status = text;
        }
      case 'manual':
        manual = e['on'] == true;
      case 'net':
        final k = '${e['kind'] ?? ''}';
        offline = k == 'offline' || k == 'lost';
      case 'pick':
        pickSeq++;
      case 'fullscreen':
        fullscreenSeq++;
      default:
        return;
    }
    notifyListeners();
  }

  void _source(Map<String, dynamic> e) {
    final by = '${e['by'] ?? ''}';
    kind = '${e['kind'] ?? ''}';
    label = '${e['label'] ?? ''}'.trim();
    url = '${e['url'] ?? ''}';
    title = '';
    playing = false;
    at = 0;
    final what = label.isEmpty ? ruEn('видео', 'a video') : label;
    final text = switch (by) {
      'me' => ruEn('Вы включили: $what', 'You started: $what'),
      'room' => ruEn('Вы присоединились — идёт $what', 'You joined — $what is on'),
      _ => kind == 'file'
          ? ruEn('$_partner включает свой файл «$what» — откройте такой же у себя',
              '$_partner plays their file “$what” — open the same one')
          : ruEn('$_partner включает: $what', '$_partner started: $what'),
    };
    _line('source', text, mine: by == 'me');
  }

  void _act(Map<String, dynamic> e) {
    final act = '${e['act'] ?? ''}';
    final mine = e['by'] == 'me';
    final who = mine ? ruEn('Вы', 'You') : _partner;
    final pos = (e['at'] as num?)?.toDouble();
    if (e['playing'] is bool) playing = e['playing'] as bool;
    if (pos != null) at = pos;
    final c = clock(at);
    final text = switch (act) {
      'play' => ruEn('$who — воспроизведение с $c', '$who — playing from $c'),
      'pause' => ruEn('$who — пауза на $c', '$who — paused at $c'),
      'seek' => ruEn('$who — перемотка на $c', '$who — jumped to $c'),
      'countdown' => ruEn('$who — отсчёт 3·2·1, жмите вместе', '$who — countdown 3·2·1, press together'),
      'pauseNow' => ruEn('$who — пауза у обоих', '$who — pause for both'),
      _ => '',
    };
    if (text.isEmpty) return;
    _line(act, text, mine: mine, merge: true);
  }

  /// Перемотка и «играть» сразу за ней — одно действие, а не две строки.
  static const mergeWindow = Duration(milliseconds: 2500);

  void _line(String kind, String text, {bool mine = false, bool merge = false}) {
    final now = _now().millisecondsSinceEpoch;
    final line = ForkRoomLine(at: now, text: text, kind: kind, mine: mine);
    if (merge && lines.isNotEmpty) {
      final last = lines.last;
      final acts = const {'play', 'pause', 'seek'};
      if (acts.contains(last.kind) &&
          acts.contains(kind) &&
          last.mine == mine &&
          now - last.at < mergeWindow.inMilliseconds) {
        // «перемотка на 12:34» важнее следующего за ней «играет».
        final keep = last.kind == 'seek' && kind == 'play'
            ? ForkRoomLine(at: now, text: last.text, kind: 'seek', mine: mine)
            : line;
        lines[lines.length - 1] = keep;
        return;
      }
    }
    lines.add(line);
    if (lines.length > linesLimit) lines.removeAt(0);
  }

  /// «Сейчас» для полосы: что делал последний.
  String get lastAct {
    for (final l in lines.reversed) {
      if (const {'play', 'pause', 'seek', 'countdown', 'pauseNow'}.contains(l.kind)) {
        return l.text;
      }
      if (l.kind == 'source') return '';
    }
    return '';
  }

  static String clock(double sec) {
    final s = sec.isNaN || sec < 0 ? 0 : sec.floor();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  }
}
