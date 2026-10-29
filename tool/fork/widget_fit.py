#!/usr/bin/env python3
"""Влезает ли разметка виджета в ячейку, которую гарантирует лончер (B7).

Лончер выдаёт виджету `minHeight` из его `res/xml/*_info.xml` (70*n-30:
столько занимают n ячеек стандартной сетки), но не больше, если сетка тесная: OnePlus 9R даёт «Скучаю» 2×2 около 110dp. Разметка же складывает
блоки фиксированной высоты (паддинги, шапка, кегль числа, кнопка), а
растяжки-спейсеры только растут — не сжимаются. Если сумма больше ячейки,
RemoteViews молча срезает низ: так пропала кнопка «Скучаю».

Скрипт оценивает минимальную высоту разметки снизу:

- `layout_height` в dp — как есть (плюс поля);
- `wrap_content` у TextView — строка кегля: ~1.17 em без
  `includeFontPadding`, ~1.33 em с ним, умножить на `lines`/`minLines`
  (иначе одна строка — короче текст не бывает);
- ImageView/ProgressBar на `wrap_content` и пустой блок `0dp` с весом —
  ноль: картинку и растяжку LinearLayout сожмёт, а не вытолкнет низ за край.
  Блок с весом и содержимым считается по содержимому — сжатый, он срежет
  свой низ;
- вертикальный LinearLayout — сумма детей, горизонтальный и FrameLayout —
  максимум; паддинги и поля сверху и снизу; `gone` не считается.

Кегли из кода (`setTextViewTextSize`) в тесноте не меньше XML: `WidgetSizing.scale`
только растягивает. Поэтому XML — честная нижняя граница.

Что не влезло, считается исправленным, если есть компактная разметка
`<имя>_compact.xml`, она влезает, и Kotlin-провайдер выбирает её вызовом
`WidgetSizing.fit(context, options, R.layout.<имя>, R.layout.<имя>_compact, N)`,
где N — не меньше оценки полной разметки: иначе в ячейке чуть ниже нужного
останется полная и срежется.

    python3 tool/fork/widget_fit.py           # таблица и код выхода
    python3 tool/fork/widget_fit.py --all     # с запасом каждого виджета

Страж — test/fork/widget_fit_test.dart.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"
KOTLIN = ROOT / "android/app/src/main/kotlin"
A = "{http://schemas.android.com/apk/res/android}"

# Виджеты, которые сверяем: новые tg_* и статистика пары (B7).
INFO_RE = re.compile(r"^(tg_.*|relationship_stats_widget)_info\.xml$")

# Высота строки в долях кегля (Roboto/Onest): ascent+descent без
# внутренних полей шрифта и с ними.
LINE_TIGHT = 1.17
LINE_PADDED = 1.33


def dp(value: str | None) -> float | None:
    """'12dp', '10.5sp', '3dip' → число; остальное (match_parent…) → None."""
    if not value:
        return None
    m = re.fullmatch(r"(-?\d+(?:\.\d+)?)(dp|dip|sp|px)", value.strip())
    return float(m.group(1)) if m else None


def attr(el: ET.Element, name: str) -> str | None:
    return el.get(A + name)


def vertical_box(el: ET.Element, side: str) -> float:
    """Паддинг по стороне ('Top'/'Bottom') с учётом общих атрибутов."""
    for name in (f"padding{side}", "paddingVertical", "padding"):
        v = dp(attr(el, name))
        if v is not None:
            return v
    return 0.0


def margins(el: ET.Element) -> float:
    total = 0.0
    for side in ("Top", "Bottom"):
        for name in (f"layout_margin{side}", "layout_marginVertical", "layout_margin"):
            v = dp(attr(el, name))
            if v is not None:
                total += v
                break
    return total


def text_height(el: ET.Element) -> float:
    size = dp(attr(el, "textSize")) or 14.0
    padded = attr(el, "includeFontPadding") != "false"
    lines = 1
    for name in ("lines", "minLines"):
        v = attr(el, name)
        if v and v.isdigit():
            lines = max(lines, int(v))
    extra = dp(attr(el, "lineSpacingExtra")) or 0.0
    return size * (LINE_PADDED if padded else LINE_TIGHT) * lines + extra * (lines - 1)


def tag(el: ET.Element) -> str:
    return el.tag.rsplit(".", 1)[-1]


def min_height(el: ET.Element, layouts: Path) -> float:
    """Минимальная высота элемента без полей (поля добавляет родитель)."""
    if attr(el, "visibility") == "gone":
        return 0.0
    if tag(el) == "include":
        ref = (el.get("layout") or "").removeprefix("@layout/")
        inc = ET.parse(layouts / f"{ref}.xml").getroot()
        return min_height(inc, layouts)

    fixed = dp(attr(el, "layout_height"))
    floor = dp(attr(el, "minHeight")) or 0.0
    if fixed is not None and fixed > 0:
        return max(fixed, floor)
    # Пустой `0dp` с весом — растяжка: в тесноте LinearLayout отдаёт ей
    # остаток, а не меньше нуля. Блок с содержимым так не считаем: сжатый,
    # он срежет свой низ (подписи плиток, число).
    if fixed == 0 and float(attr(el, "layout_weight") or 0) > 0 and len(el) == 0:
        return floor

    pad = vertical_box(el, "Top") + vertical_box(el, "Bottom")
    children = [c for c in el if attr(c, "visibility") != "gone"]
    kind = tag(el)

    if kind in ("TextView", "Button", "TextClock", "Chronometer"):
        content = text_height(el)
    elif not children:
        content = 0.0
    elif kind == "LinearLayout" and attr(el, "orientation") == "vertical":
        content = sum(min_height(c, layouts) + margins(c) for c in children)
    else:
        # Горизонтальный LinearLayout, FrameLayout, RelativeLayout — слои.
        content = max(min_height(c, layouts) + margins(c) for c in children)
    return max(content + pad, floor)


def widgets() -> list[dict]:
    out = []
    for info in sorted((RES / "xml").glob("*_info.xml")):
        if not INFO_RE.match(info.name):
            continue
        root = ET.parse(info).getroot()
        layout = (attr(root, "initialLayout") or "").removeprefix("@layout/")
        cell = dp(attr(root, "minHeight")) or 0.0
        out.append({"info": info.stem, "layout": layout, "cell": cell})
    return out


FIT_RE = re.compile(
    r"WidgetSizing\.fit\(\s*[^,()]+,\s*[^,()]+,\s*"
    r"R\.layout\.(\w+),\s*R\.layout\.(\w+),\s*(\d+)\s*,?\s*\)"
)


def fit_thresholds() -> dict[str, tuple[str, int]]:
    """Полная разметка → (компактная, порог dp) из вызовов WidgetSizing.fit."""
    code = "\n".join(p.read_text(encoding="utf-8") for p in KOTLIN.rglob("*.kt"))
    return {m.group(1): (m.group(2), int(m.group(3))) for m in FIT_RE.finditer(code)}


def check() -> list[dict]:
    layouts = RES / "layout"
    fits = fit_thresholds()
    rows = []
    for w in widgets():
        need = min_height(ET.parse(layouts / f"{w['layout']}.xml").getroot(), layouts)
        row = {**w, "need": need, "compact": None, "ok": need <= w["cell"]}
        compact = layouts / f"{w['layout']}_compact.xml"
        if not row["ok"] and compact.exists():
            row["compact"] = min_height(ET.parse(compact).getroot(), layouts)
            fit = fits.get(w["layout"])
            row["problem"] = (
                "провайдер не выбирает её через WidgetSizing.fit"
                if fit is None or fit[0] != compact.stem
                else f"порог в WidgetSizing.fit {fit[1]}dp меньше нужного полной"
                if fit[1] < need
                else None
            )
            row["ok"] = row["problem"] is None and row["compact"] <= w["cell"]
        rows.append(row)
    return rows


def main(argv: list[str]) -> int:
    rows = check()
    bad = [r for r in rows if not r["ok"]]
    for r in rows if "--all" in argv else bad:
        line = f"{r['info']:<34} {r['layout']:<28} нужно {r['need']:6.1f}dp, ячейка {r['cell']:.0f}dp"
        if r["compact"] is not None:
            line += f"; компактная {r['compact']:.1f}dp"
            if r.get("problem"):
                line += f" ({r['problem']})"
        print(("ok  " if r["ok"] else "FAIL") + " " + line)
    if bad:
        print(
            f"\n{len(bad)} виджет(ов) не влезают в гарантированную ячейку: "
            "ужать разметку или добавить <имя>_compact.xml и выбирать её в "
            "провайдере через WidgetSizing.fit (см. MissWidgetProvider).",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
