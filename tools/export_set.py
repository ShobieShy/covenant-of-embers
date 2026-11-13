#!/usr/bin/env python3
"""Export set for terrain layers (audit F1).

Textures stay on disk. export_presets.cfg excludes the ones no level toml
names, plus the unreferenced Ground054 set. A referenced layer that is
excluded fails this check: TerrainZone would otherwise draw a checker
with no error, and the test suite runs from the source tree so it would
not notice.

  tools/export_set.py            rewrite both presets' exclude_filter
  tools/export_set.py --check    exit 1 if the presets drift
"""
from __future__ import annotations

import fnmatch
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRESETS = ROOT / "export_presets.cfg"
LEVELS = ROOT / "data" / "levels"
EMBER = ROOT / "assets" / "original" / "ember_art" / "terrain"
AMBIENT = ROOT / "assets" / "ambientcg"

# The filters that were already there. Terrain globs are appended, sorted.
BASE = (
    "tests/*, archive/*, playtest/*, docs/*, tools/*, "
    "assets/kenney/blaster-kit/Models/FBX format/*, "
    "assets/kenney/blaster-kit/Models/OBJ format/*, "
    "assets/kenney/blaster-kit/Previews/*, "
    "assets/quaternius/*_preview.png, "
    "assets/kenney/ui-pack/Vector/*, "
    "assets/kenney/ui-pack/PNG/*/Double/*"
)


def referenced_layers() -> set[str]:
    ids: set[str] = set()
    for path in sorted(LEVELS.glob("*.toml")):
        text = path.read_text(encoding="utf-8")
        # Only the [terrain] table. A later table ends the search.
        m = re.search(r"(?ms)^\[terrain\]\n(.*?)(?:^\[|\Z)", text)
        if not m:
            continue
        for raw in re.findall(r'^layers\s*=\s*\[([^\]]*)\]', m.group(1), re.M):
            ids.update(re.findall(r'"([^"]+)"', raw))
    return ids


def _used_as_material(folder: str) -> bool:
    needle = f"assets/ambientcg/{folder}"
    for path in list(LEVELS.glob("*.toml")) + list((ROOT / "scenes").rglob("*.tscn")):
        if needle in path.read_text(encoding="utf-8", errors="replace"):
            return True
    return False


def exclude_patterns() -> list[str]:
    used = referenced_layers()
    patterns: list[str] = []
    if EMBER.is_dir():
        for png in sorted(EMBER.glob("*_albedo_height.png")):
            layer = png.name[: -len("_albedo_height.png")]
            if layer not in used:
                patterns.append(f"assets/original/ember_art/terrain/{layer}_*.png")
    if AMBIENT.is_dir():
        for folder in sorted(p for p in AMBIENT.iterdir() if p.is_dir()):
            if not (folder / "terrain_alb_ht.png").is_file():
                continue
            if folder.name not in used:
                patterns.append(f"assets/ambientcg/{folder.name}/terrain_*.png")
            # Ground054's colour set is not a level material either.
            if folder.name == "Ground054" and "Ground054" not in used and not _used_as_material("Ground054"):
                patterns.append("assets/ambientcg/Ground054/*")
    return patterns


def wanted_filter() -> str:
    extra = exclude_patterns()
    if not extra:
        return BASE
    return BASE + ", " + ", ".join(extra)


def _filters(text: str) -> list[str]:
    return re.findall(r'^exclude_filter="([^"]*)"', text, re.M)


def _matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pat) for pat in patterns)


def _split(filt: str) -> list[str]:
    return [p.strip() for p in filt.split(",") if p.strip()]


def check() -> int:
    bad = 0
    text = PRESETS.read_text(encoding="utf-8")
    filters = _filters(text)
    want = wanted_filter()
    if len(filters) != 2 or any(f != want for f in filters):
        print("[export_set] exclude_filter drifted: run tools/export_set.py", file=sys.stderr)
        bad += 1
        return bad
    patterns = _split(want)
    used = referenced_layers()
    for layer in sorted(used):
        candidates = [
            f"assets/original/ember_art/terrain/{layer}_albedo_height.png",
            f"assets/original/ember_art/terrain/{layer}_normal_roughness.png",
            f"assets/ambientcg/{layer}/terrain_alb_ht.png",
            f"assets/ambientcg/{layer}/terrain_nrm_rgh.png",
        ]
        present = [c for c in candidates if (ROOT / c).is_file()]
        if len(present) < 2:
            print(f"[export_set] layer {layer} is named but has no texture pair", file=sys.stderr)
            bad += 1
            continue
        for c in present:
            if _matches(c, patterns):
                print(f"[export_set] layer {layer} is excluded ({c})", file=sys.stderr)
                bad += 1
    # Unused terrain files must be excluded, or they ship in the PCK.
    if EMBER.is_dir():
        for png in EMBER.glob("*.png"):
            layer = png.name.split("_albedo_height")[0].split("_normal_roughness")[0]
            # preview-less packed pairs only
            if not (png.name.endswith("_albedo_height.png") or png.name.endswith("_normal_roughness.png")):
                continue
            layer = png.name.replace("_albedo_height.png", "").replace("_normal_roughness.png", "")
            if layer in used:
                continue
            rel = str(png.relative_to(ROOT))
            if not _matches(rel, patterns):
                print(f"[export_set] unused terrain still exported: {rel}", file=sys.stderr)
                bad += 1
    return bad


def write() -> None:
    want = wanted_filter()
    text = PRESETS.read_text(encoding="utf-8")
    text2, n = re.subn(r'^exclude_filter="[^"]*"', f'exclude_filter="{want}"', text, flags=re.M)
    if n != 2:
        raise SystemExit(f"expected 2 exclude_filter lines, rewrote {n}")
    PRESETS.write_text(text2, encoding="utf-8")
    print(f"[export_set] {len(exclude_patterns())} terrain exclude pattern(s)")


def main(argv: list[str]) -> int:
    if "--check" in argv:
        bad = check()
        if bad:
            return 1
        print("export set: OK")
        return 0
    write()
    return check()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
