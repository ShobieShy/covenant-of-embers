#!/usr/bin/env python3
"""Bob's lab interior mesh. Original geometry, ambientCG PBR, no engine primitives.

The hollow is an oval timber room inside a rock shell: ground floor, spiral stair
on the west, loft with the slab table, potion shelves and cauldron bench. Run from
the repo root: python3 assets/levels/bobs_lab/build_hollow.py
"""
from __future__ import annotations

import json
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent

FLOOR_TOP = 0.40
LOFT_TOP = 3.36
CEIL_Y = 6.12
RX = 3.90
RZ = 3.20
DOOR_HALF = 0.96
DOOR_TOP = 2.52
# Spiral on the west. Angle 0 points east (+X). Positive angle turns toward +Z (south).
SCX, SCZ = -1.58, 0.08
STAIR_R = 1.16
RADIAL = 1.52
TANG = 1.58
TREAD = 0.16
N_STEPS = 16
RISE = (LOFT_TOP - FLOOR_TOP) / N_STEPS
STEP_ARC = 0.44
DANG = STEP_ARC / STAIR_R
ANG0 = 0.20

WOOD = "wood"
WOOD_DARK = "wood_dark"
ROCK = "rock"
PLASTER = "plaster"
METAL = "metal"
PARCHMENT = "parchment"
LIQUID = "liquid"
FIRE = "fire"
GLASS = {
    "violet": (0.42, 0.12, 0.78),
    "green": (0.08, 0.55, 0.22),
    "amber": (0.86, 0.48, 0.08),
    "blue": (0.12, 0.32, 0.82),
    "red": (0.72, 0.08, 0.10),
}


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def length(a):
    return math.sqrt(dot(a, a))


def norm(a):
    n = length(a)
    return (0.0, 1.0, 0.0) if n < 1e-8 else mul(a, 1.0 / n)


def lerp(a, b, t):
    return add(mul(a, 1.0 - t), mul(b, t))


def write_png(path: Path, w: int, h: int, rgb: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgb[y * w * 3:(y + 1) * w * 3] for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def _hash(ix: int, iy: int) -> float:
    n = (ix * 374761393 + iy * 668265263) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def _noise(x: float, y: float) -> float:
    x0, y0 = math.floor(x), math.floor(y)
    fx, fy = x - x0, y - y0
    ix, iy = int(x0), int(y0)
    v00, v10 = _hash(ix, iy), _hash(ix + 1, iy)
    v01, v11 = _hash(ix, iy + 1), _hash(ix + 1, iy + 1)
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    return (v00 * (1 - sx) + v10 * sx) * (1 - sy) + (v01 * (1 - sx) + v11 * sx) * sy


def make_textures() -> None:
    w = h = 512
    plaster = bytearray(w * h * 3)
    parchment = bytearray(w * h * 3)
    for y in range(h):
        for x in range(w):
            n = _noise(x / 64.0, y / 64.0) * 0.7 + _noise(x / 18.0, y / 18.0) * 0.3
            crack = _noise(x / 7.0, y / 90.0)
            dark = 55 if crack > 0.82 else 0
            base = (188 + n * 22 - dark, 170 + n * 18 - dark, 142 + n * 14 - dark)
            i = (y * w + x) * 3
            plaster[i:i + 3] = bytes(max(0, min(255, int(c))) for c in base)
            edge = min(x, y, w - 1 - x, h - 1 - y) / 28.0
            ink = 0.0
            if 40 < x < 470 and abs(y - 80 - 40 * math.sin(x / 40.0)) < 2:
                ink = 1.0
            if 60 < y < 450 and abs(x - 200 - 30 * math.sin(y / 35.0)) < 2:
                ink = 1.0
            paper = 214 - (1.0 - min(edge, 1.0)) * 70 - ink * 140 + _noise(x / 20.0, y / 20.0) * 12
            parchment[i:i + 3] = bytes(max(0, min(255, int(paper - k))) for k in (0, 12, 36))
    write_png(OUT / "plaster.png", w, h, bytes(plaster))
    write_png(OUT / "parchment.png", w, h, bytes(parchment))


class Mesh:
    def __init__(self) -> None:
        self.prims: dict[str, dict] = {}

    def _p(self, mat: str) -> dict:
        return self.prims.setdefault(mat, {"p": [], "n": [], "uv": [], "i": []})

    def quad(self, mat: str, corners: list, hint, uv_scale: float = 1.0) -> None:
        e1 = sub(corners[1], corners[0])
        e2 = sub(corners[3], corners[0])
        n = cross(e1, e2)
        if length(n) < 1e-8:
            return
        if dot(n, hint) < 0:
            corners = [corners[0], corners[3], corners[2], corners[1]]
            e1 = sub(corners[1], corners[0])
            e2 = sub(corners[3], corners[0])
            n = cross(e1, e2)
        n = norm(n)
        lu = max(length(e1), 1e-4) * uv_scale
        lv = max(length(e2), 1e-4) * uv_scale
        m = self._p(mat)
        base = len(m["p"]) // 3
        for p, uv in ((corners[0], (0.0, 0.0)), (corners[1], (lu, 0.0)), (corners[2], (lu, lv)), (corners[3], (0.0, lv))):
            m["p"].extend(p)
            m["n"].extend(n)
            m["uv"].extend(uv)
        m["i"].extend([base, base + 1, base + 2, base, base + 2, base + 3])

    def box(self, mat: str, center, size, ax=(1, 0, 0), ay=(0, 1, 0), az=(0, 0, 1), uv=1.0) -> None:
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5

        def corner(sx, sy, sz):
            return add(center, add(mul(ax, sx * hx), add(mul(ay, sy * hy), mul(az, sz * hz))))

        faces = (
            ((1, -1, -1), (1, -1, 1), (1, 1, 1), (1, 1, -1), ax),
            ((-1, -1, 1), (-1, -1, -1), (-1, 1, -1), (-1, 1, 1), mul(ax, -1)),
            ((-1, 1, -1), (1, 1, -1), (1, 1, 1), (-1, 1, 1), ay),
            ((-1, -1, 1), (1, -1, 1), (1, -1, -1), (-1, -1, -1), mul(ay, -1)),
            ((-1, -1, 1), (-1, 1, 1), (1, 1, 1), (1, -1, 1), az),
            ((1, -1, -1), (1, 1, -1), (-1, 1, -1), (-1, -1, -1), mul(az, -1)),
        )
        for a, b, c, d, hint in faces:
            self.quad(mat, [corner(*a), corner(*b), corner(*c), corner(*d)], hint, uv)

    def cylinder(self, mat: str, a, b, radius: float, segs: int = 12, uv=1.0, caps=True) -> None:
        axis = norm(sub(b, a))
        tmp = (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)
        t1 = norm(cross(axis, tmp))
        t2 = cross(axis, t1)
        rings = []
        for p in (a, b):
            ring = []
            for i in range(segs):
                ang = 2 * math.pi * i / segs
                ring.append(add(p, add(mul(t1, math.cos(ang) * radius), mul(t2, math.sin(ang) * radius))))
            rings.append(ring)
        for i in range(segs):
            j = (i + 1) % segs
            mid = mul(add(add(rings[0][i], rings[0][j]), add(rings[1][i], rings[1][j])), 0.25)
            hint = sub(mid, mul(add(a, b), 0.5))
            self.quad(mat, [rings[0][i], rings[0][j], rings[1][j], rings[1][i]], hint, uv)
        if caps:
            for ring, end, sign in ((rings[0], a, -1), (rings[1], b, 1)):
                c = end
                m = self._p(mat)
                base = len(m["p"]) // 3
                m["p"].extend(c)
                m["n"].extend(mul(axis, sign))
                m["uv"].extend((0.5, 0.5))
                for i in range(segs):
                    m["p"].extend(ring[i])
                    m["n"].extend(mul(axis, sign))
                    m["uv"].extend((0.5 + 0.5 * math.cos(2 * math.pi * i / segs), 0.5 + 0.5 * math.sin(2 * math.pi * i / segs)))
                for i in range(segs):
                    j = (i + 1) % segs
                    if sign > 0:
                        m["i"].extend([base, base + 1 + i, base + 1 + j])
                    else:
                        m["i"].extend([base, base + 1 + j, base + 1 + i])


def ellipse(theta: float, y: float, rx: float, rz: float, bulge: float) -> tuple:
    x = math.sin(theta) * rx
    z = math.cos(theta) * rz
    outward = norm((x, 0.0, z))
    wobble = bulge * (0.10 * math.sin(theta * 3.0 + y * 0.55) + 0.05 * math.sin(theta * 7.0 - y * 0.8))
    return (x + outward[0] * wobble, y, z + outward[2] * wobble), outward


def in_door(theta: float) -> bool:
    # theta 0 is +Z, the south door. Wrap into -pi..pi.
    a = (theta + math.pi) % (2 * math.pi) - math.pi
    return abs(a) < 0.30


def steps() -> list[dict]:
    out = []
    for i in range(N_STEPS):
        a = ANG0 + i * DANG
        radial = (math.cos(a), 0.0, math.sin(a))
        tangent = (-math.sin(a), 0.0, math.cos(a))
        top = FLOOR_TOP + (i + 1) * RISE
        center = (SCX + radial[0] * STAIR_R, top - TREAD * 0.5, SCZ + radial[2] * STAIR_R)
        out.append({
            "i": i + 1,
            "a": a,
            "center": center,
            "top": top,
            "radial": radial,
            "tangent": tangent,
            "yaw": -math.degrees(a),
        })
    return out


def build() -> Mesh:
    m = Mesh()
    segs = 44
    bands = ((FLOOR_TOP, 1.42, WOOD), (1.42, LOFT_TOP + 0.02, PLASTER), (LOFT_TOP + 0.02, CEIL_Y, PLASTER))
    for i in range(segs):
        t0 = -math.pi + 2 * math.pi * i / segs
        t1 = -math.pi + 2 * math.pi * (i + 1) / segs
        tm = (t0 + t1) * 0.5
        door = in_door(tm)
        for y0, y1, mat in bands:
            if door and y1 <= DOOR_TOP:
                continue
            ya, yb = (DOOR_TOP, y1) if door and y0 < DOOR_TOP else (y0, y1)
            p00, _ = ellipse(t0, ya, RX - 0.08, RZ - 0.08, 0.35)
            p10, _ = ellipse(t1, ya, RX - 0.08, RZ - 0.08, 0.35)
            p11, _ = ellipse(t1, yb, RX - 0.08, RZ - 0.08, 0.35)
            p01, _ = ellipse(t0, yb, RX - 0.08, RZ - 0.08, 0.35)
            inward = mul(norm(p00), -1)
            m.quad(mat, [p00, p10, p11, p01], inward, 0.55 if mat == WOOD else 0.85)
            o00, n0 = ellipse(t0, ya, RX + 0.34, RZ + 0.30, 1.0)
            o10, n1 = ellipse(t1, ya, RX + 0.34, RZ + 0.30, 1.0)
            o11, _ = ellipse(t1, yb, RX + 0.34, RZ + 0.30, 1.0)
            o01, _ = ellipse(t0, yb, RX + 0.34, RZ + 0.30, 1.0)
            m.quad(ROCK, [o00, o01, o11, o10], add(n0, n1), 0.35)
        if not door and i % 3 == 0:
            p, _ = ellipse(t0, FLOOR_TOP, RX - 0.16, RZ - 0.16, 0.2)
            m.box(WOOD_DARK, (p[0], (FLOOR_TOP + CEIL_Y) * 0.5, p[2]), (0.14, CEIL_Y - FLOOR_TOP, 0.16), uv=1.4)
        if not door and i % 4 == 0:
            for yb in (1.38, LOFT_TOP - 0.02, CEIL_Y - 0.18):
                a, _ = ellipse(t0, yb, RX - 0.12, RZ - 0.12, 0.2)
                b, _ = ellipse(t1, yb, RX - 0.12, RZ - 0.12, 0.2)
                mid = mul(add(a, b), 0.5)
                span = length(sub(b, a))
                axis = norm(sub(b, a))
                m.box(WOOD_DARK, mid, (span, 0.10, 0.12), axis, (0, 1, 0), norm(cross((0, 1, 0), axis)), 1.6)
    # Door jambs and a timber arch. The opening itself stays clear for the exit.
    for side in (-1, 1):
        m.box(WOOD_DARK, (side * DOOR_HALF, FLOOR_TOP + DOOR_TOP * 0.5, RZ - 0.02), (0.16, DOOR_TOP, 0.42), uv=1.2)
    arch_segs = 10
    for i in range(arch_segs):
        u0 = i / arch_segs
        u1 = (i + 1) / arch_segs
        a0 = math.pi * (1 - u0)
        a1 = math.pi * (1 - u1)
        for inset in (0.0, 0.18):
            def ap(ang, inset=inset):
                return (math.cos(ang) * (DOOR_HALF - 0.02), DOOR_TOP + math.sin(ang) * 0.72 - inset, RZ - 0.02)
            m.quad(WOOD_DARK, [ap(a0), ap(a1), add(ap(a1), (0, 0.12, 0)), add(ap(a0), (0, 0.12, 0))], (0, 0, 1), 1.2)
    # Swung-open door leaf, clear of the threshold.
    m.box(WOOD, (DOOR_HALF + 0.46, FLOOR_TOP + 1.15, RZ - 0.55), (0.08, 2.2, 0.78), (0.35, 0, 0.94), (0, 1, 0), norm(cross((0, 1, 0), (0.35, 0, 0.94))), 1.1)

    def floor_disc(y, rx, rz, hole, hole_r, mat):
        nx, nz = 16, 14
        for ix in range(nx):
            for iz in range(nz):
                x0 = -rx + 2 * rx * ix / nx
                x1 = -rx + 2 * rx * (ix + 1) / nx
                z0 = -rz + 2 * rz * iz / nz
                z1 = -rz + 2 * rz * (iz + 1) / nz
                cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
                if (cx / rx) ** 2 + (cz / rz) ** 2 > 0.98:
                    continue
                if hole and (cx - hole[0]) ** 2 + (cz - hole[1]) ** 2 < hole_r ** 2:
                    continue
                m.box(mat, (cx, y - 0.035, cz), (x1 - x0, 0.07, z1 - z0), uv=1.3)

    floor_disc(FLOOR_TOP, RX - 0.18, RZ - 0.18, None, 0.0, WOOD)
    # The loft is the whole oval except the stair well. The landing is the east lip.
    floor_disc(LOFT_TOP, RX - 0.22, RZ - 0.22, (SCX, SCZ), STAIR_R + RADIAL * 0.42, WOOD)
    m.box(WOOD, (SCX + STAIR_R + 0.55, LOFT_TOP - 0.035, SCZ), (1.35, 0.07, 1.7), uv=1.2)

    # Ceiling planks and beams.
    floor_disc(CEIL_Y, RX - 0.28, RZ - 0.28, None, 0.0, WOOD_DARK)
    for z, w in ((-1.6, 0.16), (-0.4, 0.18), (0.8, 0.16), (1.9, 0.14)):
        m.box(WOOD_DARK, (0.15, CEIL_Y - 0.16, z), (RX * 1.55, 0.14, w), uv=0.8)
    m.box(WOOD_DARK, (0.0, CEIL_Y - 0.28, 0.1), (0.2, 0.16, RZ * 1.7), uv=0.7)
    # Living-wood ribs dropping from the ceiling.
    for k, theta in enumerate((0.9, 1.7, 2.5, 3.6, 4.4, 5.3)):
        top, _ = ellipse(theta, CEIL_Y - 0.1, RX - 0.4, RZ - 0.35, 0.4)
        low, _ = ellipse(theta, 2.2 + (k % 3) * 0.4, RX - 0.2, RZ - 0.18, 0.3)
        m.cylinder(WOOD_DARK, top, low, 0.07, 8, 1.4)

    for s in steps():
        # Collision treads overlap so the navmesh connects. The visible tread is shorter.
        tread = (s["center"][0], s["top"] - 0.04, s["center"][2])
        m.box(WOOD, tread, (RADIAL * 0.9, 0.08, 0.7), s["radial"], (0, 1, 0), s["tangent"], 1.5)
        outer = add(s["center"], mul(s["radial"], RADIAL * 0.48))
        m.box(WOOD_DARK, (outer[0], s["top"] + 0.48, outer[2]), (0.06, 0.96, 0.06), uv=2.0)
        rail = (outer[0], s["top"] + 0.92, outer[2])
        nxt_a = s["a"] + DANG
        nxt = (SCX + math.cos(nxt_a) * (STAIR_R + RADIAL * 0.48), s["top"] + RISE + 0.92, SCZ + math.sin(nxt_a) * (STAIR_R + RADIAL * 0.48))
        if s["i"] < N_STEPS:
            m.cylinder(WOOD_DARK, rail, nxt, 0.035, 6, 2.0, caps=False)
    m.cylinder(WOOD_DARK, (SCX, FLOOR_TOP, SCZ), (SCX, LOFT_TOP + 0.9, SCZ), 0.09, 10, 1.2)

    def shelf(origin, yaw: float, width: float, depth: float, rows: int) -> None:
        ax = (math.cos(yaw), 0.0, math.sin(yaw))  # width
        az = (-math.sin(yaw), 0.0, math.cos(yaw))  # depth, into the room
        height = 0.42 + rows * 0.48
        back = add(origin, (0, height * 0.5, 0))
        m.box(WOOD_DARK, back, (width, height, 0.06), ax, (0, 1, 0), az, 1.2)
        for side in (-1, 1):
            m.box(WOOD, add(origin, add(mul(ax, side * (width * 0.5 - 0.04)), (0, height * 0.5, 0))),
                  (0.07, height, depth), ax, (0, 1, 0), az, 1.4)
        colors = list(GLASS)
        for r in range(rows):
            sy = 0.34 + r * 0.48
            board = add(origin, add((0, sy, 0), mul(az, depth * 0.42)))
            m.box(WOOD, board, (width - 0.1, 0.05, depth * 0.82), ax, (0, 1, 0), az, 1.6)
            for c in range(6):
                u = (c + 0.5) / 6.0 - 0.5
                foot = add(origin, add(mul(ax, u * (width - 0.28)), add((0, sy + 0.03, 0), mul(az, depth * 0.45))))
                col = colors[(c + r) % len(colors)]
                h = 0.22 + (c % 3) * 0.04
                m.cylinder(col, foot, add(foot, (0, h, 0)), 0.045 + (c % 2) * 0.01, 8, 2.0)
                m.cylinder(col, add(foot, (0, h, 0)), add(foot, (0, h + 0.06, 0)), 0.02, 6, 2.0)

    shelf((0.85, LOFT_TOP, -2.95), 0.0, 2.3, 0.46, 4)  # north wall; depth runs +Z into the room
    shelf((2.55, FLOOR_TOP, 1.55), math.pi, 1.5, 0.42, 3)  # ground, south side facing -Z (into the room from the south-east)
    # Stone table, the centre of the loft.
    table = (1.42, LOFT_TOP, -0.22)
    m.box(ROCK, (table[0], table[1] + 0.74, table[2]), (1.45, 0.14, 0.92), uv=0.9)
    for sx, sz in ((-0.52, -0.30), (0.52, -0.30), (-0.52, 0.30), (0.52, 0.30)):
        m.box(ROCK, (table[0] + sx, table[1] + 0.34, table[2] + sz), (0.14, 0.68, 0.14), uv=1.2)
    # Workbench and two violet cauldrons.
    bench = (2.62, LOFT_TOP, 0.95)
    m.box(WOOD, (bench[0], bench[1] + 0.78, bench[2]), (1.85, 0.08, 0.72), uv=1.1)
    for sx, sz in ((-0.75, -0.26), (0.75, -0.26), (-0.75, 0.26), (0.75, 0.26)):
        m.box(WOOD_DARK, (bench[0] + sx, bench[1] + 0.38, bench[2] + sz), (0.08, 0.76, 0.08), uv=1.5)
    for ox in (-0.42, 0.42):
        c = (bench[0] + ox, bench[1] + 0.86, bench[2] + 0.02)
        m.cylinder(METAL, (c[0], c[1], c[2]), (c[0], c[1] + 0.22, c[2]), 0.20, 12, 1.5)
        m.cylinder(METAL, (c[0], c[1] + 0.18, c[2]), (c[0], c[1] + 0.26, c[2]), 0.24, 12, 1.2)
        m.cylinder(LIQUID, (c[0], c[1] + 0.16, c[2]), (c[0], c[1] + 0.20, c[2]), 0.16, 10, 1.0)
        m.cylinder("violet", (c[0] + 0.28, c[1] + 0.02, c[2] - 0.22), (c[0] + 0.28, c[1] + 0.20, c[2] - 0.22), 0.035, 7, 2)
    # Pinned parchment on the north plaster.
    m.box(PARCHMENT, (1.55, LOFT_TOP + 1.45, -2.72), (0.7, 0.5, 0.02), uv=1.4)
    # Ground hearth, barrels, jars.
    hearth = (2.35, FLOOR_TOP, -1.55)
    m.cylinder(ROCK, hearth, (hearth[0], hearth[1] + 0.28, hearth[2]), 0.46, 12, 0.8)
    m.cylinder(METAL, (hearth[0], hearth[1] + 0.22, hearth[2]), (hearth[0], hearth[1] + 0.55, hearth[2]), 0.28, 12, 1.2)
    m.cylinder(FIRE, (hearth[0], hearth[1] + 0.30, hearth[2]), (hearth[0], hearth[1] + 0.62, hearth[2]), 0.10, 8, 1.0)
    m.cylinder(WOOD_DARK, (hearth[0] - 0.55, FLOOR_TOP + 0.08, hearth[2] + 0.15), (hearth[0] - 0.05, FLOOR_TOP + 0.14, hearth[2] - 0.1), 0.07, 6, 1.5)
    for ox, oz, rad in ((-0.15, 1.45, 0.22), (0.35, 1.72, 0.18), (0.85, 1.4, 0.16)):
        m.cylinder(WOOD, (ox, FLOOR_TOP, oz), (ox, FLOOR_TOP + rad * 2.3, oz), rad, 10, 1.3)
        m.cylinder(METAL, (ox, FLOOR_TOP + rad * 0.7, oz), (ox, FLOOR_TOP + rad * 0.82, oz), rad + 0.015, 10, 1.0)
        m.cylinder(METAL, (ox, FLOOR_TOP + rad * 1.7, oz), (ox, FLOOR_TOP + rad * 1.82, oz), rad + 0.015, 10, 1.0)
    for j, (ox, oz, col) in enumerate(((-0.55, -1.65, "green"), (-0.15, -1.85, "amber"), (0.25, -1.6, "blue"), (0.55, -1.9, "red"))):
        m.cylinder(col, (ox, FLOOR_TOP, oz), (ox, FLOOR_TOP + 0.28, oz), 0.09, 8, 1.5)
    # Hanging lanterns: a cage and an emissive core. Omni lights sit on these points.
    for pos in ((1.15, 5.25, -0.35), (0.15, 2.35, 1.55), (2.45, 5.15, 1.15)):
        m.cylinder(WOOD_DARK, (pos[0], pos[1] + 0.16, pos[2]), (pos[0], pos[1] + 0.55, pos[2]), 0.02, 5, 1)
        m.cylinder(WOOD, (pos[0], pos[1] - 0.16, pos[2]), (pos[0], pos[1] + 0.16, pos[2]), 0.07, 6, 1)
        m.cylinder(FIRE, (pos[0], pos[1] - 0.08, pos[2]), (pos[0], pos[1] + 0.08, pos[2]), 0.035, 6, 1)
    return m


def save_glb(mesh: Mesh, path: Path) -> None:
    images = {
        WOOD: ("../../ambientcg/Wood049/color.jpg", "../../ambientcg/Wood049/roughness.jpg", "../../ambientcg/Wood049/normal.jpg", "image/jpeg"),
        WOOD_DARK: ("../../ambientcg/Wood049/color.jpg", "../../ambientcg/Wood049/roughness.jpg", "../../ambientcg/Wood049/normal.jpg", "image/jpeg"),
        ROCK: ("../../ambientcg/Rock030/color.jpg", "../../ambientcg/Rock030/roughness.jpg", "../../ambientcg/Rock030/normal.jpg", "image/jpeg"),
        PLASTER: ("plaster.png", None, None, "image/png"),
        METAL: ("../../ambientcg/Metal032/color.jpg", "../../ambientcg/Metal032/roughness.jpg", "../../ambientcg/Metal032/normal.jpg", "image/jpeg"),
        PARCHMENT: ("parchment.png", None, None, "image/png"),
    }
    # Unique image uris.
    uri_index: dict[str, int] = {}
    image_list = []
    def img(uri, mime):
        if uri not in uri_index:
            uri_index[uri] = len(image_list)
            image_list.append({"uri": uri, "mimeType": mime})
        return uri_index[uri]

    materials = []
    mat_index = {}

    def add_mat(name, *, color=(1, 1, 1, 1), metallic=0.0, roughness=0.8, emissive=(0, 0, 0), strength=1.0, alpha=None, tex=None):
        if name in mat_index:
            return mat_index[name]
        pbr = {"baseColorFactor": list(color), "metallicFactor": metallic, "roughnessFactor": roughness}
        mat = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": False}
        if tex:
            color_uri, rough_uri, normal_uri, mime = tex
            pbr["baseColorTexture"] = {"index": img(color_uri, mime)}
            if rough_uri:
                pbr["metallicRoughnessTexture"] = {"index": img(rough_uri, mime)}
            if normal_uri:
                mat["normalTexture"] = {"index": img(normal_uri, mime)}
        if any(emissive):
            mat["emissiveFactor"] = list(emissive)
            mat["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": strength}}
        if alpha:
            mat["alphaMode"] = "BLEND"
        mat_index[name] = len(materials)
        materials.append(mat)
        return mat_index[name]

    factors = {
        WOOD: ((1, 1, 1, 1), 0.0, 0.78),
        WOOD_DARK: ((0.45, 0.32, 0.2, 1), 0.0, 0.7),
        ROCK: ((0.55, 0.52, 0.48, 1), 0.0, 0.9),
        PLASTER: ((1, 1, 1, 1), 0.0, 0.86),
        METAL: ((0.7, 0.68, 0.64, 1), 0.85, 0.38),
        PARCHMENT: ((1, 1, 1, 1), 0.0, 0.9),
        LIQUID: None,
        FIRE: None,
    }
    for name in mesh.prims:
        if name in GLASS:
            r, g, b = GLASS[name]
            add_mat(name, color=(r, g, b, 0.82), metallic=0.04, roughness=0.12, emissive=(r * 0.6, g * 0.6, b * 0.6), strength=1.6, alpha=True)
        elif name == LIQUID:
            add_mat(name, color=(0.45, 0.12, 0.85, 1), metallic=0.1, roughness=0.18, emissive=(0.55, 0.15, 1.0), strength=2.8)
        elif name == FIRE:
            add_mat(name, color=(1.0, 0.45, 0.1, 1), metallic=0.0, roughness=0.4, emissive=(1.0, 0.35, 0.05), strength=8.0)
        else:
            col, metal, rough = factors[name]
            add_mat(name, color=col, metallic=metal, roughness=rough, tex=images.get(name))

    buffer = bytearray()
    accessors = []
    buffer_views = []
    primitives = []

    def push(data: bytes, target: int | None) -> int:
        offset = len(buffer)
        while len(buffer) % 4:
            buffer.append(0)
            offset = len(buffer)
        buffer.extend(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        buffer_views.append(view)
        return len(buffer_views) - 1

    for name, prim in mesh.prims.items():
        positions = prim["p"]
        normals = prim["n"]
        uvs = prim["uv"]
        indices = prim["i"]
        count = len(positions) // 3
        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        p_bytes = struct.pack("<" + "f" * len(positions), *positions)
        n_bytes = struct.pack("<" + "f" * len(normals), *normals)
        u_bytes = struct.pack("<" + "f" * len(uvs), *uvs)
        i_bytes = struct.pack("<" + "I" * len(indices), *indices)
        pv = push(p_bytes, 34962)
        nv = push(n_bytes, 34962)
        uvv = push(u_bytes, 34962)
        iv = push(i_bytes, 34963)
        accessors.append({"bufferView": pv, "componentType": 5126, "count": count, "type": "VEC3",
                          "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]})
        pa = len(accessors) - 1
        accessors.append({"bufferView": nv, "componentType": 5126, "count": count, "type": "VEC3"})
        na = len(accessors) - 1
        accessors.append({"bufferView": uvv, "componentType": 5126, "count": count, "type": "VEC2"})
        ua = len(accessors) - 1
        accessors.append({"bufferView": iv, "componentType": 5125, "count": len(indices), "type": "SCALAR"})
        ia = len(accessors) - 1
        primitives.append({"attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ua}, "indices": ia, "material": mat_index[name]})

    gltf = {
        "asset": {"version": "2.0", "generator": "bobs_lab.build_hollow"},
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "hollow"}],
        "meshes": [{"name": "hollow", "primitives": primitives}],
        "materials": materials,
        "images": image_list,
        "textures": [{"source": i, "sampler": 0} for i in range(len(image_list))],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(buffer)}],
    }
    # Fix texture indices: images were appended in uri order, and materials reference image indices
    # as texture indices because textures[i].source = i. Good.
    # But baseColorTexture index must be a TEXTURE index, which equals the image index. Good.
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    js += b" " * ((4 - len(js) % 4) % 4)
    bin_chunk = bytes(buffer) + b"\x00" * ((4 - len(buffer) % 4) % 4)
    blob = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(bin_chunk))
    blob += struct.pack("<I", len(js)) + b"JSON" + js
    blob += struct.pack("<I", len(bin_chunk)) + b"BIN\x00" + bin_chunk
    path.write_bytes(blob)
    tris = sum(len(p["i"]) // 3 for p in mesh.prims.values())
    print(f"[hollow] {path.name} {tris} tris, {len(mesh.prims)} materials")


def write_toml() -> None:
    def box(name, kind, center, size, rot=None):
        r = "" if not rot else f"rotation_deg = [{rot[0]}, {rot[1]}, {rot[2]}]\n"
        c = ", ".join(f"{v:.4f}" for v in center)
        s = ", ".join(f"{v:.4f}" for v in size)
        return (f'[[box]]\nname = "{name}"\nkind = "{kind}"\ncenter = [{c}]\nsize = [{s}]\n'
                f"color = [0.35, 0.26, 0.16]\ncollision_only = true\n{r}")

    wall_h = CEIL_Y - FLOOR_TOP
    wall_y = FLOOR_TOP + wall_h * 0.5
    thick = 0.36
    parts = [
        box("lab_floor", "platform", (0, FLOOR_TOP * 0.5, 0), (RX * 2, FLOOR_TOP, RZ * 2)),
        box("lab_wall_n", "wall", (0, wall_y, -(RZ + thick * 0.5)), (RX * 2 + thick, wall_h, thick)),
        box("lab_wall_s_w", "wall", (-(DOOR_HALF + RX) * 0.5, wall_y, RZ + thick * 0.5), (RX - DOOR_HALF, wall_h, thick)),
        box("lab_wall_s_e", "wall", ((DOOR_HALF + RX) * 0.5, wall_y, RZ + thick * 0.5), (RX - DOOR_HALF, wall_h, thick)),
        box("lab_wall_e", "wall", (RX + thick * 0.5, wall_y, 0), (thick, wall_h, RZ * 2)),
        box("lab_wall_w", "wall", (-(RX + thick * 0.5), wall_y, 0), (thick, wall_h, RZ * 2)),
    ]
    # Loft slabs leave the stair well open and still meet the top tread.
    loft_y = LOFT_TOP - 0.1
    loft_t = 0.2
    parts.append(box("lab_loft_e", "platform", (1.85, loft_y, 0.05), (3.7, loft_t, 5.5)))
    parts.append(box("lab_loft_n", "platform", (-1.15, loft_y, 2.15), (4.6, loft_t, 1.55)))
    parts.append(box("lab_loft_s", "platform", (-0.9, loft_y, -2.15), (5.1, loft_t, 1.55)))
    top = steps()[-1]
    parts.append(box("lab_landing", "platform", (top["center"][0] + 0.45, loft_y, top["center"][2]), (1.9, loft_t, 1.9)))
    for s in steps():
        parts.append(box(
            f"lab_step_{s['i']}", "platform", s["center"], (RADIAL, TREAD, TANG),
            (0.0, round(s["yaw"], 3), 0.0),
        ))
    lights = (
        ("lantern_loft", (1.15, 5.15, -0.35), (1.0, 0.72, 0.42), 2.6, 7.5),
        ("lantern_ground", (0.15, 2.25, 1.55), (1.0, 0.68, 0.38), 1.5, 5.0),
        ("lantern_bench", (2.45, 5.05, 1.15), (1.0, 0.7, 0.4), 1.8, 6.0),
        ("cauldron_west", (2.20, 4.30, 0.97), (0.62, 0.22, 1.0), 1.7, 3.4),
        ("cauldron_east", (3.04, 4.30, 0.97), (0.5, 0.16, 0.95), 1.4, 3.2),
        ("hearth", (2.35, 1.15, -1.55), (1.0, 0.42, 0.12), 2.4, 5.5),
    )
    light_txt = ""
    for name, pos, col, energy, rng in lights:
        light_txt += (f'[[light]]\nname = "{name}"\nposition = [{pos[0]}, {pos[1]}, {pos[2]}]\n'
                      f"color = [{col[0]}, {col[1]}, {col[2]}]\nenergy = {energy}\nrange = {rng}\nshadows = true\n")
    text = f"""# Bob's lab. A two-floor hollow matched to the cutaway in docs/maps/levels/bobs_lab.jpg.
# Collision only: the visible room is assets/levels/bobs_lab/hollow.glb.

[level]
id = "bobs_lab"
name = "Bob's lab"
world_offset = [0.0, 0.0]

[materials]
ground = "assets/ambientcg/Wood049"
uv_scale = 0.4

[environment]
sky_color = [0.07, 0.05, 0.04]
ambient_color = [0.28, 0.2, 0.14]
fog_density = 0.012
grade = [1.0, 1.06, 1.04]

[sun]
to_light = [0.15, 0.7, 0.55]
color = [1.0, 0.78, 0.55]
energy = 0.22

[player_start]
position = [0.9, {FLOOR_TOP}, 2.15]
yaw_deg = 180.0

{''.join(parts)}
[[exit]]
name = "to_town"
to = "town_square"
position = [0.9, {FLOOR_TOP}, 2.65]

{light_txt}"""
    path = ROOT / "data/levels/bobs_lab.toml"
    path.write_text(text, encoding="utf-8")
    print(f"[hollow] wrote {path.relative_to(ROOT)}")
    print(f"[hollow] top step at {top['center']} yaw {top['yaw']:.1f}")
    print(f"[hollow] east wall inner x = {RX}")


def main() -> None:
    make_textures()
    mesh = build()
    save_glb(mesh, OUT / "hollow.glb")
    write_toml()


if __name__ == "__main__":
    main()
