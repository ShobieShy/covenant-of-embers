#!/usr/bin/env python3
"""OW1: stitch every terrain level's heightfield into one world heightmap.

  godot --headless --path . -s res://tools/export_zone_heights.gd   # build/world/<id>.f32 + .json
  tools/build_world.py              # -> build/world/world_height.f32, world_control.u32, world.json, world_preview.png
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
SPACING = 1.0  # OPEN_WORLD_PLAN section 2: 1 m grid, 256 m regions
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
        ctl = OUT / f"{id_}.ctl"
        if ctl.exists():
            z["c"] = np.fromfile(ctl, dtype="<u4").reshape(h, w)
    return z


def _jacobi(h, free, n):
    for _ in range(n):
        avg = 0.25 * (np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1))
        h[free] = avg[free]


def relax(h, free, iters, levels=3):
    """Harmonic fill of the free cells: coarse-to-fine so 1 m grids converge in seconds."""
    if levels > 0 and min(h.shape) > 64:
        hc, fc = h[::4, ::4].copy(), free[::4, ::4].copy()
        relax(hc, fc, iters, levels - 1)
        up = np.repeat(np.repeat(hc, 4, 0), 4, 1)[: h.shape[0], : h.shape[1]]
        h[free] = up[free]
        _jacobi(h, free, max(50, iters // 20))
    else:
        _jacobi(h, free, iters)


LAYER_SHIFT, OVER_SHIFT, BLEND_SHIFT = 27, 22, 14
NAV, AUTO = 2, 1


def world_layers(zones):
    out = []
    for z in zones:
        for n in z.get("layers", []):
            if n not in out:
                out.append(n)
    return out


# Terrain3D renders a full 255 blend black at some texels; stay just under it.
BLEND_MAX = 240
# OW11 polish: the strip between two zones meets in a shared transition material (docs/OPEN_WORLD_PLAN.md
# section 2: Eldoria -> mud -> Landfill; the dirt texture is near-flat tan and read as a placeholder, Landfill -> ash -> Breach), so each side blends its own flat
# layer into it and the midline is the same on both sides: no seam, no straight two-texture smear.
STRIP_MID = {
    frozenset(("town_square", "old_oak")): "grass",
    frozenset(("town_square", "midden")): "mud_filth",
    frozenset(("old_oak", "midden")): "mud_filth",
    frozenset(("midden", "breach")): "ash_scorched",
    frozenset(("town_square", "breach")): "ash_scorched",
}
# OW11 polish: zone paint overrides for the world. "pad": [base, overlay] for the walkable pads (the
# Landfill's flat tan dirt read as placeholder squares); "patch": a ground layer broken into noise
# patches on the flats; "feather": metres the pad layer bleeds past the pad edge.
ZONE_PAINT = {
    "midden": {"pad": ["mud_filth", "rubble_junk"], "patch": "mud_filth", "feather": 3.0},
}


def smooth_noise(shape, cell, seed):
    """Deterministic value noise in [-1, 1] with features about `cell` samples wide."""
    from scipy import ndimage
    rng = np.random.default_rng(seed)
    n = ndimage.gaussian_filter(rng.standard_normal(shape).astype(np.float32), cell, mode="wrap")
    return np.clip(n / max(float(np.abs(n).max()), 1e-6), -1, 1)


def paint(zones, owner, xs, zs, layers):
    """OW2 control map, OW11 polish: zone cells keep their own paint (ids remapped to the world layer
    list, auto-shader cells made explicit: flat layer 0 / slope layer 1 by the zone's own slope, with
    ZONE_PAINT overrides); the strips between zones blend each zone's flat layer into the pair's
    STRIP_MID material, broken up by noise."""
    from scipy import ndimage
    t = [z for z in zones if z.get("terrain")]
    nz, nx = owner.shape
    ctl = np.zeros((nz, nx), np.uint32)
    dist = np.full((len(t), nz, nx), np.inf, np.float32)
    for k, z in enumerate(t):
        dist[k] = ndimage.distance_transform_edt(owner != k) * SPACING
    order = np.argsort(dist, 0)
    d1 = np.take_along_axis(dist, order[:1], 0)[0]
    d2 = np.take_along_axis(dist, order[1:2], 0)[0] if len(t) > 1 else d1 + 1
    noise = smooth_noise((nz, nx), 6.0, 11)
    fine = smooth_noise((nz, nx), 2.0, 12)
    flat = np.array([layers.index(z["layers"][0]) for z in t], np.uint32)
    a = order[0]
    b = order[1] if len(t) > 1 else order[0]
    mid = np.zeros((len(t), len(t)), np.uint32)
    for i, zi in enumerate(t):
        for j, zj in enumerate(t):
            m = STRIP_MID.get(frozenset((zi.get("id", ""), zj.get("id", ""))))
            mid[i, j] = layers.index(m) if m in layers else flat[j]
    f = d1 / np.maximum(d1 + d2, 1e-3)  # 0 at the zone edge, 0.5 at the midline
    blend = np.clip(2 * f * 255 + noise * 70 + fine * 25, 0, BLEND_MAX).astype(np.uint32)
    blend[f >= 0.45] = BLEND_MAX  # both sides show only the shared material at the midline
    ctl[:] = (flat[a] << LAYER_SHIFT) | (mid[a, b] << OVER_SHIFT) | (blend << BLEND_SHIFT) | NAV
    for k, z in enumerate(t):
        if "c" not in z:
            continue
        m = owner == k
        iz, ix = np.nonzero(m)
        ox, oz = z["origin"]
        wx, wz = z["world_offset"]
        px = np.clip(np.rint((xs[ix] - wx - ox) / z["spacing"]).astype(int), 0, z["c"].shape[1] - 1)
        pz = np.clip(np.rint((zs[iz] - wz - oz) / z["spacing"]).astype(int), 0, z["c"].shape[0] - 1)
        c = z["c"][pz, px]
        remap = np.array([layers.index(n) for n in z["layers"]] + [0] * 32, np.uint32)
        base = remap[(c >> LAYER_SHIFT) & 31]
        gy, gx = np.gradient(z["h"])
        slope = np.hypot(gx, gy)[pz, px] / z["spacing"]
        auto = (c & AUTO) != 0
        sl = remap[min(1, len(z["layers"]) - 1)]
        fl = remap[0]
        bl = np.clip((slope - 0.6) / 0.8 * 255, 0, 255).astype(np.uint32)
        ov = np.full(bl.shape, sl, np.uint32)
        cfg = ZONE_PAINT.get(z.get("id", ""), {})
        nzk, fzk = noise[iz, ix], fine[iz, ix]
        if "patch" in cfg:  # noise patches of a second ground layer where the slope layer is absent
            pb = np.clip((nzk * 0.7 + fzk * 0.3 - 0.05) * 400, 0, 200).astype(np.uint32)
            use = bl == 0
            ov = np.where(use, layers.index(cfg["patch"]), ov)
            bl = np.where(use, pb, bl)
        out = np.where(auto, (fl << LAYER_SHIFT) | (ov << OVER_SHIFT) | (bl << BLEND_SHIFT) | NAV,
                       (base << LAYER_SHIFT) | (base << OVER_SHIFT) | NAV)
        if "pad" in cfg:
            pad = ~auto
            pb_, po = layers.index(cfg["pad"][0]), layers.index(cfg["pad"][1])
            pbl = np.clip(45 + nzk * 45 + fzk * 40, 0, 160).astype(np.uint32)
            out = np.where(pad, (pb_ << LAYER_SHIFT) | (po << OVER_SHIFT) | (pbl << BLEND_SHIFT) | NAV, out)
            grid = np.zeros((nz, nx), bool)
            grid[iz[pad], ix[pad]] = True
            dpad = ndimage.distance_transform_edt(~grid)[iz, ix] * SPACING
            fe = cfg.get("feather", 0.0)
            edge = auto & (dpad > 0) & (dpad < fe) & (bl < 128)
            eb = np.clip(BLEND_MAX * (1 - dpad / max(fe, 1e-3)) + fzk * 60, 0, BLEND_MAX).astype(np.uint32)
            out = np.where(edge, (fl << LAYER_SHIFT) | (pb_ << OVER_SHIFT) | (eb << BLEND_SHIFT) | NAV, out)
        ctl[iz, ix] = out
    return ctl


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
    relax(hw, free, iters)
    layers = world_layers(t)
    ctl = paint(t, owner, xs, zs, layers) if all("layers" in z for z in t) else None
    meta = {
        "layers": layers,
        "origin": [float(x0), float(z0)], "grid": [nx, nz], "spacing": SPACING,
        "regions": [int((x1 - x0) / REGION), int((z1 - z0) / REGION)],
        "zones": {z["id"]: {"world_offset": z["world_offset"], "footprint": list(footprint(z))} for z in t},
        "height_range": [float(hw.min()), float(hw.max())],
    }
    return hw, owner, meta, ctl


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
    hw, owner, meta, _ = stitch([a, b], iters=3000)
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
    hw, owner, meta, ctl = stitch(zones)
    hw.astype("<f4").tofile(OUT / "world_height.f32")
    if ctl is not None:
        ctl.astype("<u4").tofile(OUT / "world_control.u32")
    (OUT / "world.json").write_text(json.dumps(meta, indent=2))
    preview(hw, owner, OUT / "world_preview.png")
    print("[build_world] %dx%d at %.0f m (%dx%d regions), heights %.1f..%.1f m -> build/world/" % (
        *meta["grid"], SPACING, *meta["regions"], *meta["height_range"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
