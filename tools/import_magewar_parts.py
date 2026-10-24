#!/usr/bin/env python3
"""Import Magewar's staff/wand parts, equipment and potions (BUILD_PLAN steps 15 and 19).

Reads the read-only reference copies assets/magewar/resources/items/parts/*.tres
(Magewar StaffPartItem; ShobieShy's own IP, weapon/loot system follows Magewar directly)
and writes resources/parts/<stem>.tres (script res://scripts/magic/wieldable_part.gd).
Mapping: name -> display_name, description, part_type (same enum order), rarity
(ItemRarity int -> Rarity id), element (MagicElement int = ElementTable.Element, NONE =
Arcane), damage_bonus, fire_rate_modifier, accuracy_bonus, handling_bonus, gem_slots.
Magewar's inventory fields (icon, stack size, item size) are not part of our part model.
Step 19: assets/magewar/resources/items/equipment/*.tres (Magewar EquipmentItem) ->
resources/equipment/<stem>.tres (EquipmentItem: name -> display_name, description,
equip_slot, rarity, element_affinity, the seven stat fields) and
assets/magewar/resources/items/consumables/*.tres (Cogito ConsumableItemPD) ->
resources/consumables/<stem>.tres (ConsumableItem: name, description, attribute_name ->
attribute, attribute_change_amount -> amount, stack_size, hint_text_on_use -> hint).

Usage: import_magewar_parts.py            write resources/parts, equipment, consumables
       import_magewar_parts.py --check    exit 1 when any of them is out of date
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
EQUIP_SRC = ROOT / "assets/magewar/resources/items/equipment"
EQUIP_DST = ROOT / "resources/equipment"
EQUIP_FLOATS = ["health_bonus", "mana_bonus", "stamina_bonus", "speed_modifier",
                "spell_damage_bonus", "elemental_resistance", "mana_regen_bonus"]
POTION_SRC = ROOT / "assets/magewar/resources/items/consumables"
POTION_DST = ROOT / "resources/consumables"


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


def convert_equipment(stem: str, m: dict[str, str]) -> str:
    for k in ["name", "equip_slot", "rarity", "element_affinity", *EQUIP_FLOATS]:
        if k not in m:
            raise ValueError(f"{stem}: Magewar equipment has no '{k}'")
    rarity = int(m["rarity"])
    if not 0 <= rarity < len(RARITY_IDS):
        raise ValueError(f"{stem}: rarity {rarity} out of range")
    lines = [
        '[gd_resource type="Resource" script_class="EquipmentItem" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/loot/equipment_item.gd" id="1"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        f'id = "{stem}"',
        f"display_name = {m['name']}",
        "description = " + m.get("description", '""'),
        f"slot = {int(m['equip_slot'])}",
        f'rarity = "{RARITY_IDS[rarity]}"',
        f"element_affinity = {int(m['element_affinity'])}",
    ]
    lines += [f"{k} = {fnum(m[k])}" for k in EQUIP_FLOATS]
    return "\n".join(lines) + "\n"


def convert_potion(stem: str, m: dict[str, str]) -> str:
    for k in ["name", "attribute_name", "attribute_change_amount"]:
        if k not in m:
            raise ValueError(f"{stem}: Magewar consumable has no '{k}'")
    if m["attribute_name"].strip('"') not in ("health", "mana"):
        raise ValueError(f"{stem}: attribute {m['attribute_name']} is not health/mana")
    lines = [
        '[gd_resource type="Resource" script_class="ConsumableItem" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://scripts/loot/consumable_item.gd" id="1"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        f'id = "{stem}"',
        f"display_name = {m['name']}",
        "description = " + m.get("description", '""'),
        f"attribute = {m['attribute_name']}",
        f"amount = {fnum(m['attribute_change_amount'])}",
        f"stack_size = {int(m.get('stack_size', '1'))}",
        "hint = " + m.get("hint_text_on_use", '""'),
    ]
    return "\n".join(lines) + "\n"


SETS = [  # (label, source dir, destination dir, converter)
    ("parts", SRC, DST, convert),
    ("equipment", EQUIP_SRC, EQUIP_DST, convert_equipment),
    ("consumables", POTION_SRC, POTION_DST, convert_potion),
]


def build(src: Path, conv) -> dict[str, str]:
    files = sorted(src.glob("*.tres"))
    if not files:
        raise SystemExit(f"no Magewar resources under {src}")
    return {f.stem + ".tres": conv(f.stem, parse_tres(f.read_text())) for f in files}


def main(argv: list[str]) -> int:
    check = "--check" in argv
    status = 0
    for label, src, dst, conv in SETS:
        want = build(src, conv)
        rel = dst.relative_to(ROOT)
        if check:
            have = {p.name for p in dst.glob("*.tres")} if dst.exists() else set()
            bad = sorted(n for n in want if not (dst / n).exists() or (dst / n).read_text() != want[n])
            extra = sorted(have - set(want))
            if bad or extra:
                print(f"[import_magewar_parts] {rel} out of date: {bad + extra}; run tools/import_magewar_parts.py")
                status = 1
            else:
                print(f"[import_magewar_parts] {len(want)} {label} in sync")
            continue
        dst.mkdir(parents=True, exist_ok=True)
        for n, text in want.items():
            (dst / n).write_text(text)
        print(f"[import_magewar_parts] wrote {len(want)} {label} to {rel}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
