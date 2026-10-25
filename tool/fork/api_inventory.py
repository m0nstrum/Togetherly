#!/usr/bin/env python3
"""Карта API: какие роуты зовёт клиент и где они реализованы на сервере.

    python3 tool/fork/api_inventory.py            # таблица TSV
    python3 tool/fork/api_inventory.py --missing  # клиент зовёт, сервера нет
        # осознанно отсутствующие — tool/fork/api_absent.txt

Сканирует:
  - lib/**/*.dart: строки `/api/...`, плюс динамические `_call('x')` в
    pb_coins_service.dart (→ /api/coins/x) и `_callGroupRoute('x')` в
    pb_data_service.dart (→ /api/group/x);
  - server/pb_hooks/*.pb.js: `routerAdd("METHOD", "/path"`;
  - server/internal/handler/*.go: Go-роуты.
Встроенные роуты PocketBase (`/api/collections`, `/api/files`, `/api/realtime`,
`/api/oauth2-redirect`) и `/internal/*` не выводятся. Флаг `--fork` остался
от времён апстрима и ничего не меняет.
"""

from __future__ import annotations

import collections
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

# Внешние API, которые клиент зовёт напрямую, а не у нашего сервера.
EXTERNAL = {"/api/oembed", "/api/search", "/api/video"}
BUILTIN_PREFIXES = ("/api/collections", "/api/files", "/internal")
BUILTIN = {"/api/realtime", "/api/oauth2-redirect", "/api/coins", "/api/group"}


def client_routes() -> dict[str, set[str]]:
    out: dict[str, set[str]] = collections.defaultdict(set)
    for p in ROOT.glob("lib/**/*.dart"):
        if "/fork/" in str(p):
            continue
        rel = str(p.relative_to(ROOT / "lib"))
        for m in re.finditer(r"/api/([a-zA-Z0-9_\-]+(?:/[a-zA-Z0-9_\-]+)*)", p.read_text(errors="ignore")):
            out["/api/" + m.group(1).rstrip("/")].add(rel)
    coins = ROOT / "lib/services/pb_coins_service.dart"
    for n in set(re.findall(r"_call\('([a-z\-]+)'", coins.read_text())):
        out["/api/coins/" + n].add("services/pb_coins_service.dart")
    data = ROOT / "lib/services/pb_data_service.dart"
    for n in set(re.findall(r"_callGroupRoute\('([a-z\-]+)'", data.read_text())):
        out["/api/group/" + n].add("services/pb_data_service.dart")
    return out


def server_routes() -> dict[str, set[str]]:
    out: dict[str, set[str]] = collections.defaultdict(set)
    for p in ROOT.glob("server/pb_hooks/*.pb.js"):
        for method, path in re.findall(r"routerAdd\(\s*['\"]([A-Z]+)['\"]\s*,\s*['\"]([^'\"]+)", p.read_text()):
            out[path].add(f"{method} {p.name}")
    for p in ROOT.glob("server/internal/handler/*.go"):
        for method, path in re.findall(r'\.(GET|POST|PATCH|PUT|DELETE)\("(/api/[^"]+)"', p.read_text()):
            out[path].add(f"{method} {p.name}")
    return out


def absent() -> set[str]:
    p = ROOT / "tool/fork/api_absent.txt"
    return {l.split()[0] for l in p.read_text().splitlines() if l.strip() and not l.startswith("#")}


def main() -> None:
    client, server = client_routes(), server_routes()
    missing_only = "--missing" in sys.argv
    skip = absent() if missing_only else set()
    for path in sorted(set(client) | set(server)):
        if path.startswith(BUILTIN_PREFIXES) or path in BUILTIN or path in EXTERNAL:
            continue
        if missing_only and (path in server or path not in client or path in skip):
            continue
        srv = ", ".join(sorted(server.get(path, ()))) or "—"
        cli = ", ".join(sorted(client.get(path, ()))) or "—"
        print(f"{path}\t{srv}\t{cli}")


if __name__ == "__main__":
    main()
