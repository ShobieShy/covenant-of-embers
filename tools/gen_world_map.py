#!/usr/bin/env python3
"""OW7: the map screen's world texture, drawn from the built world (no painted art yet):
each vertex coloured by its Terrain3D base layer (control bits 27-31), hill-shaded, at
2 m per pixel. tools/gen_world_map.py [--check]  -> world/map.png
"""
import json, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "build/world"
OUT = ROOT / "world/map.png"
SCALE = 2
COLOR = {  # world.json "layers" name -> map ink
    "ash_scorched": (70, 60, 58), "crystal": (150, 120, 190), "rubble_junk": (120, 105, 90),
    "rock": (125, 122, 118), "dirt": (140, 115, 80), "mud_filth": (95, 85, 55),
    "grass": (95, 130, 70), "path_cobble": (205, 190, 160),
}


def render():
    meta = json.loads((SRC / "world.json").read_text())
    w, h = meta["grid"]
    hw = np.fromfile(SRC / "world_height.f32", "<f4").reshape(h, w)
    ctl = np.fromfile(SRC / "world_control.u32", "<u4").reshape(h, w)
    pal = np.array([COLOR.get(n, (128, 128, 128)) for n in meta["layers"]] + [(128, 128, 128)] * 32, np.float32)
    rgb = pal[(ctl >> 27) & 31]
    gz, gx = np.gradient(hw)
    shade = np.clip(1.0 + (gx * -0.7 + gz * -0.7) * 0.6, 0.6, 1.3)
    rgb = np.clip(rgb * shade[..., None], 0, 255).astype(np.uint8)
    img = Image.fromarray(rgb[: h - 1, : w - 1]).resize(((w - 1) // SCALE, (h - 1) // SCALE), Image.BILINEAR)
    return img, meta


def main(argv):
    img, meta = render()
    if "--check" in argv:
        ok = OUT.exists() and Image.open(OUT).size == img.size and OUT.with_suffix(".json").exists()
        print("[gen_world_map] %s" % ("OK" if ok else "STALE: run tools/gen_world_map.py"))
        return 0 if ok else 1
    img.save(OUT, optimize=True)
    w, h = meta["grid"]
    info = {"origin": meta["origin"], "size": [(w - 1) * meta["spacing"], (h - 1) * meta["spacing"]]}
    OUT.with_suffix(".json").write_text(json.dumps(info, indent=2) + "\n")
    print("[gen_world_map] %dx%d -> %s" % (*img.size, OUT.relative_to(ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
