#!/usr/bin/env python3
"""Иконка форка Tethered: два сцепленных кольца на тёмном фоне.

Кладёт ресурсы в android/app/src/fork/res — этот каталог подключён к
build-type source set'ам (см. android/app/build.gradle.kts, блок fork) и
перекрывает одноимённые ресурсы из src/main. PNG апстрима не трогаем, поэтому
при мёрже его иконки не конфликтуют с нашими.

Перекрывается только основная иконка (launcher_icon*). Тематические иконки
(ic_launcher_<тема>) остаются апстримовскими.

Запуск: python3 tool/fork/gen_icon.py  (нужен Pillow)
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android" / "app" / "src" / "fork" / "res"

BG = (24, 32, 56)  # тёмно-синий
RING_A = (255, 122, 107)  # коралловый
RING_B = (245, 240, 230)  # молочный

# Плотности: (каталог, сторона legacy-иконки 48dp, сторона слоя adaptive 108dp)
DENSITIES = [
    ("mdpi", 48, 108),
    ("hdpi", 72, 162),
    ("xhdpi", 96, 216),
    ("xxhdpi", 144, 324),
    ("xxxhdpi", 192, 432),
]

SS = 4  # суперсэмплинг для сглаживания


def _rings(size: int, scale: float) -> Image.Image:
    """Два сцепленных кольца, вписанных в долю `scale` от стороны."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = s * scale * 0.26  # внешний радиус кольца
    w = max(2, int(s * scale * 0.085))  # толщина
    cy = s / 2
    off = r * 0.62
    ca = (s / 2 - off, cy)
    cb = (s / 2 + off, cy)

    def ring(c, color, start=0, end=360):
        box = [c[0] - r, c[1] - r, c[0] + r, c[1] + r]
        d.arc(box, start, end, fill=color, width=w)

    # Сцепление: правое кольцо целиком, левое поверх, затем кусок правого
    # снова поверх левого у нижнего пересечения (128°) — получается
    # переплетение.
    ring(cb, RING_B)
    ring(ca, RING_A)
    ring(cb, RING_B, 100, 160)
    return img.resize((size, size), Image.LANCZOS)


def _rounded_bg(size: int, radius_frac: float) -> Image.Image:
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius_frac), fill=BG)
    return img.resize((size, size), Image.LANCZOS)


def _legacy(size: int, round_: bool) -> Image.Image:
    bg = _rounded_bg(size, 0.5 if round_ else 0.22)
    bg.alpha_composite(_rings(size, 0.95))
    return bg


def main() -> None:
    for name, legacy, layer in DENSITIES:
        out = RES / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)
        _legacy(legacy, False).save(out / "launcher_icon.png", optimize=True)
        _legacy(legacy, True).save(out / "launcher_icon_round.png", optimize=True)
        # Слой adaptive: видимы центральные 72 из 108 dp, кольца держим там.
        _rings(layer, 0.62).save(out / "launcher_icon_fg.png", optimize=True)

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "fork_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Сгенерировано tool/fork/gen_icon.py. Фон адаптивной иконки форка. -->\n"
        "<resources>\n"
        '    <color name="ic_launcher_background">#%02X%02X%02X</color>\n' % BG
        + "</resources>\n",
        encoding="utf-8",
    )
    print(f"ok: {RES.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
