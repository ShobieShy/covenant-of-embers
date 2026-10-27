#!/usr/bin/env python3
"""OW1: stitch every terrain level's heightfield into one world heightmap.

  godot --headless --path . -s res://tools/export_zone_heights.gd   # build/world/<id>.f32 + .json
  tools/build_world.py              # -> build/world/world_height.f32, world.json, world_preview.png
  tools/build_world.py --check      # layout checks only (footprints, gaps, 16 m offsets)
  tools/build_world.py --self-test

Each zone lands at its [level] world_offset (docs/WORLD_LAYOUT.md). The zone's edge rim
(TerrainZone.EDGE metres rising to `rim`) is cut off; the land between zones is a smooth
Laplace fill from the zone edges, falling to 0 at the world edge. World grid: SPACING m,
origin snapped to the Terrain3D region grid (256 vertices). Needs numpy (+ Pillow for the
preview).
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "world"
SPACING = 2.0
REGION = 256 * SPACING
EDGE = 24.0  # TerrainZone.EDGE
MIN_GAP = 64.0  # transition strip between footprints (OPEN_WORLD_PLAN section 2: 24-64 m)
MARGIN = 256.0


def footprint(z):
    (cx, cz), (sx, sz), (ox, oz) = z["center"], z["size"], z["world_offset"]
    return (cx + ox - sx / 2, cz + oz - sz / 2, cx + ox + sx / 2, cz + oz + sz / 2)


def gap(a, b):
    dx = max(b[0] - a[2], a[0] - b[2], 0.0)
    dz = max(b[1] - a[3], a[1] - b[3], 0.0)
    overlap = b[0] < a[2] and a[0] < b[2] and b[1] < a[3] and a[1] < b[3]
    return -1.0 if overlap else max(dx, dz)


def check(zones):
    errs = []
    for z in zones:
        if any(v % 16 for v in z["world_offset"]):
            errs.append(f"{z['id']}: world_offset {z['world_offset']} not on the 16 m grid")
    t = [z for z in zones if z.get("terrain")]
    for i, a in enumerate(t):
        for b in t[i + 1:]:
            g = gap(footprint(a), footprint(b))
            if g < MIN_GAP:
                errs.append(f"{a['id']} / {b['id']}: gap {g:.0f} m < {MIN_GAP:.0f} m")
    return errs


def load(id_):
    z = json.loads((OUT / f"{id_}.json").read_text())
    if z.get("terrain"):
        w, h = z["grid"]
        z["h"] = np.fromfile(OUT / f"{id_}.f32", dtype="<f4").reshape(h, w)
    return z


def stitch(zones, iters=4000):
    t = [z for z in zones if z.get("terrain")]
    fp = np.array([footprint(z) for z in t])
    x0 = np.floor((fp[:, 0].min() - MARGIN) / REGION) * REGION
    z0 = np.floor((fp[:, 1].min() - MARGIN) / REGION) * REGION
    x1 = np.ceil((fp[:, 2].max() + MARGIN) / REGION) * REGION
    z1 = np.ceil((fp[:, 3].max() + MARGIN) / REGION) * REGION
    nx, nz = int((x1 - x0) / SPACING) + 1, int((z1 - z0) / SPACING) + 1
    hw = np.zeros((nz, nx), np.float32)
    fixed = np.zeros((nz, nx), bool)
    owner = np.full((nz, nx), -1, np.int8)
    xs, zs = x0 + np.arange(nx) * SPACING, z0 + np.arange(nz) * SPACING
    for k, z in enumerate(t):
        a = footprint(z)
        ix = np.where((xs >= a[0] + EDGE) & (xs <= a[2] - EDGE))[0]
        iz = np.where((zs >= a[1] + EDGE) & (zs <= a[3] - EDGE))[0]
        ox, oz = z["origin"]
        s = z["spacing"]
        wx, wz = z["world_offset"]
        # world -> zone pixel (nearest; zone spacing <= world spacing)
        px = np.clip(np.rint((xs[ix] - wx - ox) / s).astype(int), 0, z["h"].shape[1] - 1)
        pz = np.clip(np.rint((zs[iz] - wz - oz) / s).astype(int), 0, z["h"].shape[0] - 1)
        hw[np.ix_(iz, ix)] = z["h"][np.ix_(pz, px)]
        fixed[np.ix_(iz, ix)] = True
        owner[np.ix_(iz, ix)] = k
    border = np.zeros_like(fixed)
    border[0, :] = border[-1, :] = border[:, 0] = border[:, -1] = True
    free = ~fixed & ~border
    hw[border] = 0.0
    for _ in range(iters):  # Jacobi relaxation of the gaps (harmonic fill)
        avg = 0.25 * (np.roll(hw, 1, 0) + np.roll(hw, -1, 0) + np.roll(hw, 1, 1) + np.roll(hw, -1, 1))
        hw[free] = avg[free]
    meta = {
        "origin": [float(x0), float(z0)], "grid": [nx, nz], "spacing": SPACING,
        "regions": [int((x1 - x0) / REGION), int((z1 - z0) / REGION)],
        "zones": {z["id"]: {"world_offset": z["world_offset"], "footprint": list(footprint(z))} for z in t},
        "height_range": [float(hw.min()), float(hw.max())],
    }
    return hw, owner, meta


def preview(hw, owner, path):
    from PIL import Image
    g = (hw - hw.min()) / max(1e-6, float(hw.max() - hw.min()))
    rgb = np.stack([g, g, g], -1)
    tint = np.array([[1, .8, .8], [.8, 1, .8], [.8, .8, 1], [1, 1, .7]])
    for k in range(int(owner.max()) + 1):
        rgb[owner == k] *= tint[k % 4]
    Image.fromarray((rgb * 255).astype(np.uint8)).save(path)


def self_test():
    a = {"id": "a", "terrain": True, "center": [0, 0], "size": [100, 100], "world_offset": [0, 0]}
    b = dict(a, id="b", world_offset=[176, 0])
    assert not check([a, b]), check([a, b])
    assert check([a, dict(b, world_offset=[144, 0])])  # 44 m gap
    assert check([a, dict(b, world_offset=[32, 0])])  # overlap
    assert check([dict(a, world_offset=[8, 0])])  # off-grid
    for z, off in ((a, 0), (b, 176)):
        z["origin"], z["spacing"], z["h"] = [-50, -50], 1.0, np.full((101, 101), 5.0 if off else 1.0, np.float32)
    hw, owner, meta = stitch([a, b], iters=3000)
    mid = hw[int((0 - meta["origin"][1]) / SPACING), int((88 - meta["origin"][0]) / SPACING)]
    assert 1.0 < mid < 5.0, mid  # the gap blends between the two zones
    assert meta["origin"][0] % REGION == 0
    print("[build_world] self-test OK")


def main(argv):
    if "--self-test" in argv:
        self_test()
        return 0
    ids = [p.stem for p in sorted(OUT.glob("*.json")) if p.stem != "world"]
    if not ids:
        print("[build_world] no exports: run tools/export_zone_heights.gd first")
        return 1
    zones = [load(i) for i in ids]
    errs = check(zones)
    for e in errs:
        print("[build_world] ERROR", e)
    if errs or "--check" in argv:
        print("[build_world] layout %s (%d zones)" % ("FAILED" if errs else "OK", len(zones)))
        return 1 if errs else 0
    hw, owner, meta = stitch(zones)
    hw.astype("<f4").tofile(OUT / "world_height.f32")
    (OUT / "world.json").write_text(json.dumps(meta, indent=2))
    preview(hw, owner, OUT / "world_preview.png")
    print("[build_world] %dx%d at %.0f m (%dx%d regions), heights %.1f..%.1f m -> build/world/" % (
        *meta["grid"], SPACING, *meta["regions"], *meta["height_range"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
