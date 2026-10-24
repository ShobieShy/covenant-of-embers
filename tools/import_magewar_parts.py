#!/usr/bin/env python3
"""Import Magewar's staff/wand parts as WieldablePart resources (BUILD_PLAN step 15).

Reads the read-only reference copies assets/magewar/resources/items/parts/*.tres
(Magewar StaffPartItem; ShobieShy's own IP, weapon/loot system follows Magewar directly)
and writes resources/parts/<stem>.tres (script res://scripts/magic/wieldable_part.gd).
Mapping: name -> display_name, description, part_type (same enum order), rarity
(ItemRarity int -> Rarity id), element (MagicElement int = ElementTable.Element, NONE =
Arcane), damage_bonus, fire_rate_modifier, accuracy_bonus, handling_bonus, gem_slots.
Magewar's inventory fields (icon, stack size, item size) are not part of our part model.

Usage: import_magewar_parts.py            write resources/parts/
       import_magewar_parts.py --check    exit 1 when resources/parts is out of date
Python stdlib only.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/magewar/resources/items/parts"
DST = ROOT / "resources/parts"
RARITY_IDS = ["basic", "uncommon", "rare", "mythic", "primordial", "unique"]
INT_KEYS = ["part_type", "element", "gem_slots"]
FLOAT_KEYS = ["damage_bonus", "fire_rate_modifier", "accuracy_bonus", "handling_bonus"]


def parse_tres(text: str) -> dict[str, str]:
    """`key = value` lines of the [resource] section (raw values, strings still quoted)."""
    out: dict[str, str] = {}
    in_res = False
    for line in text.splitlines():
        if line.startswith("["):
            in_res = line.strip() == "[resource]"
            continue
        if in_res and " = " in line:
            k, v = line.split(" = ", 1)
            out[k.strip()] = v.strip()
    return out


def fnum(v: str) -> str:
    x = float(v)
    return repr(x)


def convert(stem: str, m: dict[str, str]) -> str:
    for k in ["name", "part_type", "rarity", "element", *FLOAT_KEYS, "gem_slots"]:
        if k not in m:
            raise ValueError(f"{stem}: Magewar part has no '{k}'")
    rarity = int(m["rarity"])
    if not 0 <= rarity < len(RARITY_IDS):
        raise ValueError(f"{stem}: rarity {rarity} out of range")
    lines = [
        '[gd_resource type="Resource" script_class="WieldablePart" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/magic/wieldable_part.gd" id="1"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        f'id = "{stem}"',
        f"display_name = {m['name']}",
        "description = " + m.get("description", '""'),
        f"part_type = {int(m['part_type'])}",
        f'rarity = "{RARITY_IDS[rarity]}"',
        f"element = {int(m['element'])}",
    ]
    lines += [f"{k} = {fnum(m[k])}" for k in FLOAT_KEYS]
    lines.append(f"gem_slots = {int(m['gem_slots'])}")
    return "\n".join(lines) + "\n"


def build() -> dict[str, str]:
    files = sorted(SRC.glob("*.tres"))
    if not files:
        raise SystemExit(f"no Magewar parts under {SRC}")
    return {f.stem + ".tres": convert(f.stem, parse_tres(f.read_text())) for f in files}


def main(argv: list[str]) -> int:
    want = build()
    if "--check" in argv:
        have = {p.name for p in DST.glob("*.tres")} if DST.exists() else set()
        bad = sorted(n for n in want if not (DST / n).exists() or (DST / n).read_text() != want[n])
        extra = sorted(have - set(want))
        if bad or extra:
            print(f"[import_magewar_parts] resources/parts out of date: {bad + extra}; run tools/import_magewar_parts.py")
            return 1
        print(f"[import_magewar_parts] {len(want)} parts in sync")
        return 0
    DST.mkdir(parents=True, exist_ok=True)
    for n, text in want.items():
        (DST / n).write_text(text)
    print(f"[import_magewar_parts] wrote {len(want)} parts to {DST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
