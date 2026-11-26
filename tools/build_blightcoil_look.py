#!/usr/bin/env python3
"""Build the Act II cavern mesh (shell, Rotheart, shelves, props).

Textures are CC0: ambientCG Bark014, Moss004, plus Rock030 and Ground037
already in the tree. The mesh is original. Run from the repo root:

  python3 tools/build_blightcoil_look.py
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "original" / "ember_art" / "blightcoil_look" / "cavern_look.glb"
TEX = {
    "rock_c": ROOT / "assets/ambientcg/Rock030/color.jpg",
    "rock_n": ROOT / "assets/ambientcg/Rock030/normal.jpg",
    "rock_r": ROOT / "assets/ambientcg/Rock030/roughness.jpg",
    "floor_c": ROOT / "assets/ambientcg/Ground037/color.jpg",
    "floor_n": ROOT / "assets/ambientcg/Ground037/normal.jpg",
    "floor_r": ROOT / "assets/ambientcg/Ground037/roughness.jpg",
    "bark_c": ROOT / "assets/ambientcg/Bark014/color.jpg",
    "bark_n": ROOT / "assets/ambientcg/Bark014/normal.jpg",
    "bark_r": ROOT / "assets/ambientcg/Bark014/roughness.jpg",
    "moss_c": ROOT / "assets/ambientcg/Moss004/color.jpg",
    "moss_n": ROOT / "assets/ambientcg/Moss004/normal.jpg",
    "moss_r": ROOT / "assets/ambientcg/Moss004/roughness.jpg",
}


def noise(x: float, y: float, z: float) -> float:
    def h(ix: int, iy: int, iz: int) -> float:
        n = (ix * 374761393 + iy * 668265263 + iz * 1440670377) & 0xFFFFFFFF
        n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
        return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0

    x, y, z = x * 0.17, y * 0.17, z * 0.17
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)

    def g(dx: int, dy: int, dz: int) -> float:
        return h(ix + dx, iy + dy, iz + dz)

    c00 = g(0, 0, 0) * (1 - fx) + g(1, 0, 0) * fx
    c10 = g(0, 1, 0) * (1 - fx) + g(1, 1, 0) * fx
    c01 = g(0, 0, 1) * (1 - fx) + g(1, 0, 1) * fx
    c11 = g(0, 1, 1) * (1 - fx) + g(1, 1, 1) * fx
    c0 = c00 * (1 - fy) + c10 * fy
    c1 = c01 * (1 - fy) + c11 * fy
    return c0 * (1 - fz) + c1 * fz


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


def vnorm(a):
    m = math.sqrt(vdot(a, a)) or 1.0
    return (a[0] / m, a[1] / m, a[2] / m)


class Mesh:
    def __init__(self) -> None:
        self.pos: list[tuple[float, float, float]] = []
        self.nrm: list[tuple[float, float, float]] = []
        self.uv: list[tuple[float, float]] = []
        self.idx: list[int] = []

    def add(self, p, n, uv) -> int:
        self.pos.append(p)
        self.nrm.append(n)
        self.uv.append(uv)
        return len(self.pos) - 1

    def tri(self, a: int, b: int, c: int) -> None:
        self.idx.extend((a, b, c))

    def smooth(self) -> None:
        acc = [(0.0, 0.0, 0.0) for _ in self.pos]
        for i in range(0, len(self.idx), 3):
            a, b, c = self.idx[i], self.idx[i + 1], self.idx[i + 2]
            fn = vcross(vsub(self.pos[b], self.pos[a]), vsub(self.pos[c], self.pos[a]))
            for k in (a, b, c):
                acc[k] = vadd(acc[k], fn)
        self.nrm = [vnorm(n) for n in acc]


def add_tube(mesh: Mesh, points: list[tuple], radii: list[float], sides: int = 10, uv_scale: float = 2.0) -> None:
    rings: list[list[int]] = []
    for i, p in enumerate(points):
        if i == 0:
            d = vnorm(vsub(points[1], points[0]))
        elif i == len(points) - 1:
            d = vnorm(vsub(points[-1], points[-2]))
        else:
            d = vnorm(vsub(points[i + 1], points[i - 1]))
        up = (0.0, 1.0, 0.0) if abs(d[1]) < 0.92 else (1.0, 0.0, 0.0)
        side = vnorm(vcross(d, up))
        lift = vnorm(vcross(side, d))
        ring = []
        for s in range(sides):
            a = math.tau * s / sides
            radial = vadd(vmul(side, math.cos(a)), vmul(lift, math.sin(a)))
            wobble = 1.0 + (noise(p[0] + s, p[1], p[2]) - 0.5) * 0.22
            pos = vadd(p, vmul(radial, radii[i] * wobble))
            ring.append(mesh.add(pos, radial, (s / sides * uv_scale, i * 0.35)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for s in range(sides):
            s2 = (s + 1) % sides
            a, b = rings[i][s], rings[i][s2]
            c, d = rings[i + 1][s], rings[i + 1][s2]
            mesh.tri(a, b, c)
            mesh.tri(b, d, c)


def sag_points(a, b, n: int, dip: float) -> list[tuple]:
    out = []
    for i in range(n):
        t = i / (n - 1)
        p = (
            a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t - math.sin(t * math.pi) * dip,
            a[2] + (b[2] - a[2]) * t,
        )
        out.append(p)
    return out


def build_shell() -> Mesh:
    mesh = Mesh()
    nu, nv = 72, 40
    rx, ry, rz = 33.0, 19.0, 25.0
    cy = 15.5
    grid: list[list[int | None]] = []
    for iv in range(nv + 1):
        phi = math.pi * iv / nv
        row: list[int | None] = []
        for iu in range(nu):
            theta = math.tau * iu / nu
            st, ct = math.sin(phi), math.cos(phi)
            x = rx * st * math.cos(theta)
            y = cy + ry * ct
            z = rz * st * math.sin(theta)
            outward = vnorm((x / rx, (y - cy) / ry, z / rz))
            disp = (noise(x, y, z) - 0.42) * 4.2
            disp += (noise(x * 2.1, y * 1.4, z * 2.1) - 0.5) * 1.6
            disp += math.sin(theta * 5.0 + y * 0.22) * 0.7
            disp += math.sin(phi * 4.0 + theta * 2.0) * 0.45
            pos = vadd((x, y, z), vmul(outward, disp))
            # South window, so a side camera sees the cutaway.
            if z > 13.5 and 5.5 < y < 31.0:
                row.append(None)
                continue
            uv = (theta / math.tau * 6.0, y / 8.0)
            row.append(mesh.add(pos, vmul(outward, -1.0), uv))
        grid.append(row)
    for iv in range(nv):
        for iu in range(nu):
            a = grid[iv][iu]
            b = grid[iv][(iu + 1) % nu]
            c = grid[iv + 1][iu]
            d = grid[iv + 1][(iu + 1) % nu]
            if None in (a, b, c, d):
                continue
            # Inward faces: the previous winding showed the outside.
            mesh.tri(a, c, b)
            mesh.tri(b, c, d)
    mesh.smooth()
    return mesh


def build_tree() -> Mesh:
    mesh = Mesh()
    rings_n, sides = 48, 22
    grid = []
    for i in range(rings_n + 1):
        t = i / rings_n
        y = -0.4 + 33.5 * t
        base = 5.6 * (1.0 - 0.62 * t)
        if t < 0.18:
            base += (0.18 - t) / 0.18 * 2.6
        if t > 0.82:
            base += (t - 0.82) / 0.18 * 1.1
        row = []
        for s in range(sides):
            a = math.tau * s / sides
            front = max(0.0, math.sin(a))
            r = base
            if 0.40 < t < 0.60:
                cave = math.sin((t - 0.40) / 0.20 * math.pi)
                r -= front * cave * 2.8
            r += (noise(math.cos(a) * 4, y * 0.5, math.sin(a) * 4) - 0.5) * 0.7
            r += math.sin(a * 4.0 + y * 0.55) * 0.28
            r = max(r, 0.55)
            x, z = math.cos(a) * r, math.sin(a) * r
            row.append(mesh.add((x, y, z), (math.cos(a), 0.0, math.sin(a)), (s / sides * 3.0, y / 4.0)))
        grid.append(row)
    for i in range(rings_n):
        for s in range(sides):
            s2 = (s + 1) % sides
            a, b = grid[i][s], grid[i][s2]
            c, d = grid[i + 1][s], grid[i + 1][s2]
            mesh.tri(a, b, c)
            mesh.tri(b, d, c)
    limbs = [
        ((1.6, 22.0, 1.2), (18.0, 25.5, 3.0), 1.55, 0.35, 0.6),
        ((-1.4, 22.5, 0.8), (-20.0, 26.0, 1.5), 1.7, 0.4, 0.7),
        ((0.8, 27.0, 0.2), (14.0, 30.0, -3.0), 1.15, 0.28, 0.4),
        ((-0.6, 27.5, -0.2), (-15.0, 30.5, -2.0), 1.2, 0.3, 0.45),
        ((1.2, 18.5, 3.2), (9.0, 15.5, 13.0), 0.95, 0.22, 0.35),
        ((-1.0, 18.0, 2.8), (-11.0, 14.5, 12.0), 0.9, 0.2, 0.3),
        ((3.4, 12.5, 1.0), (16.0, 13.2, 6.0), 0.85, 0.22, 0.25),
        ((-3.2, 12.2, 0.6), (-18.0, 13.0, 2.0), 0.9, 0.22, 0.3),
        ((2.2, 8.0, 2.0), (10.0, 4.0, 14.0), 0.7, 0.18, 0.4),
        ((-2.0, 7.5, 1.6), (-12.0, 3.5, 12.0), 0.75, 0.18, 0.45),
    ]
    for a, b, r0, r1, dip in limbs:
        pts = sag_points(a, b, 8, dip)
        rad = [r0 + (r1 - r0) * (i / 7) for i in range(8)]
        add_tube(mesh, pts, rad, 8)
    roots = [
        ((4.2, 0.6, 2.4), (16.0, 0.35, 10.0), 1.5, 0.28),
        ((-4.0, 0.6, 2.0), (-18.0, 0.4, 8.0), 1.6, 0.3),
        ((3.0, 0.5, -2.5), (12.0, 0.3, -12.0), 1.2, 0.25),
        ((-2.6, 0.5, -2.2), (-14.0, 0.35, -10.0), 1.25, 0.25),
        ((1.5, 0.7, 4.5), (3.0, 0.25, 17.0), 1.1, 0.22),
        ((-1.2, 0.7, 4.2), (-7.0, 0.25, 15.0), 1.0, 0.2),
        ((5.0, 1.2, 0.5), (22.0, 6.0, 4.0), 0.7, 0.16),
        ((-4.8, 1.2, 0.4), (-22.0, 8.0, 2.0), 0.75, 0.16),
    ]
    for a, b, r0, r1 in roots:
        pts = sag_points(a, b, 7, 0.15)
        rad = [r0 + (r1 - r0) * (i / 6) for i in range(7)]
        add_tube(mesh, pts, rad, 8)
    mesh.smooth()
    return mesh


def build_heart() -> Mesh:
    mesh = Mesh()
    for iv in range(10):
        phi = math.pi * iv / 9
        row = []
        for iu in range(16):
            th = math.tau * iu / 16
            x = math.sin(phi) * math.cos(th) * 1.5
            y = 15.4 + math.cos(phi) * 1.9
            z = 3.6 + math.sin(phi) * math.sin(th) * 1.15
            if math.sin(th) > 0.35 and 0.25 < iv / 9 < 0.75:
                z -= 0.45
            n = vnorm((x, y - 15.4, z - 3.6))
            row.append(mesh.add((x, y, z), n, (iu / 16, iv / 9)))
        if iv == 0:
            continue
        prev = iv  # placeholder to satisfy the linter structure below
        _ = prev
    # rebuild simply with stored rows
    mesh.pos.clear()
    mesh.nrm.clear()
    mesh.uv.clear()
    mesh.idx.clear()
    grid = []
    for iv in range(11):
        phi = math.pi * iv / 10
        row = []
        for iu in range(18):
            th = math.tau * iu / 18
            x = math.sin(phi) * math.cos(th) * 1.55
            y = 15.3 + math.cos(phi) * 2.0
            z = 3.7 + math.sin(phi) * math.sin(th) * 1.2
            n = vnorm((x, (y - 15.3) / 1.3, (z - 3.7)))
            row.append(mesh.add((x, y, z), n, (iu / 18, iv / 10)))
        grid.append(row)
    for iv in range(10):
        for iu in range(18):
            s2 = (iu + 1) % 18
            mesh.tri(grid[iv][iu], grid[iv][s2], grid[iv + 1][iu])
            mesh.tri(grid[iv][s2], grid[iv + 1][s2], grid[iv + 1][iu])
    return mesh


def add_shelf(mesh: Mesh, x0, z0, x1, z1, y, step=1.8, skirt=2.2, hole=0.0) -> None:
    xs = [x0]
    while xs[-1] < x1 - 0.2:
        xs.append(min(x1, xs[-1] + step))
    if xs[-1] != x1:
        xs.append(x1)
    zs = [z0]
    while zs[-1] < z1 - 0.2:
        zs.append(min(z1, zs[-1] + step))
    if zs[-1] != z1:
        zs.append(z1)
    ids: dict[tuple[int, int], int | None] = {}
    for iz, z in enumerate(zs):
        for ix, x in enumerate(xs):
            if hole and x * x + z * z < hole * hole:
                ids[(ix, iz)] = None
                continue
            edge = min(x - x0, x1 - x, z - z0, z1 - z)
            n = noise(x * 1.3, y, z * 1.3)
            yy = y + (n - 0.5) * 0.28 + math.sin(x * 0.35) * math.cos(z * 0.28) * 0.08
            xx, zz = x, z
            if edge < 1.3:
                cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
                pull = (1.3 - edge) / 1.3 * (0.35 + n * 0.4)
                xx += (cx - x) * pull * 0.15
                zz += (cz - z) * pull * 0.15
            ids[(ix, iz)] = mesh.add((xx, yy, zz), (0.0, 1.0, 0.0), (xx / 3.2, zz / 3.2))
    for iz in range(len(zs) - 1):
        for ix in range(len(xs) - 1):
            a, b = ids[(ix, iz)], ids[(ix + 1, iz)]
            c, d = ids[(ix, iz + 1)], ids[(ix + 1, iz + 1)]
            if None in (a, b, c, d):
                continue
            mesh.tri(a, c, b)
            mesh.tri(b, c, d)
    # Thick earthen edge, the strata in the painting.
    def drop(p, dy):
        return mesh.add((p[0], p[1] - dy, p[2]), p, (p[0] / 3.2, p[1] / 3.2))

    for iz in range(len(zs) - 1):
        for ix, side in ((0, -1), (len(xs) - 1, 1)):
            a, c = ids[(ix, iz)], ids[(ix, iz + 1)]
            if a is None or c is None:
                continue
            pa, pc = mesh.pos[a], mesh.pos[c]
            ba, bc = drop(pa, skirt), drop(pc, skirt)
            if side < 0:
                mesh.tri(a, ba, c)
                mesh.tri(c, ba, bc)
            else:
                mesh.tri(a, c, ba)
                mesh.tri(c, bc, ba)
    for ix in range(len(xs) - 1):
        for iz, side in ((0, -1), (len(zs) - 1, 1)):
            a, b = ids[(ix, iz)], ids[(ix + 1, iz)]
            if a is None or b is None:
                continue
            pa, pb = mesh.pos[a], mesh.pos[b]
            ba, bb = drop(pa, skirt), drop(pb, skirt)
            if side < 0:
                mesh.tri(a, b, ba)
                mesh.tri(b, bb, ba)
            else:
                mesh.tri(a, ba, b)
                mesh.tri(b, ba, bb)


def build_sump() -> Mesh:
    mesh = Mesh()
    add_shelf(mesh, -28, -14, 28, 30, 0.04, step=2.2, skirt=1.2, hole=0.0)
    mesh.smooth()
    return mesh


def build_floors() -> Mesh:
    mesh = Mesh()
    # Canopy front deck, after the ramp pulls the west face back to x=-2.8.
    add_shelf(mesh, -5.2, 3.0, 16.0, 19.0, 12.02, skirt=2.3, hole=4.6)
    add_shelf(mesh, -24.0, -6.0, -14.0, 10.0, 12.02, skirt=2.0)
    add_shelf(mesh, -17.0, -7.0, -5.0, -1.0, 12.02, skirt=1.6, hole=4.6)
    add_shelf(mesh, 26.0, 3.0, 34.0, 13.0, 12.02, skirt=2.0)
    # Crown arena, west, after the landing pull (z max -5.2) plus a lip to the ramp.
    add_shelf(mesh, -25.0, -17.0, -7.0, -6.6, 24.02, skirt=2.4, hole=4.8)
    add_shelf(mesh, 8.0, -14.0, 24.0, 6.0, 24.02, skirt=2.2)
    add_shelf(mesh, -9.0, -15.0, 5.0, -9.0, 24.02, skirt=1.8, hole=4.8)
    add_shelf(mesh, -35.0, -14.0, -25.0, -2.0, 24.02, skirt=2.0)
    mesh.smooth()
    return mesh


def build_ramps() -> Mesh:
    mesh = Mesh()
    spans = [
        ((-20.0, 0.15, 24.0), (-4.0, 12.1, 8.0)),
        ((2.0, 12.15, 8.0), (18.0, 24.1, -10.0)),
    ]
    for a, b in spans:
        d = vsub(b, a)
        run = math.sqrt(d[0] * d[0] + d[2] * d[2]) or 1.0
        along = (d[0] / run, 0.0, d[2] / run)
        side = (-along[2], 0.0, along[0])
        steps = 16
        for i in range(steps):
            t0 = i / steps
            t1 = (i + 1) / steps
            def at(t, side_m, y_lift):
                return (
                    a[0] + d[0] * t + side[0] * side_m,
                    a[1] + d[1] * t + y_lift + math.sin(t * 18.0) * 0.05,
                    a[2] + d[2] * t + side[2] * side_m,
                )
            w = 3.4
            p00, p10 = at(t0, -w, 0.0), at(t0, w, 0.0)
            p01, p11 = at(t1, -w, 0.0), at(t1, w, 0.0)
            uv0 = t0 * run / 3.0
            i00 = mesh.add(p00, (0, 1, 0), (0.0, uv0))
            i10 = mesh.add(p10, (0, 1, 0), (2.0, uv0))
            i01 = mesh.add(p01, (0, 1, 0), (0.0, t1 * run / 3.0))
            i11 = mesh.add(p11, (0, 1, 0), (2.0, t1 * run / 3.0))
            mesh.tri(i00, i01, i10)
            mesh.tri(i10, i01, i11)
            # A second thinner root beside the walk, so the span reads as roots.
            q00 = mesh.add(at(t0, -w - 1.3, -0.35), (0, 1, 0), (0, uv0))
            q10 = mesh.add(at(t0, -w - 0.2, -0.15), (0, 1, 0), (0.6, uv0))
            q01 = mesh.add(at(t1, -w - 1.3, -0.35), (0, 1, 0), (0, t1 * run / 3.0))
            q11 = mesh.add(at(t1, -w - 0.2, -0.15), (0, 1, 0), (0.6, t1 * run / 3.0))
            mesh.tri(q00, q01, q10)
            mesh.tri(q10, q01, q11)
    mesh.smooth()
    return mesh


def build_pools() -> Mesh:
    mesh = Mesh()
    lobes = [(-16.0, 5.0, 9.5, 6.6), (15.5, 3.5, 9.2, 6.4)]
    for cx, cz, rx, rz in lobes:
        grid = []
        for iv in range(9):
            row = []
            for iu in range(16):
                th = math.tau * iu / 16
                rad = iv / 8
                x = cx + math.cos(th) * rx * rad
                z = cz + math.sin(th) * rz * rad
                y = 0.38 + (noise(x, 2.0, z) - 0.5) * 0.08
                row.append(mesh.add((x, y, z), (0, 1, 0), (iu / 16, rad)))
            grid.append(row)
        for iv in range(8):
            for iu in range(16):
                s2 = (iu + 1) % 16
                mesh.tri(grid[iv][iu], grid[iv][s2], grid[iv + 1][iu])
                mesh.tri(grid[iv][s2], grid[iv + 1][s2], grid[iv + 1][iu])
    return mesh


def build_mushrooms() -> Mesh:
    mesh = Mesh()

    def one(pos, height, cap_r, tilt):
        stem_h = height * 0.62
        sides = 10
        rings = []
        for i in range(6):
            t = i / 5
            y = pos[1] + stem_h * t
            r = cap_r * (0.22 + 0.08 * math.sin(t * math.pi))
            x = pos[0] + tilt[0] * t
            z = pos[2] + tilt[1] * t
            ring = []
            for s in range(sides):
                a = math.tau * s / sides
                n = (math.cos(a), 0.15, math.sin(a))
                ring.append(mesh.add((x + math.cos(a) * r, y, z + math.sin(a) * r), vnorm(n), (s / sides, t)))
            rings.append(ring)
        for i in range(5):
            for s in range(sides):
                s2 = (s + 1) % sides
                mesh.tri(rings[i][s], rings[i][s2], rings[i + 1][s])
                mesh.tri(rings[i][s2], rings[i + 1][s2], rings[i + 1][s])
        cx, cy, cz = pos[0] + tilt[0], pos[1] + stem_h, pos[2] + tilt[1]
        cap = []
        for iv in range(6):
            phi = (iv / 5) * math.pi * 0.55
            row = []
            for iu in range(14):
                th = math.tau * iu / 14
                rr = cap_r * math.sin(phi) * (1.0 + 0.06 * math.sin(th * 3))
                y = cy + math.cos(phi) * cap_r * 0.42
                row.append(
                    mesh.add(
                        (cx + math.cos(th) * rr, y, cz + math.sin(th) * rr),
                        vnorm((math.cos(th) * math.sin(phi), 0.7, math.sin(th) * math.sin(phi))),
                        (0.5 + math.cos(th) * rr / 4, 0.5 + math.sin(th) * rr / 4),
                    )
                )
            cap.append(row)
        for iv in range(5):
            for iu in range(14):
                s2 = (iu + 1) % 14
                mesh.tri(cap[iv][iu], cap[iv][s2], cap[iv + 1][iu])
                mesh.tri(cap[iv][s2], cap[iv + 1][s2], cap[iv + 1][iu])

    spots = [
        ((-20.0, 24.0, -10.0), 3.4, 2.1, (0.3, 0.1)),
        ((-14.0, 24.0, -14.0), 2.6, 1.6, (-0.2, 0.2)),
        ((-22.5, 24.0, -6.0), 2.2, 1.35, (0.15, -0.1)),
        ((-30.0, 24.0, -8.0), 2.8, 1.7, (-0.2, 0.05)),
        ((14.0, 24.0, -2.0), 3.2, 2.0, (0.2, 0.15)),
        ((19.0, 24.0, -8.0), 2.5, 1.55, (-0.15, 0.1)),
        ((12.0, 24.0, 2.0), 1.8, 1.15, (0.1, -0.2)),
        ((20.0, 12.0, 10.0), 2.4, 1.45, (0.2, 0.0)),
        ((-19.0, 12.0, 2.0), 2.1, 1.3, (-0.1, 0.15)),
        ((-22.0, 0.05, 18.0), 1.6, 0.95, (0.05, 0.1)),
        ((20.0, 0.05, 20.0), 1.7, 1.0, (-0.1, 0.05)),
        ((-8.0, 0.05, 16.0), 1.3, 0.8, (0.1, 0.0)),
    ]
    for pos, h, r, tilt in spots:
        one(pos, h, r, tilt)
    mesh.smooth()
    return mesh


def build_crystals() -> Mesh:
    mesh = Mesh()

    def cluster(origin, scale, yaw):
        for k, (ox, oy, oz, h, lean) in enumerate(
            (
                (0.0, 0.0, 0.0, 2.4, 0.15),
                (0.45, 0.0, 0.25, 1.6, -0.2),
                (-0.35, 0.0, 0.3, 1.3, 0.25),
                (0.15, 0.0, -0.4, 1.1, 0.05),
            )
        ):
            cy = origin[1]
            cx = origin[0] + ox * scale
            cz = origin[2] + oz * scale
            hh = h * scale
            rad = 0.22 * scale * (1.1 - k * 0.12)
            sides = 6
            bot, top = [], []
            for s in range(sides):
                a = math.tau * s / sides + yaw
                n = (math.cos(a), 0.2, math.sin(a))
                bot.append(mesh.add((cx + math.cos(a) * rad, cy, cz + math.sin(a) * rad), vnorm(n), (s / sides, 0)))
                top.append(
                    mesh.add(
                        (
                            cx + math.cos(a) * rad * 0.35 + lean,
                            cy + hh,
                            cz + math.sin(a) * rad * 0.35,
                        ),
                        vnorm((math.cos(a), 1.2, math.sin(a))),
                        (s / sides, 1),
                    )
                )
            apex = mesh.add((cx + lean * 0.4, cy + hh + 0.35 * scale, cz), (0, 1, 0), (0.5, 1))
            for s in range(sides):
                s2 = (s + 1) % sides
                mesh.tri(bot[s], bot[s2], top[s])
                mesh.tri(bot[s2], top[s2], top[s])
                mesh.tri(top[s], top[s2], apex)

    for origin, scale, yaw in (
        ((-30.5, 24.0, -8.0), 1.4, 0.4),
        ((21.5, 24.0, 3.0), 1.6, 1.1),
        ((-20.0, 0.1, 22.0), 1.15, 0.2),
        ((22.0, 0.1, 16.0), 1.25, 2.0),
        ((-12.0, 24.0, -16.0), 1.1, 0.8),
        ((8.0, 12.0, 16.0), 0.9, 1.4),
        ((0.0, 28.5, 1.5), 1.3, 0.6),
    ):
        cluster(origin, scale, yaw)
    return mesh


def build_shrine() -> Mesh:
    mesh = Mesh()

    def box(c, sz):
        hx, hy, hz = sz[0] * 0.5, sz[1] * 0.5, sz[2] * 0.5
        x, y, z = c
        corners = []
        for dz in (-1, 1):
            for dy in (-1, 1):
                for dx in (-1, 1):
                    corners.append((x + dx * hx, y + dy * hy, z + dz * hz))
        # 8 corners: dx, dy, dz with dz outer, dy mid, dx inner? 
        # index: ((dz+1)//2)*4 + ((dy+1)//2)*2 + (dx+1)//2 but dx is last in the loop
        # loop order: dz, dy, dx → index = dz_i*4 + dy_i*2 + dx_i
        faces = [
            (0, 1, 2, 3),
            (4, 6, 5, 7),
            (0, 4, 1, 5),
            (2, 3, 6, 7),
            (0, 2, 4, 6),
            (1, 5, 3, 7),
        ]
        norms = [(-1, 0, 0), (1, 0, 0), (0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1)]
        # The loop stores dx fastest, so faces above are wrong. Build explicitly.
        _ = faces, norms
        pts = [
            (x - hx, y - hy, z - hz),
            (x + hx, y - hy, z - hz),
            (x + hx, y + hy, z - hz),
            (x - hx, y + hy, z - hz),
            (x - hx, y - hy, z + hz),
            (x + hx, y - hy, z + hz),
            (x + hx, y + hy, z + hz),
            (x - hx, y + hy, z + hz),
        ]
        quads = [
            (0, 1, 2, 3, (0, 0, -1)),
            (5, 4, 7, 6, (0, 0, 1)),
            (4, 0, 3, 7, (-1, 0, 0)),
            (1, 5, 6, 2, (1, 0, 0)),
            (3, 2, 6, 7, (0, 1, 0)),
            (4, 5, 1, 0, (0, -1, 0)),
        ]
        for i0, i1, i2, i3, nrm in quads:
            uv = (0.0, 0.0)
            a = mesh.add(pts[i0], nrm, uv)
            b = mesh.add(pts[i1], nrm, (1, 0))
            c = mesh.add(pts[i2], nrm, (1, 1))
            d = mesh.add(pts[i3], nrm, (0, 1))
            mesh.tri(a, b, c)
            mesh.tri(a, c, d)
        return corners

    # Altar in front of the trunk, mother stands just to the east (+X).
    box((-1.4, 12.45, 8.2), (2.2, 0.9, 1.4))
    box((-2.2, 13.35, 8.0), (0.4, 1.5, 0.4))
    box((-0.6, 13.35, 8.0), (0.4, 1.5, 0.4))
    box((-1.4, 14.2, 8.0), (2.2, 0.34, 0.46))
    # Broken arch curve.
    for i in range(7):
        t = i / 6
        ang = math.pi * (1 - t)
        cx = -1.4 + math.cos(ang) * 0.9
        cy = 14.05 + math.sin(ang) * 0.65
        box((cx, cy, 8.0), (0.3, 0.26, 0.34))
    return mesh


def build_gate() -> Mesh:
    mesh = Mesh()

    def block(c, sz):
        hx, hy, hz = sz[0] * 0.5, sz[1] * 0.5, sz[2] * 0.5
        x, y, z = c
        pts = [
            (x - hx, y - hy, z - hz),
            (x + hx, y - hy, z - hz),
            (x + hx, y + hy, z - hz),
            (x - hx, y + hy, z - hz),
            (x - hx, y - hy, z + hz),
            (x + hx, y - hy, z + hz),
            (x + hx, y + hy, z + hz),
            (x - hx, y + hy, z + hz),
        ]
        quads = [
            (0, 1, 2, 3, (0, 0, -1)),
            (5, 4, 7, 6, (0, 0, 1)),
            (4, 0, 3, 7, (-1, 0, 0)),
            (1, 5, 6, 2, (1, 0, 0)),
            (3, 2, 6, 7, (0, 1, 0)),
            (4, 5, 1, 0, (0, -1, 0)),
        ]
        for i0, i1, i2, i3, nrm in quads:
            ids = [
                mesh.add(pts[i0], nrm, (0, 0)),
                mesh.add(pts[i1], nrm, (1, 0)),
                mesh.add(pts[i2], nrm, (1, 1)),
                mesh.add(pts[i3], nrm, (0, 1)),
            ]
            mesh.tri(ids[0], ids[1], ids[2])
            mesh.tri(ids[0], ids[2], ids[3])

    # Ruined gate at the top of the cutaway, "From the Warrens".
    y = 29.2
    z = 4.5
    block((-4.3, y, z), (1.3, 4.2, 1.1))
    block((4.3, y, z), (1.3, 3.4, 1.1))
    block((0.0, y + 2.3, z), (7.4, 0.8, 1.2))
    block((-2.2, y + 2.9, z), (1.6, 0.7, 1.0))
    block((2.6, y + 1.2, z + 0.4), (0.9, 1.4, 0.8))
    return mesh


def build_moss_cards() -> Mesh:
    mesh = Mesh()
    spots = []
    for i in range(18):
        a = math.tau * i / 18
        if math.sin(a) > 0.55:
            continue  # leave the south window clear
        x = math.cos(a) * 27.5
        z = math.sin(a) * 20.5
        spots.append((x, 3.0, z, a))
        spots.append((x * 0.92, 14.5, z * 0.92, a))
    for x, y, z, a in spots:
        inward = vnorm((-x, 0.2, -z))
        tang = vnorm(vcross((0, 1, 0), inward))
        for du, dv, uu, vv in ((-1, 0, 0, 0), (1, 0, 1, 0), (1, 1, 1, 1), (-1, 1, 0, 1)):
            pass
        p0 = vadd((x, y, z), vmul(tang, -1.6))
        p1 = vadd((x, y, z), vmul(tang, 1.6))
        p2 = vadd(p1, (0, 2.4, 0))
        p3 = vadd(p0, (0, 2.4, 0))
        ids = [
            mesh.add(p0, inward, (0, 0)),
            mesh.add(p1, inward, (1, 0)),
            mesh.add(p2, inward, (1, 1)),
            mesh.add(p3, inward, (0, 1)),
        ]
        mesh.tri(ids[0], ids[1], ids[2])
        mesh.tri(ids[0], ids[2], ids[3])
    return mesh


def jpeg_bytes(path: Path, size: int = 512, quality: int = 78, rough_pack: bool = False) -> bytes:
    im = Image.open(path).convert("RGB")
    im = im.resize((size, size), Image.Resampling.LANCZOS)
    if rough_pack:
        # glTF metallic-roughness: G = roughness, B = metallic.
        g = im.split()[1]
        im = Image.merge("RGB", (Image.new("L", im.size, 0), g, Image.new("L", im.size, 0)))
    buf = __import__("io").BytesIO()
    im.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def mushroom_albedo() -> bytes:
    im = Image.new("RGB", (256, 256))
    px = im.load()
    for y in range(256):
        for x in range(256):
            dx, dy = (x - 128) / 128, (y - 40) / 90
            cap = dx * dx + dy * dy
            n = noise(x * 0.4, y * 0.4, 3.0)
            if y < 150 and cap < 1.15:
                r = int(150 + 50 * n - cap * 30)
                g = int(78 + 40 * n)
                b = int(48 + 20 * n)
                if n > 0.72:
                    r, g, b = 92, 48, 110
            else:
                r = int(92 + 40 * n)
                g = int(70 + 30 * n)
                b = int(48 + 16 * n)
            px[x, y] = (max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    buf = __import__("io").BytesIO()
    im.save(buf, format="JPEG", quality=80)
    return buf.getvalue()


class Writer:
    def __init__(self) -> None:
        self.blob = bytearray()
        self.views = []
        self.accessors = []
        self.materials = []
        self.images = []
        self.textures = []
        self.primitives = []

    def _align(self) -> None:
        while len(self.blob) % 4:
            self.blob.append(0)

    def view(self, data: bytes, target: int | None = None) -> int:
        self._align()
        off = len(self.blob)
        self.blob.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        self.views.append(v)
        return len(self.views) - 1

    def image(self, data: bytes) -> int:
        idx = self.view(data)
        self.images.append({"bufferView": idx, "mimeType": "image/jpeg"})
        self.textures.append({"sampler": 0, "source": len(self.images) - 1})
        return len(self.textures) - 1

    def material(self, name, color, normal, rough, factor, emissive=None, alpha=None, double=True) -> int:
        pbr = {
            "baseColorTexture": {"index": color},
            "metallicFactor": 0.0,
            "roughnessFactor": 1.0,
        }
        if factor is not None:
            pbr["baseColorFactor"] = factor
        if rough is not None:
            pbr["metallicRoughnessTexture"] = {"index": rough}
        m = {"name": name, "pbrMetallicRoughness": pbr, "doubleSided": double}
        if normal is not None:
            m["normalTexture"] = {"index": normal}
        if emissive is not None:
            m["emissiveFactor"] = emissive
        if alpha:
            m["alphaMode"] = alpha
        self.materials.append(m)
        return len(self.materials) - 1

    def flat_material(self, name, factor, emissive, rough, alpha=None) -> int:
        m = {
            "name": name,
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": factor,
                "metallicFactor": 0.05,
                "roughnessFactor": rough,
            },
            "emissiveFactor": emissive,
        }
        if alpha:
            m["alphaMode"] = alpha
        self.materials.append(m)
        return len(self.materials) - 1

    def add_mesh(self, mesh: Mesh, material: int) -> None:
        if not mesh.idx:
            return
        pos = b"".join(struct.pack("<3f", *p) for p in mesh.pos)
        nrm = b"".join(struct.pack("<3f", *n) for n in mesh.nrm)
        uv = b"".join(struct.pack("<2f", *t) for t in mesh.uv)
        idx = struct.pack("<%dI" % len(mesh.idx), *mesh.idx)
        xs = [p[0] for p in mesh.pos]
        ys = [p[1] for p in mesh.pos]
        zs = [p[2] for p in mesh.pos]
        pv = self.view(pos, 34962)
        nv = self.view(nrm, 34962)
        tv = self.view(uv, 34962)
        iv = self.view(idx, 34963)
        pa = len(self.accessors)
        self.accessors.append(
            {
                "bufferView": pv,
                "componentType": 5126,
                "count": len(mesh.pos),
                "type": "VEC3",
                "min": [min(xs), min(ys), min(zs)],
                "max": [max(xs), max(ys), max(zs)],
            }
        )
        self.accessors.append({"bufferView": nv, "componentType": 5126, "count": len(mesh.pos), "type": "VEC3"})
        self.accessors.append({"bufferView": tv, "componentType": 5126, "count": len(mesh.pos), "type": "VEC2"})
        self.accessors.append(
            {"bufferView": iv, "componentType": 5125, "count": len(mesh.idx), "type": "SCALAR"}
        )
        self.primitives.append(
            {
                "attributes": {"POSITION": pa, "NORMAL": pa + 1, "TEXCOORD_0": pa + 2},
                "indices": pa + 3,
                "material": material,
            }
        )


def main() -> None:
    w = Writer()
    rock_c = w.image(jpeg_bytes(TEX["rock_c"]))
    rock_n = w.image(jpeg_bytes(TEX["rock_n"]))
    rock_r = w.image(jpeg_bytes(TEX["rock_r"], rough_pack=True))
    bark_c = w.image(jpeg_bytes(TEX["bark_c"]))
    bark_n = w.image(jpeg_bytes(TEX["bark_n"]))
    bark_r = w.image(jpeg_bytes(TEX["bark_r"], rough_pack=True))
    floor_c = w.image(jpeg_bytes(TEX["floor_c"]))
    floor_n = w.image(jpeg_bytes(TEX["floor_n"]))
    floor_r = w.image(jpeg_bytes(TEX["floor_r"], rough_pack=True))
    moss_c = w.image(jpeg_bytes(TEX["moss_c"]))
    moss_n = w.image(jpeg_bytes(TEX["moss_n"]))
    moss_r = w.image(jpeg_bytes(TEX["moss_r"], rough_pack=True))
    mush_c = w.image(mushroom_albedo())

    mat_rock = w.material("rock", rock_c, rock_n, rock_r, [0.62, 0.55, 0.46, 1])
    mat_bark = w.material("bark", bark_c, bark_n, bark_r, [0.78, 0.62, 0.42, 1])
    mat_floor = w.material("floor", floor_c, floor_n, floor_r, [0.5, 0.58, 0.34, 1])
    mat_sump = w.material("sump", floor_c, floor_n, floor_r, [0.28, 0.32, 0.18, 1])
    mat_moss = w.material("moss", moss_c, moss_n, moss_r, [0.45, 0.62, 0.32, 1])
    mat_mush = w.material("mushroom", mush_c, bark_n, bark_r, [1, 1, 1, 1])
    mat_heart = w.flat_material("heart", [1.0, 0.42, 0.12, 1], [2.2, 0.55, 0.08], 0.32)
    mat_crystal = w.flat_material("crystal", [0.42, 0.18, 0.9, 1], [0.85, 0.28, 1.5], 0.16)
    mat_pool = w.flat_material("pool", [0.62, 0.78, 0.18, 0.94], [0.45, 0.7, 0.05], 0.22, "BLEND")

    shell = build_shell()
    interior = [
        (build_tree(), mat_bark),
        (build_heart(), mat_heart),
        (build_sump(), mat_sump),
        (build_floors(), mat_floor),
        (build_ramps(), mat_bark),
        (build_pools(), mat_pool),
        (build_mushrooms(), mat_mush),
        (build_crystals(), mat_crystal),
        (build_shrine(), mat_rock),
        (build_gate(), mat_rock),
        (build_moss_cards(), mat_moss),
    ]
    parts = [(shell, mat_rock)] + interior
    for mesh, mat in parts:
        print(f"  {w.materials[mat]['name']:10} verts={len(mesh.pos):6} tris={len(mesh.idx)//3:6}")
        w.add_mesh(mesh, mat)

    gltf = {
        "asset": {"version": "2.0", "generator": "build_blightcoil_look.py"},
        "scene": 0,
        "scenes": [{"nodes": [0, 1]}],
        "nodes": [{"name": "Shell", "mesh": 0}, {"name": "Interior", "mesh": 1}],
        "meshes": [
            {"name": "Shell", "primitives": w.primitives[:1]},
            {"name": "Interior", "primitives": w.primitives[1:]},
        ],
        "materials": w.materials,
        "accessors": w.accessors,
        "bufferViews": w.views,
        "buffers": [{"byteLength": len(w.blob)}],
        "images": w.images,
        "textures": w.textures,
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    blob = bytes(w.blob)
    while len(blob) % 4:
        blob += b"\x00"
    total = 12 + 8 + len(js) + 8 + len(blob)
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON")
    out += js
    out += struct.pack("<I4s", len(blob), b"BIN\x00")
    out += blob
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(out)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(out)/1e6:.2f} MB)")


if __name__ == "__main__":
    main()
