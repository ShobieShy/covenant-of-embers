#!/usr/bin/env python3
"""Project-made staff and wand part meshes (phase 0.15.0).

Reads the silhouettes in docs/specs/WEAPONS_0.15.0.md and writes glTF binaries.
One mesh per part type and tier. Staff and wand share them. No Godot primitives.

  python3 tools/make_weapon_parts.py
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "original" / "weapons" / "staff_kit"
MAT_DIR = ROOT / "resources" / "weapons"
SCENE = ROOT / "scenes" / "weapons" / "staff_wand_parts.tscn"

TAU = math.pi * 2.0
TIERS = ["basic", "uncommon", "rare", "mythic", "primordial", "unique"]
PARTS = ["head", "exterior", "interior", "handle", "charm"]

# Authored staff, metres. The wand is this assembly scaled to 0.40 m.
LAYOUT = {
    "staff_length": 1.82,
    "wand_length": 0.40,
    "handle": [0.00, 0.42],
    "exterior": [0.38, 1.38],
    "interior": [0.76, 1.22],
    "head": [1.32, 1.82],
    "charm_hook": [0.11, 1.50, 0.02],
    "view_staff": 0.72,
    "view_wand": 0.34,
}

SHAFT_R = 0.036
SEGS = 12

ELEMENTS = {
    "arcane": (0.58, 0.22, 0.82),
    "fire": (0.95, 0.28, 0.06),
    "water": (0.10, 0.45, 0.78),
    "earth": (0.32, 0.52, 0.18),
    "air": (0.72, 0.88, 0.95),
    "light": (1.00, 0.78, 0.35),
    "dark": (0.22, 0.08, 0.42),
}

WOOD = {
    "basic": (0.36, 0.24, 0.14),
    "uncommon": (0.66, 0.54, 0.36),
    "rare": (0.30, 0.18, 0.11),
    "mythic": (0.14, 0.09, 0.08),
    "primordial": (0.40, 0.30, 0.20),
    "unique": (0.26, 0.16, 0.11),
}


def vadd(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def vsub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vmul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def vdot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def vcross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def vlen(a):
    return math.sqrt(vdot(a, a))


def vnorm(a):
    length = vlen(a)
    if length < 1e-8:
        return (0.0, 1.0, 0.0)
    return vmul(a, 1.0 / length)


class Surf:
    def __init__(self):
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, int, int]] = []

    def add(self, p):
        self.verts.append((float(p[0]), float(p[1]), float(p[2])))
        return len(self.verts) - 1

    def tri(self, a, b, c):
        self.faces.append((a, b, c))

    def quad(self, a, b, c, d):
        self.tri(a, b, c)
        self.tri(a, c, d)

    def tris(self) -> int:
        return len(self.faces)


def lathe(surf: Surf, rings: list[tuple[float, float]], segs=SEGS, rx=1.0, rz=1.0, cap_ends=True):
    """rings are (y, radius). Outward winding, optional end caps."""
    grid = []
    for y, r in rings:
        row = []
        for i in range(segs):
            a = TAU * i / segs
            row.append(surf.add((r * rx * math.cos(a), y, r * rz * math.sin(a))))
        grid.append(row)
    for j in range(len(grid) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            surf.quad(grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i])
    if cap_ends and rings:
        c0 = surf.add((0.0, rings[0][0], 0.0))
        c1 = surf.add((0.0, rings[-1][0], 0.0))
        for i in range(segs):
            i2 = (i + 1) % segs
            surf.tri(c0, grid[0][i2], grid[0][i])
            surf.tri(c1, grid[-1][i], grid[-1][i2])
    return grid


def bark(surf: Surf, amp: float, fy=46.0, fa=3.0, y0=-1e9, y1=1e9):
    for i, (x, y, z) in enumerate(surf.verts):
        if y < y0 or y > y1:
            continue
        radial = math.hypot(x, z)
        if radial < 1e-4:
            continue
        ang = math.atan2(z, x)
        d = amp * (0.65 * math.sin(y * fy) * math.sin(ang * fa) + 0.35 * math.sin(y * fy * 0.37 + ang * 5.0))
        scale = (radial + d) / radial
        surf.verts[i] = (x * scale, y, z * scale)


def tube(surf: Surf, pts, rads, segs=5):
    if len(pts) < 2:
        return
    frames = []
    prev = (0.0, 0.0, 1.0)
    for i, p in enumerate(pts):
        if i == 0:
            tang = vsub(pts[1], pts[0])
        elif i == len(pts) - 1:
            tang = vsub(pts[i], pts[i - 1])
        else:
            tang = vsub(pts[i + 1], pts[i - 1])
        tang = vnorm(tang)
        side = vsub(prev, vmul(tang, vdot(prev, tang)))
        if vlen(side) < 1e-4:
            axis = (0.0, 1.0, 0.0) if abs(tang[1]) < 0.85 else (1.0, 0.0, 0.0)
            side = vsub(axis, vmul(tang, vdot(axis, tang)))
        side = vnorm(side)
        bit = vcross(tang, side)
        prev = side
        frames.append((p, side, bit, rads[i] if i < len(rads) else rads[-1]))
    rings = []
    for p, side, bit, rad in frames:
        row = []
        for s in range(segs):
            a = TAU * s / segs
            row.append(surf.add(vadd(p, vadd(vmul(side, rad * math.cos(a)), vmul(bit, rad * math.sin(a))))))
        rings.append(row)
    for j in range(len(rings) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            surf.quad(rings[j][i], rings[j][i2], rings[j + 1][i2], rings[j + 1][i])
    # caps
    for j, sign in ((0, -1), (len(rings) - 1, 1)):
        p, side, bit, rad = frames[j]
        c = surf.add(p)
        for i in range(segs):
            i2 = (i + 1) % segs
            if sign < 0:
                surf.tri(c, rings[j][i2], rings[j][i])
            else:
                surf.tri(c, rings[j][i], rings[j][i2])


def arc_pts(cx, cy, cz, radius, a0, a1, n, z_push=0.0):
    pts = []
    for i in range(n):
        t = i / (n - 1)
        a = a0 + (a1 - a0) * t
        pts.append((cx + radius * math.cos(a), cy + radius * math.sin(a), cz + z_push * math.sin(a)))
    return pts


def gem(surf: Surf, c, rx, ry, rz, segs=6):
    """Marquise / diamond, pointed on Y."""
    steps = 4
    grid = []
    for s in range(steps + 1):
        t = s / steps
        k = math.sin(t * math.pi)
        y = c[1] + (t * 2.0 - 1.0) * ry
        row = []
        for i in range(segs):
            a = TAU * i / segs
            row.append(surf.add((c[0] + rx * k * math.cos(a), y, c[2] + rz * k * math.sin(a))))
        grid.append(row)
    for j in range(steps):
        for i in range(segs):
            i2 = (i + 1) % segs
            surf.quad(grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i])


def bezel(surf: Surf, c, rx, rz, segs=8):
    rings = [(c[1] - 0.004, 0.72), (c[1], 1.0), (c[1] + 0.004, 0.72)]
    grid = []
    for y, k in rings:
        row = []
        for i in range(segs):
            a = TAU * i / segs
            row.append(surf.add((c[0] + rx * k * math.cos(a), y, c[2] + rz * k * math.sin(a))))
        grid.append(row)
    for j in range(len(grid) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            surf.quad(grid[j][i], grid[j][i2], grid[j + 1][i2], grid[j + 1][i])


def helix(surf: Surf, y0, y1, radius, tube_r, turns, n=18, phase=0.0, segs=4):
    pts = []
    rads = []
    for i in range(n):
        t = i / (n - 1)
        a = phase + turns * TAU * t
        pts.append((radius * math.cos(a), y0 + (y1 - y0) * t, radius * math.sin(a)))
        rads.append(tube_r)
    tube(surf, pts, rads, segs)


def band(surf: Surf, y, r_in, r_out, h, segs=SEGS):
    lathe(
        surf,
        [(y - h * 0.5, r_in), (y - h * 0.35, r_out), (y + h * 0.35, r_out), (y + h * 0.5, r_in)],
        segs,
        cap_ends=False,
    )


def front_x(surf: Surf, y0, y1, r, tube_r):
    z = r * 0.15
    a = (-r * 0.55, y0, r + z)
    b = (r * 0.55, y1, r + z)
    c = (r * 0.55, y0, r + z)
    d = (-r * 0.55, y1, r + z)
    for p, q in ((a, b), (c, d)):
        pts = [p, q]
        tube(surf, pts, [tube_r, tube_r], 4)


def leaf(surf: Surf, origin, along, width):
    o = origin
    tip = vadd(o, along)
    side = vnorm(vcross(along, (0.0, 0.0, 1.0)))
    if vlen(side) < 0.5:
        side = (1.0, 0.0, 0.0)
    w = vmul(side, width)
    a = surf.add(o)
    b = surf.add(vadd(vadd(o, vmul(along, 0.45)), w))
    c = surf.add(tip)
    d = surf.add(vadd(vadd(o, vmul(along, 0.45)), vmul(w, -1.0)))
    surf.tri(a, b, c)
    surf.tri(a, c, d)


def disc(surf: Surf, c, radius, segs=12, normal_z=0.012):
    """Coin facing +Z."""
    center = surf.add(c)
    ring = []
    for i in range(segs):
        a = TAU * i / segs
        ring.append(surf.add((c[0] + radius * math.cos(a), c[1] + radius * math.sin(a), c[2] + normal_z)))
    for i in range(segs):
        surf.tri(center, ring[i], ring[(i + 1) % segs])
    back = surf.add((c[0], c[1], c[2] - normal_z))
    bring = []
    for i in range(segs):
        a = TAU * i / segs
        bring.append(surf.add((c[0] + radius * math.cos(a), c[1] + radius * math.sin(a), c[2] - normal_z)))
    for i in range(segs):
        surf.tri(back, bring[(i + 1) % segs], bring[i])
    for i in range(segs):
        i2 = (i + 1) % segs
        surf.quad(ring[i], bring[i], bring[i2], ring[i2])


def torus_link(surf: Surf, c, axis, ring_r, tube_r, n=7, m=4):
    axis = vnorm(axis)
    side = vnorm(vcross(axis, (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (1.0, 0.0, 0.0)))
    bit = vcross(axis, side)
    rings = []
    for i in range(n):
        a = TAU * i / n
        center = vadd(c, vadd(vmul(side, ring_r * math.cos(a)), vmul(bit, ring_r * math.sin(a))))
        tang = vadd(vmul(side, -math.sin(a)), vmul(bit, math.cos(a)))
        nrm = vnorm(vsub(center, c))
        row = []
        for j in range(m):
            b = TAU * j / m
            row.append(surf.add(vadd(center, vadd(vmul(nrm, tube_r * math.cos(b)), vmul(tang, tube_r * math.sin(b))))))
        rings.append(row)
    for i in range(n):
        i2 = (i + 1) % n
        for j in range(m):
            j2 = (j + 1) % m
            surf.quad(rings[i][j], rings[i][j2], rings[i2][j2], rings[i2][j])


def chain(surf: Surf, origin, count, link_r, along=(0.0, -1.0, 0.0), n=6, m=3):
    step = link_r * 1.55
    direction = vnorm(along)
    for i in range(count):
        c = vadd(origin, vmul(direction, step * i))
        axis = (0.0, 0.0, 1.0) if i % 2 == 0 else (1.0, 0.0, 0.0)
        torus_link(surf, c, axis, link_r, link_r * 0.34, n, m)


def spindle_cage(metal: Surf, y0, y1, r_mid, bars, rings_y, cap_r):
    """Vertical bars that bow out, plus horizontal rings. Caps are separate."""
    for i in range(bars):
        a = TAU * i / bars
        pts = []
        rads = []
        steps = 5
        for s in range(steps):
            t = s / (steps - 1)
            y = y0 + (y1 - y0) * t
            bow = math.sin(t * math.pi)
            rad = cap_r * 0.55 + (r_mid - cap_r * 0.55) * bow
            pts.append((rad * math.cos(a), y, rad * math.sin(a)))
            rads.append(0.006 + 0.003 * bow)
        tube(metal, pts, rads, 4)
    for y in rings_y:
        t = (y - y0) / max(1e-4, y1 - y0)
        bow = math.sin(max(0.0, min(1.0, t)) * math.pi)
        rad = cap_r * 0.55 + (r_mid - cap_r * 0.55) * bow
        band(metal, y, rad * 0.92, rad * 1.08, 0.012, 10)


def heart(surf: Surf, c, s):
    """Two bulbs and a point, readable from the front."""
    gem(surf, (c[0] - s * 0.18, c[1] + s * 0.08, c[2]), s * 0.32, s * 0.30, s * 0.18, 6)
    gem(surf, (c[0] + s * 0.18, c[1] + s * 0.08, c[2]), s * 0.32, s * 0.30, s * 0.18, 6)
    gem(surf, (c[0], c[1] - s * 0.12, c[2]), s * 0.30, s * 0.40, s * 0.16, 6)


def gear(surf: Surf, c, r, teeth=8):
    z0 = c[2] - 0.004
    z1 = c[2] + 0.004
    inner = []
    outer = []
    for i in range(teeth * 2):
        a = TAU * i / (teeth * 2)
        rad = r if i % 2 == 0 else r * 0.72
        inner.append(surf.add((c[0] + rad * 0.45 * math.cos(a), c[1] + rad * 0.45 * math.sin(a), z1)))
        outer.append(surf.add((c[0] + rad * math.cos(a), c[1] + rad * math.sin(a), z1)))
    hub = surf.add((c[0], c[1], z1))
    n = teeth * 2
    for i in range(n):
        i2 = (i + 1) % n
        surf.tri(hub, inner[i], inner[i2])
        surf.quad(inner[i], outer[i], outer[i2], inner[i2])
    # back
    hubb = surf.add((c[0], c[1], z0))
    innerb = []
    outerb = []
    for i in range(n):
        a = TAU * i / n
        rad = r if i % 2 == 0 else r * 0.72
        innerb.append(surf.add((c[0] + rad * 0.45 * math.cos(a), c[1] + rad * 0.45 * math.sin(a), z0)))
        outerb.append(surf.add((c[0] + rad * math.cos(a), c[1] + rad * math.sin(a), z0)))
    for i in range(n):
        i2 = (i + 1) % n
        surf.tri(hubb, innerb[i2], innerb[i])
        surf.quad(outerb[i], innerb[i], innerb[i2], outerb[i2])


def dragon(metal: Surf, gem_s: Surf, origin_y: float):
    """Pommel dragon, face toward +Z, snout down."""
    skull_y = origin_y + 0.07
    lathe(
        metal,
        [
            (origin_y + 0.01, 0.02),
            (origin_y + 0.04, 0.048),
            (skull_y, 0.055),
            (origin_y + 0.10, 0.04),
            (origin_y + 0.12, 0.028),
        ],
        10,
    )
    snout = [
        (0.0, skull_y - 0.01, 0.03),
        (0.0, origin_y + 0.02, 0.045),
        (0.0, origin_y - 0.02, 0.03),
    ]
    tube(metal, snout, [0.028, 0.02, 0.01], 5)
    jaw = [
        (0.0, skull_y - 0.02, 0.01),
        (0.0, origin_y + 0.005, 0.02),
    ]
    tube(metal, jaw, [0.016, 0.01], 4)
    for sign in (-1.0, 1.0):
        horn = [
            (sign * 0.02, skull_y + 0.01, 0.01),
            (sign * 0.045, skull_y + 0.06, -0.01),
            (sign * 0.06, skull_y + 0.10, -0.02),
        ]
        tube(metal, horn, [0.012, 0.008, 0.004], 4)
        gem(gem_s, (sign * 0.02, skull_y, 0.05), 0.008, 0.006, 0.006, 5)


def ensure_outward(surf: Surf, around=(0.0, 0.0, 0.0)):
    if not surf.faces:
        return
    acc = 0.0
    samples = 0
    for a, b, c in surf.faces[: min(40, len(surf.faces))]:
        pa, pb, pc = surf.verts[a], surf.verts[b], surf.verts[c]
        n = vcross(vsub(pb, pa), vsub(pc, pa))
        mid = vmul(vadd(vadd(pa, pb), pc), 1.0 / 3.0)
        acc += vdot(n, vsub(mid, around))
        samples += 1
    if acc < 0.0:
        surf.faces = [(a, c, b) for a, b, c in surf.faces]


def normals_of(surf: Surf):
    acc = [[0.0, 0.0, 0.0] for _ in surf.verts]
    for a, b, c in surf.faces:
        pa, pb, pc = surf.verts[a], surf.verts[b], surf.verts[c]
        n = vcross(vsub(pb, pa), vsub(pc, pa))
        for i in (a, b, c):
            acc[i][0] += n[0]
            acc[i][1] += n[1]
            acc[i][2] += n[2]
    out = []
    for x, y, z in acc:
        length = math.sqrt(x * x + y * y + z * z) or 1.0
        out.append((x / length, y / length, z / length))
    return out


# --- parts -----------------------------------------------------------------


def _gems(surf_g, surf_m, layout):
    for i, (x, y, z, rx, ry, rz) in enumerate(layout):
        gem(surf_g, (x, y, z), rx, ry, rz, 6)
        bezel(surf_m, (x, y, z), rx * 1.15, rz * 1.15, 8)


def build_head(tier: str):
    wood, metal, wrap, gems, core = Surf(), Surf(), Surf(), Surf(), Surf()
    # stub and collar
    lathe(wood, [(0.0, SHAFT_R * 0.9), (0.14, SHAFT_R), (0.18, SHAFT_R * 1.15)], cap_ends=True)
    if tier == "basic":
        bark(wood, 0.004, y0=0.0, y1=0.2)
        helix(wrap, 0.08, 0.20, SHAFT_R * 1.2, 0.006, 1.2, 10, segs=3)
    elif tier == "mythic":
        lathe(wood, [(0.16, SHAFT_R * 1.05), (0.22, SHAFT_R * 1.25), (0.24, SHAFT_R * 0.9)], cap_ends=False)
    else:
        band(metal, 0.20, SHAFT_R * 1.05, SHAFT_R * 1.45, 0.028)
        if tier in ("rare", "unique", "primordial"):
            band(metal, 0.15, SHAFT_R, SHAFT_R * 1.25, 0.016)

    # crescent horn
    a0, a1 = math.radians(200), math.radians(15)
    thick = {"basic": 0.034, "uncommon": 0.028, "rare": 0.024, "mythic": 0.016, "primordial": 0.036, "unique": 0.022}[tier]
    n = 16 if tier != "mythic" else 18
    pts = arc_pts(0.0, 0.34, 0.0, 0.155, a0, a1, n)
    rads = [thick * (1.0 - 0.62 * (i / (n - 1))) for i in range(n)]
    host = wood if tier in ("basic", "uncommon", "primordial") else metal
    if tier == "mythic":
        host = wood
    tube(host, pts, rads, 5)
    # root into the collar
    tube(host, [(0.0, 0.18, 0.0), pts[0]], [SHAFT_R * 0.55, rads[0]], 5)
    if tier == "basic":
        bark(wood, 0.0035, fy=30.0, fa=2.0, y0=0.2, y1=0.55)
    if tier in ("rare", "mythic", "unique"):
        outer = arc_pts(0.0, 0.33, 0.0, 0.148, a0 + 0.2, a1 + 0.15, 14)
        tube(metal, outer, [0.007] * len(outer), 4)
    if tier == "mythic":
        for phase in (-0.35, 0.15, 0.55):
            tine = arc_pts(0.0, 0.33, 0.0, 0.10, math.radians(120) + phase, math.radians(40) + phase, 6)
            tube(wood, tine, [0.006, 0.005, 0.004, 0.003, 0.002, 0.001], 3)
    if tier == "unique":
        for i, p in enumerate(pts[2:-1]):
            if i % 2:
                continue
            outward = vnorm((p[0], p[1] - 0.33, 0.0))
            leaf(metal, p, vmul(outward, 0.035), 0.012)
        # wing ribbons
        wing = arc_pts(-0.02, 0.30, 0.02, 0.09, math.radians(200), math.radians(20), 8)
        tube(metal, wing, [0.006] * len(wing), 3)

    layouts = {
        "basic": [(0.0, 0.33, 0.02, 0.028, 0.048, 0.016)],
        "uncommon": [( -0.01, 0.35, 0.02, 0.024, 0.042, 0.014), (0.045, 0.27, 0.02, 0.014, 0.024, 0.01)],
        "rare": [(-0.01, 0.36, 0.022, 0.022, 0.04, 0.014), (0.04, 0.29, 0.02, 0.013, 0.022, 0.009), (0.015, 0.25, 0.02, 0.012, 0.02, 0.008)],
        "mythic": [(0.0, 0.34, 0.02, 0.022, 0.04, 0.014)],
        "primordial": [
            (0.0, 0.40, 0.02, 0.016, 0.026, 0.01),
            (-0.028, 0.33, 0.02, 0.014, 0.022, 0.009),
            (0.028, 0.33, 0.02, 0.014, 0.022, 0.009),
            (-0.018, 0.26, 0.02, 0.012, 0.02, 0.008),
            (0.018, 0.26, 0.02, 0.012, 0.02, 0.008),
        ],
        "unique": [
            (0.0, 0.36, 0.025, 0.026, 0.046, 0.016),
            (-0.055, 0.30, 0.02, 0.012, 0.02, 0.008),
            (0.05, 0.28, 0.02, 0.012, 0.02, 0.008),
            (0.0, 0.24, 0.02, 0.01, 0.018, 0.008),
        ],
    }
    _gems(gems, metal, layouts[tier])
    if tier == "primordial":
        gem(gems, (0.0, 0.10, SHAFT_R + 0.002), 0.01, 0.016, 0.004, 4)
    extras = []
    focus = layouts[tier][0]
    focus_pos = [focus[0], focus[1], focus[2]]
    tip = [0.0, 0.50, 0.0]
    if tier == "unique":
        for x in (-0.04, 0.045):
            extras.append(("chain", (x, 0.20, 0.03), 1, 0.012))
    return {"wood": wood, "metal": metal, "wrap": wrap, "gem": gems, "core": core}, focus_pos, tip, extras


def build_exterior(tier: str):
    wood, metal, wrap, gems, core = Surf(), Surf(), Surf(), Surf(), Surf()
    h = 1.00
    r = SHAFT_R
    if tier == "uncommon":
        lathe(wood, [(0.0, r * 0.95), (0.08, r), (h - 0.08, r), (h, r * 0.95)])
        band(metal, 0.18, r, r * 1.18, 0.02)
        band(metal, 0.34, r, r * 1.18, 0.02)
        # element inlay between the bands
        lathe(core, [(0.22, r * 0.98), (0.28, r * 1.02), (0.30, r * 0.98)], cap_ends=False)
        band(wrap, h * 0.72, r, r * 1.12, 0.016)
    elif tier == "basic":
        lathe(wood, [(0.0, r), (h, r)])
        bark(wood, 0.0035)
        band(wood, 0.16, r, r * 1.28, 0.03)
        band(wood, h - 0.16, r, r * 1.28, 0.03)
        front_x(wrap, 0.32, 0.62, r, 0.007)
        lathe(core, [(0.40, r * 0.2), (0.48, r * 0.55), (0.52, r * 0.2)], cap_ends=False, rx=0.4, rz=1.4)
    elif tier == "primordial":
        lathe(wood, [(0.0, r * 0.9), (0.06, r), (h - 0.06, r), (h, r * 0.9)])
        bark(wood, 0.002)
        band(metal, 0.08, r, r * 1.22, 0.02)
        band(metal, h - 0.08, r, r * 1.22, 0.02)
        for y in (0.28, 0.46, 0.64, 0.80):
            gem(gems, (0.0, y, r + 0.004), 0.012, 0.012, 0.006, 4)
    else:
        # rare, mythic, unique share a capped shaft; ornament differs
        lathe(wood, [(0.0, r * 0.95), (0.05, r), (h - 0.05, r), (h, r * 0.95)])
        if tier == "mythic":
            bark(wood, 0.0025)
        band(metal, 0.06, r, r * 1.3, 0.022)
        band(metal, h - 0.06, r, r * 1.3, 0.022)
        if tier == "unique":
            helix(wrap, 0.12, h - 0.12, r * 1.05, 0.008, 2.5, 14, phase=0.4, segs=4)
            helix(wrap, 0.12, h - 0.12, r * 1.05, 0.007, 2.5, 14, phase=math.pi + 0.4, segs=4)
            for i, y in enumerate((0.25, 0.4, 0.55, 0.7, 0.82)):
                ang = i * 1.3
                leaf(wrap, (r * math.cos(ang), y, r * math.sin(ang)), (0.02 * math.cos(ang), 0.03, 0.02 * math.sin(ang)), 0.012)
            lathe(core, [(0.35, 0.004), (0.5, 0.01), (0.65, 0.004)], cap_ends=False, rx=0.5, rz=3.0)
        else:
            turns = 2.2 if tier == "rare" else 3.2
            helix(metal, 0.14, h - 0.14, r * 1.08, 0.007, turns, 20, segs=4)
            helix(metal, 0.14, h - 0.14, r * 1.08, 0.006, turns, 20, phase=math.pi, segs=4)
            lathe(core, [(0.3, 0.005), (0.5, 0.012), (0.7, 0.005)], cap_ends=False, rx=0.6, rz=2.6)
    return {"wood": wood, "metal": metal, "wrap": wrap, "gem": gems, "core": core}


def build_interior(tier: str):
    wood, metal, wrap, gems, core = Surf(), Surf(), Surf(), Surf(), Surf()
    h = 0.46
    cap_r = SHAFT_R
    r_mid = 0.072
    lathe(wood, [(0.0, cap_r * 0.85), (0.045, cap_r), (0.07, cap_r * 0.7)], cap_ends=True)
    lathe(wood, [(h - 0.07, cap_r * 0.7), (h - 0.045, cap_r), (h, cap_r * 0.85)], cap_ends=True)
    if tier == "basic":
        spindle_cage(wood, 0.06, h - 0.06, r_mid * 0.9, 6, [0.16, h - 0.16], cap_r)
        gem(core, (0.0, h * 0.5, 0.0), 0.028, 0.09, 0.02, 8)
    elif tier == "uncommon":
        band(metal, 0.06, cap_r, cap_r * 1.25, 0.016)
        band(metal, h - 0.06, cap_r, cap_r * 1.25, 0.016)
        spindle_cage(metal, 0.07, h - 0.07, r_mid, 8, [0.14, h * 0.5, h - 0.14], cap_r)
        gem(core, (0.0, h * 0.5, 0.0), 0.02, 0.08, 0.016, 8)
    elif tier == "mythic":
        band(metal, 0.055, cap_r, cap_r * 1.3, 0.018)
        band(metal, h - 0.055, cap_r, cap_r * 1.3, 0.018)
        spindle_cage(metal, 0.07, h - 0.07, r_mid * 1.05, 8, [0.12, h - 0.12], cap_r)
        heart(core, (0.0, h * 0.50, 0.01), 0.09)
    elif tier == "primordial":
        band(metal, 0.05, cap_r, cap_r * 1.2, 0.016)
        band(metal, h - 0.05, cap_r, cap_r * 1.2, 0.016)
        spindle_cage(metal, 0.08, h - 0.08, r_mid * 0.85, 6, [h * 0.5], cap_r)
        # hexagonal prism
        lathe(core, [(h * 0.28, 0.012), (h * 0.32, 0.034), (h * 0.68, 0.034), (h * 0.72, 0.012)], segs=6)
    elif tier == "unique":
        band(metal, 0.05, cap_r, cap_r * 1.35, 0.02)
        band(metal, h - 0.05, cap_r, cap_r * 1.35, 0.02)
        spindle_cage(metal, 0.08, h - 0.08, r_mid, 4, [0.14, h - 0.14], cap_r)
        # pointed window: two bowed bars in front
        for sign in (-1.0, 1.0):
            pts = [(sign * 0.01, 0.12, 0.03), (sign * 0.04, h * 0.55, 0.04), (sign * 0.01, h - 0.12, 0.03)]
            tube(metal, pts, [0.006, 0.007, 0.006], 4)
        gem(core, (0.0, h * 0.52, 0.015), 0.018, 0.10, 0.012, 6)
        gear(metal, (0.0, h * 0.62, 0.03), 0.022, 7)
        gear(metal, (0.015, h * 0.40, 0.028), 0.016, 6)
    else:
        # rare ley channel: leaf-bowed bars
        band(metal, 0.05, cap_r, cap_r * 1.32, 0.018)
        band(metal, h - 0.05, cap_r, cap_r * 1.32, 0.018)
        spindle_cage(metal, 0.07, h - 0.07, r_mid * 1.05, 8, [0.15, h * 0.5, h - 0.15], cap_r)
        for i in range(6):
            a = TAU * i / 6
            leaf(
                metal,
                (0.03 * math.cos(a), h * 0.35, 0.03 * math.sin(a)),
                (0.02 * math.cos(a), 0.08, 0.02 * math.sin(a)),
                0.014,
            )
        gem(core, (0.0, h * 0.5, 0.012), 0.02, 0.11, 0.014, 6)
    return {"wood": wood, "metal": metal, "wrap": wrap, "gem": gems, "core": core}


def build_handle(tier: str):
    wood, metal, wrap, gems, core = Surf(), Surf(), Surf(), Surf(), Surf()
    h = 0.42
    r = SHAFT_R
    lathe(wood, [(h - 0.08, r), (h, r * 0.95)], cap_ends=True)
    if tier == "basic":
        lathe(wrap, [(0.10, r * 1.05), (0.30, r * 1.15), (0.32, r)], cap_ends=False)
        helix(wrap, 0.12, 0.30, r * 1.2, 0.005, 3.0, 16, segs=3)
        helix(wrap, 0.12, 0.30, r * 1.2, 0.005, 3.0, 16, phase=math.pi, segs=3)
        lathe(wood, [(0.0, 0.02), (0.04, r * 1.35), (0.09, r * 1.45), (0.13, r * 1.05)], cap_ends=True)
        gem(gems, (0.0, 0.045, r * 1.35), 0.012, 0.02, 0.008, 5)
        band(metal, 0.115, r, r * 1.2, 0.012)
    elif tier == "uncommon":
        lathe(wrap, [(0.08, r * 0.95), (0.12, r * 1.12), (0.30, r * 1.12), (0.33, r)], cap_ends=False)
        lathe(wood, [(0.0, 0.015), (0.035, r * 1.15), (0.08, r * 1.2), (0.11, r)], cap_ends=True)
        gem(gems, (0.0, 0.04, r * 1.15), 0.008, 0.014, 0.006, 5)
        band(metal, 0.31, r, r * 1.18, 0.012)
    elif tier == "unique":
        lathe(wrap, [(0.12, r * 1.02), (0.16, r * 1.12), (0.32, r * 1.12), (0.36, r)], cap_ends=False)
        helix(wrap, 0.14, 0.34, r * 1.15, 0.008, 2.4, 14, segs=4)
        helix(wrap, 0.14, 0.34, r * 1.15, 0.007, 2.4, 14, phase=1.2, segs=4)
        band(metal, 0.35, r, r * 1.25, 0.014)
        dragon(metal, gems, 0.0)
    else:
        # rare chain, mythic runes, primordial crystalweave: filigree, woven middle, shaped pommel
        lathe(wood, [(0.02, r * 0.85), (0.08, r), (0.36, r)], cap_ends=False)
        helix(metal, 0.22, 0.36, r * 1.12, 0.006, 1.6, 12, segs=3)
        helix(metal, 0.22, 0.36, r * 1.12, 0.006, 1.6, 12, phase=math.pi, segs=3)
        for i in range(5):
            y = 0.12 + i * 0.018
            torus_link(wrap, (0.0, y, 0.0), (1.0, 0.2, 0.0), r * 1.15, 0.005, 8, 3)
        if tier == "mythic":
            for y in (0.18, 0.24, 0.30):
                gem(gems, (0.0, y, r * 1.25), 0.008, 0.012, 0.004, 4)
        if tier == "primordial":
            for y in (0.16, 0.28):
                band(metal, y, r * 1.05, r * 1.35, 0.012, 6)
        lathe(
            metal,
            [(0.0, 0.018), (0.03, r * 1.15), (0.055, r * 1.4), (0.08, r * 1.15), (0.10, r * 0.95)],
            segs=8 if tier == "primordial" else 10,
        )
        band(metal, 0.36, r, r * 1.28, 0.014)
    return {"wood": wood, "metal": metal, "wrap": wrap, "gem": gems, "core": core}


def build_charm(tier: str):
    """Origin at the loop. Body extends down, -Y."""
    wood, metal, wrap, gems, core = Surf(), Surf(), Surf(), Surf(), Surf()
    if tier == "basic":
        torus_link(wrap, (0.0, -0.02, 0.0), (0.0, 0.0, 1.0), 0.018, 0.005, 8, 3)
        tube(wrap, [(0.0, -0.038, 0.0), (0.0, -0.06, 0.0)], [0.005, 0.005], 4)
        lathe(wood, [(-0.07, 0.01), (-0.10, 0.038), (-0.16, 0.042), (-0.22, 0.012), (-0.24, 0.004)])
        gem(gems, (0.0, -0.15, 0.03), 0.022, 0.04, 0.012, 6)
        bezel(metal, (0.0, -0.15, 0.03), 0.026, 0.016, 8)
    elif tier == "uncommon":
        torus_link(metal, (0.0, -0.018, 0.0), (1.0, 0.0, 0.0), 0.016, 0.004, 8, 3)
        tube(metal, [(0.0, -0.034, 0.0), (0.0, -0.055, 0.0)], [0.005, 0.006], 4)
        lathe(wood, [(-0.06, 0.012), (-0.09, 0.032), (-0.15, 0.036), (-0.20, 0.01)])
        gem(gems, (0.0, -0.14, 0.028), 0.018, 0.034, 0.01, 6)
        bezel(metal, (0.0, -0.14, 0.028), 0.022, 0.014, 8)
    elif tier == "mythic":
        chain(metal, (0.0, -0.02, 0.0), 3, 0.01)
        # almond frame
        lathe(metal, [(-0.07, 0.008), (-0.10, 0.032), (-0.15, 0.04), (-0.20, 0.028), (-0.23, 0.006)], segs=10)
        gem(gems, (0.0, -0.15, 0.02), 0.016, 0.028, 0.008, 4)
        disc(metal, (0.0, -0.15, 0.012), 0.034, 10, 0.004)
        gem(metal, (0.0, -0.075, 0.0), 0.006, 0.012, 0.004, 4)
        gem(metal, (0.0, -0.225, 0.0), 0.006, 0.014, 0.004, 4)
    elif tier == "unique":
        torus_link(metal, (0.0, -0.016, 0.0), (1.0, 0.0, 0.0), 0.014, 0.004, 8, 3)
        tube(metal, [(0.0, -0.03, 0.0), (0.0, -0.07, 0.0)], [0.005, 0.006], 4)
        disc(metal, (0.0, -0.15, 0.0), 0.055, 14, 0.008)
        disc(wrap, (0.0, -0.15, 0.006), 0.042, 12, 0.004)
        gem(gems, (0.0, -0.15, 0.016), 0.02, 0.028, 0.01, 4)
        gem(gems, (0.0, -0.09, 0.01), 0.008, 0.014, 0.006, 4)
        for x in (-0.028, 0.0, 0.028):
            tube(metal, [(x, -0.19, 0.0), (x, -0.23, 0.0)], [0.003, 0.003], 3)
            gem(gems, (x, -0.25, 0.0), 0.008, 0.014, 0.006, 4)
    else:
        # rare sigil and primordial relic: chain, round medallion, star gem
        links = 3 if tier == "rare" else 2
        link_r = 0.011 if tier == "primordial" else 0.01
        chain(metal, (0.0, -0.015, 0.0), links, link_r)
        rad = 0.048 if tier == "primordial" else 0.04
        y = -0.015 - link_r * 1.55 * links - rad * 0.15
        disc(metal, (0.0, y, 0.0), rad, 12, 0.008)
        disc(wrap, (0.0, y, 0.006), rad * 0.78, 12, 0.003)
        gem(gems, (0.0, y, 0.012), rad * 0.36, rad * 0.36, 0.01, 4)
        if tier == "primordial":
            band_pts = arc_pts(0.0, y, 0.0, rad * 1.05, 0.0, TAU * 0.92, 12, 0.0)
            # arc_pts is in XY; a ring facing +Z is what we want. Use torus instead.
            torus_link(metal, (0.0, y, 0.0), (0.0, 0.0, 1.0), rad, 0.006, 10, 3)
    return {"wood": wood, "metal": metal, "wrap": wrap, "gem": gems, "core": core}


def build_shaft():
    wood = Surf()
    lathe(wood, [(0.0, SHAFT_R), (1.0, SHAFT_R * 0.92)])
    bark(wood, 0.0025)
    return {"wood": wood, "metal": Surf(), "wrap": Surf(), "gem": Surf(), "core": Surf()}


def build_focus_gem():
    g = Surf()
    gem(g, (0.0, 0.0, 0.0), 0.55, 1.0, 0.38, 8)
    return {"wood": Surf(), "metal": Surf(), "wrap": Surf(), "gem": g, "core": Surf()}


def build_flare():
    g = Surf()
    gem(g, (0.0, 0.0, 0.0), 1.0, 1.0, 1.0, 6)
    return {"wood": Surf(), "metal": Surf(), "wrap": Surf(), "gem": g, "core": Surf()}


def build_figure():
    """1.8 m scale figure. A mannequin, not a character."""
    wood = Surf()
    lathe(wood, [(0.0, 0.06), (0.08, 0.07), (0.75, 0.09), (0.95, 0.16), (1.15, 0.14), (1.45, 0.11), (1.62, 0.08)], segs=8)
    lathe(wood, [(1.62, 0.08), (1.70, 0.11), (1.80, 0.07)], segs=8)
    return {"wood": wood, "metal": Surf(), "wrap": Surf(), "gem": Surf(), "core": Surf()}


# --- glb -------------------------------------------------------------------

MATS = [
    ("wood", (0.40, 0.28, 0.16), 0.02, 0.86, None),
    ("metal", (0.62, 0.58, 0.50), 0.85, 0.32, None),
    ("wrap", (0.28, 0.16, 0.10), 0.04, 0.72, None),
    ("gem", (1.0, 1.0, 1.0), 0.15, 0.08, (1.0, 1.0, 1.0)),
    ("core", (1.0, 1.0, 1.0), 0.05, 0.22, (1.0, 1.0, 1.0)),
]


def write_glb(path: Path, surfaces: dict[str, Surf], extras_nodes: list[dict]):
    roles = {name: i for i, (name, *_) in enumerate(MATS)}
    blobs_pos = bytearray()
    blobs_nrm = bytearray()
    blobs_idx = bytearray()
    primitives = []
    for name, _color, _met, _rough, _em in MATS:
        surf = surfaces.get(name)
        if surf is None or not surf.faces:
            continue
        ensure_outward(surf)
        norms = normals_of(surf)
        for p in surf.verts:
            blobs_pos += struct.pack("<fff", *p)
        for n in norms:
            blobs_nrm += struct.pack("<fff", *n)
        start_idx = len(blobs_idx) // 4
        for a, b, c in surf.faces:
            # Indices are local to this primitive's vertex accessor.
            blobs_idx += struct.pack("<III", a, b, c)
        count_i = len(surf.faces) * 3
        primitives.append((name, roles[name], 0, len(surf.verts), start_idx, count_i, surf))

    bin_blob = bytearray()
    views = []

    def push(data: bytes, target=None):
        nonlocal bin_blob
        while len(bin_blob) % 4:
            bin_blob.append(0)
        offset = len(bin_blob)
        bin_blob += data
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        return len(views) - 1

    # one view per primitive's positions, normals, indices so accessors stay simple
    accessors = []
    gl_prims = []
    # We'll store per-primitive slices. Rebuild from primitives using global buffers
    # sliced by byte ranges.
    pos_all = bytes(blobs_pos)
    nrm_all = bytes(blobs_nrm)
    idx_all = bytes(blobs_idx)
    pos_view = push(pos_all, 34962)
    nrm_view = push(nrm_all, 34962)
    idx_view = push(idx_all, 34963)

    cursor_v = 0
    cursor_i = 0
    for name, mat_i, _base, vcount, _istart, icount, surf in primitives:
        pmin = [min(p[k] for p in surf.verts) for k in range(3)]
        pmax = [max(p[k] for p in surf.verts) for k in range(3)]
        acc_pos = {
            "bufferView": pos_view,
            "byteOffset": cursor_v * 12,
            "componentType": 5126,
            "count": vcount,
            "type": "VEC3",
            "min": pmin,
            "max": pmax,
        }
        acc_nrm = {
            "bufferView": nrm_view,
            "byteOffset": cursor_v * 12,
            "componentType": 5126,
            "count": vcount,
            "type": "VEC3",
        }
        acc_idx = {
            "bufferView": idx_view,
            "byteOffset": cursor_i * 4,
            "componentType": 5125,
            "count": icount,
            "type": "SCALAR",
        }
        ip = len(accessors)
        accessors.extend([acc_pos, acc_nrm, acc_idx])
        gl_prims.append(
            {
                "attributes": {"POSITION": ip, "NORMAL": ip + 1},
                "indices": ip + 2,
                "material": mat_i,
            }
        )
        cursor_v += vcount
        cursor_i += icount

    materials = []
    for name, color, met, rough, em in MATS:
        m = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [color[0], color[1], color[2], 1.0],
                "metallicFactor": met,
                "roughnessFactor": rough,
            },
        }
        if em:
            m["emissiveFactor"] = list(em)
        materials.append(m)

    nodes = [{"name": path.stem, "mesh": 0, "children": []}]
    for extra in extras_nodes:
        nodes.append(extra)
        nodes[0]["children"].append(len(nodes) - 1)
    if not nodes[0]["children"]:
        del nodes[0]["children"]

    gltf = {
        "asset": {"version": "2.0", "generator": "make_weapon_parts.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": [{"name": path.stem, "primitives": gl_prims}],
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(bin_blob)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    blob = bytes(bin_blob)
    while len(blob) % 4:
        blob += b"\x00"
    total = 12 + 8 + len(js) + 8 + len(blob)
    data = struct.pack("<III", 0x46546C67, 2, total)
    data += struct.pack("<II", len(js), 0x4E4F534A) + js
    data += struct.pack("<II", len(blob), 0x004E4942) + blob
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return sum(s.tris() for s in surfaces.values())


def chain_mesh(count, link_r):
    s = Surf()
    chain(s, (0.0, 0.0, 0.0), count, link_r)
    # end drop
    gem(s, (0.0, -link_r * 1.55 * count - 0.01, 0.0), link_r * 0.7, link_r * 1.1, link_r * 0.45, 5)
    return s


def write_tres():
    MAT_DIR.mkdir(parents=True, exist_ok=True)
    files = []
    for name, color in ELEMENTS.items():
        text = (
            '[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\n'
            f'resource_name = "element_{name}"\n'
            f"albedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\n"
            "metallic = 0.12\nroughness = 0.1\nemission_enabled = true\n"
            f"emission = Color({color[0]}, {color[1]}, {color[2]}, 1)\n"
            "emission_energy_multiplier = 1.7\n"
        )
        p = MAT_DIR / f"element_{name}.tres"
        p.write_text(text)
        files.append(p.name)
    bases = {
        "weapon_wood.tres": ((0.40, 0.28, 0.16), 0.02, 0.86, False),
        "weapon_metal.tres": ((0.62, 0.58, 0.50), 0.85, 0.32, False),
        "weapon_wrap.tres": ((0.28, 0.16, 0.10), 0.04, 0.72, False),
    }
    for fname, (color, met, rough, _em) in bases.items():
        text = (
            '[gd_resource type="StandardMaterial3D" format=3]\n\n[resource]\n'
            f"albedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\n"
            f"metallic = {met}\nroughness = {rough}\n"
        )
        (MAT_DIR / fname).write_text(text)
        files.append(fname)
    return files


def write_scene(names: list[str]):
    SCENE.parent.mkdir(parents=True, exist_ok=True)
    lines = ["[gd_scene load_steps=%d format=3]\n" % (len(names) + 1)]
    for i, name in enumerate(names, start=1):
        lines.append(
            f'[ext_resource type="PackedScene" path="res://assets/original/weapons/staff_kit/{name}.glb" id="{i}"]\n'
        )
    lines.append('\n[node name="StaffWandParts" type="Node3D"]\n')
    for i, name in enumerate(names, start=1):
        lines.append(f'\n[node name="{name}" parent="." instance=ExtResource("{i}")]\n')
        lines.append(f"transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {(i - 1) * 0.35}, 0, 0)\n")
    SCENE.write_text("".join(lines))


def main():
    builders = {
        "head": build_head,
        "exterior": build_exterior,
        "interior": build_interior,
        "handle": build_handle,
        "charm": build_charm,
    }
    counts = {}
    names = []
    focus = {}
    for part in PARTS:
        for tier in TIERS:
            built = builders[part](tier)
            extras = []
            if part == "head":
                surfaces, focus_pos, tip, chains = built
                extras.append({"name": "Focus", "translation": focus_pos})
                extras.append({"name": "Tip", "translation": tip})
                focus[tier] = focus_pos
                # chains are separate meshes so they can hang
                # Stored inside this glb as extra nodes. Built below after we know the format.
                chain_prims = []
                for kind, origin, count, link_r in chains:
                    chain_prims.append((origin, count, link_r))
            else:
                surfaces = built
                chain_prims = []
            # Unique head chains: merge into the metal/gem surfaces so the part
            # sheet shows them without a second mesh. StaffKit hangs nothing
            # inside the head; the chains are short ornaments along -Y.
            if part == "head":
                for origin, count, link_r in chain_prims:
                    chain(surfaces["metal"], origin, count, link_r)
                    gem(
                        surfaces["gem"],
                        (origin[0], origin[1] - link_r * 1.55 * count, origin[2]),
                        link_r * 0.55,
                        link_r * 0.9,
                        link_r * 0.4,
                        4,
                    )
            path = OUT / f"{part}_{tier}.glb"
            counts[path.name] = write_glb(path, surfaces, extras if part == "head" else [])
            names.append(path.stem)
            print(f"{path.name:24} {counts[path.name]:5} tris")

    for label, fn in (
        ("shaft_plain", build_shaft),
        ("focus_gem", build_focus_gem),
        ("muzzle_flare", build_flare),
        ("scale_figure", build_figure),
    ):
        path = OUT / f"{label}.glb"
        counts[path.name] = write_glb(path, fn(), [])
        names.append(label)
        print(f"{path.name:24} {counts[path.name]:5} tris")

    # Worst-case full kit: unique of every part plus the focus gem.
    full = sum(counts[f"{p}_unique.glb"] for p in PARTS) + counts["focus_gem.glb"]
    print(f"unique full kit + gem {full} tris")
    if full > 3800:
        raise SystemExit(f"unique kit is {full} tris, over the 3800 headroom for the 4k viewmodel cap")

    layout = dict(LAYOUT)
    layout["focus_local"] = focus
    layout["files"] = names
    (OUT / "layout.json").write_text(json.dumps(layout, indent=2) + "\n")
    write_tres()
    write_scene(names)
    print(f"wrote {len(names)} meshes, materials, {SCENE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
