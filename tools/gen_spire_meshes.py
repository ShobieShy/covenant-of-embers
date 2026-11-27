#!/usr/bin/env python3
"""Act V mesh kit. Original geometry (CC0) for the Inverted Spire: the hanging
tower, rock shelves, crystals, nests, the false-sky disc, and the void wall.
Textures stay outside the glb; SpireTheme binds ambientCG PBR at load.

    python3 tools/gen_spire_meshes.py
"""

from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "spire"
MESH = OUT / "meshes"
TEX = OUT / "textures"


def _cross(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.cross(a, b)


def _norm(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-8)


class Mesh:
    def __init__(self) -> None:
        self.pos: list[np.ndarray] = []
        self.idx: list[int] = []

    def add(self, pos: np.ndarray, idx: np.ndarray) -> None:
        base = len(self.pos)
        self.pos.extend(np.asarray(pos, dtype=np.float32))
        self.idx.extend((np.asarray(idx, dtype=np.int64) + base).tolist())

    def pack(self) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        pos = np.asarray(self.pos, dtype=np.float32).reshape(-1, 3)
        idx = np.asarray(self.idx, dtype=np.uint32).reshape(-1, 3)
        nrm = np.zeros_like(pos)
        for tri in idx:
            a, b, c = (int(i) for i in tri)
            fn = _cross(pos[b] - pos[a], pos[c] - pos[a])
            nrm[a] += fn
            nrm[b] += fn
            nrm[c] += fn
        nrm = _norm(nrm)
        uv = np.stack((pos[:, 0], pos[:, 2]), axis=1).astype(np.float32)
        return pos, nrm, uv, idx.reshape(-1)


def _grid(nu: int, nv: int, sample, outward: np.ndarray | None = None) -> tuple[np.ndarray, np.ndarray]:
    """nu x nv samples. `sample(i, a)` -> xyz. Faces wind so the normal faces `outward`."""
    pos = np.zeros((nv, nu, 3), dtype=np.float64)
    for j in range(nv):
        for i in range(nu):
            pos[j, i] = sample(i, j)
    tris: list[int] = []
    for j in range(nv - 1):
        for i in range(nu - 1):
            a = j * nu + i
            b = a + 1
            c = a + nu
            d = c + 1
            p0, p1, p2 = pos.reshape(-1, 3)[a], pos.reshape(-1, 3)[c], pos.reshape(-1, 3)[b]
            fn = _cross(p2 - p0, p1 - p0)  # a, b, c
            expect = outward
            if expect is None:
                expect = pos[j, i]
                expect = expect / max(np.linalg.norm(expect), 1e-8)
            wind = (a, b, d, a, d, c) if float(np.dot(fn, expect)) >= 0 else (a, c, d, a, d, b)
            tris.extend(wind)
    return pos.reshape(-1, 3).astype(np.float32), np.asarray(tris, dtype=np.uint32)


def island(rx: float, rz: float, thick: float, seed: int) -> Mesh:
    rng = np.random.default_rng(seed)
    na, nr = 72, 14
    phase = rng.uniform(0, 6)

    def rad(i: int, t: float) -> float:
        th = 2 * np.pi * i / na
        wobble = (
            0.10 * np.sin(th * 3 + phase)
            + 0.06 * np.sin(th * 5 - phase)
            + 0.04 * np.sin(th * 8 + seed)
        )
        return t * (1.0 + wobble)

    def sample_top(i: int, j: int) -> np.ndarray:
        t = j / (nr - 1)
        th = 2 * np.pi * i / na
        s = rad(i, t)
        y = 0.05 * np.sin(th * 4 + t * 6) * (0.35 if t < 0.72 else 1.0)
        if t > 0.84:
            y -= thick * 0.15 * ((t - 0.84) / 0.16) ** 1.4
        return np.array((np.cos(th) * rx * s, y, np.sin(th) * rz * s))

    pos, idx = _grid(na + 1, nr, sample_top, np.array((0.0, 1.0, 0.0)))
    # Close the seam by duplicating angle 0 at angle n (sample uses i, so i=na matches i=0
    # only if rad is periodic). rad uses i/na, i=na equals i=0. Good.

    def sample_bot(i: int, j: int) -> np.ndarray:
        t = j / (nr - 1)
        th = 2 * np.pi * i / na
        s = rad(i, t) * (1.0 - 0.08 * t)
        y = -thick * (0.55 + 0.45 * (1.0 - t) ** 1.15) + 0.08 * np.sin(th * 3 + seed)
        return np.array((np.cos(th) * rx * s, y, np.sin(th) * rz * s))

    bp, bi = _grid(na + 1, nr, sample_bot, np.array((0.0, -1.0, 0.0)))
    m = Mesh()
    m.add(pos, idx)
    m.add(bp, bi)
    # Wall between the two outer rings.
    top_rim = pos.reshape(nr, na + 1, 3)[-1]
    bot_rim = bp.reshape(nr, na + 1, 3)[-1]
    wall_p = np.stack((top_rim, bot_rim), axis=0).reshape(-1, 3)
    wall_i: list[int] = []
    for i in range(na):
        a, b = i, i + 1
        c, d = i + (na + 1), i + 1 + (na + 1)
        fn = _cross(wall_p[b] - wall_p[a], wall_p[c] - wall_p[a])
        outward = wall_p[a] * np.array((1.0, 0.0, 1.0))
        if float(np.dot(fn, outward)) < 0:
            wall_i.extend((a, c, b, b, c, d))
        else:
            wall_i.extend((a, b, c, b, d, c))
    m.add(wall_p, np.asarray(wall_i, dtype=np.uint32))
    return m


def crystal(height: float = 2.4, radius: float = 0.28, sides: int = 6) -> Mesh:
    """Hex prism with pyramidal caps. Origin at the base centre, tip up."""
    pos = [(0.0, -height * 0.08, 0.0)]
    for k in range(sides):
        th = 2 * np.pi * k / sides
        pos.append((np.cos(th) * radius, height * 0.22, np.sin(th) * radius))
    for k in range(sides):
        th = 2 * np.pi * k / sides + np.pi / sides
        pos.append((np.cos(th) * radius * 0.72, height * 0.62, np.sin(th) * radius * 0.72))
    pos.append((0.0, height, 0.0))
    p = np.asarray(pos, dtype=np.float32)
    idx: list[int] = []
    tip_b, tip_t = 0, 1 + 2 * sides

    def fan(center: int, ring: int, n: int, up: bool) -> None:
        for k in range(n):
            a = ring + k
            b = ring + (k + 1) % n
            idx.extend((center, a, b) if up else (center, b, a))

    fan(tip_b, 1, sides, False)
    for k in range(sides):
        a = 1 + k
        b = 1 + (k + 1) % sides
        c = 1 + sides + k
        d = 1 + sides + (k + 1) % sides
        idx.extend((a, c, b, b, c, d))
    fan(tip_t, 1 + sides, sides, True)
    m = Mesh()
    m.add(p, np.asarray(idx, dtype=np.uint32))
    return m


def cluster(seed: int, n: int = 7) -> Mesh:
    rng = np.random.default_rng(seed)
    m = Mesh()
    for i in range(n):
        h = float(rng.uniform(0.9, 3.3))
        r = float(rng.uniform(0.12, 0.42))
        part = crystal(h, r)
        pos, _nrm, _uv, idx = part.pack()
        ang = float(rng.uniform(0, 6.28))
        tilt = float(rng.uniform(0.05, 0.38))
        c, s = np.cos(tilt), np.sin(tilt)
        ca, sa = np.cos(ang), np.sin(ang)
        # Tilt toward +X then spin.
        x, y, z = pos[:, 0], pos[:, 1], pos[:, 2]
        y2 = y * c - z * s
        z2 = y * s + z * c
        x2 = x * ca - z2 * sa
        z3 = x * sa + z2 * ca
        spun = np.stack((x2, y2, z3), axis=1)
        spun[:, 0] += float(rng.uniform(-0.55, 0.55))
        spun[:, 2] += float(rng.uniform(-0.55, 0.55))
        m.add(spun, idx)
    return m


def _tube(pts: np.ndarray, radius: float, sides: int = 5) -> tuple[np.ndarray, np.ndarray]:
    pts = np.asarray(pts, dtype=np.float64)
    frames = []
    for i in range(len(pts)):
        tangent = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        tangent = tangent / max(np.linalg.norm(tangent), 1e-8)
        up = np.array((0.0, 1.0, 0.0))
        side = np.cross(up, tangent)
        if np.linalg.norm(side) < 1e-4:
            side = np.cross(np.array((1.0, 0.0, 0.0)), tangent)
        side = side / np.linalg.norm(side)
        up = np.cross(tangent, side)
        frames.append((side, up))
    pos = []
    for p, (side, up) in zip(pts, frames):
        for k in range(sides):
            th = 2 * np.pi * k / sides
            pos.append(p + (np.cos(th) * side + np.sin(th) * up) * radius)
    pos_a = np.asarray(pos, dtype=np.float32)
    idx: list[int] = []
    for i in range(len(pts) - 1):
        for k in range(sides):
            a = i * sides + k
            b = i * sides + (k + 1) % sides
            c = (i + 1) * sides + k
            d = (i + 1) * sides + (k + 1) % sides
            idx.extend((a, c, b, b, c, d))
    return pos_a, np.asarray(idx, dtype=np.uint32)


def nest() -> Mesh:
    m = Mesh()
    rng = np.random.default_rng(11)
    for i in range(16):
        ang = 2 * np.pi * i / 16
        pts = []
        for k in range(7):
            a = ang + k / 6 * (2 * np.pi / 16) * 1.35
            r = 0.95 + 0.12 * np.sin(a * 3 + i)
            y = 0.05 + 0.16 * np.sin(k / 6 * np.pi) + 0.04 * np.cos(a * 2)
            pts.append((np.cos(a) * r, y, np.sin(a) * r))
        m.add(*_tube(np.asarray(pts), 0.045))
    for i in range(7):
        ang = 2 * np.pi * i / 7 + 0.4
        pts = []
        for k in range(6):
            t = k / 5
            r = 0.15 + t * 0.85
            y = 0.28 * np.sin(t * np.pi) * 0.5 + 0.02
            a = ang + 0.35 * np.sin(t * np.pi)
            pts.append((np.cos(a) * r, y, np.sin(a) * r))
        m.add(*_tube(np.asarray(pts), 0.035))
    for i in range(5):
        ang = float(rng.uniform(0, 6.28))
        pts = [(np.cos(ang) * 0.7, 0.1, np.sin(ang) * 0.7)]
        pts.append((np.cos(ang) * 0.35, 0.55 + 0.2 * i % 2, np.sin(ang) * 0.35))
        m.add(*_tube(np.asarray(pts), 0.03))
    return m


def tower() -> tuple[Mesh, Mesh]:
    """Hanging gothic mass. Local +Y is up, origin is the needle tip."""
    height = 32.0
    nh, na = 36, 24
    stone = Mesh()
    glass = Mesh()

    def radius(t: float) -> float:
        if t < 0.10:
            return 0.15 + 2.8 * (t / 0.10) ** 0.55
        u = (t - 0.10) / 0.90
        r = 2.8 + 10.2 * (u ** 0.62)
        for band, amp in ((0.28, 0.45), (0.48, 0.55), (0.70, 0.7), (0.88, 1.1)):
            r += amp * np.exp(-((t - band) / 0.012) ** 2)
        return float(r)

    def sample(i: int, j: int) -> np.ndarray:
        t = j / (nh - 1)
        th = 2 * np.pi * i / na
        lobe = max(0.0, np.cos(th * 8.0)) ** 3
        r = radius(t) + lobe * (0.35 + 2.4 * np.sin(np.pi * t) ** 1.15)
        return np.array((np.cos(th) * r, t * height, np.sin(th) * r))

    pos, idx = _grid(na + 1, nh, sample, None)
    stone.add(pos, idx)
    # Cap the crown.
    crown = pos.reshape(nh, na + 1, 3)[-1]
    center = np.array((0.0, height, 0.0), dtype=np.float32)
    cap_p = np.vstack((center, crown))
    cap_i: list[int] = []
    for i in range(na):
        cap_i.extend((0, i + 1, i + 2))
    stone.add(cap_p, np.asarray(cap_i, dtype=np.uint32))

    def add_pinnacle(base: np.ndarray, direction: np.ndarray, length: float, rad: float) -> None:
        direction = direction / max(np.linalg.norm(direction), 1e-8)
        tip = base + direction * length
        side = np.cross(direction, np.array((0.0, 1.0, 0.0)))
        if np.linalg.norm(side) < 1e-4:
            side = np.cross(direction, np.array((1.0, 0.0, 0.0)))
        side = side / np.linalg.norm(side)
        up = np.cross(side, direction)
        sides = 6
        ring = [base + (np.cos(2 * np.pi * k / sides) * side + np.sin(2 * np.pi * k / sides) * up) * rad for k in range(sides)]
        p = np.asarray([tip, *ring, base], dtype=np.float32)
        ix: list[int] = []
        for k in range(sides):
            a = 1 + k
            b = 1 + (k + 1) % sides
            ix.extend((0, b, a))  # tip, outward-ish
            ix.extend((1 + sides, a, b))
        stone.add(p, np.asarray(ix, dtype=np.uint32))

    for k in range(12):
        th = 2 * np.pi * k / 12
        t = 0.18 + (k % 4) * 0.16
        r = radius(t) + 0.4
        base = np.array((np.cos(th) * r, t * height, np.sin(th) * r))
        hang = np.array((np.cos(th) * 0.35, -1.0, np.sin(th) * 0.35))
        add_pinnacle(base, hang, 2.2 + (k % 3) * 1.4, 0.28 + (k % 2) * 0.12)
    for k in range(16):
        th = 2 * np.pi * k / 16 + 0.1
        r = radius(0.96) + 0.2
        base = np.array((np.cos(th) * r, height * 0.98, np.sin(th) * r))
        hang = np.array((np.cos(th) * 0.25, -1.0, np.sin(th) * 0.25))
        add_pinnacle(base, hang, 3.5 + (k % 4) * 0.8, 0.22)

    def lancet(width: float, h: float) -> np.ndarray:
        """Flat lancet in the XY plane, centred, z = 0. Returns a triangle list's positions."""
        n = 9
        left = []
        right = []
        for i in range(n):
            u = i / (n - 1)
            y = u * h
            # Two arcs meeting at the apex. x falls to 0 at the top.
            pinch = np.sin(u * np.pi * 0.5)
            x = (width * 0.5) * (1.0 - pinch ** 1.35)
            left.append((-x, y, 0.0))
            right.append((x, y, 0.0))
        ring = left + right[::-1]
        c = np.array((0.0, h * 0.42, 0.0))
        p = [c, *ring]
        return np.asarray(p, dtype=np.float64)

    def add_window(t: float, th: float, w: float, h: float) -> None:
        r = radius(t) + 0.15
        origin = np.array((np.cos(th) * r, t * height - h * 0.15, np.sin(th) * r))
        outward = np.array((np.cos(th), 0.0, np.sin(th)))
        up = np.array((0.0, 1.0, 0.0))
        side = np.cross(up, outward)
        shape = lancet(w, h)
        world = origin + shape[:, 0:1] * side + shape[:, 1:2] * up + shape[:, 2:3] * outward
        # A thin second layer so the pane has a stone hood just outside.
        hood = world + outward * 0.05
        ix: list[int] = []
        n = (len(shape) - 1)
        for k in range(1, n - 1):
            ix.extend((0, k, k + 1))
        glass.add(world.astype(np.float32), np.asarray(ix, dtype=np.uint32))
        # Hood ring as a stone lip: skip, the body mouldings carry it.

    for row, t, w, h in ((0, 0.30, 0.7, 2.2), (1, 0.50, 0.85, 2.6), (2, 0.72, 1.0, 3.0)):
        for k in range(8):
            th = 2 * np.pi * (k + 0.5) / 8
            add_window(t, th, w, h)
    return stone, glass


def cylinder(radius: float, height: float, segments: int, inward: bool) -> Mesh:
    def sample(i: int, j: int) -> np.ndarray:
        th = 2 * np.pi * i / segments
        y = height * j / 8
        wobble = 1.0 + 0.015 * np.sin(th * 5 + j)
        return np.array((np.cos(th) * radius * wobble, y, np.sin(th) * radius * wobble))

    expect = np.array((0.0, 0.0, 0.0)) if inward else None
    # Per-vertex outward is used when expect is None. For inward, flip after.
    pos, idx = _grid(segments + 1, 9, sample, None)
    if inward:
        idx = idx.reshape(-1, 3)[:, [0, 2, 1]].reshape(-1)
    m = Mesh()
    m.add(pos, idx)
    return m


def dome(segments: int = 56, rings: int = 14) -> Mesh:
    """Unit hemisphere. Equator at y=0, crown at y=1. UVs are a top-down disc."""

    def sample(i: int, j: int) -> np.ndarray:
        th = 2 * np.pi * i / segments
        phi = (j / rings) * (np.pi * 0.5)
        r = np.cos(phi)
        return np.array((np.cos(th) * r, np.sin(phi), np.sin(th) * r))

    pos, idx = _grid(segments + 1, rings + 1, sample, np.array((0.0, -1.0, 0.0)))
    m = Mesh()
    m.add(pos, idx)
    return m


def ring(inner: float, outer: float, segments: int = 64) -> Mesh:
    def sample(i: int, j: int) -> np.ndarray:
        th = 2 * np.pi * i / segments
        r = inner + (outer - inner) * j
        return np.array((np.cos(th) * r, 0.0, np.sin(th) * r))

    pos, idx = _grid(segments + 1, 2, sample, np.array((0.0, -1.0, 0.0)))
    m = Mesh()
    m.add(pos, idx)
    return m


def streak() -> Mesh:
    pos = np.array(
        [
            (0.0, 0.0, -0.5),
            (0.04, 0.0, 0.15),
            (0.0, 0.015, 0.5),
            (-0.04, 0.0, 0.15),
        ],
        dtype=np.float32,
    )
    idx = np.array([0, 1, 2, 0, 2, 3], dtype=np.uint32)
    m = Mesh()
    m.add(pos, idx)
    return m


def column() -> Mesh:
    def sample(i: int, j: int) -> np.ndarray:
        th = 2 * np.pi * i / 12
        y = j / 8
        r = 0.55 * (1.0 - 0.65 * y)
        return np.array((np.cos(th) * r, y, np.sin(th) * r))

    pos, idx = _grid(13, 9, sample, None)
    m = Mesh()
    m.add(pos, idx)
    return m


def sky_texture(path: Path) -> None:
    s = 1024
    y, x = np.mgrid[0:s, 0:s]
    dx = (x - s / 2) / (s / 2)
    dy = (y - s / 2) / (s / 2)
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    swirl = ang * 2.0 + 3.4 * np.sin(r * 3.1) + 1.6 / (0.18 + r)
    band = 0.55 + 0.45 * np.sin(swirl) * np.cos(r * 7.0 + ang)
    glow = np.clip(1.15 - r * 0.85, 0, 1) ** 1.4
    arm = np.clip(np.sin(swirl * 1.4) * 0.5 + 0.5, 0, 1) * np.clip(1.1 - r, 0, 1)
    violet = np.array((0.16, 0.05, 0.28))
    mid = np.array((0.58, 0.22, 0.82))
    pale = np.array((0.88, 0.72, 1.0))
    core = np.array((0.95, 0.92, 1.0))
    col = violet * (1 - glow)[:, :, None] + mid * glow[:, :, None]
    col = col * (0.45 + 0.55 * band)[:, :, None]
    col = col + pale * (arm * 0.55)[:, :, None]
    col = col + core * (np.clip(1.0 - r * 3.2, 0, 1) ** 2)[:, :, None] * 0.85
    rng = np.random.default_rng(5)
    img = np.clip(col, 0, 1)
    ys = rng.integers(0, s, 700)
    xs = rng.integers(0, s, 700)
    for px, py, bright in zip(xs, ys, rng.uniform(0.45, 1.0, 700)):
        if r[py, px] < 0.96:
            img[py, px] = np.clip(img[py, px] + np.array((bright, bright, 1.0)) * bright, 0, 1)
    img[r > 1.0] = 0.0
    alpha = np.clip(1.15 - r, 0, 1) * 255
    rgba = np.dstack((img * 255, alpha)).astype(np.uint8)
    image = Image.fromarray(rgba, "RGBA").filter(ImageFilter.GaussianBlur(radius=0.6))
    # Stars got blurred; punch a few back in.
    pix = image.load()
    for px, py, bright in zip(xs[::2], ys[::2], rng.uniform(0.7, 1.0, 350)):
        if r[py, px] < 0.94:
            v = int(200 + 55 * bright)
            pix[int(px), int(py)] = (v, v, 255, 255)
    image.save(path)


def _glb(path: Path, parts: list[tuple[str, Mesh]]) -> None:
    blobs = bytearray()
    views = []
    accs = []
    meshes = []
    nodes = []

    def push(array: np.ndarray) -> int:
        raw = np.ascontiguousarray(array).tobytes()
        pad = (4 - (len(blobs) % 4)) % 4
        blobs.extend(b"\x00" * pad)
        start = len(blobs)
        blobs.extend(raw)
        views.append({"buffer": 0, "byteOffset": start, "byteLength": len(raw)})
        return len(views) - 1

    for name, mesh in parts:
        pos, nrm, uv, idx = mesh.pack()
        pv = push(pos.astype(np.float32))
        nv = push(nrm.astype(np.float32))
        uvv = push(uv.astype(np.float32))
        iv = push(idx.astype(np.uint32))
        base = len(accs)
        accs.append(
            {
                "bufferView": pv,
                "componentType": 5126,
                "count": int(pos.shape[0]),
                "type": "VEC3",
                "min": pos.min(0).tolist(),
                "max": pos.max(0).tolist(),
            }
        )
        accs.append({"bufferView": nv, "componentType": 5126, "count": int(nrm.shape[0]), "type": "VEC3"})
        accs.append({"bufferView": uvv, "componentType": 5126, "count": int(uv.shape[0]), "type": "VEC2"})
        accs.append({"bufferView": iv, "componentType": 5125, "count": int(idx.shape[0]), "type": "SCALAR"})
        meshes.append(
            {
                "name": name,
                "primitives": [
                    {
                        "attributes": {"POSITION": base, "NORMAL": base + 1, "TEXCOORD_0": base + 2},
                        "indices": base + 3,
                    }
                ],
            }
        )
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    gltf = {
        "asset": {"version": "2.0", "generator": "gen_spire_meshes.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "accessors": accs,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blobs)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    pad = (4 - (len(js) % 4)) % 4
    js += b" " * pad
    blob_pad = (4 - (len(blobs) % 4)) % 4
    blobs += b"\x00" * blob_pad
    out = bytearray()
    out += struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blobs))
    out += struct.pack("<I4s", len(js), b"JSON")
    out += js
    out += struct.pack("<I4s", len(blobs), b"BIN\x00")
    out += blobs
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(out)
    print(f"[spire] {path.relative_to(ROOT)} {path.stat().st_size} bytes")


def main() -> None:
    MESH.mkdir(parents=True, exist_ok=True)
    TEX.mkdir(parents=True, exist_ok=True)
    sky_texture(TEX / "false_sky.png")
    _glb(MESH / "island_wide.glb", [("Stone", island(1.0, 0.82, 0.34, 3))])
    _glb(MESH / "island_round.glb", [("Stone", island(1.0, 1.0, 0.4, 9))])
    _glb(MESH / "island_shard.glb", [("Stone", island(1.15, 0.62, 0.46, 15))])
    _glb(MESH / "crystal_cluster.glb", [("Crystal", cluster(4, 7))])
    _glb(MESH / "crystal_cluster_blue.glb", [("Crystal", cluster(8, 5))])
    _glb(MESH / "nest.glb", [("Twig", nest())])
    stone, glass = tower()
    _glb(MESH / "inverted_tower.glb", [("Stone", stone), ("Glass", glass)])
    _glb(MESH / "void_wall.glb", [("Stone", cylinder(1.0, 1.0, 72, True))])
    _glb(MESH / "sky_disc.glb", [("Sky", dome())])
    _glb(MESH / "sky_ring.glb", [("Stone", ring(0.78, 1.0))])
    _glb(MESH / "light_column.glb", [("Beam", column())])
    _glb(MESH / "wind_streak.glb", [("Streak", streak())])
    print("[spire] meshes written")


if __name__ == "__main__":
    main()
