#!/usr/bin/env python3
"""Быстрые проверки репозитория (docs/DEVELOPMENT.md, раздел CI).

    python3 tool/fork/repo_check.py            # быстрые проверки, секунды
    python3 tool/fork/repo_check.py --full     # плюс анализатор и все тесты

Ловят то, что тесты не видят:
  - маркеры конфликтов в файлах;
  - вернулись убранные зависимости (реклама, IAP, OAuth);
  - клиент зовёт роут, которого нет на сервере (api_inventory --fork;
    осознанно отсутствующие — tool/fork/api_absent.txt);
  - сборка хуков и статики по спискам проходит.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Зависимости, которые мы убрали (реклама, покупки, вход через Google,
# обновления через Play).
REMOVED_DEPS = ("google_sign_in", "google_mobile_ads", "yandex_mobileads", "in_app_purchase",
                "flutter_rustore_billing", "firebase_core", "firebase_messaging", "in_app_update",
                "sign_in_with_apple")

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




def sync_scripts() -> list[str]:
    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        for script in ("sync-public.sh",):
            r = subprocess.run(["sh", f"server/scripts/{script}", f"{tmp}/{script}"],
                               cwd=ROOT, capture_output=True, text=True)
            if r.returncode:
                problems.append(f"{script}: {(r.stderr or r.stdout).strip()}")
    return problems


def full() -> None:
    steps = [
        ("анализатор", ["tool/fork/analyze_check.sh"]),
        ("тесты", ["flutter", "test", "--dart-define-from-file=env/test.json",
                                     "--exclude-tags", "fork-runtime"]),
        ("поведение боевой сборки", ["flutter", "test", "test/fork", "--tags", "fork-runtime"]),
        ("сервер: go test", ["sh", "-c", "cd server && go test ./..."]),
        ("сервер: смоук", ["server/scripts/smoke.sh"]),
        ("сервер: паритет", ["server/scripts/parity.sh"]),
    ]
    for name, cmd in steps:
        r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        check(name, [] if r.returncode == 0 else (r.stdout + r.stderr).strip().splitlines()[-15:])


def main() -> None:
    check("нет маркеров конфликтов", conflict_markers())
    check("убранные зависимости не вернулись", removed_deps())
    check("все роуты клиента есть на сервере", api_routes())
    check("статика собирается по списку", sync_scripts())
    if "--full" in sys.argv:
        full()
    print()
    print("всё в порядке" if not failed else f"проблем: {len(failed)}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
