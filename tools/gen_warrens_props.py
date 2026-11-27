#!/usr/bin/env python3
"""Act I Goblin Warrens hero props (CC0, original geometry for this project).

Writes glTF binary meshes and two small textures under
assets/original/ember_art/warrens/pbr/. Materials are flat factors here;
Godot overrides them with ambientCG PBR (Ground080, Rock030, Wood049, Metal032).
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "original" / "ember_art" / "warrens" / "pbr"


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    ):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _plaque() -> None:
    img = Image.new("RGB", (1024, 512), (42, 32, 26))
    px = img.load()
    for y in range(512):
        for x in range(1024):
            n = (
                math.sin(x * 0.04) * math.cos(y * 0.07)
                + math.sin(x * 0.11 + y * 0.05) * 0.5
            )
            c = 48 + int(n * 14)
            px[x, y] = (c + 8, c - 2, c - 10)
    draw = ImageDraw.Draw(img)
    font = _font(118)
    text = "Joe's Graffiti"
    box = draw.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    ox, oy = (1024 - tw) // 2, (512 - th) // 2 - 10
    for dx, dy in ((4, 6), (0, 0)):
        draw.text((ox + dx, oy + dy), text, font=font, fill=(120, 18, 16) if dx else (168, 28, 22))
    # Drips under the letters, one painted mark.
    rng = 1
    for i in range(14):
        rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
        x = 180 + (rng % 680)
        length = 28 + (rng % 70)
        draw.line((x, oy + th - 8, x + (rng % 7) - 3, oy + th + length), fill=(150, 22, 18), width=3 + rng % 3)
    img = img.filter(ImageFilter.SMOOTH)
    img.save(OUT / "joe_plaque.png", quality=90)


def _sigil() -> None:
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse((28, 28, 228, 228), outline=(150, 190, 255, 255), width=8)
    d.polygon([(128, 48), (188, 128), (128, 208), (68, 128)], outline=(190, 220, 255, 255))
    d.line((128, 40, 128, 216), fill=(210, 230, 255, 255), width=4)
    d.line((48, 128, 208, 128), fill=(210, 230, 255, 255), width=4)
    d.ellipse((108, 108, 148, 148), fill=(230, 240, 255, 255))
    img.save(OUT / "crate_sigil.png")


class Mesh:
    def __init__(self, name: str, material: str) -> None:
        self.name = name
        self.material = material
        self.pos: list[float] = []
        self.nor: list[float] = []
        self.uv: list[float] = []
        self.idx: list[int] = []

    def _vert(self, p, n, uv) -> int:
        self.pos.extend(p)
        ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0
        self.nor.extend((n[0] / ln, n[1] / ln, n[2] / ln))
        self.uv.extend(uv)
        return len(self.pos) // 3 - 1

    def tri(self, a, na, ua, b, nb, ub, c, nc, uc) -> None:
        ia, ib, ic = self._vert(a, na, ua), self._vert(b, nb, ub), self._vert(c, nc, uc)
        self.idx.extend((ia, ib, ic))

    def face(self, pts, n, uv0=(0.0, 0.0), uv1=(1.0, 1.0)) -> None:
        # pts: 4 corners, CCW when looking along the normal.
        uvs = [(uv0[0], uv0[1]), (uv1[0], uv0[1]), (uv1[0], uv1[1]), (uv0[0], uv1[1])]
        self.tri(pts[0], n, uvs[0], pts[1], n, uvs[1], pts[2], n, uvs[2])
        self.tri(pts[0], n, uvs[0], pts[2], n, uvs[2], pts[3], n, uvs[3])


def _box(mesh: Mesh, c, s, uv=(1.0, 1.0)) -> None:
    x, y, z = c
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    v = [
        (x - hx, y - hy, z - hz),
        (x + hx, y - hy, z - hz),
        (x + hx, y + hy, z - hz),
        (x - hx, y + hy, z - hz),
        (x - hx, y - hy, z + hz),
        (x + hx, y - hy, z + hz),
        (x + hx, y + hy, z + hz),
        (x - hx, y + hy, z + hz),
    ]
    faces = [
        (4, 5, 6, 7, (0, 0, 1)),
        (1, 0, 3, 2, (0, 0, -1)),
        (5, 1, 2, 6, (1, 0, 0)),
        (0, 4, 7, 3, (-1, 0, 0)),
        (3, 7, 6, 2, (0, 1, 0)),
        (0, 1, 5, 4, (0, -1, 0)),
    ]
    for a, b, c2, d, n in faces:
        mesh.face([v[a], v[b], v[c2], v[d]], n, (0, 0), uv)


def _bulged_crate(mesh: Mesh, origin, size) -> None:
    """A crate with a bowed plank on each side, not a bare cube."""
    ox, oy, oz = origin
    sx, sy, sz = size
    steps = 3
    # (normal, u axis, v axis, half-extents along u and v)
    specs = (
        ((0, 0, 1), (1, 0, 0), (0, 1, 0), sx, sy),
        ((0, 0, -1), (-1, 0, 0), (0, 1, 0), sx, sy),
        ((1, 0, 0), (0, 0, -1), (0, 1, 0), sz, sy),
        ((-1, 0, 0), (0, 0, 1), (0, 1, 0), sz, sy),
        ((0, 1, 0), (1, 0, 0), (0, 0, -1), sx, sz),
        ((0, -1, 0), (1, 0, 0), (0, 0, 1), sx, sz),
    )
    for n, u, v, su, sv in specs:
        depth = (sx if n[0] else sy if n[1] else sz) * 0.5
        for i in range(steps):
            for j in range(steps):
                pts = []
                for di, dj in ((0, 0), (1, 0), (1, 1), (0, 1)):
                    tu = (i + di) / steps - 0.5
                    tv = (j + dj) / steps - 0.5
                    bow = 0.04 * math.cos(tu * math.pi) * math.cos(tv * math.pi)
                    if n[1] > 0:
                        py = oy + sy + bow
                    elif n[1] < 0:
                        py = oy
                        bow = 0.0
                    else:
                        py = oy + sy * 0.5 + tv * sy
                    pts.append((
                        ox + n[0] * (depth + bow) + u[0] * tu * su + v[0] * tv * sv,
                        py,
                        oz + n[2] * (depth + bow) + u[2] * tu * su + v[2] * tv * sv,
                    ))
                mesh.face(pts, n, (i / steps, j / steps), ((i + 1) / steps, (j + 1) / steps))


def _cone(mesh: Mesh, base, tip, radius, sides=9) -> None:
    bx, by, bz = base
    tx, ty, tz = tip
    axis = (tx - bx, ty - by, tz - bz)
    up = (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)
    ux, uy, uz = _cross(axis, up)
    ul = math.sqrt(ux * ux + uy * uy + uz * uz) or 1
    ux, uy, uz = ux / ul, uy / ul, uz / ul
    vx, vy, vz = _cross(axis, (ux, uy, uz))
    ring = []
    for i in range(sides):
        a = i / sides * math.tau
        ring.append((bx + (ux * math.cos(a) + vx * math.sin(a)) * radius, by + (uy * math.cos(a) + vy * math.sin(a)) * radius, bz + (uz * math.cos(a) + vz * math.sin(a)) * radius))
    for i in range(sides):
        p0, p1 = ring[i], ring[(i + 1) % sides]
        n = _cross(_sub(p1, p0), _sub((tx, ty, tz), p0))
        mesh.tri(p0, n, (i / sides, 0), p1, n, ((i + 1) / sides, 0), (tx, ty, tz), axis, (0.5, 1))


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _lathe(mesh: Mesh, profile, sides=18) -> None:
    rings = []
    for y, r in profile:
        ring = []
        for i in range(sides):
            a = i / sides * math.tau
            ring.append((math.cos(a) * r, y, math.sin(a) * r))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for i in range(sides):
            a, b = rings[j][i], rings[j][(i + 1) % sides]
            c, d = rings[j + 1][(i + 1) % sides], rings[j + 1][i]
            n = _cross(_sub(b, a), _sub(d, a))
            mesh.tri(a, n, (i / sides, j / 6), b, n, ((i + 1) / sides, j / 6), c, n, ((i + 1) / sides, (j + 1) / 6))
            mesh.tri(a, n, (i / sides, j / 6), c, n, ((i + 1) / sides, (j + 1) / 6), d, n, (i / sides, (j + 1) / 6))


def _prism(mesh: Mesh, y0, y1, r0, r1, sides, twist=0.0) -> None:
    def ring(y, r, ang0):
        return [(math.cos(ang0 + i / sides * math.tau) * r, y, math.sin(ang0 + i / sides * math.tau) * r) for i in range(sides)]

    a = ring(y0, r0, 0.0)
    b = ring(y1, r1, twist)
    for i in range(sides):
        p0, p1 = a[i], a[(i + 1) % sides]
        p2, p3 = b[(i + 1) % sides], b[i]
        n = _cross(_sub(p1, p0), _sub(p3, p0))
        mesh.tri(p0, n, (i / sides, 0), p1, n, ((i + 1) / sides, 0), p2, n, ((i + 1) / sides, 1))
        mesh.tri(p0, n, (i / sides, 0), p2, n, ((i + 1) / sides, 1), p3, n, (i / sides, 1))
    # cap
    c0 = (0, y1, 0)
    for i in range(sides):
        mesh.tri(c0, (0, 1, 0), (0.5, 0.5), b[i], (0, 1, 0), (0, 0), b[(i + 1) % sides], (0, 1, 0), (1, 0))


def _tube(mesh: Mesh, pts, r0, r1, sides=7) -> None:
    rings = []
    for i, p in enumerate(pts):
        t = i / max(1, len(pts) - 1)
        r = r0 + (r1 - r0) * t
        if i == 0:
            direction = _sub(pts[1], p)
        elif i == len(pts) - 1:
            direction = _sub(p, pts[i - 1])
        else:
            direction = _sub(pts[i + 1], pts[i - 1])
        up = (0.0, 1.0, 0.0) if abs(direction[1]) < 0.85 else (1.0, 0.0, 0.0)
        ux, uy, uz = _cross(direction, up)
        ul = math.sqrt(ux * ux + uy * uy + uz * uz) or 1
        ux, uy, uz = ux / ul, uy / ul, uz / ul
        vx, vy, vz = _cross(direction, (ux, uy, uz))
        vl = math.sqrt(vx * vx + vy * vy + vz * vz) or 1
        vx, vy, vz = vx / vl, vy / vl, vz / vl
        ring = []
        for s in range(sides):
            a = s / sides * math.tau
            ring.append((
                p[0] + (ux * math.cos(a) + vx * math.sin(a)) * r,
                p[1] + (uy * math.cos(a) + vy * math.sin(a)) * r,
                p[2] + (uz * math.cos(a) + vz * math.sin(a)) * r,
            ))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for i in range(sides):
            a, b = rings[j][i], rings[j][(i + 1) % sides]
            c, d = rings[j + 1][(i + 1) % sides], rings[j + 1][i]
            n = _cross(_sub(b, a), _sub(d, a))
            mesh.tri(a, n, (i / sides, j / 4), b, n, ((i + 1) / sides, j / 4), c, n, ((i + 1) / sides, (j + 1) / 4))
            mesh.tri(a, n, (i / sides, j / 4), c, n, ((i + 1) / sides, (j + 1) / 4), d, n, (i / sides, (j + 1) / 4))


def _crystal(mesh: Mesh, base, height, radius, tilt) -> None:
    sides = 6
    tip = (base[0] + tilt[0], base[1] + height, base[2] + tilt[1])
    mid_y = base[1] + height * 0.62
    mid = (base[0] + tilt[0] * 0.35, mid_y, base[2] + tilt[1] * 0.35)
    lower, upper = [], []
    for i in range(sides):
        a = i / sides * math.tau
        c, s = math.cos(a), math.sin(a)
        lower.append((base[0] + c * radius, base[1], base[2] + s * radius))
        upper.append((mid[0] + c * radius * 0.72, mid[1], mid[2] + s * radius * 0.72))
    for i in range(sides):
        a, b = lower[i], lower[(i + 1) % sides]
        c, d = upper[(i + 1) % sides], upper[i]
        n = _cross(_sub(b, a), _sub(d, a))
        mesh.tri(a, n, (i / sides, 0), b, n, ((i + 1) / sides, 0), c, n, ((i + 1) / sides, 0.6))
        mesh.tri(a, n, (i / sides, 0), c, n, ((i + 1) / sides, 0.6), d, n, (i / sides, 0.6))
        n2 = _cross(_sub(c, d), _sub(tip, d))
        mesh.tri(d, n2, (i / sides, 0.6), c, n2, ((i + 1) / sides, 0.6), tip, (tilt[0], 1, tilt[1]), (0.5, 1))


def _chunk(mesh: Mesh, scale: float) -> None:
    # Subdivided octahedron with a lumpy radius, a loose rock.
    verts = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    faces = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
    for _ in range(2):
        mid = {}
        new = []
        def mp(i, j):
            k = (min(i, j), max(i, j))
            if k not in mid:
                a, b = verts[i], verts[j]
                p = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
                ln = math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2) or 1
                mid[k] = len(verts)
                verts.append((p[0] / ln, p[1] / ln, p[2] / ln))
            return mid[k]
        for a, b, c in faces:
            ab, bc, ca = mp(a, b), mp(b, c), mp(c, a)
            new.extend(((a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)))
        faces = new
    for a, b, c in faces:
        def lump(p):
            n = math.sin(p[0] * 4.2) * math.cos(p[1] * 3.1) * math.sin(p[2] * 5.0)
            r = scale * (0.82 + 0.18 * n)
            return (p[0] * r, p[1] * r * 0.72 + scale * 0.15, p[2] * r)
        pa, pb, pc = lump(verts[a]), lump(verts[b]), lump(verts[c])
        n = _cross(_sub(pb, pa), _sub(pc, pa))
        mesh.tri(pa, n, (0, 0), pb, n, (1, 0), pc, n, (0.5, 1))


def build() -> dict[str, list[Mesh]]:
    out: dict[str, list[Mesh]] = {}
    barrel = Mesh("barrel", "wood")
    _lathe(barrel, [(0.02, 0.22), (0.08, 0.34), (0.18, 0.38), (0.45, 0.42), (0.78, 0.38), (0.95, 0.30), (1.05, 0.22)])
    hoops = Mesh("hoops", "metal")
    for y in (0.22, 0.55, 0.84):
        _lathe(hoops, [(y, 0.40), (y + 0.015, 0.445), (y + 0.045, 0.445), (y + 0.06, 0.40)], 18)
    out["barrel"] = [barrel, hoops]

    pot = Mesh("pot", "metal")
    _lathe(pot, [(0.02, 0.16), (0.06, 0.28), (0.28, 0.34), (0.48, 0.30), (0.56, 0.36), (0.62, 0.33)])
    flame = Mesh("flame", "flame")
    _cone(flame, (0, 0.62, 0), (0.04, 1.25, 0.02), 0.16, 8)
    _cone(flame, (-0.06, 0.64, 0.04), (0.02, 1.05, -0.02), 0.10, 7)
    _cone(flame, (0.07, 0.64, -0.03), (-0.02, 1.08, 0.04), 0.09, 7)
    out["ward_pot"] = [pot, flame]

    crystals = Mesh("crystal_cluster", "crystal")
    _crystal(crystals, (0, 0, 0), 1.7, 0.18, (0.12, 0.05))
    _crystal(crystals, (0.28, 0, 0.12), 1.15, 0.12, (-0.08, 0.16))
    _crystal(crystals, (-0.22, 0, 0.16), 1.35, 0.14, (-0.16, -0.05))
    _crystal(crystals, (0.08, 0, -0.26), 0.9, 0.1, (0.05, -0.12))
    _crystal(crystals, (-0.12, 0, -0.16), 0.7, 0.08, (0.1, 0.08))
    out["crystal_cluster"] = [crystals]

    throne = Mesh("throne_pyramid", "bone")
    for i, (y, r) in enumerate(((0.0, 3.4), (0.55, 2.7), (1.15, 2.05), (1.7, 1.45), (2.2, 0.9))):
        _prism(throne, y, y + 0.5, r, r * 0.82, 8, i * 0.08)
    for i in range(16):
        a = i / 16 * math.tau
        rad = 2.4 - (i % 3) * 0.35
        y = 0.45 + (i % 4) * 0.4
        base = (math.cos(a) * rad, y, math.sin(a) * rad)
        tip = (math.cos(a) * (rad + 0.35), y + 1.1 + (i % 5) * 0.28, math.sin(a) * (rad + 0.35))
        _cone(throne, base, tip, 0.08 + (i % 3) * 0.03, 6)
    _cone(throne, (0, 2.5, 0), (0.1, 5.6, -0.05), 0.22, 7)
    _cone(throne, (0.3, 2.4, 0.2), (0.55, 4.4, 0.35), 0.12, 6)
    _cone(throne, (-0.35, 2.45, -0.1), (-0.6, 4.7, -0.2), 0.13, 6)
    out["throne_pyramid"] = [throne]

    crate = Mesh("crates", "wood")
    _bulged_crate(crate, (-0.15, 0, 0.1), (0.9, 0.72, 0.85))
    _bulged_crate(crate, (0.55, 0, -0.15), (0.78, 0.6, 0.8))
    _bulged_crate(crate, (0.05, 0.72, -0.02), (0.7, 0.55, 0.68))
    _bulged_crate(crate, (0.35, 1.25, 0.05), (0.55, 0.48, 0.55))
    sig = Mesh("sigil", "sigil")
    sig.face(
        [(-0.05, 0.95, 0.36), (0.45, 0.95, 0.36), (0.45, 1.55, 0.36), (-0.05, 1.55, 0.36)],
        (0, 0, 1),
    )
    out["sigil_crates"] = [crate, sig]

    plaque = Mesh("joe_plaque", "plaque")
    # Slab. Textured face is +z.
    plaque.face([(-1.6, 0.7, 0.08), (1.6, 0.7, 0.08), (1.6, 2.5, 0.08), (-1.6, 2.5, 0.08)], (0, 0, 1), (0, 1), (1, 0))
    plaque.face([(1.6, 0.7, -0.08), (-1.6, 0.7, -0.08), (-1.6, 2.5, -0.08), (1.6, 2.5, -0.08)], (0, 0, -1))
    plaque.face([(-1.6, 0.7, -0.08), (-1.6, 0.7, 0.08), (-1.6, 2.5, 0.08), (-1.6, 2.5, -0.08)], (-1, 0, 0))
    plaque.face([(1.6, 0.7, 0.08), (1.6, 0.7, -0.08), (1.6, 2.5, -0.08), (1.6, 2.5, 0.08)], (1, 0, 0))
    plaque.face([(-1.6, 2.5, 0.08), (1.6, 2.5, 0.08), (1.6, 2.5, -0.08), (-1.6, 2.5, 0.08)], (0, 1, 0))
    out["joe_plaque"] = [plaque]

    roots = Mesh("root_cluster", "wood")
    bends = (
        ((-0.8, 0, 0.2), (0.4, 0.9, -0.6), (0.0, 0.4, 0.5)),
        ((0.6, 0, -0.2), (-0.5, 0.7, 0.4), (0.3, 0.2, -0.4)),
        ((0.1, 0, 0.7), (-0.2, 1.1, -0.2), (0.5, 0.3, 0.2)),
        ((-0.4, 0, -0.6), (0.7, 0.55, 0.3), (-0.2, 0.5, 0.1)),
        ((0.9, 0, 0.4), (-0.1, 0.4, -0.8), (0.2, 0.15, 0.4)),
        ((-1.0, 0, -0.3), (0.2, 0.35, 0.6), (-0.4, 0.2, -0.2)),
    )
    for a, b, bend in bends:
        pts = []
        for i in range(8):
            t = i / 7
            pts.append((
                a[0] + (b[0] - a[0]) * t + bend[0] * math.sin(t * math.pi),
                a[1] + (b[1] - a[1]) * t + bend[1] * math.sin(t * math.pi),
                a[2] + (b[2] - a[2]) * t + bend[2] * math.sin(t * math.pi),
            ))
        _tube(roots, pts, 0.16, 0.04, 6)
    out["root_cluster"] = [roots]

    spikes = Mesh("spike_row", "wood")
    _box(spikes, (0, 0.18, 0), (2.6, 0.28, 0.34))
    for i in range(6):
        x = -1.05 + i * 0.42
        _cone(spikes, (x, 0.28, 0.05), (x + 0.18, 1.15, -0.45), 0.07, 6)
    out["spike_row"] = [spikes]

    beam = Mesh("timber_beam", "wood")
    # 4 m beam along X, slight sag, chamfered by a lathed-in-place grid.
    for i in range(16):
        t0, t1 = i / 16, (i + 1) / 16
        x0, x1 = -2 + 4 * t0, -2 + 4 * t1
        sag0 = 0.08 * math.sin(t0 * math.pi)
        sag1 = 0.08 * math.sin(t1 * math.pi)
        s = 0.16
        for y0, z0, y1, z1, n in (
            (s, -s, s, s, (0, 1, 0)),
            (-s, s, -s, -s, (0, -1, 0)),
            (-s, -s, s, -s, (0, 0, -1)),
            (s, s, -s, s, (0, 0, 1)),
        ):
            beam.face(
                [
                    (x0, y0 - sag0, z0),
                    (x1, y0 - sag1, z0),
                    (x1, y1 - sag1, z1),
                    (x0, y1 - sag0, z1),
                ],
                n,
                (t0, 0),
                (t1, 1),
            )
    out["timber_beam"] = [beam]

    post = Mesh("timber_post", "wood")
    _box(post, (0, 2.0, 0), (0.28, 4.0, 0.28), (1, 4))
    _box(post, (0, 3.55, 0.18), (0.34, 0.16, 0.16))
    out["timber_post"] = [post]

    rock = Mesh("rock_chunk", "rock")
    _chunk(rock, 0.85)
    out["rock_chunk"] = [rock]
    return out


def _glb(meshes: list[Mesh], path: Path) -> None:
    blobs = bytearray()
    views = []
    accessors = []
    primitives = []
    mat_names = []
    mat_index = {}

    def add_mat(name: str) -> int:
        if name not in mat_index:
            mat_index[name] = len(mat_names)
            mat_names.append(name)
        return mat_index[name]

    def push(data: bytes, target: int | None) -> int:
        while len(blobs) % 4:
            blobs.append(0)
        start = len(blobs)
        blobs.extend(data)
        views.append({"buffer": 0, "byteOffset": start, "byteLength": len(data), **({"target": target} if target else {})})
        return len(views) - 1

    nodes = []
    gl_meshes = []
    for mi, mesh in enumerate(meshes):
        pf = struct.pack("<%df" % len(mesh.pos), *mesh.pos)
        nf = struct.pack("<%df" % len(mesh.nor), *mesh.nor)
        uf = struct.pack("<%df" % len(mesh.uv), *mesh.uv)
        ind = struct.pack("<%dH" % len(mesh.idx), *mesh.idx)
        pv, nv, uvv, iv = push(pf, 34962), push(nf, 34962), push(uf, 34962), push(ind, 34963)
        count = len(mesh.pos) // 3

        def acc(view, comp, ctype, cnt, mins=None, maxs=None):
            item = {"bufferView": view, "componentType": ctype, "count": cnt, "type": comp}
            if mins is not None:
                item["min"] = mins
                item["max"] = maxs
            accessors.append(item)
            return len(accessors) - 1

        xs, ys, zs = mesh.pos[0::3], mesh.pos[1::3], mesh.pos[2::3]
        pa = acc(pv, "VEC3", 5126, count, [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)])
        na = acc(nv, "VEC3", 5126, count)
        ua = acc(uvv, "VEC2", 5126, len(mesh.uv) // 2)
        ia = acc(iv, "SCALAR", 5123, len(mesh.idx))
        gl_meshes.append({
            "name": mesh.name,
            "primitives": [{
                "attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ua},
                "indices": ia,
                "material": add_mat(mesh.material),
            }],
        })
        nodes.append({"name": mesh.name, "mesh": mi})

    colors = {
        "wood": [0.45, 0.3, 0.16, 1],
        "metal": [0.35, 0.36, 0.38, 1],
        "rock": [0.35, 0.3, 0.26, 1],
        "bone": [0.62, 0.54, 0.42, 1],
        "crystal": [0.45, 0.3, 0.75, 1],
        "flame": [0.4, 1.0, 0.35, 1],
        "sigil": [0.35, 0.55, 1.0, 1],
        "plaque": [0.4, 0.28, 0.22, 1],
    }
    materials = []
    for name in mat_names:
        m = {
            "name": name,
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": colors.get(name, [1, 1, 1, 1]),
                "metallicFactor": 0.15 if name == "metal" else 0.0,
                "roughnessFactor": 0.35 if name in ("crystal", "sigil", "flame") else 0.9,
            },
        }
        if name == "flame":
            m["emissiveFactor"] = [0.25, 0.9, 0.2]
        elif name == "sigil":
            m["emissiveFactor"] = [0.25, 0.45, 1.0]
        elif name == "crystal":
            m["emissiveFactor"] = [0.18, 0.08, 0.35]
        materials.append(m)

    gltf = {
        "asset": {"version": "2.0", "generator": "gen_warrens_props.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": gl_meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blobs)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    while len(blobs) % 4:
        blobs.append(0)
    bin_chunk = struct.pack("<I", len(blobs)) + b"BIN\0" + bytes(blobs)
    json_chunk = struct.pack("<I", len(js)) + b"JSON" + js
    data = b"glTF" + struct.pack("<II", 2, 12 + len(json_chunk) + len(bin_chunk)) + json_chunk + bin_chunk
    path.write_bytes(data)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    _plaque()
    _sigil()
    for name, meshes in build().items():
        _glb(meshes, OUT / f"{name}.glb")
        print(name, sum(len(m.idx) // 3 for m in meshes), "tris")


if __name__ == "__main__":
    main()
