#!/usr/bin/env python3
"""Проверка переводов: Texts.en (эталон) против Texts.ru и всех Config/Locales/*.luau.

Ошибки (код выхода 1):
  - нет ключа из Texts.en;
  - ключ повторяется в одном языке;
  - набор подстановок {name} не совпадает с английским;
  - строка таблицы, которую не удалось разобрать.
Предупреждения (код выхода 0):
  - лишний ключ (нет в Texts.en);
  - эмодзи в начале строки есть в EN, но нет в переводе (или наоборот);
  - перевод длиннее английского больше чем в 1.8 раза (риск не влезть в кнопку).

Запуск из корня репозитория: python3 tools/locale_check.py [--quiet]
"""

from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXTS = ROOT / "src" / "shared" / "Config" / "Texts.luau"
LOCALES = ROOT / "src" / "shared" / "Config" / "Locales"

OVERFLOW_RATIO = 1.8
OVERFLOW_MIN_EN = 4  # совсем короткие строки («OK», «$») не считаем — там проценты шумят

# Названия из Config (name/nameEn в Genres, Topics, Critics…): RU и EN живут в конфиге, в Locales —
# только переводы. Для них сверяем, что набор ключей одинаков во всех Locales
CONFIG_PREFIXES = ("critic_", "employee_", "genre_", "pass_", "product_", "quest_", "research_", "stage_", "topic_")
# Ключи Texts.en, у которых русский текст берётся из Config (upgrade.name через ClientState.localText)
RU_FROM_CONFIG = ("upgrade_",)

ENTRY = re.compile(
    r"""^\s*(?:(?P<key>[A-Za-z_][A-Za-z0-9_]*)|\[\s*"(?P<qkey>[^"]+)"\s*\])\s*=\s*"""
    r"""(?P<value>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')\s*,?\s*(?:--.*)?$"""
)
PLACEHOLDER = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "a": "\a", "b": "\b"}


def unescape(raw: str) -> str:
    body = raw[1:-1]
    out: list[str] = []
    i = 0
    while i < len(body):
        ch = body[i]
        if ch != "\\":
            out.append(ch)
            i += 1
            continue
        nxt = body[i + 1] if i + 1 < len(body) else ""
        if nxt == "u" and body[i + 2 : i + 3] == "{":
            end = body.index("}", i)
            out.append(chr(int(body[i + 3 : end], 16)))
            i = end + 1
        elif nxt.isdigit():
            m = re.match(r"\d{1,3}", body[i + 1 :])
            assert m
            out.append(chr(int(m.group(0))))
            i += 1 + len(m.group(0))
        else:
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
    return "".join(out)


class Table:
    def __init__(self, name: str) -> None:
        self.name = name
        self.values: dict[str, str] = {}
        self.duplicates: list[tuple[str, int]] = []
        self.unparsed: list[tuple[int, str]] = []

    def add_line(self, lineno: int, line: str) -> None:
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            return
        m = ENTRY.match(line)
        if not m:
            self.unparsed.append((lineno, stripped))
            return
        key = m.group("key") or m.group("qkey")
        if key in self.values:
            self.duplicates.append((key, lineno))
        self.values[key] = unescape(m.group("value"))


def parse_texts() -> tuple[Table, Table]:
    tables: dict[str, Table] = {}
    current: Table | None = None
    for lineno, line in enumerate(TEXTS.read_text(encoding="utf-8").splitlines(), 1):
        start = re.match(r"^Texts\.(ru|en) = \{\s*$", line)
        if start:
            current = tables.setdefault(start.group(1), Table(start.group(1)))
            continue
        if current is not None:
            if re.match(r"^\}", line):
                current = None
                continue
            current.add_line(lineno, line)
    if "ru" not in tables or "en" not in tables:
        sys.exit("locale_check: Texts.ru / Texts.en not found in " + str(TEXTS))
    return tables["ru"], tables["en"]


def parse_locale(path: Path) -> Table:
    table = Table(path.stem)
    inside = False
    for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not inside:
            if re.match(r"^return \{\s*$", line):
                inside = True
            continue
        if re.match(r"^\}", line):
            break
        table.add_line(lineno, line)
    return table


def starts_with_emoji(text: str) -> bool:
    text = text.lstrip()
    if not text:
        return False
    ch = text[0]
    code = ord(ch)
    return unicodedata.category(ch) == "So" or 0x1F000 <= code <= 0x1FAFF


def main() -> int:
    quiet = "--quiet" in sys.argv
    ru, en = parse_texts()
    tables = [ru] + [parse_locale(p) for p in sorted(LOCALES.glob("*.luau"))]
    errors: list[str] = []
    warnings: list[str] = []
    overflow: list[tuple[float, str, str, int, int]] = []

    for table in [en] + tables:
        for key, lineno in table.duplicates:
            errors.append(f"[{table.name}] duplicate key {key} (line {lineno})")
        for lineno, text in table.unparsed:
            errors.append(f"[{table.name}] cannot parse line {lineno}: {text[:80]}")

    en_placeholders = {k: set(PLACEHOLDER.findall(v)) for k, v in en.values.items()}
    locales = [t for t in tables if t.name != "ru"]
    config_keys = {k for t in locales for k in t.values if k not in en.values and k.startswith(CONFIG_PREFIXES)}
    for table in tables:
        for key in en.values:
            if key in table.values:
                continue
            if table.name == "ru" and key.startswith(RU_FROM_CONFIG):
                continue
            errors.append(f"[{table.name}] missing key {key}")
        if table.name != "ru":
            for key in sorted(config_keys - table.values.keys()):
                errors.append(f"[{table.name}] missing config name {key} (other locales have it)")
        for key in table.values:
            if key not in en.values and not (table.name != "ru" and key in config_keys):
                target = errors if table.name == "ru" else warnings
                target.append(f"[{table.name}] key {key} is not in Texts.en")
        for key, value in table.values.items():
            if key not in en.values:
                continue
            source = en.values[key]
            have = set(PLACEHOLDER.findall(value))
            want = en_placeholders[key]
            if have != want:
                lost = ", ".join("{" + p + "}" for p in sorted(want - have))
                extra = ", ".join("{" + p + "}" for p in sorted(have - want))
                detail = "; ".join(x for x in (f"missing {lost}" if lost else "", f"extra {extra}" if extra else "") if x)
                errors.append(f"[{table.name}] placeholders differ in {key}: {detail}")
            if starts_with_emoji(source) != starts_with_emoji(value):
                side = "EN starts with emoji, translation does not" if starts_with_emoji(source) else "translation starts with emoji, EN does not"
                warnings.append(f"[{table.name}] emoji mismatch in {key}: {side}")
            if len(source) >= OVERFLOW_MIN_EN and len(value) > OVERFLOW_RATIO * len(source):
                overflow.append((len(value) / len(source), table.name, key, len(source), len(value)))

    print(
        f"locale_check: en has {len(en.values)} keys (+{len(config_keys)} config names); "
        f"checked ru + {len(locales)} locales"
    )
    if not quiet:
        for line in warnings:
            print("WARN  " + line)
        if overflow:
            print(f"\nOverflow risk (> {OVERFLOW_RATIO}x English length, en >= {OVERFLOW_MIN_EN} chars):")
            for ratio, name, key, en_len, len_value in sorted(overflow, key=lambda row: (row[1], -row[0])):
                print(f"  [{name}] {key}: {len_value} vs {en_len} chars (x{ratio:.2f})")
    for line in errors:
        print("ERROR " + line)
    print(f"\n{len(errors)} errors, {len(warnings)} warnings, {len(overflow)} overflow risks")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
