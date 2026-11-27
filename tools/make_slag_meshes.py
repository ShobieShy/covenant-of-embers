#!/usr/bin/env python3
"""Original Slagworks meshes (metres). Materials are applied in Godot from CC0
ambientCG textures. Geometry is authored for this project, CC0.

    python3 tools/make_slag_meshes.py
"""
from __future__ import annotations

import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "assets" / "original" / "slagworks"


class Mesh:
    def __init__(self) -> None:
        self.pos: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, int, int]] = []

    def v(self, x: float, y: float, z: float) -> int:
        self.pos.append((x, y, z))
        return len(self.pos) - 1

    def tri(self, a: int, b: int, c: int) -> None:
        self.faces.append((a, b, c))

    def quad(self, a: int, b: int, c: int, d: int) -> None:
        self.tri(a, b, c)
        self.tri(a, c, d)

    def box(self, c: tuple[float, float, float], s: tuple[float, float, float]) -> None:
        hx, hy, hz = s[0] * 0.5, s[1] * 0.5, s[2] * 0.5
        cx, cy, cz = c
        p = []
        for z in (-hz, hz):
            for y in (-hy, hy):
                for x in (-hx, hx):
                    p.append(self.v(cx + x, cy + y, cz + z))
        # 0-1-3-2 front? indices: x changes fastest
        # 0 (- - -), 1 (+ - -), 2 (- + -), 3 (+ + -), 4 (- - +), 5 (+ - +), 6 (- + +), 7 (+ + +)
        self.quad(p[0], p[2], p[3], p[1])  # -Z
        self.quad(p[4], p[5], p[7], p[6])  # +Z
        self.quad(p[0], p[1], p[5], p[4])  # -Y
        self.quad(p[2], p[6], p[7], p[3])  # +Y
        self.quad(p[0], p[4], p[6], p[2])  # -X
        self.quad(p[1], p[3], p[7], p[5])  # +X

    def frustum(
        self, y0: float, r0: float, y1: float, r1: float, sides: int, z_bias: float = 0.0
    ) -> None:
        a = [self.v(math.cos(t) * r0, y0, math.sin(t) * r0 + z_bias) for t in _angs(sides)]
        b = [self.v(math.cos(t) * r1, y1, math.sin(t) * r1 + z_bias) for t in _angs(sides)]
        for i in range(sides):
            j = (i + 1) % sides
            self.quad(a[i], a[j], b[j], b[i])
        cap0 = self.v(0, y0, z_bias)
        cap1 = self.v(0, y1, z_bias)
        for i in range(sides):
            j = (i + 1) % sides
            self.tri(cap0, a[j], a[i])
            self.tri(cap1, b[i], b[j])


def _angs(n: int):
    return [math.tau * i / n for i in range(n)]


def _n(a: float, b: float) -> float:
    return math.sin(a * 3.7 + b * 1.3) * 0.55 + math.sin(a * 8.1 - b * 4.4) * 0.3


def cliff() -> Mesh:
    """4 m wide, 6 m tall, jagged basalt panel. Origin at the base centre."""
    m = Mesh()
    w, h, cols, rows = 4.0, 6.0, 10, 14
    grid = []
    for r in range(rows + 1):
        row = []
        v = r / rows
        for c in range(cols + 1):
            u = c / cols
            x = (u - 0.5) * w
            y = v * h
            bulge = (1.0 - abs(u - 0.5) * 1.4) * (0.55 + 0.45 * math.sin(v * math.pi))
            z = 0.35 + bulge * 0.9 + _n(u * 4.0, v * 5.0) * 0.38
            z += 0.22 * math.sin(v * 18.0 + u * 6.0) * (0.3 + v)
            row.append(m.v(x, y, z))
        grid.append(row)
    for r in range(rows):
        for c in range(cols):
            m.quad(grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
    # back slab so the panel is not a single sheet
    m.box((0, h * 0.5, -0.25), (w * 0.92, h * 0.96, 0.4))
    return m


def stone() -> Mesh:
    """4 m stone slab, origin at centre, top at y = 0.18."""
    m = Mesh()
    n = 8
    span = 4.0
    grid = []
    for r in range(n + 1):
        row = []
        for c in range(n + 1):
            u, v = c / n, r / n
            x = (u - 0.5) * span
            z = (v - 0.5) * span
            edge = min(u, v, 1 - u, 1 - v)
            y = 0.12 + _n(u * 6, v * 6) * 0.045
            if edge < 0.12:
                y -= (0.12 - edge) * 1.1
            row.append(m.v(x, y, z))
        grid.append(row)
    for r in range(n):
        for c in range(n):
            m.quad(grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
    m.box((0, -0.08, 0), (3.7, 0.16, 3.7))
    return m


def gantry() -> Mesh:
    """Iron grate, 4 m along X, 3 m along Z, deck top near y = 0.2. Origin centre."""
    m = Mesh()
    m.box((-1.85, 0.0, 0), (0.18, 0.22, 3.0))
    m.box((1.85, 0.0, 0), (0.18, 0.22, 3.0))
    m.box((0, 0.0, -1.4), (3.7, 0.16, 0.16))
    m.box((0, 0.0, 1.4), (3.7, 0.16, 0.16))
    for i in range(7):
        z = -1.15 + i * 0.38
        m.box((0, 0.08, z), (3.5, 0.06, 0.08))
    for i in range(5):
        x = -1.4 + i * 0.7
        m.box((x, -0.28, 0), (0.1, 0.4, 2.7))
    return m


def rail() -> Mesh:
    """4 m of track along X. Ties sit on y = 0, rails above."""
    m = Mesh()
    for i in range(5):
        x = -1.6 + i * 0.8
        m.box((x, 0.05, 0), (0.28, 0.08, 1.15))
    for z in (-0.42, 0.42):
        m.box((0, 0.16, z), (4.0, 0.06, 0.08))
        m.box((0, 0.22, z), (4.0, 0.05, 0.14))
    return m


def lava() -> Mesh:
    """4 m lava sheet, origin centre, surface around y = 0."""
    m = Mesh()
    n = 16
    grid = []
    for r in range(n + 1):
        row = []
        for c in range(n + 1):
            u, v = c / n, r / n
            x = (u - 0.5) * 4.0
            z = (v - 0.5) * 4.0
            y = 0.08 * math.sin(u * 9.0 + v * 3.0) + 0.05 * math.cos(v * 11.0)
            row.append(m.v(x, y, z))
        grid.append(row)
    for r in range(n):
        for c in range(n):
            m.quad(grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c])
    return m


def furnace() -> Mesh:
    """Conical furnace-anvil. Mouth opens toward -Z. About 7.2 m tall."""
    m = Mesh()
    m.frustum(0.0, 3.15, 5.6, 1.85, 18)
    m.frustum(5.6, 2.15, 6.5, 2.05, 16)
    # hearth block and molten mouth on -Z
    m.box((0.0, 1.55, -2.35), (2.4, 1.7, 1.5))
    m.box((0.0, 1.55, -3.05), (1.7, 1.15, 0.35))
    # anvil horn
    m.box((0.0, 0.7, -1.5), (2.8, 0.55, 1.1))
    m.box((0.9, 0.85, -2.3), (0.7, 0.35, 0.9))
    # stacks
    m.frustum(6.4, 0.42, 8.6, 0.32, 10, z_bias=0.55)
    # second stack offset by building it then... frustum is centred. Use a cylinder via frustum at an offset by translating verts is messy.
    # Add a second stack as a thin box cluster.
    m.box((-0.85, 7.5, -0.15), (0.7, 2.2, 0.7))
    m.box((-0.85, 8.7, -0.15), (0.9, 0.28, 0.9))
    m.box((0.7, 8.7, 0.55), (0.85, 0.25, 0.85))
    # drip lip
    m.box((0.0, 0.85, -3.2), (0.7, 1.3, 0.28))
    return m


def arch() -> Mesh:
    """Stone mine arch, opening toward -Z, about 4.2 m wide and 5.2 m tall."""
    m = Mesh()
    m.box((-1.85, 2.2, 0), (0.7, 4.4, 1.3))
    m.box((1.85, 2.2, 0), (0.7, 4.4, 1.3))
    m.box((0, 4.7, 0), (4.4, 0.7, 1.4))
    # stepped arch stones
    for i in range(5):
        t = (i + 0.5) / 5.0
        ang = math.pi * (1.0 - t)
        x = math.cos(ang) * 1.55
        y = 3.3 + math.sin(ang) * 1.15
        m.box((x, y, 0.15), (0.55, 0.42, 1.15))
    m.box((0, 0.18, 0.9), (3.2, 0.28, 0.8))
    return m


def door_leaf() -> Mesh:
    m = Mesh()
    m.box((0, 1.7, 0), (2.1, 3.3, 0.16))
    m.box((-0.55, 1.7, 0.1), (0.12, 3.0, 0.08))
    m.box((0.55, 1.7, 0.1), (0.12, 3.0, 0.08))
    m.box((0, 2.4, 0.12), (0.22, 0.22, 0.1))
    return m


def lift() -> Mesh:
    """Stone-and-iron lift tower, 9 m tall."""
    m = Mesh()
    for x in (-1.5, 1.5):
        for z in (-1.5, 1.5):
            m.box((x, 4.2, z), (0.55, 8.4, 0.55))
    m.box((0, 8.3, 0), (3.6, 0.4, 3.6))
    m.box((0, 1.1, 0), (2.4, 0.22, 2.4))
    m.box((0, 4.4, 0), (0.16, 6.4, 0.16))
    for i in range(8):
        y = 2.0 + i * 0.7
        m.box((0.55, y, 0), (0.35, 0.08, 0.08))
        m.box((-0.55, y + 0.3, 0), (0.35, 0.08, 0.08))
    m.box((0, 0.3, 1.7), (2.2, 0.5, 0.4))
    return m


def slag_cast() -> Mesh:
    """Cooling slag disc with an empty humanoid depression. Radius 7 m."""
    m = Mesh()
    rings, segs = 18, 40
    grid = []
    for r in range(rings + 1):
        row = []
        rad = 7.0 * r / rings
        for s in range(segs):
            ang = math.tau * s / segs
            x = math.cos(ang) * rad
            z = math.sin(ang) * rad
            hollow = _figure(x, z)
            rim = max(0.0, (rad - 5.6) / 1.4)
            y = 0.08 + rim * 0.55 + _n(x, z) * 0.04 - hollow * 0.62
            row.append(m.v(x, y, z))
        grid.append(row)
    for r in range(rings):
        for s in range(segs):
            j = (s + 1) % segs
            m.quad(grid[r][s], grid[r][j], grid[r + 1][j], grid[r + 1][s])
    return m


def _figure(x: float, z: float) -> float:
    """1 inside the humanoid mould, 0 outside. z+ is the feet."""
    def ball(cx, cz, rx, rz) -> float:
        dx = (x - cx) / rx
        dz = (z - cz) / rz
        d = dx * dx + dz * dz
        if d >= 1.0:
            return 0.0
        return 1.0 - d

    def cap(x0, z0, x1, z1, r) -> float:
        vx, vz = x1 - x0, z1 - z0
        l2 = vx * vx + vz * vz
        t = 0.0 if l2 < 1e-6 else max(0.0, min(1.0, ((x - x0) * vx + (z - z0) * vz) / l2))
        d = math.hypot(x - (x0 + vx * t), z - (z0 + vz * t))
        if d >= r:
            return 0.0
        return 1.0 - d / r

    head = ball(0.0, -1.7, 0.55, 0.62)
    torso = ball(0.0, -0.35, 0.78, 1.15)
    arm_l = cap(-0.45, -0.7, -1.7, -0.15, 0.26)
    arm_r = cap(0.45, -0.7, 1.7, -0.15, 0.26)
    leg_l = cap(-0.28, 0.55, -0.42, 1.9, 0.28)
    leg_r = cap(0.28, 0.55, 0.42, 1.9, 0.28)
    return max(head, torso, arm_l, arm_r, leg_l, leg_r)


def ore() -> Mesh:
    m = Mesh()
    seeds = [(0, 0, 0, 0.7), (0.45, 0.1, 0.2, 0.45), (-0.4, 0.05, 0.15, 0.4), (0.1, 0.15, -0.35, 0.5), (-0.15, 0.0, 0.4, 0.35)]
    for sx, sy, sz, sc in seeds:
        sides = 7
        tip = m.v(sx, sy + 1.1 * sc, sz)
        ring = []
        for i, ang in enumerate(_angs(sides)):
            ring.append(m.v(sx + math.cos(ang) * 0.28 * sc, sy + 0.15 * sc, sz + math.sin(ang) * 0.28 * sc))
        base = m.v(sx, sy, sz)
        for i in range(sides):
            j = (i + 1) % sides
            m.tri(ring[i], tip, ring[j])
            m.tri(base, ring[j], ring[i])
    return m


def cart() -> Mesh:
    m = Mesh()
    m.box((0, 0.55, 0), (1.35, 0.55, 0.85))
    m.box((0, 0.85, -0.38), (1.25, 0.28, 0.08))
    m.box((0, 0.85, 0.38), (1.25, 0.28, 0.08))
    m.box((-0.62, 0.7, 0), (0.08, 0.4, 0.75))
    m.box((0.62, 0.7, 0), (0.08, 0.4, 0.75))
    for x in (-0.45, 0.45):
        for z in (-0.32, 0.32):
            _wheel(m, (x, 0.22, z), 0.22)
    return m


def _wheel(m: Mesh, c: tuple[float, float, float], r: float) -> None:
    sides = 10
    y = c[1]
    a = [m.v(c[0] + math.cos(t) * r, y + math.sin(t) * r, c[2] - 0.06) for t in _angs(sides)]
    b = [m.v(c[0] + math.cos(t) * r, y + math.sin(t) * r, c[2] + 0.06) for t in _angs(sides)]
    ca = m.v(c[0], y, c[2] - 0.06)
    cb = m.v(c[0], y, c[2] + 0.06)
    for i in range(sides):
        j = (i + 1) % sides
        m.quad(a[i], a[j], b[j], b[i])
        m.tri(ca, a[j], a[i])
        m.tri(cb, b[i], b[j])


def boulder() -> Mesh:
    m = Mesh()
    rings, segs = 10, 14
    grid = []
    for r in range(rings + 1):
        row = []
        phi = math.pi * r / rings
        for s in range(segs):
            theta = math.tau * s / segs
            n = 1.0 + 0.22 * _n(theta * 2, phi * 2)
            rr = 1.0 * n
            x = rr * math.sin(phi) * math.cos(theta)
            y = rr * math.cos(phi) * 0.72 + 0.55
            z = rr * math.sin(phi) * math.sin(theta) * 0.85
            row.append(m.v(x, max(y, 0.02), z))
        grid.append(row)
    for r in range(rings):
        for s in range(segs):
            j = (s + 1) % segs
            m.quad(grid[r][s], grid[r][j], grid[r + 1][j], grid[r + 1][s])
    return m


def chain() -> Mesh:
    m = Mesh()
    for i in range(6):
        y = -i * 0.34
        _link(m, y, i % 2 == 0)
    return m


def _link(m: Mesh, y: float, turned: float) -> None:
    sides = 8
    ring = 10
    r_tube = 0.035
    r_ring = 0.12
    for i in range(ring):
        ang = math.tau * i / ring
        cx = math.cos(ang) * r_ring
        cy = y + math.sin(ang) * r_ring
        cz = 0.0
        if turned:
            cx, cz = 0.0, cx
        nxt = []
        for k in range(sides):
            b = math.tau * k / sides
            ox = math.cos(b) * r_tube
            oy = math.sin(b) * r_tube * 0.35
            # push outward
            px = cx + math.cos(ang) * ox
            py = cy + oy
            pz = cz + (math.sin(ang) * ox if not turned else math.cos(ang) * ox)
            nxt.append(m.v(px, py, pz))
        if i == 0:
            prev = nxt
            first = nxt
            continue
        for k in range(sides):
            j = (k + 1) % sides
            m.quad(prev[k], prev[j], nxt[j], nxt[k])
        prev = nxt
    for k in range(sides):
        j = (k + 1) % sides
        m.quad(prev[k], prev[j], first[j], first[k])


def pillar() -> Mesh:
    m = Mesh()
    m.frustum(0.0, 0.48, 0.25, 0.55, 10)
    m.frustum(0.25, 0.38, 3.0, 0.34, 10)
    m.frustum(3.0, 0.5, 3.35, 0.55, 10)
    return m


def _normals(m: Mesh) -> list[tuple[float, float, float]]:
    acc = [[0.0, 0.0, 0.0] for _ in m.pos]
    for a, b, c in m.faces:
        ax, ay, az = m.pos[a]
        bx, by, bz = m.pos[b]
        cx, cy, cz = m.pos[c]
        nx = (by - ay) * (cz - az) - (bz - az) * (cy - ay)
        ny = (bz - az) * (cx - ax) - (bx - ax) * (cz - az)
        nz = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        for i in (a, b, c):
            acc[i][0] += nx
            acc[i][1] += ny
            acc[i][2] += nz
    out = []
    for x, y, z in acc:
        l = math.sqrt(x * x + y * y + z * z) or 1.0
        out.append((x / l, y / l, z / l))
    return out


def _uv(m: Mesh) -> list[tuple[float, float]]:
    uvs = []
    for x, y, z in m.pos:
        uvs.append((x * 0.35 + z * 0.15, y * 0.35 + z * 0.1))
    return uvs


def write_glb(path: Path, m: Mesh) -> None:
    normals = _normals(m)
    uvs = _uv(m)
    pos_b = b"".join(struct.pack("<3f", *p) for p in m.pos)
    nrm_b = b"".join(struct.pack("<3f", *p) for p in normals)
    uv_b = b"".join(struct.pack("<2f", *p) for p in uvs)
    idx_b = b"".join(struct.pack("<I", i) for face in m.faces for i in face)
    blobs = [pos_b, nrm_b, uv_b, idx_b]
    # 4-byte align each view
    bin_parts = []
    views = []
    offset = 0
    for blob in blobs:
        pad = (4 - (len(blob) % 4)) % 4
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob)})
        bin_parts.append(blob + b"\x00" * pad)
        offset += len(blob) + pad
    binary = b"".join(bin_parts)
    vc = len(m.pos)

    def acc(buf, comp, ctype, count, mins=None, maxs=None):
        d = {"bufferView": buf, "componentType": ctype, "count": count, "type": comp}
        if mins is not None:
            d["min"] = mins
            d["max"] = maxs
        return d

    xs = [p[0] for p in m.pos]
    ys = [p[1] for p in m.pos]
    zs = [p[2] for p in m.pos]
    gltf = {
        "asset": {"version": "2.0", "generator": "make_slag_meshes.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": path.stem}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": views,
        "accessors": [
            acc(0, "VEC3", 5126, vc, [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]),
            acc(1, "VEC3", 5126, vc),
            acc(2, "VEC2", 5126, vc),
            acc(3, "SCALAR", 5125, len(m.faces) * 3),
        ],
    }
    import json

    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((4 - (len(js) % 4)) % 4)
    out = b"glTF" + struct.pack("<III", 2, 12 + 8 + len(js) + 8 + len(binary), len(js))
    # header is 12, then chunk0 header 8 + js, chunk1 header 8 + bin. The length field must include everything.
    total = 12 + 8 + len(js) + 8 + len(binary)
    out = struct.pack("<4sII", b"glTF", 2, total)
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(binary), b"BIN\x00") + binary
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)


def main() -> None:
    pieces = {
        "cliff": cliff,
        "stone": stone,
        "gantry": gantry,
        "rail": rail,
        "lava": lava,
        "furnace": furnace,
        "arch": arch,
        "door": door_leaf,
        "lift": lift,
        "slag_cast": slag_cast,
        "ore": ore,
        "cart": cart,
        "boulder": boulder,
        "chain": chain,
        "pillar": pillar,
    }
    for name, fn in pieces.items():
        mesh = fn()
        dest = ROOT / f"{name}.glb"
        write_glb(dest, mesh)
        print(f"{name}: {len(mesh.pos)} verts, {len(mesh.faces)} tris -> {dest.name}")


if __name__ == "__main__":
    main()
