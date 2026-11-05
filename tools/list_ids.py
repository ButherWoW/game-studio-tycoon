#!/usr/bin/env python3
"""Таблица ID товаров/геймпассов/значков из src/shared/Config (обе вселенные).

Ищет пары Universe.pick({ test = N, main = M }) и записи `ключ = { test = N, main = M }`
(подарки Social.giftProducts, значки Achievements.badgeIds). Печатает Markdown-таблицу
для docs/IDS.md:

    python3 tools/list_ids.py            # таблица в stdout
    python3 tools/list_ids.py --write    # переписать таблицу в docs/IDS.md между маркерами
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "src" / "shared" / "Config"
DOC = ROOT / "docs" / "IDS.md"
BEGIN = "<!-- ids:begin -->"
END = "<!-- ids:end -->"

PICK = re.compile(
    r"(?P<field>\w+)\s*=\s*Universe\.pick\(\{\s*test\s*=\s*(?P<test>\d+)\s*,\s*main\s*=\s*(?P<main>\d+)\s*,?\s*\}\)"
)
PAIR = re.compile(
    r"^\s*(?P<key>\w+)\s*=\s*\{\s*test\s*=\s*(?P<test>\d+)\s*,\s*main\s*=\s*(?P<main>\d+)\s*,?\s*\}",
    re.M,
)
ITEM_ID = re.compile(r'\bid\s*=\s*"(?P<id>[^"]+)"')
TABLE_KEY = re.compile(r"^\s*(?P<key>\w+)\s*=\s*\{", re.M)
SECTION = re.compile(r"^local (?P<name>\w+)\b", re.M)
# Таблицы, где ключ повторяет id товара из list: показываем с префиксом (deals.patch)
PREFIXED = {"offers", "deals"}

KIND = {"productId": "Developer Product", "gamePassId": "GamePass", "badgeId": "Badge"}


def key_for(text: str, pos: int) -> str:
    """Ключ записи: ближайший перед ID `id = "..."` или `ключ = {` (что ближе)."""
    before = text[:pos]
    best_pos, best = -1, "?"
    for m in ITEM_ID.finditer(before):
        if m.start() > best_pos:
            best_pos, best = m.start(), m.group("id")
    for m in TABLE_KEY.finditer(before):
        if m.start() > best_pos:
            best_pos, best = m.start(), m.group("key")
    return best


def collect() -> list[tuple[str, str, str, str, str]]:
    rows = []
    for path in sorted(CONFIG.glob("*.luau")):
        if path.name == "Universe.luau":
            continue
        text = path.read_text(encoding="utf-8")
        # Комментарии не считаем (примеры в них)
        text = re.sub(r"--[^\n]*", lambda m: " " * len(m.group(0)), text)
        for m in PICK.finditer(text):
            key = key_for(text, m.start())
            sections = SECTION.findall(text[: m.start()])
            if sections and sections[-1] in PREFIXED:
                key = f"{sections[-1]}.{key}"
            rows.append((path.stem, key, KIND.get(m.group("field"), m.group("field")), m.group("test"), m.group("main")))
        for m in PAIR.finditer(text):
            kind = "Badge" if path.stem == "Achievements" else "Developer Product"
            rows.append((path.stem, m.group("key"), kind, m.group("test"), m.group("main")))
    return rows


def table(rows: list[tuple[str, str, str, str, str]]) -> str:
    def cell(v: str) -> str:
        return "" if v == "0" else v

    out = [
        "| Конфиг | Ключ | Тип | test (v2, 10774624686) | main (10774551088) |",
        "|---|---|---|---|---|",
    ]
    for cfg, key, kind, test, main in rows:
        out.append(f"| {cfg} | `{key}` | {kind} | {cell(test) or '—'} | {cell(main)} |")
    filled = sum(1 for r in rows if r[4] != "0")
    created = sum(1 for r in rows if r[3] != "0")
    out.append("")
    out.append(f"Всего записей: {len(rows)}; создано в test: {created}; заполнено в main: {filled}.")
    return "\n".join(out)


def main() -> None:
    result = table(collect())
    if "--write" in sys.argv:
        doc = DOC.read_text(encoding="utf-8")
        start, end = doc.index(BEGIN) + len(BEGIN), doc.index(END)
        DOC.write_text(doc[:start] + "\n" + result + "\n" + doc[end:], encoding="utf-8")
        print(f"docs/IDS.md обновлён ({result.count(chr(10)) - 3} строк)")
    else:
        print(result)


if __name__ == "__main__":
    main()
