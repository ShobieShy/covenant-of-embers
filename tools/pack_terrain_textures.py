#!/usr/bin/env python3
"""Step 152 (Phase W1): pack ambientCG sets into Terrain3D's channel layout.

Terrain3D wants albedo RGB + height A (`terrain_alb_ht.png`) and normal RGB (OpenGL) +
roughness A (`terrain_nrm_rgh.png`), all the same size. Reads assets/ambientcg/<id>/
color/normal/roughness(.jpg) and height.jpg when present (else albedo luminance), writes
the two PNGs into the same folder (so ASSETS.toml's entry still covers them).
Usage: pack_terrain_textures.py [--check] ID...   (default: every TERRAIN_LAYERS id)
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZE = 512
TERRAIN_LAYERS = ["Grass004", "Ground037", "Rock030", "Gravel022", "Ground054", "PavingStones131"]


def pack(tid: str) -> tuple[Image.Image, Image.Image]:
    d = ROOT / "assets/ambientcg" / tid
    col = Image.open(d / "color.jpg").convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    hp = d / "height.jpg"
    ht = (Image.open(hp) if hp.is_file() else col).convert("L").resize((SIZE, SIZE), Image.LANCZOS)
    nrm = Image.open(d / "normal.jpg").convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    rgh = Image.open(d / "roughness.jpg").convert("L").resize((SIZE, SIZE), Image.LANCZOS)
    return Image.merge("RGBA", (*col.split(), ht)), Image.merge("RGBA", (*nrm.split(), rgh))


def main(argv: list[str]) -> int:
    check = "--check" in argv
    ids = [a for a in argv if not a.startswith("--")] or TERRAIN_LAYERS
    bad = 0
    for tid in ids:
        d = ROOT / "assets/ambientcg" / tid
        for img, name in zip(pack(tid), ("terrain_alb_ht.png", "terrain_nrm_rgh.png")):
            if check:
                if not (d / name).is_file():
                    print(f"[pack_terrain] missing {d / name}")
                    bad += 1
            else:
                img.save(d / name, optimize=True)
                print(f"[pack_terrain] {tid}/{name}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
