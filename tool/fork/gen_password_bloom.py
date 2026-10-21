#!/usr/bin/env python3
"""Фильтр Блума утёкших паролей для проверки пароля бэкапа ключей
(docs/fork/E2E.md §7, lib/fork/e2e/password_policy.dart).

    python3 -I tool/fork/gen_password_bloom.py Pwdb_top-1000000.txt

Источник — SecLists (MIT), Passwords/Common-Credentials/Pwdb_top-1000000.txt,
пароли из утечек по убыванию частоты. Берём первые TOP. Пароль бэкапа не
короче 12 символов и с буквами, поэтому в фильтр идут:
  - сам пароль в нижнем регистре, если он не короче 12;
  - его «основа» (см. base) не короче 4 — так `P@ssw0rd2024!` ловится через
    `password`.
Нормализация обязана совпадать с Dart (PasswordPolicy.forms).

Формат: b"TBLM", версия (1 байт), k (1 байт), m бит (4 байта BE), биты.
Индексы: h = BLAKE2b-128(utf8(слово)); h1, h2 — первые два uint32 BE,
h2 |= 1; i-й индекс — (h1 + i·h2) mod m.
"""

from __future__ import annotations

import hashlib
import math
import pathlib
import struct
import sys

TOP = 300_000
FP = 0.001
OUT = pathlib.Path(__file__).resolve().parents[2] / "assets/fork/leaked_passwords.bloom"

LEET = str.maketrans({"@": "a", "4": "a", "3": "e", "1": "i", "!": "i", "0": "o", "$": "s", "5": "s", "7": "t"})


def strip(s: str) -> str:
    i, j = 0, len(s)
    while i < j and not s[i].isalpha():
        i += 1
    while j > i and not s[j - 1].isalpha():
        j -= 1
    return s[i:j]


def forms(pw: str) -> set[str]:
    low = pw.lower()
    out = set()
    if len(low) >= 12:
        out.add(low)
    base = strip(low).translate(LEET)
    if len(base) >= 4:
        out.add(base)
    return out


def indices(word: str, k: int, m: int) -> list[int]:
    h = hashlib.blake2b(word.encode(), digest_size=16).digest()
    h1, h2 = struct.unpack(">II", h[:8])
    h2 |= 1
    return [(h1 + i * h2) % m for i in range(k)]


def main() -> None:
    lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="ignore").splitlines()[:TOP]
    words: set[str] = set()
    for line in lines:
        words |= forms(line.strip())
    n = len(words)
    m = math.ceil(-n * math.log(FP) / math.log(2) ** 2 / 8) * 8
    k = max(1, round(m / n * math.log(2)))
    bits = bytearray(m // 8)
    for w in sorted(words):
        for idx in indices(w, k, m):
            bits[idx >> 3] |= 1 << (idx & 7)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(b"TBLM" + bytes([1, k]) + struct.pack(">I", m) + bytes(bits))
    print(f"{n} форм, m={m} бит ({m // 8 // 1024} КБ), k={k} → {OUT}")


if __name__ == "__main__":
    main()
