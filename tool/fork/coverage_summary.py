"""Сводка покрытия Dart для job summary Fork CI (docs/DEVELOPMENT.md, «CI»).

    python3 tool/fork/coverage_summary.py coverage/lcov.info [ещё.info ...]

Склеивает отчёты lcov (`flutter test --coverage` разных прогонов): строка
покрыта, если её прошёл хоть один прогон. Печатает Markdown — общий процент и
разбивку по папкам `lib/`. Только отчёт: порога нет, падает лишь на пустом или
отсутствующем отчёте — значит, покрытие не собралось.

Считаются только файлы, которые тесты загрузили: `flutter test` не знает о
файлах `lib/`, которых не импортирует ни один тест.
"""
import pathlib
import sys


def parse(paths):
    """Файл → {строка: число проходов}, максимум по всем отчётам."""
    files = {}
    for path in paths:
        current = None
        for raw in pathlib.Path(path).read_text(encoding='utf-8').splitlines():
            line = raw.strip()
            if line.startswith('SF:'):
                current = files.setdefault(normalize(line[3:]), {})
            elif line.startswith('DA:') and current is not None:
                number, hits = line[3:].split(',')[:2]
                number, hits = int(number), int(hits)
                current[number] = max(current.get(number, 0), hits)
            elif line == 'end_of_record':
                current = None
    return files


def normalize(name):
    """Путь от корня репозитория: lcov пишет и абсолютные, и относительные."""
    name = name.replace('\\', '/')
    if name.startswith('lib/'):
        return name
    at = name.find('/lib/')
    return name[at + 1:] if at >= 0 else name


def group(name):
    """Папка для разбивки: lib/fork, lib/services, … ; файлы в корне lib — lib."""
    parts = name.split('/')
    return '/'.join(parts[:2]) if len(parts) > 2 else parts[0]


def percent(hit, total):
    return f'{100 * hit / total:.1f} %' if total else '—'


def summary(files):
    groups = {}
    for name, lines in files.items():
        g = groups.setdefault(group(name), [0, 0, 0])
        g[0] += 1
        g[1] += sum(1 for hits in lines.values() if hits > 0)
        g[2] += len(lines)
    hit = sum(g[1] for g in groups.values())
    total = sum(g[2] for g in groups.values())
    out = [
        '## Покрытие Dart',
        '',
        f'**{percent(hit, total)}** — {hit} из {total} строк в {len(files)} файлах.',
        '',
        '| Папка | Файлов | Строк | Покрыто |',
        '|---|---:|---:|---:|',
    ]
    for name, (count, h, t) in sorted(groups.items(), key=lambda kv: -kv[1][2]):
        out.append(f'| `{name}` | {count} | {t} | {percent(h, t)} |')
    out += ['', 'Только отчёт, без порога. Полный lcov — в артефакте `dart-coverage`.']
    return '\n'.join(out), total


def main(argv):
    paths = [p for p in argv if pathlib.Path(p).is_file()]
    if not paths:
        print(f'нет отчётов покрытия: {" ".join(argv) or "(пусто)"}', file=sys.stderr)
        return 1
    text, total = summary(parse(paths))
    print(text)
    if not total:
        print('в отчётах ни одной строки — покрытие не собралось', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
