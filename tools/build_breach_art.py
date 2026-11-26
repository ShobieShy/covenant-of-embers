#!/usr/bin/env python3
"""Build the Breach crater shell (CC0 PBR glTF) and data/levels/breach_slice.toml.

The labyrinth gate stays at (0, 0, 125), where EmberArt places it. The outer cliff is
the scaled breach_crater_rim. Colliders are boxes (nav, doors, the vault). The visible
crater is a real mesh: rock and paving from ambientCG, plus arches, crystals and water.

  python3 tools/build_breach_art.py
  python3 tools/toml_to_scene.py data/levels/breach_slice.toml scenes/levels/breach.tscn
"""
from __future__ import annotations

import heapq
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_GLB = ROOT / "assets/original/ember_art/breach/breach_shell.glb"
OUT_TOML = ROOT / "data/levels/breach_slice.toml"

CZ = 125.0
RX, RZ = 74.0, 78.0
# Gameplay feet. North is -Z. The gate is the crater's centre.
START = (0.0, 178.0)
EXIT = (-3.0, 186.0)
WAYSTONE = (3.0, 172.0)
STATION = (2.5, 164.0)
DEN = (-38.0, 154.0)
GAL_W = (-48.0, 128.0)
GAL_E = (-36.0, 134.0)
CIST = (32.0, 164.0)
LEV_W = (40.0, 144.0)
LEV_E = (50.0, 144.0)
DAIS = (0.0, 72.0)
WING_W = (-8.0, 74.0)
WING_E = (8.0, 74.0)
CHEST = (24.5, 71.0)
DEN_POINT = (-0.25, 59.7)

ROCK = ROOT / "assets/ambientcg/Rock030/color.jpg"
ROCK_N = ROOT / "assets/ambientcg/Rock030/normal.jpg"
PAVE = ROOT / "assets/ambientcg/PavingStones131/color.jpg"
PAVE_N = ROOT / "assets/ambientcg/PavingStones131/normal.jpg"
DIRT = ROOT / "assets/ambientcg/Ground037/color.jpg"
DIRT_N = ROOT / "assets/ambientcg/Ground037/normal.jpg"


def _ellipse_inside(x: float, z: float, scale: float = 1.0) -> bool:
    return (x / RX) ** 2 + ((z - CZ) / RZ) ** 2 <= scale


# --- glTF -------------------------------------------------------------------

class Bin:
    def __init__(self) -> None:
        self.buf = bytearray()

    def pad(self, n: int = 4) -> None:
        while len(self.buf) % n:
            self.buf.append(0)

    def blob(self, data: bytes) -> int:
        self.pad(4)
        off = len(self.buf)
        self.buf += data
        return off


def _pack(seq, fmt: str) -> bytes:
    flat = []
    for v in seq:
        flat.extend(v if isinstance(v, tuple) else (v,))
    return struct.pack("<" + fmt * (len(flat) // len(fmt) if False else len(seq[0]) if seq and isinstance(seq[0], tuple) else 1), *flat) if False else struct.pack("<" + (fmt * len(flat)), *flat)


def face_normals(verts, idx):
    acc = [[0.0, 0.0, 0.0] for _ in verts]
    for i in range(0, len(idx), 3):
        a, b, c = (verts[idx[i + k]] for k in range(3))
        ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
        vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
        nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
        for k in range(3):
            acc[idx[i + k]][0] += nx
            acc[idx[i + k]][1] += ny
            acc[idx[i + k]][2] += nz
    out = []
    for x, y, z in acc:
        ln = math.sqrt(x * x + y * y + z * z) or 1.0
        out.append((x / ln, y / ln, z / ln))
    return out


def ellipse_disc(cx, cz, rx, rz, y, seg=56):
    verts = [(cx, y, cz)]
    uvs = [(cx * 0.08, cz * 0.08)]
    for i in range(seg):
        a = math.tau * i / seg
        x, z = cx + rx * math.sin(a), cz + rz * math.cos(a)
        verts.append((x, y, z))
        uvs.append((x * 0.08, z * 0.08))
    idx = []
    for i in range(seg):
        idx += [0, 1 + i, 1 + (i + 1) % seg]
    return verts, uvs, idx


def ribbon(pts, width, y):
    if len(pts) < 2:
        return [], [], []
    sides = []
    for i, (x, z) in enumerate(pts):
        if i == 0:
            dx, dz = pts[1][0] - x, pts[1][1] - z
        elif i == len(pts) - 1:
            dx, dz = x - pts[i - 1][0], z - pts[i - 1][1]
        else:
            dx, dz = pts[i + 1][0] - pts[i - 1][0], pts[i + 1][1] - pts[i - 1][1]
        ln = math.hypot(dx, dz) or 1.0
        px, pz = -dz / ln * width * 0.5, dx / ln * width * 0.5
        sides.append((x + px, z + pz, x - px, z - pz))
    verts, uvs, idx = [], [], []
    for i, (lx, lz, rx_, rz_) in enumerate(sides):
        verts += [(lx, y, lz), (rx_, y, rz_)]
        uvs += [(lx * 0.12, lz * 0.12), (rx_ * 0.12, rz_ * 0.12)]
        if i:
            a = (i - 1) * 2
            idx += [a, a + 1, a + 2, a + 1, a + 3, a + 2]
    return verts, uvs, idx


def circle_pts(cx, cz, r, seg=40):
    pts = [(cx + r * math.sin(math.tau * i / seg), cz + r * math.cos(math.tau * i / seg)) for i in range(seg)]
    pts.append(pts[0])
    return pts


def add_box_mesh(center, size):
    x, y, z = center
    hx, hy, hz = (size[i] * 0.5 for i in range(3))
    faces = [
        ((-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)),
        ((1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)),
        ((-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)),
        ((-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)),
        ((1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)),
        ((-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)),
    ]
    verts, uvs, idx = [], [], []
    for f in faces:
        b = len(verts)
        for s in f:
            verts.append((x + s[0] * hx, y + s[1] * hy, z + s[2] * hz))
            uvs.append(((s[0] + 1) * 0.5, (s[1] + 1) * 0.5))
        idx += [b, b + 1, b + 2, b, b + 2, b + 3]
    return verts, uvs, idx


def transform(verts, origin, yaw_deg=0.0, scale=(1, 1, 1)):
    a = math.radians(yaw_deg)
    c, s = math.cos(a), math.sin(a)
    out = []
    for x, y, z in verts:
        x, y, z = x * scale[0], y * scale[1], z * scale[2]
        xr, zr = x * c + z * s, -x * s + z * c
        out.append((xr + origin[0], y + origin[1], zr + origin[2]))
    return out


def arch_parts(width=6.4, height=7.6, thick=0.9):
    """Pointed stone arch, opening along Z, pivot on the ground at the opening centre."""
    span = width * 0.5 - 0.45
    spring = height * 0.58
    parts = []
    for sx in (-1, 1):
        parts.append(add_box_mesh((sx * (span + 0.22), spring * 0.5, 0), (0.85, spring, thick)))
    curve = []
    for i in range(16):
        t = i / 15
        curve.append((-span * (1 - t), spring + (height - spring) * math.sin(t * math.pi * 0.5)))
    for i in range(1, 16):
        t = i / 15
        curve.append((span * t, spring + (height - spring) * math.cos(t * math.pi * 0.5)))
    verts, uvs, idx = [], [], []
    half = thick * 0.5
    rad = 0.42
    for i in range(len(curve) - 1):
        x0, y0 = curve[i]
        x1, y1 = curve[i + 1]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln * rad, dx / ln * rad
        ring = [
            (x0 + nx, y0 + ny, half), (x0 - nx, y0 - ny, half),
            (x0 - nx, y0 - ny, -half), (x0 + nx, y0 + ny, -half),
            (x1 + nx, y1 + ny, half), (x1 - nx, y1 - ny, half),
            (x1 - nx, y1 - ny, -half), (x1 + nx, y1 + ny, -half),
        ]
        b = len(verts)
        for p in ring:
            verts.append(p)
            uvs.append((p[0] * 0.15, p[1] * 0.15))
        quads = [(0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        for q in quads:
            idx += [b + q[0], b + q[1], b + q[2], b + q[0], b + q[2], b + q[3]]
    parts.append((verts, uvs, idx))
    return parts


def spike_mesh(h, r, sides=6):
    verts, idx = [], []
    for i in range(sides):
        a = math.tau * i / sides
        verts.append((r * math.cos(a), 0.0, r * math.sin(a)))
    tip = len(verts)
    verts.append((0.0, h, 0.0))
    base = len(verts)
    verts.append((0.0, 0.0, 0.0))
    for i in range(sides):
        j = (i + 1) % sides
        idx += [i, j, tip, base, j, i]
    uvs = [(v[0], v[2]) for v in verts]
    return verts, uvs, idx


def ico_mesh():
    t = (1 + math.sqrt(5)) / 2
    v = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    f = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
         (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
         (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    verts = [(x / t, y / t, z / t) for x, y, z in v]
    idx = [i for tri in f for i in tri]
    uvs = [(x * 0.5 + 0.5, z * 0.5 + 0.5) for x, _, z in verts]
    return verts, uvs, idx


ICO_V, ICO_UV, ICO_I = ico_mesh()


def hash01(i: int) -> float:
    x = math.sin(i * 127.1 + 311.7) * 43758.5453
    return x - math.floor(x)


def build_document() -> dict:
    images = {
        "rock": ROCK.read_bytes(), "rock_n": ROCK_N.read_bytes(),
        "pave": PAVE.read_bytes(), "pave_n": PAVE_N.read_bytes(),
        "dirt": DIRT.read_bytes(), "dirt_n": DIRT_N.read_bytes(),
    }
    # Materials: 0 rock, 1 pave, 2 dirt, 3 gallery, 4 water, 5 cistern water, 6 crystal, 7 beam, 8 bone, 9 violet stone
    specs = [
        ("rock", "rock", "rock_n", (0.55, 0.50, 0.46, 1), None, 0.92, False),
        ("pave", "pave", "pave_n", (0.72, 0.66, 0.58, 1), None, 0.84, False),
        ("dirt", "dirt", "dirt_n", (0.62, 0.56, 0.48, 1), None, 0.95, False),
        ("gallery", "rock", "rock_n", (1.0, 0.48, 0.18, 1), (0.45, 0.12, 0.02), 0.72, False),
        ("moat", None, None, (0.04, 0.05, 0.10, 0.90), None, 0.42, True),
        ("pool", None, None, (0.05, 0.22, 0.10, 0.90), (0.02, 0.12, 0.04), 0.35, True),
        ("crystal", None, None, (0.42, 0.16, 0.82, 0.9), (0.35, 0.08, 0.7), 0.22, True),
        ("beam", None, None, (0.50, 0.16, 0.90, 0.45), (0.48, 0.12, 0.85), 0.25, True),
        ("bone", "dirt", "dirt_n", (0.72, 0.66, 0.55, 1), None, 0.9, False),
        ("relic", "rock", "rock_n", (0.48, 0.36, 0.62, 1), (0.08, 0.03, 0.14), 0.75, False),
        ("cistern_floor", "dirt", "dirt_n", (0.42, 0.52, 0.36, 1), None, 0.88, False),
        ("ember", "rock", "rock_n", (0.55, 0.18, 0.05, 1), (0.7, 0.18, 0.02), 0.5, False),
    ]
    parts = []  # (name, verts, uvs, idx, mat)

    def add(name, verts, uvs, idx, mat):
        if idx:
            parts.append((name, verts, uvs, idx, mat))

    add("breach_floor", *ellipse_disc(0, CZ, RX - 1.5, RZ - 1.5, 0.0, 72), 0)
    chambers = [
        ("breach_den_floor", DEN, 15, 11, 8),
        ("breach_gallery_floor", ((GAL_W[0] + GAL_E[0]) * 0.5, (GAL_W[1] + GAL_E[1]) * 0.5), 16, 13, 3),
        ("breach_ossuary_floor", (-34, 102), 13, 10, 8),
        ("breach_cistern_floor", CIST, 14, 11, 10),
        ("breach_switch_floor", (45, 144), 13, 10, 0),
        ("breach_reliquary_floor", (50, 118), 11, 9, 9),
        ("breach_bell_floor", (42, 98), 11, 9, 9),
        ("breach_arena_floor", DAIS, 15, 13, 1),
        ("breach_vault_floor", CHEST, 7, 6, 0),
        ("breach_plinth_floor", (0, CZ), 8.2, 8.2, 1),
        ("breach_hall_floor", (0, 176), 6.5, 16, 2),
    ]
    for name, (cx, cz), rx, rz, mat in chambers:
        add(name, *ellipse_disc(cx, cz, rx, rz, 0.012, 36), mat)
    paths = [
        ([(0, 198), (0, 140)], 5.0),
        (circle_pts(0, CZ, 21, 48), 4.2),
        ([(-18, 150), DEN], 3.6),
        ([(-18, 128), GAL_W], 3.4),
        ([(16, 156), CIST], 3.6),
        ([(18, 144), (48, 144)], 3.4),
        ([(16, 118), (50, 118)], 3.2),
        ([(14, 108), (42, 98)], 3.2),
        ([(-16, 110), (-34, 102)], 3.2),
        ([(0, 108), (0, 90)], 4.0),
    ]
    pv, pu, pi = [], [], []
    for pts, w in paths:
        v, u, i = ribbon(pts, w, 0.02)
        b = len(pv)
        pv += v
        pu += u
        pi += [n + b for n in i]
    add("breach_paths", pv, pu, pi, 1)
    # Moat: annulus with two bridge gaps (south and north).
    moat_v, moat_u, moat_i = [], [], []
    seg = 64
    for i in range(seg):
        a0 = math.tau * i / seg
        a1 = math.tau * (i + 1) / seg
        mid = (a0 + a1) * 0.5
        # 0 is +Z (south). Skip ±0.42 rad south and north (north is pi).
        south = abs((mid + math.pi) % math.tau - math.pi) < 0.42
        north = abs((mid) % math.tau - math.pi) < 0.42
        if south or north:
            continue
        ring = []
        for a, rad in ((a0, 9.2), (a0, 16.5), (a1, 16.5), (a1, 9.2)):
            ring.append((rad * math.sin(a), 0.03, CZ + rad * math.cos(a)))
        b = len(moat_v)
        moat_v += ring
        moat_u += [(p[0] * 0.1, p[2] * 0.1) for p in ring]
        moat_i += [b, b + 1, b + 2, b, b + 2, b + 3]
    add("breach_moat", moat_v, moat_u, moat_i, 4)
    add("breach_cistern_pool", *ellipse_disc(CIST[0], CIST[1], 8.5, 6.2, 0.035, 32), 5)
    # Crystals
    spots = []
    for i, deg in enumerate((20, 70, 120, 160, 210, 250, 300, 340)):
        a = math.radians(deg)
        spots.append((58 * math.sin(a), 0.0, CZ + 60 * math.cos(a), 18 * i))
    spots += [(-30, 0, 108, 3), (28, 0, 96, 7), (-8, 0, 64, 2)]
    for n, (x, y, z, seed) in enumerate(spots):
        cv, cu, ci = [], [], []
        for s in range(5):
            h = 1.6 + hash01(seed + s) * 2.8
            r = 0.18 + hash01(seed + 20 + s) * 0.22
            ox = (hash01(seed + 40 + s) - 0.5) * 1.1
            oz = (hash01(seed + 60 + s) - 0.5) * 1.1
            sv, su, si = spike_mesh(h, r)
            b = len(cv)
            cv += [(px + x + ox, py + y, pz + z + oz) for px, py, pz in sv]
            cu += su
            ci += [k + b for k in si]
        add(f"breach_crystal_{n + 1}", cv, cu, ci, 6)
    # Beam
    bv, bu, bi = [], [], []
    sides = 10
    for i in range(sides):
        a0 = math.tau * i / sides
        a1 = math.tau * (i + 1) / sides
        quad = []
        for a, yy, rad in ((a0, 0.4, 0.85), (a1, 0.4, 0.85), (a1, 18.0, 0.28), (a0, 18.0, 0.28)):
            quad.append((rad * math.cos(a), yy, CZ + rad * math.sin(a)))
        b = len(bv)
        bv += quad
        bu += [(0, 0), (1, 0), (1, 1), (0, 1)]
        bi += [b, b + 1, b + 2, b, b + 2, b + 3]
    add("breach_beam", bv, bu, bi, 7)
    # Arches
    for name, origin in (("breach_entrance_arch", (0, 0, 168)), ("breach_arena_arch", (0, 0, 61.5))):
        for j, (v, u, i) in enumerate(arch_parts()):
            vv = [(p[0] + origin[0], p[1] + origin[1], p[2] + origin[2]) for p in v]
            add(f"{name}_{j}", vv, u, i, 0)
    # Ember coals
    ev, eu, ei = [], [], []
    gx = (GAL_W[0] + GAL_E[0]) * 0.5
    gz = (GAL_W[1] + GAL_E[1]) * 0.5
    for s in range(14):
        ox = (hash01(200 + s) - 0.5) * 10
        oz = (hash01(300 + s) - 0.5) * 8
        sc = 0.35 + hash01(400 + s) * 0.7
        vv = transform(ICO_V, (gx + ox, 0.25 * sc, gz + oz), hash01(500 + s) * 360, (sc, sc * 0.45, sc))
        b = len(ev)
        ev += vv
        eu += ICO_UV
        ei += [k + b for k in ICO_I]
    add("breach_embers", ev, eu, ei, 11)
    # Loose rock along the inner rim and between chambers. Kept off the paved paths.
    def near_path(x, z) -> bool:
        samples = []
        for pts, w in paths:
            samples.append((pts, w))
        for pts, w in samples:
            for px, pz in pts:
                if (x - px) ** 2 + (z - pz) ** 2 < (w * 0.55 + 1.3) ** 2:
                    return True
        return False

    rv, ru, ri = [], [], []
    rock_i = 0
    for i in range(90):
        a = math.tau * i / 90
        rad = 50 + hash01(i) * 10
        x, z = rad * math.sin(a), CZ + rad * math.cos(a)
        if not _ellipse_inside(x, z, 0.92) or near_path(x, z):
            continue
        if math.hypot(x, z - 72) < 18:
            continue
        sc = 0.7 + hash01(i + 9) * 1.5
        vv = transform(ICO_V, (x, sc * 0.55, z), hash01(i + 3) * 360, (sc * 1.3, sc * 0.8, sc))
        b = len(rv)
        rv += vv
        ru += ICO_UV
        ri += [k + b for k in ICO_I]
        rock_i += 1
    add("breach_rim_rocks", rv, ru, ri, 0)
    # Stepped rim just inside the shattered outer cliff, so the bowl reads as terraces.
    tv, tu, ti = [], [], []
    steps = [(58.0, 0.15), (62.5, 2.0), (66.5, 4.2), (70.5, 6.6)]
    seg = 80
    for s in range(len(steps) - 1):
        r0, y0 = steps[s]
        r1, y1 = steps[s + 1]
        for i in range(seg):
            a0 = math.tau * i / seg
            a1 = math.tau * (i + 1) / seg
            mid = (a0 + a1) * 0.5
            # South gap: the landfill road cuts the terraces.
            if abs((mid + math.pi) % math.tau - math.pi) < 0.28:
                continue
            ring = []
            for a, rad, yy in ((a0, r0, y0), (a1, r0, y0), (a1, r1, y1), (a0, r1, y1)):
                ring.append((rad * math.sin(a), yy, CZ + rad * math.cos(a)))
            b = len(tv)
            tv += ring
            tu += [(p[0] * 0.06, p[2] * 0.06) for p in ring]
            ti += [b, b + 1, b + 2, b, b + 2, b + 3]
            flat = []
            for a, rad in ((a0, r0), (a1, r0), (a1, r1), (a0, r1)):
                flat.append((rad * math.sin(a), y1 + 0.02, CZ + rad * math.cos(a)))
            b = len(tv)
            tv += flat
            tu += [(p[0] * 0.06, p[2] * 0.06) for p in flat]
            ti += [b, b + 1, b + 2, b, b + 2, b + 3]
    add("breach_terraces", tv, tu, ti, 0)
    # Arena pillars (visual; collision is a separate box).
    for name, (x, z) in (("nw", (-7, 66)), ("ne", (7, 66)), ("sw", (-7, 78)), ("se", (7, 78))):
        v, u, i = add_box_mesh((0, 1.7, 0), (1.15, 3.4, 1.15))
        cap_v, cap_u, cap_i = add_box_mesh((0, 3.55, 0), (1.55, 0.35, 1.55))
        vv = [(p[0] + x, p[1], p[2] + z) for p in v + cap_v]
        add(f"breach_pillar_{name}", vv, u + cap_u, i + [n + len(v) for n in cap_i], 0)
    return {"images": images, "specs": specs, "parts": parts}


def write_glb(doc: dict, path: Path) -> None:
    blob = Bin()
    accessors, views, meshes, nodes = [], [], [], []
    # images first so buffer views stay stable
    image_views = {}
    for key, data in doc["images"].items():
        off = blob.blob(data)
        image_views[key] = len(views)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
    textures, images_js = [], []
    tex_index = {}
    for key in doc["images"]:
        images_js.append({"mimeType": "image/jpeg", "bufferView": image_views[key]})
        tex_index[key] = len(textures)
        textures.append({"source": len(images_js) - 1})
    materials = []
    for name, albedo, normal, factor, emissive, rough, blend in doc["specs"]:
        m = {
            "name": name,
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": list(factor),
                "metallicFactor": 0.0,
                "roughnessFactor": rough,
            },
        }
        if albedo:
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex_index[albedo]}
        if normal:
            m["normalTexture"] = {"index": tex_index[normal]}
        if blend:
            m["alphaMode"] = "BLEND"
        if emissive:
            m["emissiveFactor"] = list(emissive)
            strength = 1.6 if name in ("gallery", "ember", "pool", "relic") else 3.2
            m["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": strength}}
        materials.append(m)
    for name, verts, uvs, idx, mat in doc["parts"]:
        norms = face_normals(verts, idx)
        vbytes = struct.pack("<" + "f" * (len(verts) * 3), *[c for v in verts for c in v])
        nbytes = struct.pack("<" + "f" * (len(norms) * 3), *[c for v in norms for c in v])
        ubytes = struct.pack("<" + "f" * (len(uvs) * 2), *[c for v in uvs for c in v])
        ibytes = struct.pack("<" + "I" * len(idx), *idx)
        xs = [v[0] for v in verts]
        ys = [v[1] for v in verts]
        zs = [v[2] for v in verts]
        chunks = [(vbytes, 3, "VEC3", (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))),
                  (nbytes, 3, "VEC3", None, None),
                  (ubytes, 2, "VEC2", None, None)]
        attr = {}
        for key, (data, comps, typ, mn, mx) in zip(("POSITION", "NORMAL", "TEXCOORD_0"), chunks):
            off = blob.blob(data)
            views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": 34962})
            acc = {"bufferView": len(views) - 1, "componentType": 5126, "count": len(verts), "type": typ}
            if mn:
                acc["min"] = list(mn)
                acc["max"] = list(mx)
            attr[key] = len(accessors)
            accessors.append(acc)
        off = blob.blob(ibytes)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(ibytes), "target": 34963})
        accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": len(idx), "type": "SCALAR"})
        meshes.append({"name": name, "primitives": [{
            "attributes": attr, "indices": len(accessors) - 1, "material": mat,
        }]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    root = {"name": "breach_shell", "children": list(range(len(nodes)))}
    nodes.append(root)
    blob.pad(4)
    gltf = {
        "asset": {"version": "2.0", "generator": "tools/build_breach_art.py"},
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob.buf)}],
        "materials": materials,
        "textures": textures,
        "images": images_js,
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    bin_chunk = bytes(blob.buf)
    while len(bin_chunk) % 4:
        bin_chunk += b"\x00"
    total = 12 + 8 + len(js) + 8 + len(bin_chunk)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(bin_chunk), b"BIN\x00") + bin_chunk
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)


# --- level colliders --------------------------------------------------------

def boxes() -> list[dict]:
    out = []
    step, size = 6.5, 7.6
    xs = []
    x = -80.0
    while x <= 80.0:
        xs.append(round(x, 3))
        x += step
    zs = []
    z = CZ - 84.0
    while z <= CZ + 84.0:
        zs.append(round(z, 3))
        z += step
    n = 0
    for x in xs:
        for z in zs:
            if _ellipse_inside(x, z, 0.97):
                out.append({"name": f"ground_{n:03d}", "kind": "ground",
                            "center": (x, -0.1, z), "size": (size, 0.2, size)})
                n += 1
    walls = [
        ("corridor_west", (-6.6, 2.0, 178.0), (1.3, 4.0, 24.0), "wall"),
        ("corridor_east", (6.6, 2.0, 178.0), (1.3, 4.0, 24.0), "wall"),
        ("arena_n", (0.0, 2.0, 56.4), (40.0, 4.0, 1.6), "wall"),
        ("arena_w", (-18.4, 2.0, 72.0), (1.8, 4.0, 33.0), "wall"),
        ("arena_s_w", (-11.6, 2.0, 86.8), (15.2, 4.0, 1.8), "wall"),
        ("arena_s_e", (11.6, 2.0, 86.8), (15.2, 4.0, 1.8), "wall"),
        ("switch_gate", (0.0, 2.0, 86.8), (11.2, 4.0, 2.2), "wall"),
        ("arena_e_n", (18.4, 2.0, 62.4), (1.8, 4.0, 13.0), "wall"),
        ("arena_e_s", (18.4, 2.0, 80.2), (1.8, 4.0, 14.0), "wall"),
        ("vault_door", (18.4, 2.0, 71.0), (2.6, 4.0, 7.4), "wall"),
        ("vault_west", (25.2, 2.0, 66.2), (15.0, 4.0, 2.2), "wall"),
        ("vault_east", (25.2, 2.0, 76.4), (15.0, 4.0, 2.2), "wall"),
        ("vault_back", (31.4, 2.0, 71.2), (1.6, 4.0, 13.0), "wall"),
        ("pillar_nw", (-7.0, 1.7, 66.0), (1.3, 3.4, 1.3), "crate"),
        ("pillar_ne", (7.0, 1.7, 66.0), (1.3, 3.4, 1.3), "crate"),
        ("pillar_sw", (-7.0, 1.7, 78.0), (1.3, 3.4, 1.3), "crate"),
        ("pillar_se", (7.0, 1.7, 78.0), (1.3, 3.4, 1.3), "crate"),
        ("boss_dais", (0.0, 0.1, 72.0), (6.4, 0.2, 3.6), "platform"),
        ("gate_plinth", (0.0, 0.08, CZ), (14.0, 0.16, 14.0), "platform"),
    ]
    for name, center, size, kind in walls:
        out.append({"name": name, "kind": kind, "center": center, "size": size})
    return out


def _on_top(box, x, y, z, eps=0.05) -> bool:
    cx, cy, cz = box["center"]
    sx, sy, sz = box["size"]
    top = cy + sy * 0.5
    if abs(y - top) > eps:
        return False
    return abs(x - cx) <= sx * 0.5 + eps and abs(z - cz) <= sz * 0.5 + eps


def on_surface(all_boxes, x, y, z) -> bool:
    return any(_on_top(b, x, y, z) for b in all_boxes)


def ring(center, n):
    if n <= 1:
        return [center]
    return [(center[0] + 1.5 * math.sin(math.tau * i / n), center[1], center[2] - 1.5 * math.cos(math.tau * i / n))
            for i in range(n)]


def flood(all_boxes, removed: set[str]):
    """Walk grid. `removed` doors are not blockers. Returns (nearest, route_length)."""
    agent = 0.55
    cell = 0.5

    def cell_of(x, z):
        return (int(math.floor(x / cell)), int(math.floor(z / cell)))

    walk = set()
    for b in all_boxes:
        top = b["center"][1] + b["size"][1] * 0.5
        if not (b["size"][1] <= 0.4 and top <= 0.25):
            continue
        cx, cz = b["center"][0], b["center"][2]
        hx, hz = b["size"][0] * 0.5, b["size"][2] * 0.5
        for ix in range(int(math.floor((cx - hx) / cell)), int(math.floor((cx + hx) / cell)) + 1):
            for iz in range(int(math.floor((cz - hz) / cell)), int(math.floor((cz + hz) / cell)) + 1):
                px, pz = (ix + 0.5) * cell, (iz + 0.5) * cell
                if abs(px - cx) <= hx and abs(pz - cz) <= hz:
                    walk.add((ix, iz))
    for b in all_boxes:
        if b["size"][1] <= 1.0 or b["name"] in removed:
            continue
        cx, cz = b["center"][0], b["center"][2]
        hx, hz = b["size"][0] * 0.5 + agent, b["size"][2] * 0.5 + agent
        for ix in range(int(math.floor((cx - hx) / cell)), int(math.floor((cx + hx) / cell)) + 1):
            for iz in range(int(math.floor((cz - hz) / cell)), int(math.floor((cz + hz) / cell)) + 1):
                px, pz = (ix + 0.5) * cell, (iz + 0.5) * cell
                if abs(px - cx) <= hx and abs(pz - cz) <= hz:
                    walk.discard((ix, iz))

    def nearest(x, z, tol):
        c = cell_of(x, z)
        best = None
        reach = int(math.ceil(tol / cell))
        for dz in range(-reach, reach + 1):
            for dx in range(-reach, reach + 1):
                k = (c[0] + dx, c[1] + dz)
                if k in walk:
                    d = math.hypot((k[0] + 0.5) * cell - x, (k[1] + 0.5) * cell - z)
                    if best is None or d < best:
                        best = d
        return best

    def route(a, b):
        def snap(p):
            c = cell_of(*p)
            for rad in range(0, 10):
                for dz in range(-rad, rad + 1):
                    for dx in range(-rad, rad + 1):
                        k = (c[0] + dx, c[1] + dz)
                        if k in walk:
                            return k
            return None

        start, goal = snap(a), snap(b)
        if start is None or goal is None:
            return None
        dist = {start: 0.0}
        heap = [(0.0, start)]
        while heap:
            d, cur = heapq.heappop(heap)
            if d != dist[cur]:
                continue
            if cur == goal:
                return d
            for dx, dz, step in ((1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
                                 (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)):
                nxt = (cur[0] + dx, cur[1] + dz)
                nd = d + step * cell
                if nxt in walk and nd < dist.get(nxt, 1e18):
                    dist[nxt] = nd
                    heapq.heappush(heap, (nd, nxt))
        return None

    return nearest, route


def check(all_boxes) -> None:
    feet = {
        "start": (*START, 0.0), "exit": (*EXIT, 0.0), "waystone": (*WAYSTONE, 0.0),
        "station": (*STATION, 0.0), "den": (*DEN, 0.0), "gal_w": (*GAL_W, 0.0),
        "gal_e": (*GAL_E, 0.0), "cist": (*CIST, 0.0), "lev_w": (*LEV_W, 0.0),
        "lev_e": (*LEV_E, 0.0), "wing_w": (*WING_W, 0.0), "wing_e": (*WING_E, 0.0),
        "chest": (*CHEST, 0.0), "den_point": (*DEN_POINT, 0.0), "dais": (*DAIS, 0.2),
    }
    for name, (x, z, y) in feet.items():
        if not on_surface(all_boxes, x, y, z):
            raise SystemExit(f"off surface: {name} {(x, y, z)}")
    def at(xz, y=0.0):
        return (xz[0], y, xz[1])

    rings = [
        (at(DEN), 3), (at(CIST), 2), (at(WING_W), 2), (at(WING_E), 2),
        (at(GAL_W), 1), (at(GAL_E), 1), (at(DAIS, 0.2), 1),
    ]
    for center, n in rings:
        for spot in ring(center, n):
            if not on_surface(all_boxes, *spot):
                raise SystemExit(f"ring off surface: {spot} from {center} n={n}")
    closed, route = None, None
    nearest, route = flood(all_boxes, set())
    goals_open = ["den", "gal_w", "gal_e", "cist", "lev_w", "lev_e", "station", "exit", "waystone"]
    for g in goals_open:
        if nearest(*feet[g][:2], 1.2) is None:
            raise SystemExit(f"sealed: cannot stand at {g}")
    if nearest(*DAIS, 1.2) is not None and route(START, DAIS) is not None:
        # route() snaps; a blocked arena should not connect
        if route(START, DAIS) is not None and nearest(*feet["dais"][:2], 0.8) is not None:
            length = route(START, DAIS)
            if length is not None and length < 200:
                raise SystemExit(f"arena leak before the gate: {length:.1f} m")
    nearest_g, route_g = flood(all_boxes, {"switch_gate"})
    length = route_g(DEN_POINT, DAIS)
    if length is None or length > 40:
        raise SystemExit(f"den point to dais: {length}")
    for g in ("wing_w", "wing_e", "dais"):
        if nearest_g(*feet[g][:2], 1.0) is None:
            raise SystemExit(f"after gate, {g} unreachable")
    if route_g(START, CHEST) is not None:
        raise SystemExit("vault leak before its door")
    nearest_v, route_v = flood(all_boxes, {"switch_gate", "vault_door"})
    if route_v(START, CHEST) is None:
        raise SystemExit("vault unreachable after the door opens")
    print(f"[breach] colliders ok, den-point path {length:.1f} m, ground boxes "
          f"{sum(1 for b in all_boxes if b['kind']=='ground')}")


def toml_text(all_boxes) -> str:
    def vec(v):
        return "[" + ", ".join(f"{x:.3f}".rstrip("0").rstrip(".") if isinstance(x, float) else str(x) for x in v) + "]"

    lines = [
        "# The Breach — crater around the labyrinth gate at (0, 0, 125).",
        "# Generated by tools/build_breach_art.py. Colliders only; the shell mesh is the visible crater.",
        "# Gameplay ids stay: three rooms, two levers, the switch gate, the Warden, the vault,",
        "# the waystone, and the road back to the Landfill. The Core stays closed.",
        "",
        "[level]",
        'id = "breach_slice"',
        'name = "The Breach"',
        "world_offset = [1104.0, -64.0]",
        'script = "scripts/world/breach_look.gd"',
        "",
        "[environment]",
        "sky_color = [0.07, 0.05, 0.10]",
        "ambient_color = [0.40, 0.32, 0.44]",
        "fog_density = 0.004",
        "sky = true",
        "volumetric_fog = 0.02",
        "fog_albedo = [0.34, 0.22, 0.46]",
        "grade = [0.94, 1.08, 0.96]",
        "",
        "[sun]",
        "to_light = [0.22, 0.92, 0.18]",
        "color = [0.58, 0.46, 0.42]",
        "",
        "[player_start]",
        f"position = [{START[0]}, 0.0, {START[1]}]",
        "yaw_deg = 0.0",
        "",
    ]
    for b in all_boxes:
        lines += [
            "[[box]]",
            f'name = "{b["name"]}"',
            f'kind = "{b["kind"]}"',
            f"center = {vec(b['center'])}",
            f"size = {vec(b['size'])}",
            "color = [0.30, 0.28, 0.26]",
            "collide_only = true",
            "",
        ]
    lines += [
        "[waves]",
        "trigger_center = [0.0, 0.0, 80.0]",
        "trigger_radius = 5.0",
        "",
        "[[spawn_point]]",
        'name = "boss_dais"',
        f"position = [{DAIS[0]}, 0.2, {DAIS[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[spawn_point]]",
        'name = "west_wing"',
        f"position = [{WING_W[0]}, 0.0, {WING_W[1]}]",
        "yaw_deg = -90.0",
        "",
        "[[spawn_point]]",
        'name = "east_wing"',
        f"position = [{WING_E[0]}, 0.0, {WING_E[1]}]",
        "yaw_deg = 90.0",
        "",
        "[[spawn_point]]",
        'name = "station"',
        f"position = [{STATION[0]}, 0.0, {STATION[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[spawn_point]]",
        'name = "vault_chest"',
        f"position = [{CHEST[0]}, 0.0, {CHEST[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[wave]]",
        'id = "wing_gnawers"',
        "delay_s = 1.0",
        'enemies = [{ enemy = "gnawer", count = 2, at = "west_wing" }, { enemy = "gnawer", count = 2, at = "east_wing" }]',
        "",
        "[[wave]]",
        'id = "dais_heap"',
        "delay_s = 3.0",
        'enemies = [{ enemy = "heap", count = 1, at = "boss_dais" }, { enemy = "gnawer", count = 2, at = "west_wing" }]',
        "",
        "[[wave]]",
        'id = "warden"',
        "delay_s = 4.0",
        'enemies = [{ enemy = "breach_warden", count = 1, at = "boss_dais" }]',
        "",
        "[[spawn_point]]",
        'name = "den_north"',
        f"position = [{DEN[0]}, 0.0, {DEN[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[spawn_point]]",
        'name = "gallery_west"',
        f"position = [{GAL_W[0]}, 0.0, {GAL_W[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[spawn_point]]",
        'name = "gallery_east"',
        f"position = [{GAL_E[0]}, 0.0, {GAL_E[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[spawn_point]]",
        'name = "cistern_north"',
        f"position = [{CIST[0]}, 0.0, {CIST[1]}]",
        "yaw_deg = 180.0",
        "",
        "[[encounter]]",
        'id = "room1_den"',
        f"trigger_center = [{DEN[0]}, 0.0, {DEN[1]}]",
        "trigger_radius = 6.0",
        'enemies = [{ enemy = "gnawer", count = 3, at = "den_north" }]',
        "",
        "[[encounter]]",
        'id = "room2_gallery"',
        "trigger_center = [-42.0, 0.0, 131.0]",
        "trigger_radius = 6.0",
        'enemies = [{ enemy = "scorchling", count = 1, at = "gallery_west" }, { enemy = "scorchling", count = 1, at = "gallery_east" }]',
        "",
        "[[encounter]]",
        'id = "room3_cistern"',
        f"trigger_center = [{CIST[0]}, 0.0, {CIST[1]}]",
        "trigger_radius = 6.0",
        'enemies = [{ enemy = "ooze", count = 1, at = "cistern_north" }, { enemy = "gnawer", count = 1, at = "cistern_north" }]',
        "",
        "[[switch]]",
        'name = "lever_west"',
        'opens = "switch_gate"',
        f"position = [{LEV_W[0]}, 0.0, {LEV_W[1]}]",
        "yaw_deg = 90.0",
        "",
        "[[switch]]",
        'name = "lever_east"',
        'opens = "switch_gate"',
        f"position = [{LEV_E[0]}, 0.0, {LEV_E[1]}]",
        "yaw_deg = -90.0",
        "",
        "[[exit]]",
        'name = "to_midden"',
        'to = "midden"',
        f"position = [{EXIT[0]}, 0.0, {EXIT[1]}]",
        "",
        "[[waystone]]",
        'point = "breach"',
        f"position = [{WAYSTONE[0]}, 0.0, {WAYSTONE[1]}]",
        "yaw_deg = 180.0",
        "",
    ]
    props = [("breach_shell", "assets/original/ember_art/breach/breach_shell.glb", (0, 0, 0), 0, 1)]
    town = "assets/kenney/fantasy-town-kit/"
    bones = "assets/original/ember_art/warrens/"
    trash = "assets/quaternius/enemies/props/"
    rubble = [
        (-46, 160, "rock-large", 20, 2.2), (-28, 148, "rock-wide", 80, 1.8),
        (-54, 140, "rock-small", 10, 2.4), (-58, 118, "rock-large", 140, 1.8),
        (-22, 96, "rock-wide", 30, 2.0), (18, 92, "rock-small", 60, 2.2),
        (58, 108, "rock-large", 200, 1.7), (60, 136, "rock-wide", 15, 1.9),
        (22, 176, "rock-small", 90, 2.0), (-16, 188, "rock-wide", 40, 1.6),
        (8, 60, "rock-large", 0, 1.5), (-12, 84, "rock-small", 70, 1.8),
    ]
    for i, (x, z, m, rot, sc) in enumerate(rubble):
        props.append((f"rubble_{i + 1}", town + f"{m}.glb", (x, 0, z), rot, sc))
    for i, (x, z) in enumerate(((-5.4, 182), (5.4, 182), (-5.4, 170), (5.4, 170), (-40, 150), (34, 158))):
        props.append((f"breach_lantern_{i + 1}", town + "lantern.glb", (x, 0, z), i * 25, 1.5))
    for i, (x, z, rot, sc) in enumerate(((-40, 156, 20, 2.4), (-34, 150, 80, 2.0), (-32, 104, 10, 2.2), (-38, 98, 140, 1.8))):
        props.append((f"breach_bone_{i + 1}", bones + "bone_pile.glb", (x, 0, z), rot, sc))
    props.append(("breach_cookfire", bones + "cook_fire.glb", (-44, 0, 126), 30, 1.6))
    props.append(("breach_torch_den", bones + "torch_sconce.glb", (-28, 0, 160), 90, 1.3))
    props.append(("breach_torch_hall", bones + "torch_sconce.glb", (5.2, 0, 174), -90, 1.2))
    for i, (x, z, m, rot, sc) in enumerate(((-2, 192, "Trash_Bags", 15, 3.2), (2.4, 190, "Trash_Bag", 70, 3.0), (-4.2, 188, "Can_Broken", 0, 2.2))):
        props.append((f"breach_trash_{i + 1}", trash + f"{m}.glb", (x, 0, z), rot, sc))
    for name, model, pos, rot, sc in props:
        lines += [
            "[[prop]]",
            f'name = "{name}"',
            f'model = "{model}"',
            f"position = [{pos[0]}, {pos[1]}, {pos[2]}]",
            f"rotation_deg = [0.0, {rot}, 0.0]",
            f"scale = {sc}",
            "",
        ]
    lines += [
        "# ---- EXPAND_BEGIN (generated by tools/expand_maps.py; edit that, not this) ----",
        "# ---- EXPAND_END ----",
        "",
        "# ---- DRESS_BEGIN (generated by tools/dress_levels.py; edit that, not this) ----",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    all_boxes = boxes()
    check(all_boxes)
    doc = build_document()
    write_glb(doc, OUT_GLB)
    OUT_TOML.write_text(toml_text(all_boxes), encoding="utf-8")
    print(f"[breach] wrote {OUT_GLB.relative_to(ROOT)} ({OUT_GLB.stat().st_size} bytes)")
    print(f"[breach] wrote {OUT_TOML.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
