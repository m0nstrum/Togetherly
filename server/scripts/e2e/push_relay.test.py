#!/usr/bin/env python3
"""Уведомления хуков без APNs/FCM (форк): зов в ленту и порисовать доходят до
партнёра через его канал user:<uid> в Centrifugo.

Запуск — из scripts/parity.sh (BASE и WS в окружении). Код возврата 1 при
провале.
"""
import asyncio
import json
import os
import random
import string
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ["BASE"]
WS = os.environ["WS"]
T0 = time.time()
OK, FAIL = [], []


def log(*a):
    print(f"[{time.time() - T0:6.2f}s]", *a, flush=True)


def check(name, cond, detail=""):
    (OK if cond else FAIL).append(name)
    log(("  ✓ " if cond else "  ✗ ") + name + (f" — {detail}" if detail else ""))


def api(path, data=None, token=None, method=None):
    body = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(BASE + path, data=body, method=method or ("POST" if body else "GET"))
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw}


def rnd(n=8):
    return "".join(random.choice(string.ascii_lowercase + string.digits) for _ in range(n))


def signup(tag):
    email, pwd = f"relay-{tag}-{rnd(6)}@example.org", "Probe" + rnd(10) + "!"
    st, r = api("/api/collections/users/records", {
        "email": email, "password": pwd, "passwordConfirm": pwd, "display_name": tag})
    if st != 200:
        log(f"!! регистрация {tag}: {st} {r}")
        sys.exit(1)
    st, auth = api("/api/collections/users/auth-with-password", {"identity": email, "password": pwd})
    return {"uid": auth["record"]["id"], "token": auth["token"], "plus": auth["record"].get("plus")}


async def watch(u, got, ready, stop):
    import websockets
    _, ct = api("/api/centrifugo/connection-token", {}, u["token"])
    ch = f"user:{u['uid']}"
    _, sub = api("/api/centrifugo/subscription-token", {"channel": ch}, u["token"])
    async with websockets.connect(WS, ping_interval=None) as ws:
        await ws.send(json.dumps({"id": 1, "connect": {"token": ct["token"]}}))
        await ws.send(json.dumps({"id": 2, "subscribe": {"channel": ch, "token": sub["token"]}}))
        ready.set()
        while not stop.is_set():
            try:
                raw = await asyncio.wait_for(ws.recv(), timeout=1)
            except asyncio.TimeoutError:
                continue
            for line in str(raw).splitlines():
                if not line.strip():
                    continue
                m = json.loads(line)
                if m == {}:
                    await ws.send("{}")
                elif "push" in m:
                    got.append(m["push"].get("pub", {}).get("data", {}))


async def wait_for(got, pred, timeout=5):
    end = time.time() + timeout
    while time.time() < end:
        hit = next((d for d in got if pred(d)), None)
        if hit:
            return hit
        await asyncio.sleep(0.1)
    return None


async def main():
    a, b = signup("Аня"), signup("Боря")
    check("Плюс открыт у всех (решение 1)", a["plus"] is True and b["plus"] is True)
    code = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(6))
    api("/api/collections/invite_codes/records", {"code": code, "owner_uid": a["uid"]}, a["token"])
    st, r = api("/api/invite/accept", {"code": code}, b["token"])
    pair = r.get("pairId")
    check("пара собрана", st == 200 and pair, f"{st} {r}")

    got, ready, stop = [], asyncio.Event(), asyncio.Event()
    task = asyncio.create_task(watch(b, got, ready, stop))
    await asyncio.wait_for(ready.wait(), timeout=20)
    await asyncio.sleep(1)

    st, r = api("/api/reels/invite", {"group_id": pair, "feed": "shorts"}, a["token"])
    check("зов в ленту отправлен", st == 200 and r.get("sent") is True, f"{st} {r}")
    d = await wait_for(got, lambda d: d.get("collection") == "fork_notify"
                       and d.get("record", {}).get("thread") == "reels")
    rec = (d or {}).get("record", {})
    check("Боре пришёл зов в ленту", bool(d), json.dumps(rec, ensure_ascii=False)[:200])
    check("в зове группа и лента", rec.get("data", {}).get("group") == pair
          and rec.get("data", {}).get("feed") == "shorts")

    # Переключатель «порисовать» ставит приложение; незаданный bool — false,
    # и сервер считает его выключенным, как у апстрима.
    api(f"/api/collections/users/records/{b['uid']}", {"notif_draw": True}, b["token"], method="PATCH")
    st, r = api("/api/draw/invite", {"group_id": pair}, a["token"])
    check("зов порисовать отправлен", st == 200, f"{st} {r}")
    d = await wait_for(got, lambda d: d.get("record", {}).get("thread") == "draw")
    check("Боре пришёл зов порисовать", bool(d))

    stop.set()
    await task
    log(f"ИТОГ: пройдено {len(OK)}, провалено {len(FAIL)}")
    sys.exit(1 if FAIL else 0)


asyncio.run(main())
