#!/usr/bin/env python3
"""Проверки после мёржа апстрима (docs/fork/MERGE.md).

    python3 tool/fork/merge_check.py            # быстрые проверки, секунды
    python3 tool/fork/merge_check.py --full     # плюс анализатор и все тесты
    python3 tool/fork/merge_check.py --update   # принять новый состав апстрима

Быстрые проверки ловят то, что мёрж ломает молча:
  - маркеры конфликтов в файлах;
  - правка форка потерялась: файл из TOUCHPOINTS.md без пометки `fork`, или
    удалённый форком файл вернулся; пометка `fork` в файле не из реестра;
  - вернулись убранные зависимости (реклама, IAP, Firebase, OAuth);
  - клиент зовёт роут, которого нет на сервере форка (api_inventory --fork);
  - у апстрима новые или пропавшие хуки, живые тесты, страницы pb_public —
    решить, нужны ли они форку (hooks.allow, parity.allow, public.allow), и
    принять состав: --update;
  - сборка хуков и статики по спискам проходит.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "tool/fork/upstream_files.txt"

# Файлы форка: с апстримом не конфликтуют, в реестр не входят.
OWN = ("lib/fork/", "test/fork/", "tool/fork/", "android/app/src/fork/", "docs/fork/",
       "server/", "deploy/", "env/", ".github/workflows/fork-", ".dockerignore", "dart_test.yaml")

# Зависимости, которые форк убрал (решения 1–3, S2).
REMOVED_DEPS = ("google_sign_in", "google_mobile_ads", "yandex_mobileads", "in_app_purchase",
                "flutter_rustore_billing", "firebase_core", "firebase_messaging")

failed: list[str] = []


def check(name: str, problems: list[str]) -> None:
    if problems:
        failed.append(name)
        print(f"✗ {name}")
        for p in problems:
            print(f"    {p}")
    else:
        print(f"✓ {name}")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


def conflict_markers() -> list[str]:
    out = git("grep", "-nE", r"^(<<<<<<<|>>>>>>>) ", "--", ".", ":!*.md")
    return out.splitlines()


def touchpoints() -> list[str]:
    problems, listed = [], set()
    for line in (ROOT / "docs/fork/TOUCHPOINTS.md").read_text().splitlines():
        if not line.startswith("| `"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        deleted = cells[2].startswith("Удал")
        for path in re.findall(r"`([^`]+)`", cells[0]):
            path = re.sub(r" \(.*\)$", "", path)
            listed.add(path)
            f = ROOT / path
            if deleted:
                if f.exists():
                    problems.append(f"{path}: форк его удалил, а он вернулся")
            elif not f.exists():
                problems.append(f"{path}: файла нет — апстрим переименовал? поправьте реестр")
            elif "fork" not in f.read_text(errors="ignore").lower():
                problems.append(f"{path}: нет пометки fork — правка потерялась при мёрже")
    for path in git("grep", "-lE", r"(//|#|<!--) ?fork\b|fork:").split():
        if not path.startswith(OWN) and path not in listed:
            problems.append(f"{path}: пометка fork есть, а в TOUCHPOINTS.md файла нет")
    return problems


def removed_deps() -> list[str]:
    pubspec = (ROOT / "pubspec.yaml").read_text()
    return [f"pubspec.yaml: вернулась {d}" for d in REMOVED_DEPS
            if re.search(rf"^\s+{d}:", pubspec, re.M)]


def api_routes() -> list[str]:
    out = subprocess.run([sys.executable, "tool/fork/api_inventory.py", "--missing", "--fork"],
                         cwd=ROOT, capture_output=True, text=True)
    lines = [l for l in out.stdout.splitlines() if l.strip()]
    if out.returncode:
        lines.append(out.stderr.strip())
    return [f"{l.split(chr(9))[0]} (клиент: {l.split(chr(9))[-1]}) — перенести или записать в tool/fork/api_absent.txt"
            for l in lines]


def upstream_files() -> list[str]:
    pb = ROOT / "pocketbase"
    names = [f"pb_hooks/{p.name}" for p in (pb / "pb_hooks").iterdir() if p.is_file()]
    names += [p.name for p in pb.glob("*.test.py")]
    names += [f"pb_public/{p.name}" for p in (pb / "pb_public").iterdir()]
    return sorted(names)


def snapshot_diff() -> list[str]:
    now = set(upstream_files())
    was = set(SNAPSHOT.read_text().split()) if SNAPSHOT.exists() else set()
    hint = {
        "pb_hooks/": "server/hooks.allow",
        "pb_public/": "server/public.allow",
    }
    out = []
    for n in sorted(now - was):
        where = next((v for k, v in hint.items() if n.startswith(k)), "server/parity.allow")
        out.append(f"новый у апстрима: {n} — решить про {where}")
    for n in sorted(was - now):
        out.append(f"пропал у апстрима: {n}")
    if out:
        out.append("решив, примите состав: python3 tool/fork/merge_check.py --update")
    return out


def sync_scripts() -> list[str]:
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        for script in ("sync-hooks.sh", "sync-public.sh"):
            r = subprocess.run(["sh", f"server/scripts/{script}", f"{tmp}/{script}"],
                               cwd=ROOT, capture_output=True, text=True)
            if r.returncode:
                problems.append(f"{script}: {(r.stderr or r.stdout).strip()}")
    return problems


def full() -> None:
    steps = [
        ("анализатор", ["tool/fork/analyze_check.sh"]),
        ("тесты апстрима и форка", ["flutter", "test", "--dart-define-from-file=env/test.json",
                                     "--exclude-tags", "fork-runtime"]),
        ("поведение сборки форка", ["flutter", "test", "test/fork", "--tags", "fork-runtime"]),
        ("сервер: go test", ["sh", "-c", "cd server && go test ./..."]),
        ("сервер: смоук", ["server/scripts/smoke.sh"]),
        ("сервер: паритет", ["server/scripts/parity.sh"]),
    ]
    for name, cmd in steps:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        check(name, [] if r.returncode == 0 else (r.stdout + r.stderr).strip().splitlines()[-15:])


def main() -> None:
    if "--update" in sys.argv:
        SNAPSHOT.write_text("\n".join(upstream_files()) + "\n")
        print(f"состав апстрима записан: {SNAPSHOT.relative_to(ROOT)}")
        return
    check("нет маркеров конфликтов", conflict_markers())
    check("правки форка на месте (TOUCHPOINTS.md)", touchpoints())
    check("убранные зависимости не вернулись", removed_deps())
    check("все роуты клиента есть на сервере форка", api_routes())
    check("состав хуков, тестов и страниц апстрима разобран", snapshot_diff())
    check("хуки и статика собираются по спискам", sync_scripts())
    if "--full" in sys.argv:
        full()
    print()
    print("всё в порядке" if not failed else f"проблем: {len(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
