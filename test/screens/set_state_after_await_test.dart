import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `setState` после `await` идёт только после проверки `mounted` (аудит B-5).
///
/// Пока ждали сеть или диалог, экран могли закрыть; `setState` у снятого
/// `State` бросает «setState() called after dispose()». Для `context` после
/// `await` есть линт `use_build_context_synchronously` (включён ошибкой в
/// analysis_options.yaml), для `setState` стандартного линта нет — поэтому
/// этот страж: эвристика по тексту lib/ без комментариев и строк.
///
/// Метод (или замыкание) «отравлен» после `await` и после колбэков
/// `.then`/`.whenComplete`/`.catchError`/`Future.delayed`; отравление снимают
/// `if (!mounted) return;` (и `continue`/`break`/`throw`, и форма с блоком),
/// а `if (mounted) …`/`mounted && …` защищают свою ветку.
void main() {
  test('setState после await только после проверки mounted', () {
    final found = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final hit in findSetStateAfterAwait(file.readAsStringSync())) {
        final key = '${file.path}|${hit.previous}|${hit.code}';
        if (_allowed.containsKey(key)) continue;
        found.add('${file.path}:${hit.line}: ${hit.code}');
      }
    }
    expect(found, isEmpty);
  });

  test('эвристика ловит незащищённый setState и пропускает защищённый', () {
    const bad = '''
class _S extends State<W> {
  Future<void> load() async {
    final x = await api();
    setState(() => _x = x);
  }
  void tap() {
    api().then((v) {
      setState(() => _x = v);
    });
  }
  Future<void> nested() async {
    try {
      await api();
    } catch (_) {}
    setState(() {});
  }
  Future<void> condition() async {
    if (await api()) {
      return;
    }
    setState(() {});
  }
}
''';
    expect(findSetStateAfterAwait(bad).map((h) => h.line), [4, 8, 15, 21]);

    const good = '''
class _S extends State<W> {
  Future<void> load() async {
    setState(() => _busy = true);
    final x = await api(); // await в комментарии: setState(
    if (!mounted) return;
    setState(() => _x = x);
    await api();
    if (mounted) setState(() {});
    if (mounted) {
      setState(() {});
    }
    await api();
    if (!context.mounted) {
      return;
    }
    setState(() {});
    final s = 'await \${x} setState(';
    final y = await api();
    if (y == null || !mounted) return;
    setState(() {});
    if (y) {
      await api();
      return;
    }
    setState(() {});
  }
  void tap() {
    api().then((v) {
      if (!mounted) return;
      setState(() => _x = v);
    });
    onTap: () async {
      await api();
    };
    setState(() {});
  }
}
''';
    expect(findSetStateAfterAwait(good), isEmpty);
  });
}

/// Оправданные случаи: «путь|предыдущая строка|строка с setState» → почему.
const _allowed = <String, String>{
  'lib/screens/together/watch_player_screen.dart'
          '|voice.addListener(_onVoiceChanged);|setState(() {':
      'единственный await перед ним — в finally и только при !adopted, а '
      'тогда метод уже вышел; join сам сверяется с mounted (alive). Выход по '
      '!mounted здесь оставил бы контроллер и комнату без владельца',
};

class Hit {
  const Hit(this.line, this.code, this.previous);
  final int line;
  final String code;

  /// Предыдущая непустая строка: ключ allowlist устойчив к сдвигу строк.
  final String previous;
}

class _Frame {
  _Frame({required this.awaited, required this.function, this.guard = false});
  bool awaited;
  final bool function;

  /// Блок `if (!mounted) { … }` — после него метод снова чист.
  final bool guard;
}

final _positiveMounted = RegExp(r'(?<![!\w.])(?:\w+\.)?mounted\b');
final _negativeMounted = RegExp(
  r'!\s*(?:\w+\.)?mounted\b|(?<![!\w.])_disposed\b',
);
final _ifOpen = RegExp(r'\bif\s*\(');
final _exit = RegExp(r'\s*(?:return|continue|break|throw)\b');
final _exitLast = RegExp(r'(?:return|continue|break|throw)\b[^;{}]*;\s*$');
final _afterParams = RegExp(r'\)\s*(?:async\*?|sync\*)?\s*$');
final _blockKeyword = RegExp(r'\b(?:if|for|while|switch|catch)\s*$');
final _typeBody = RegExp(r'\b(?:class|mixin|extension|enum)\b');
final _asyncCallback = RegExp(
  r'(?:\.(?:then|whenComplete|catchError)\s*\(|Future\.delayed\s*\([^;]*,)\s*$',
);
final _await = RegExp(r'await\b');
final _setState = RegExp(r'setState\s*\(');

List<Hit> findSetStateAfterAwait(String source) {
  final text = _strip(source);
  final lines = source.split('\n');
  final hits = <Hit>[];
  final frames = <_Frame>[_Frame(awaited: false, function: true)];
  var boundary = 0; // начало текущего оператора
  var line = 1;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == '\n') {
      line++;
      continue;
    }
    if (char == '{') {
      frames.add(_open(text, boundary, i, frames.last));
      boundary = i + 1;
      continue;
    }
    if (char == '}') {
      final frame = frames.length > 1 ? frames.removeLast() : frames.last;
      if (frame.guard) {
        frames.last.awaited = false;
      } else if (!frame.function && !_endsWithExit(text, i)) {
        frames.last.awaited |= frame.awaited;
      }
      boundary = i + 1;
      continue;
    }
    if (char == ';') {
      boundary = i + 1;
      continue;
    }
    final wordStart = i == 0 || !RegExp(r'[\w.$]').hasMatch(text[i - 1]);
    if (!wordStart) continue;
    if (_await.matchAsPrefix(text, i) != null) {
      frames.last.awaited = true;
    } else if (_ifOpen.matchAsPrefix(text, i) != null) {
      final end = _guardEnd(text, i);
      if (end >= 0 && _exit.matchAsPrefix(text, end) != null) {
        frames.last.awaited = false;
      }
    } else if (_setState.matchAsPrefix(text, i) != null &&
        frames.last.awaited &&
        !_positiveMounted.hasMatch(text.substring(boundary, i))) {
      var prev = line - 2;
      while (prev > 0 && lines[prev].trim().isEmpty) {
        prev--;
      }
      hits.add(
        Hit(line, lines[line - 1].trim(), prev >= 0 ? lines[prev].trim() : ''),
      );
    }
  }
  return hits;
}

/// Кадр для `{` в позиции [at]: функция (чистый старт), блок (наследует
/// отравление) или защищённая ветка.
_Frame _open(String text, int boundary, int at, _Frame parent) {
  final prefix = text.substring(boundary, at);
  final ifs = _ifOpen.allMatches(prefix);
  if (ifs.isNotEmpty) {
    final start = boundary + ifs.last.start;
    final end = _guardEnd(text, start);
    if (end >= 0 && text.substring(end, at).trim().isEmpty) {
      return _Frame(awaited: parent.awaited, function: false, guard: true);
    }
    if (_positiveMounted.hasMatch(prefix)) {
      return _Frame(awaited: false, function: false);
    }
  }
  if (_afterParams.hasMatch(prefix)) {
    final close = text.lastIndexOf(')', at);
    final open = _matchingOpen(text, close);
    if (open >= 0) {
      final before = text.substring((open - 200).clamp(0, open), open);
      if (!_blockKeyword.hasMatch(before)) {
        return _Frame(awaited: _asyncCallback.hasMatch(before), function: true);
      }
    }
  }
  if (_typeBody.hasMatch(prefix)) {
    return _Frame(awaited: false, function: true);
  }
  return _Frame(awaited: parent.awaited, function: false);
}

/// Блок, закрытый в [close], кончается выходом — после него `await` из
/// блока не действует.
bool _endsWithExit(String text, int close) =>
    _exitLast.hasMatch(text.substring((close - 300).clamp(0, close), close));

/// Конец условия `if (…)` с позиции [at], если оно — защита «экран снят»
/// (`!mounted` без `&&`: `if (x == null || !mounted)`), иначе -1.
int _guardEnd(String text, int at) {
  final open = text.indexOf('(', at);
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '(') depth++;
    if (text[i] == ')' && --depth == 0) {
      final cond = text.substring(open + 1, i);
      final guard = _negativeMounted.hasMatch(cond) && !cond.contains('&&');
      return guard ? i + 1 : -1;
    }
  }
  return -1;
}

int _matchingOpen(String text, int close) {
  var depth = 0;
  for (var i = close; i >= 0; i--) {
    if (text[i] == ')') depth++;
    if (text[i] == '(') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Текст без комментариев и строковых литералов (переводы строк на месте).
String _strip(String s) {
  final out = StringBuffer();
  var i = 0;
  void blank(int to) {
    for (; i < to && i < s.length; i++) {
      out.write(s[i] == '\n' ? '\n' : ' ');
    }
  }

  while (i < s.length) {
    if (s.startsWith('//', i)) {
      final end = s.indexOf('\n', i);
      blank(end < 0 ? s.length : end);
    } else if (s.startsWith('/*', i)) {
      final end = s.indexOf('*/', i + 2);
      blank(end < 0 ? s.length : end + 2);
    } else if (s[i] == '"' || s[i] == "'") {
      final raw = i > 0 && s[i - 1] == 'r';
      final quote = s.startsWith(s[i] * 3, i) ? s[i] * 3 : s[i];
      var j = i + quote.length;
      while (j < s.length && !s.startsWith(quote, j)) {
        if (!raw && s[j] == r'\') {
          j += 2;
        } else if (!raw && s.startsWith(r'${', j)) {
          var depth = 0;
          for (; j < s.length; j++) {
            if (s[j] == '{') depth++;
            if (s[j] == '}' && --depth == 0) break;
          }
          j++;
        } else {
          j++;
        }
      }
      blank(j + quote.length);
    } else {
      out.write(s[i]);
      i++;
    }
  }
  return out.toString();
}
