#!/usr/bin/env python3
"""Project-made regular-enemy meshes for 0.14.1.

Each body is a smooth sculpt (marching cubes over ellipsoids, capsules and
boxes) plus hard parts (ears, weapons, plates, wings, cracks). Feet sit on
y = 0 and the face points toward +Z. Godot turns the glb 180 degrees so the
face points down -Z. No engine primitive is exported.

    python3 tools/build_regular_enemies.py
    python3 tools/build_regular_enemies.py --preview /tmp/enemy_preview
    python3 tools/build_regular_enemies.py --only goblin_grunt
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

import numpy as np
from skimage.measure import marching_cubes

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "original" / "ember_art" / "regular_enemies"

# sRGB palettes. Converted to linear at export.
SKIN = (0.38, 0.52, 0.24)
SKIN_Y = (0.46, 0.58, 0.26)
LEATHER = (0.45, 0.28, 0.16)
CLOTH = (0.28, 0.18, 0.12)
BOW = (0.42, 0.30, 0.16)
ROBE = (0.48, 0.22, 0.46)
EMBER = (1.0, 0.42, 0.08)
RUST = (0.62, 0.34, 0.18)
BONE = (0.78, 0.70, 0.52)
PLATE = (0.48, 0.42, 0.36)
BELLY = (0.62, 0.52, 0.42)
SNOUT = (0.72, 0.52, 0.46)
RUBBLE = (0.28, 0.24, 0.22)
VIOLET = (0.72, 0.38, 1.0)
CHAR = (0.18, 0.08, 0.05)
MOSS = (0.32, 0.48, 0.20)
MOSS_L = (0.55, 0.68, 0.32)
EARTH = (0.48, 0.34, 0.18)
WATER = (0.22, 0.38, 0.50)
WATER_L = (0.62, 0.74, 0.78)
CAP = (0.72, 0.58, 0.32)
CAP_S = (0.52, 0.28, 0.62)
BARK = (0.40, 0.26, 0.16)
FUNGUS = (0.22, 0.20, 0.16)
GROWTH = (0.48, 0.26, 0.62)
EYE_P = (0.86, 0.62, 1.0)
TROLL = (0.42, 0.18, 0.12)
LAVA = (1.0, 0.32, 0.06)
IRON = (0.32, 0.30, 0.28)
FLESH = (0.55, 0.46, 0.38)
KELP = (0.16, 0.28, 0.34)
CORAL = (0.58, 0.24, 0.36)
FEATHER = (0.74, 0.74, 0.72)
CRYSTAL = (0.72, 0.68, 0.86)
WIND = (0.90, 0.88, 1.0)
EYE_G = (0.85, 0.95, 0.35)
TOOTH = (0.90, 0.86, 0.74)


def lin(c):
    c = np.clip(np.asarray(c, np.float64), 0.0, 1.0)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def ell(p, c, r):
    r = np.maximum(np.asarray(r, np.float64), 1e-3)
    q = (p - np.asarray(c, np.float64)) / r
    return (np.linalg.norm(q, axis=-1) - 1.0) * float(np.min(r))


def cap(p, a, b, ra, rb):
    a = np.asarray(a, np.float64)
    b = np.asarray(b, np.float64)
    ba = b - a
    l2 = float(np.dot(ba, ba)) + 1e-8
    t = np.clip(np.sum((p - a) * ba, axis=-1) / l2, 0.0, 1.0)
    closest = a + ba * t[..., None]
    radius = float(ra) + (float(rb) - float(ra)) * t
    return np.linalg.norm(p - closest, axis=-1) - radius


def cube(p, c, s, rad=0.04):
    q = np.abs(p - np.asarray(c, np.float64)) - np.asarray(s, np.float64)
    outside = np.linalg.norm(np.maximum(q, 0.0), axis=-1)
    inside = np.minimum(np.max(q, axis=-1), 0.0)
    return outside + inside - float(rad)


def smin(a, b, k):
    k = max(float(k), 1e-4)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return (1.0 - h) * b + h * a - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def E(c, r, k=0.06):
    return ("ell", c, r, k)


def C(a, b, ra, rb, k=0.05):
    return ("cap", a, b, ra, rb, k)


def BX(c, s, k=0.05, rad=0.05):
    return ("box", c, s, k, rad)


def SUB(c, r, k=0.04):
    return ("sub", c, r, k)


def SUBB(c, s, k=0.04):
    return ("subbox", c, s, k)


def _eval(p, part):
    k = part[0]
    if k == "ell" or k == "sub":
        return ell(p, part[1], part[2])
    if k == "cap":
        return cap(p, part[1], part[2], part[3], part[4])
    if k == "box":
        return cube(p, part[1], part[2], part[4] if len(part) > 4 else 0.04)
    if k == "subbox":
        return cube(p, part[1], part[2], 0.02)
    raise ValueError(k)


def field_of(parts, ground=True):
    adds = [q for q in parts if q[0] not in ("sub", "subbox")]
    subs = [q for q in parts if q[0] in ("sub", "subbox")]

    def field(p):
        d = None
        for part in adds:
            nd = _eval(p, part)
            blend = part[3]
            d = nd if d is None else smin(d, nd, blend)
        for part in subs:
            d = smax(d, -_eval(p, part), part[3])
        if ground and d is not None:
            d = np.maximum(d, -p[..., 1])
        return d

    return field


def bounds_of(parts, pad=0.12):
    pts = []
    for part in parts:
        if part[0] in ("ell", "sub"):
            c = np.asarray(part[1], np.float64)
            r = np.asarray(part[2], np.float64)
            pts += [c - r, c + r]
        elif part[0] == "cap":
            a = np.asarray(part[1], np.float64)
            b = np.asarray(part[2], np.float64)
            ra, rb = float(part[3]), float(part[4])
            pts += [a - ra, a + ra, b - rb, b + rb]
        else:
            c = np.asarray(part[1], np.float64)
            s = np.asarray(part[2], np.float64)
            pts += [c - s, c + s]
    pts = np.vstack(pts)
    lo = pts.min(0) - pad
    hi = pts.max(0) + pad
    lo[1] = min(lo[1], -0.04)
    return lo, hi


def value_noise(p, freq):
    q = p * freq
    i = np.floor(q).astype(np.int32)
    f = q - i
    u = f * f * (3.0 - 2.0 * f)

    def h(ix, iy, iz):
        s = np.sin(ix * 127.1 + iy * 311.7 + iz * 74.7) * 43758.5453
        return s - np.floor(s)

    c000 = h(i[:, 0], i[:, 1], i[:, 2])
    c100 = h(i[:, 0] + 1, i[:, 1], i[:, 2])
    c010 = h(i[:, 0], i[:, 1] + 1, i[:, 2])
    c110 = h(i[:, 0] + 1, i[:, 1] + 1, i[:, 2])
    c001 = h(i[:, 0], i[:, 1], i[:, 2] + 1)
    c101 = h(i[:, 0] + 1, i[:, 1], i[:, 2] + 1)
    c011 = h(i[:, 0], i[:, 1] + 1, i[:, 2] + 1)
    c111 = h(i[:, 0] + 1, i[:, 1] + 1, i[:, 2] + 1)
    x00 = c000 * (1 - u[:, 0]) + c100 * u[:, 0]
    x10 = c010 * (1 - u[:, 0]) + c110 * u[:, 0]
    x01 = c001 * (1 - u[:, 0]) + c101 * u[:, 0]
    x11 = c011 * (1 - u[:, 0]) + c111 * u[:, 0]
    y0 = x00 * (1 - u[:, 1]) + x10 * u[:, 1]
    y1 = x01 * (1 - u[:, 1]) + x11 * u[:, 1]
    return y0 * (1 - u[:, 2]) + y1 * u[:, 2]


def face_normals(verts, faces):
    a = verts[faces[:, 0]]
    b = verts[faces[:, 1]]
    c = verts[faces[:, 2]]
    fn = np.cross(b - a, c - a)
    n = np.zeros_like(verts)
    for i in range(3):
        np.add.at(n, faces[:, i], fn)
    length = np.linalg.norm(n, axis=1, keepdims=True)
    length[length < 1e-8] = 1.0
    return n / length


def march(parts, res=None, amp=0.0, freq=4.0, ground=True):
    lo, hi = bounds_of(parts)
    span = hi - lo
    if res is None:
        res = int(np.clip(span.max() / 0.032, 40, 76))
    xs = np.linspace(lo[0], hi[0], res)
    ys = np.linspace(lo[1], hi[1], res)
    zs = np.linspace(lo[2], hi[2], res)
    dx, dy, dz = xs[1] - xs[0], ys[1] - ys[0], zs[1] - zs[0]
    x, y, z = np.meshgrid(xs, ys, zs, indexing="ij")
    vol = field_of(parts, ground)(np.stack([x, y, z], axis=-1)).astype(np.float32)
    if vol.min() >= 0 or vol.max() <= 0:
        raise RuntimeError("field did not cross zero")
    verts, faces, _norms, _ = marching_cubes(vol, level=0.0, spacing=(dx, dy, dz))
    verts = verts + np.array([xs[0], ys[0], zs[0]], np.float64)
    faces = faces.astype(np.int32)
    center = (lo + hi) * 0.5
    mid = verts[faces].mean(axis=1)
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    if np.mean(np.sum(fn * (mid - center), axis=1)) < 0:
        faces = faces[:, ::-1]
    normals = face_normals(verts, faces)
    if amp:
        verts = verts + normals * ((value_noise(verts, freq) - 0.35) * amp)[:, None]
        verts[:, 1] = np.maximum(verts[:, 1], 0.0)
        normals = face_normals(verts, faces)
    return verts, faces, normals


def shade(verts, normals, lo=0.62, hi=1.05, freq=3.2):
    up = np.clip(normals[:, 1] * 0.55 + 0.55, 0.0, 1.0)
    n = value_noise(verts, freq)
    light = lo + (hi - lo) * up
    light = light * (0.88 + 0.18 * n)
    return np.clip(light, 0.45, 1.15).astype(np.float32)


def uv_sphere(stacks, slices):
    verts = [np.array([0.0, 1.0, 0.0])]
    for i in range(1, stacks):
        phi = i / stacks * np.pi
        for j in range(slices):
            th = j / slices * np.pi * 2.0
            verts.append(np.array([
                np.sin(phi) * np.cos(th),
                np.cos(phi),
                np.sin(phi) * np.sin(th),
            ]))
    verts.append(np.array([0.0, -1.0, 0.0]))
    v = np.asarray(verts, np.float64)
    faces = []
    for j in range(slices):
        faces.append((0, 1 + (j + 1) % slices, 1 + j))
    for i in range(stacks - 2):
        row = 1 + i * slices
        nxt = row + slices
        for j in range(slices):
            a = row + j
            b = row + (j + 1) % slices
            c = nxt + j
            d = nxt + (j + 1) % slices
            faces.append((a, c, b))
            faces.append((b, c, d))
    bot = len(v) - 1
    last = 1 + (stacks - 2) * slices
    for j in range(slices):
        faces.append((bot, last + j, last + (j + 1) % slices))
    f = np.asarray(faces, np.int32)
    n = np.cross(v[f[0, 1]] - v[f[0, 0]], v[f[0, 2]] - v[f[0, 0]])
    if np.dot(n, v[f[0]].mean(0)) < 0:
        f = f[:, ::-1]
    return v, f


_SPHERE = {}


def sphere(center, radii, subdiv=1):
    key = 1 if subdiv > 0 else 0
    if key not in _SPHERE:
        _SPHERE[key] = uv_sphere(5, 8) if key else uv_sphere(3, 5)
    v, f = _SPHERE[key]
    verts = v * np.asarray(radii, np.float64) + np.asarray(center, np.float64)
    return verts, f.copy(), v.copy()


def cone(base, tip, radius, sides=8):
    base = np.asarray(base, np.float64)
    tip = np.asarray(tip, np.float64)
    axis = tip - base
    length = np.linalg.norm(axis) + 1e-8
    axis = axis / length
    helper = np.array([0.0, 1.0, 0.0]) if abs(axis[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(axis, helper)
    u /= np.linalg.norm(u)
    w = np.cross(axis, u)
    verts = [base, tip]
    for i in range(sides):
        a = i / sides * np.pi * 2
        verts.append(base + (np.cos(a) * u + np.sin(a) * w) * radius)
    v = np.asarray(verts, np.float64)
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((0, 2 + j, 2 + i))
        faces.append((1, 2 + i, 2 + j))
    f = np.asarray(faces, np.int32)
    return v, f, face_normals(v, f)


def tube(a, b, ra, rb, sides=8):
    a = np.asarray(a, np.float64)
    b = np.asarray(b, np.float64)
    axis = b - a
    length = np.linalg.norm(axis) + 1e-8
    axis = axis / length
    helper = np.array([0.0, 1.0, 0.0]) if abs(axis[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(axis, helper)
    u /= np.linalg.norm(u)
    w = np.cross(axis, u)
    rings = [a, b]
    radii = [ra, rb]
    verts = []
    for p, r in zip(rings, radii):
        for i in range(sides):
            ang = i / sides * np.pi * 2
            verts.append(p + (np.cos(ang) * u + np.sin(ang) * w) * r)
    # end caps
    verts.append(a)
    verts.append(b)
    v = np.asarray(verts, np.float64)
    faces = []
    a_cap = sides * 2
    b_cap = sides * 2 + 1
    for i in range(sides):
        j = (i + 1) % sides
        faces.append((i, j, sides + j))
        faces.append((i, sides + j, sides + i))
        faces.append((a_cap, j, i))
        faces.append((b_cap, sides + i, sides + j))
    f = np.asarray(faces, np.int32)
    return v, f, face_normals(v, f)


def extrude(profile, depth, origin, axis_x=np.array((1.0, 0.0, 0.0))):
    """profile is a list of (y, z) in the plane, extruded ±depth/2 along axis_x."""
    origin = np.asarray(origin, np.float64)
    n = len(profile)
    verts = []
    x = np.asarray(axis_x, np.float64)
    for s in (-0.5, 0.5):
        for y, z in profile:
            verts.append(origin + x * (depth * s) + np.array((0.0, y, z)))
    v = np.asarray(verts, np.float64)
    faces = []
    for i in range(1, n - 1):
        faces.append((0, i, i + 1))
        faces.append((n, n + i + 1, n + i))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, n + i, n + j))
        faces.append((i, n + j, j))
    f = np.asarray(faces, np.int32)
    return v, f, face_normals(v, f)


def feather(root, tip, width, lift=0.0):
    root = np.asarray(root, np.float64)
    tip = np.asarray(tip, np.float64)
    axis = tip - root
    length = np.linalg.norm(axis) + 1e-8
    axis = axis / length
    up = np.array([0.0, 1.0, 0.0])
    side = np.cross(axis, up)
    if np.linalg.norm(side) < 1e-4:
        side = np.array([1.0, 0.0, 0.0])
    side = side / np.linalg.norm(side)
    mid = root + axis * length * 0.45 + np.array([0.0, lift, 0.0])
    verts = np.array([
        root,
        mid + side * width,
        tip,
        mid - side * width,
        mid + np.array([0.0, width * 0.15, 0.0]),
    ], np.float64)
    faces = np.array([(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4),
                      (0, 4, 1), (1, 4, 2), (2, 4, 3), (3, 4, 0)], np.int32)
    return verts, faces, face_normals(verts, faces)


class Sculpt:
    def __init__(self):
        self.parts = []  # name, material, verts, faces, normals, vcol, double

    def add(self, name, material, verts, faces, normals=None, vcol=None, double=False):
        verts = np.asarray(verts, np.float64)
        faces = np.asarray(faces, np.int32)
        if normals is None:
            normals = face_normals(verts, faces)
        if vcol is None:
            vcol = shade(verts, normals)
        vcol = np.asarray(vcol, np.float32)
        if vcol.ndim == 1:
            vcol = np.repeat(vcol[:, None], 3, axis=1)
        self.parts.append((name, material, verts, faces, normals, vcol, double))

    def mc(self, name, material, parts, amp=0.012, freq=3.5, res=None):
        v, f, n = march(parts, res=res, amp=amp, freq=freq)
        self.add(name, material, v, f, n)

    def tris(self):
        return int(sum(len(p[3]) for p in self.parts))


def limb_pair(parts, hip, foot, ankle, r0, r1, spread, z=0.02, k=0.05):
    """Two legs from hip y down to a foot ellipsoid. hip/foot are y values."""
    for s in (-1.0, 1.0):
        knee = ((hip[0] + foot[0]) * 0.5 * s + hip[0] * 0, (hip[1] + ankle) * 0.5, z)
        # simpler: explicit coordinates passed via hip as (x, y, z)
    for s in (-1.0, 1.0):
        a = (hip[0] * s, hip[1], hip[2])
        b = (foot[0] * s, ankle, foot[2])
        parts.append(C(a, b, r0, r1, k))
        parts.append(E((b[0], 0.045, b[2] + 0.04), (r1 * 1.15, 0.045, r1 * 1.7), k))


def arm_pair(parts, shoulder, hand, r0, r1, k=0.045):
    """shoulder and hand are (x, y, z) for the positive-x arm. The other mirrors x."""
    for s in (-1.0, 1.0):
        a = (shoulder[0] * s, shoulder[1], shoulder[2])
        h = (hand[0] * s, hand[1], hand[2])
        elbow = ((a[0] + h[0]) * 0.5, (a[1] + h[1]) * 0.55 + 0.02, (a[2] + h[2]) * 0.5)
        parts.append(C(a, elbow, r0, (r0 + r1) * 0.5, k))
        parts.append(C(elbow, h, (r0 + r1) * 0.5, r1, k))
        parts.append(E(h, (r1 * 1.15, r1 * 0.8, r1 * 1.25), k))


def goblin(sculpt, skin, hood=False, robe=False, lean=1.0):
    p = []
    belly = 0.28 * lean
    p += [
        E((0, 0.62, 0.02), (belly, 0.22, 0.16), 0.07),
        E((0, 0.84, 0.04), (0.20 * lean, 0.14, 0.13), 0.055),
        E((0, 1.02, 0.06), (0.15, 0.13, 0.13), 0.04),
        E((0, 1.10, 0.10), (0.12, 0.05, 0.08), 0.03),
        E((0, 0.94, 0.14), (0.09, 0.05, 0.08), 0.03),
    ]
    for s in (-1.0, 1.0):
        p.append(C((0.09 * s, 0.46, 0.02), (0.12 * s, 0.10, 0.04), 0.09, 0.07, 0.045))
        p.append(E((0.13 * s, 0.04, 0.07), (0.08, 0.04, 0.14), 0.03))
    # right arm reaches out with the weapon, left hangs
    p.append(C((0.18, 0.86, 0.04), (0.40, 0.58, 0.12), 0.065, 0.04, 0.02))
    p.append(E((0.44, 0.52, 0.14), (0.05, 0.04, 0.045), 0.02))
    p.append(C((-0.18, 0.86, 0.02), (-0.36, 0.55, 0.06), 0.06, 0.038, 0.02))
    p.append(E((-0.38, 0.48, 0.08), (0.045, 0.035, 0.04), 0.02))
    sculpt.mc("Body", skin, p, amp=0.01, freq=5.0, res=68)
    # ears
    for s in (-1.0, 1.0):
        # Broad leaf ears beside the head, not spikes.
        v, f, n = sphere((0.20 * s, 1.08, 0.0), (0.035, 0.14, 0.10), 1)
        sculpt.add("Ear", skin, v, f)
    # tusks
    for s in (-1.0, 1.0):
        v, f, n = cone((0.035 * s, 1.02, 0.14), (0.055 * s, 0.92, 0.16), 0.018, 6)
        sculpt.add("Tusk", "bone", v, f)
    # brow leather strap and loincloth
    v, f, n = sphere((0, 0.48, 0.12), (0.22 * lean, 0.14, 0.08), 1)
    sculpt.add("Loincloth", "leather", v, f)
    v, f, n = sphere((0.18, 0.92, 0.04), (0.10, 0.07, 0.09), 1)
    sculpt.add("Pauldron", "leather", v, f)
    if hood:
        v, f, n = sphere((0, 1.22, -0.01), (0.16, 0.14, 0.15), 1)
        sculpt.add("Hood", "leather", v, f)
        v, f, n = cone((0, 1.32, -0.02), (0, 1.46, -0.02), 0.06, 7)
        sculpt.add("HoodTip", "leather", v, f)
    if robe:
        v, f, n = sphere((0, 0.72, 0.0), (0.30, 0.28, 0.16), 1)
        sculpt.add("Robe", "robe", v, f)
        v, f, n = sphere((0, 1.24, -0.02), (0.15, 0.12, 0.14), 1)
        sculpt.add("Hood", "robe", v, f)


def cleaver():
    # Blade in the XY plane so the front view shows the notched edge, not the spine.
    # Negative x is the goblin's right once Godot turns the mesh to face -Z,
    # which is the viewer's left, matching the sheet.
    profile = [
        (0.00, 0.00),
        (-0.06, 0.18),
        (-0.28, 0.55),
        (-0.02, 0.62),
        (0.04, 0.34),
        (0.00, 0.14),
    ]
    return extrude_xy(profile, 0.045, (-0.36, 0.50, 0.16))


def extrude_xy(profile, depth, origin):
    origin = np.asarray(origin, np.float64)
    n = len(profile)
    verts = []
    for s in (-0.5, 0.5):
        for x, y in profile:
            verts.append(origin + np.array((x, y, depth * s)))
    v = np.asarray(verts, np.float64)
    faces = []
    for i in range(1, n - 1):
        faces.append((0, i, i + 1))
        faces.append((n, n + i + 1, n + i))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, n + i, n + j))
        faces.append((i, n + j, j))
    f = np.asarray(faces, np.int32)
    return v, f, face_normals(v, f)


def wing_blade(sign):
    """One raised feathered wing. The flat of the wing faces the camera."""
    s = float(sign)
    outline = np.array([
        [0.10 * s, 1.15, -0.02],
        [0.55 * s, 0.85, -0.15],
        [1.15 * s, 1.15, -0.28],
        [1.45 * s, 1.85, -0.32],
        [0.85 * s, 2.15, -0.18],
        [0.28 * s, 1.72, -0.06],
    ], np.float64)
    # A thin second layer offset in z so the wing has thickness.
    front = outline.copy()
    back = outline.copy()
    back[:, 2] -= 0.04
    v = np.vstack([front, back])
    n = len(outline)
    faces = []
    for i in range(1, n - 1):
        faces.append((0, i, i + 1))
        faces.append((n, n + i + 1, n + i))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, n + i, n + j))
        faces.append((i, n + j, j))
    f = np.asarray(faces, np.int32)
    return v, f, face_normals(v, f)


def bow():
    profile = []
    for i in range(14):
        t = i / 13
        y = -0.28 + t * 0.62
        z = 0.10 * np.sin(t * np.pi)
        profile.append((y, z))
    # a thick enough limb reads as a bow; close it into a band
    back = list(reversed([(y, z - 0.025) for y, z in profile]))
    return extrude(profile + back, 0.02, (-0.06, 0.86, 0.16))


def staff():
    v, f, n = tube((0.22, 0.42, 0.08), (0.16, 1.48, 0.10), 0.025, 0.02, 7)
    return v, f, n


def build_goblin_grunt():
    s = Sculpt()
    goblin(s, "goblin_skin", lean=1.08)
    v, f, n = cleaver()
    s.add("Club", "rust", v, f, n)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.045 * sgn, 1.16, 0.13), (0.018, 0.016, 0.012), 0)
        s.add("Eye", "eye_g", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_goblin_archer():
    s = Sculpt()
    goblin(s, "goblin_skin_y", hood=True, lean=0.92)
    v, f, n = bow()
    s.add("Bow", "bowwood", v, f, n)
    v, f, n = sphere((0.0, 0.95, -0.12), (0.06, 0.10, 0.05), 1)
    s.add("Quiver", "leather", v, f)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.04 * sgn, 1.15, 0.12), (0.016, 0.014, 0.01), 0)
        s.add("Eye", "eye_g", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_goblin_shaman():
    s = Sculpt()
    goblin(s, "goblin_skin", robe=True, lean=0.86)
    v, f, n = staff()
    s.add("Staff", "bowwood", v, f, n)
    v, f, n = sphere((0.15, 1.50, 0.10), (0.055, 0.055, 0.055), 1)
    s.add("Ember", "ember", v, f, vcol=np.ones((len(v), 3)))
    v, f, n = cone((0.15, 1.54, 0.10), (0.15, 1.68, 0.10), 0.04, 6)
    s.add("Flame", "flame", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_gnawer(plague=False):
    s = Sculpt()
    skin = "plate_g" if plague else "plate"
    p = [
        E((0, 0.22, 0.0), (0.16, 0.14, 0.28), 0.05),
        E((0, 0.28, -0.04), (0.14, 0.10, 0.16), 0.04),
        C((0, 0.22, 0.22), (0, 0.18, 0.42), 0.08, 0.04, 0.04),
        E((0, 0.17, 0.44), (0.045, 0.04, 0.05), 0.02),
        C((0, 0.20, -0.24), (0.05, 0.10, -0.55), 0.04, 0.012, 0.03),
    ]
    for sgn in (-1.0, 1.0):
        for z, y in ((0.16, 0.08), (-0.08, 0.07)):
            p.append(C((0.08 * sgn, 0.16, z), (0.10 * sgn, 0.02, z + 0.02), 0.04, 0.025, 0.025))
        p.append(E((0.10 * sgn, 0.26, -0.02), (0.02, 0.045, 0.025), 0.02))
    s.mc("Body", skin, p, amp=0.006, freq=7.0, res=64)
    # keratin plates along the back
    for i, z in enumerate(np.linspace(0.20, -0.18, 6)):
        v, f, n = sphere((0, 0.38 - i * 0.012, z), (0.12 - i * 0.01, 0.045, 0.06), 1)
        s.add("Plate", skin, v, f)
    v, f, n = sphere((0.0, 0.18, 0.44), (0.015, 0.015, 0.015), 0)
    s.add("Nose", "snout", v, f)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.035 * sgn, 0.20, 0.36), (0.012, 0.012, 0.01), 0)
        s.add("Eye", "char", v, f, vcol=np.ones((len(v), 3)) * 0.4)
    return s


def build_heap():
    s = Sculpt()
    p = [
        E((0, 1.35, 0.0), (0.62, 0.55, 0.42), 0.12),
        E((0, 1.85, 0.02), (0.38, 0.32, 0.30), 0.1),
        E((0, 0.85, 0.0), (0.42, 0.28, 0.32), 0.08),
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.40 * sgn, 1.45, 0.0), (0.72 * sgn, 0.85, 0.05), 0.20, 0.14, 0.08))
        p.append(E((0.78 * sgn, 0.72, 0.08), (0.16, 0.12, 0.14), 0.05))
        p.append(C((0.22 * sgn, 0.85, 0.0), (0.28 * sgn, 0.12, 0.04), 0.22, 0.16, 0.08))
        p.append(E((0.30 * sgn, 0.08, 0.06), (0.20, 0.08, 0.24), 0.04))
        # rubble lumps
        p.append(E((0.35 * sgn, 1.7, 0.15), (0.16, 0.14, 0.12), 0.05))
    p.append(E((0.0, 2.15, 0.0), (0.12, 0.10, 0.10), 0.04))
    s.mc("Body", "rubble", p, amp=0.02, freq=3.0, res=64)
    # violet seam on the back (-Z)
    v, f, n = tube((0.0, 1.05, -0.42), (0.0, 1.9, -0.36), 0.04, 0.02, 5)
    s.add("Seam", "violet", v, f, vcol=np.ones((len(v), 3)))
    v, f, n = tube((0.0, 1.15, 0.48), (0.02, 1.85, 0.40), 0.035, 0.018, 5)
    s.add("SeamFront", "violet", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_scorchling():
    s = Sculpt()
    # Low poly on purpose: the body test stays under 1500 tris.
    s.add("Torso", "char", *sphere((0, 0.36, 0), (0.16, 0.20, 0.13), 1))
    s.add("Head", "char", *sphere((0, 0.58, 0.02), (0.11, 0.10, 0.10), 1))
    s.add("Belly", "ember", *sphere((0, 0.36, 0.08), (0.07, 0.08, 0.04), 0))
    for sgn in (-1.0, 1.0):
        s.add("Arm", "char", *tube((0.10 * sgn, 0.42, 0.02), (0.22 * sgn, 0.24, 0.08), 0.045, 0.03, 6))
        s.add("Hand", "ember", *sphere((0.24 * sgn, 0.20, 0.10), (0.035, 0.03, 0.03), 0))
        s.add("Leg", "char", *tube((0.06 * sgn, 0.22, 0.0), (0.08 * sgn, 0.04, 0.02), 0.05, 0.035, 6))
        s.add("Horn", "char", *cone((0.05 * sgn, 0.64, 0.0), (0.10 * sgn, 0.80, -0.02), 0.028, 5))
        s.add("Eye", "ember", *sphere((0.035 * sgn, 0.60, 0.09), (0.016, 0.014, 0.012), 0))
    s.add("Flame", "flame", *cone((0, 0.70, 0.0), (0, 0.98, 0.0), 0.07, 7))
    s.add("FlameB", "flame", *cone((0.0, 0.66, -0.02), (-0.04, 0.88, -0.02), 0.04, 5))
    return s


def build_ooze():
    s = Sculpt()
    p = [
        E((0, 0.48, 0.0), (0.78, 0.46, 0.62), 0.12),
        E((0.15, 0.55, 0.15), (0.28, 0.22, 0.22), 0.1),
        E((-0.2, 0.38, -0.05), (0.30, 0.20, 0.24), 0.1),
        E((0, 0.03, 0.05), (0.85, 0.035, 0.70), 0.04),
        SUB((0.12, 0.48, 0.42), (0.06, 0.05, 0.05), 0.03),
        SUB((-0.10, 0.50, 0.40), (0.055, 0.045, 0.045), 0.03),
        SUB((0.0, 0.36, 0.48), (0.10, 0.06, 0.05), 0.03),
    ]
    for i, x in enumerate((-0.45, -0.15, 0.2, 0.5)):
        p.append(C((x, 0.28, 0.35 - (i % 2) * 0.1), (x * 1.05, 0.02, 0.40), 0.05, 0.015, 0.04))
    s.mc("Body", "moss", p, amp=0.012, freq=3.0, res=60)
    return s


def build_dummy(water=False):
    s = Sculpt()
    mat = "water" if water else "earth"
    p = [
        E((0, 0.95, 0.0), (0.26, 0.32, 0.16), 0.06),
        E((0, 1.62, 0.02), (0.14, 0.16, 0.13), 0.04),
        E((0, 0.55, 0.0), (0.20, 0.16, 0.14), 0.05),
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.10 * sgn, 0.55, 0.0), (0.12 * sgn, 0.08, 0.02), 0.10, 0.08, 0.05))
        p.append(E((0.12 * sgn, 0.05, 0.04), (0.08, 0.05, 0.14), 0.03))
        p.append(C((0.24 * sgn, 1.15, 0.0), (0.30 * sgn, 0.72, 0.02), 0.07, 0.055, 0.045))
        p.append(E((0.32 * sgn, 0.64, 0.03), (0.055, 0.05, 0.05), 0.03))
    # slit where a face would be
    p.append(SUB((0, 1.50, 0.12), (0.07, 0.012, 0.02), 0.02))
    s.mc("Body", mat, p, amp=0.016 if not water else 0.01, freq=3.5, res=64)
    if water:
        for x in (-0.08, 0.1):
            v, f, n = tube((x, 1.15, 0.14), (x * 1.4, 0.72, 0.16), 0.012, 0.004, 4)
            s.add("Drip", "water_l", v, f)
    return s


def build_husk():
    s = Sculpt()
    p = [
        E((0, 0.78, 0.10), (0.28, 0.32, 0.18), 0.07),
        E((0, 1.15, 0.12), (0.16, 0.16, 0.14), 0.05),
        E((0, 1.22, 0.08), (0.20, 0.16, 0.16), 0.05),
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.08 * sgn, 0.62, 0.0), (0.14 * sgn, 0.08, 0.06), 0.09, 0.06, 0.045))
        p.append(E((0.16 * sgn, 0.05, 0.08), (0.08, 0.04, 0.16), 0.03))
        p.append(C((0.18 * sgn, 1.05, 0.04), (0.42 * sgn, 0.55, 0.16), 0.06, 0.03, 0.04))
        # vine fingers
        p.append(C((0.42 * sgn, 0.55, 0.16), (0.52 * sgn, 0.32, 0.22), 0.025, 0.012, 0.02))
    p.append(SUB((0, 1.16, 0.16), (0.06, 0.04, 0.04), 0.02))  # mouth
    s.mc("Body", "moss", p, amp=0.012, freq=4.0, res=66)
    # purple spots on the cap
    for x, z in ((0.2, 0.1), (-0.15, 0.2), (0.05, -0.25), (-0.28, -0.05), (0.3, -0.12)):
        v, f, n = sphere((x, 1.68, z), (0.06, 0.025, 0.05), 0)
        s.add("Spot", "cap_s", v, f)
    v, f, n = sphere((0, 1.34, 0.06), (0.58, 0.26, 0.48), 1)
    s.add("Cap", "cap", v, f)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.04 * sgn, 1.26, 0.12), (0.018, 0.016, 0.012), 0)
        s.add("Eye", "eye_p", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_treant():
    s = Sculpt()
    p = [
        E((0, 1.55, 0.0), (0.55, 0.70, 0.36), 0.1),
        E((0, 2.35, 0.06), (0.28, 0.32, 0.24), 0.08),
        E((0, 0.7, 0.0), (0.40, 0.35, 0.28), 0.08),
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.28 * sgn, 1.3, 0.0), (0.55 * sgn, 0.15, 0.05), 0.22, 0.14, 0.08))
        p.append(E((0.62 * sgn, 0.08, 0.08), (0.22, 0.08, 0.28), 0.04))
        p.append(C((0.40 * sgn, 1.9, 0.05), (0.85 * sgn, 1.15, 0.15), 0.12, 0.07, 0.06))
        p.append(C((0.15 * sgn, 2.55, 0.0), (0.45 * sgn, 3.15, -0.05), 0.06, 0.02, 0.04))
        p.append(C((0.05 * sgn, 2.6, 0.05), (0.15 * sgn, 3.25, 0.1), 0.05, 0.015, 0.035))
    # beard of roots
    for x in (-0.12, 0.0, 0.12):
        p.append(C((x, 2.15, 0.18), (x * 1.4, 1.55, 0.28), 0.035, 0.012, 0.03))
    p.append(SUB((0, 2.25, 0.22), (0.10, 0.06, 0.05), 0.03))
    s.mc("Body", "bark", p, amp=0.02, freq=2.4, res=60)
    # moss on the shoulders
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.35 * sgn, 2.05, 0.05), (0.22, 0.10, 0.16), 1)
        s.add("Moss", "moss", v, f)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.08 * sgn, 2.40, 0.20), (0.035, 0.03, 0.02), 0)
        s.add("Eye", "ember", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_beast():
    s = Sculpt()
    p = [
        E((0, 1.05, 0.05), (0.38, 0.32, 0.28), 0.08),
        E((0, 1.45, 0.12), (0.20, 0.18, 0.18), 0.05),
        E((0, 1.15, -0.15), (0.22, 0.28, 0.16), 0.06),  # hunched back
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.22 * sgn, 0.85, 0.05), (0.32 * sgn, 0.12, 0.08), 0.14, 0.09, 0.06))
        p.append(E((0.34 * sgn, 0.06, 0.10), (0.12, 0.05, 0.16), 0.03))
        # long arms
        p.append(C((0.28 * sgn, 1.25, 0.08), (0.48 * sgn, 0.55, 0.22), 0.09, 0.05, 0.05))
        p.append(E((0.52 * sgn, 0.48, 0.26), (0.07, 0.05, 0.08), 0.03))
        # stalks
        p.append(C((0.12 * sgn, 1.55, -0.08), (0.22 * sgn, 2.15, -0.12), 0.05, 0.09, 0.04))
        p.append(E((0.24 * sgn, 2.22, -0.12), (0.10, 0.06, 0.10), 0.03))
    p.append(SUB((0, 1.38, 0.26), (0.08, 0.045, 0.04), 0.025))
    s.mc("Body", "fungus", p, amp=0.012, freq=3.5, res=62)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.07 * sgn, 1.50, 0.24), (0.03, 0.028, 0.02), 0)
        s.add("Eye", "eye_p", v, f, vcol=np.ones((len(v), 3)))
    v, f, n = sphere((0, 1.32, 0.26), (0.09, 0.035, 0.02), 0)
    s.add("Teeth", "tooth", v, f)
    return s


def build_troll():
    s = Sculpt()
    p = [
        E((0, 1.25, 0.05), (0.55, 0.48, 0.34), 0.1),
        E((0, 1.85, 0.08), (0.28, 0.28, 0.24), 0.07),
        E((0, 1.05, 0.12), (0.42, 0.28, 0.26), 0.08),  # gut
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.28 * sgn, 1.15, 0.02), (0.40 * sgn, 0.15, 0.06), 0.20, 0.14, 0.07))
        p.append(E((0.42 * sgn, 0.08, 0.08), (0.18, 0.07, 0.24), 0.04))
        p.append(C((0.16 * sgn, 1.95, 0.08), (0.42 * sgn, 2.42, -0.04), 0.11, 0.04, 0.05))
    # spiked right fist, heavier
    p.append(C((0.45, 1.55, 0.1), (0.78, 1.25, 0.22), 0.16, 0.14, 0.06))
    p.append(E((0.88, 1.15, 0.26), (0.16, 0.14, 0.16), 0.04))
    p.append(C((-0.42, 1.55, 0.05), (-0.7, 1.05, 0.12), 0.14, 0.1, 0.05))
    p.append(SUB((0, 1.78, 0.28), (0.10, 0.06, 0.05), 0.03))
    s.mc("Body", "troll", p, amp=0.016, freq=3.0, res=60)
    # lava cracks
    cracks = [
        ((0.0, 1.15, 0.36), (0.05, 1.7, 0.30)),
        ((-0.15, 1.0, 0.32), (0.1, 1.45, 0.34)),
        ((0.2, 0.9, 0.30), (0.05, 1.3, 0.33)),
        ((0.0, 1.7, 0.28), (0.0, 1.95, 0.22)),
    ]
    for i, (a, b) in enumerate(cracks):
        v, f, n = tube(a, b, 0.025, 0.012, 4)
        s.add(f"Crack{i}", "lava", v, f, vcol=np.ones((len(v), 3)))
    v, f, n = sphere((0, 1.74, 0.26), (0.08, 0.045, 0.03), 0)
    s.add("Mouth", "lava", v, f, vcol=np.ones((len(v), 3)))
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.08 * sgn, 1.92, 0.18), (0.03, 0.025, 0.02), 0)
        s.add("Eye", "lava", v, f, vcol=np.ones((len(v), 3)))
    return s


def build_forge():
    s = Sculpt()
    p = [
        BX((0, 1.55, 0.0), (0.62, 0.55, 0.42), 0.08, 0.06),
        BX((0, 2.15, -0.05), (0.38, 0.28, 0.32), 0.06, 0.05),
        BX((0, 0.85, 0.0), (0.48, 0.28, 0.36), 0.06, 0.05),
        BX((-0.55, 2.35, -0.05), (0.14, 0.22, 0.14), 0.04, 0.03),
        BX((0.55, 2.45, -0.02), (0.12, 0.28, 0.12), 0.04, 0.03),
        SUBB((0, 1.65, 0.36), (0.28, 0.32, 0.18), 0.04),
    ]
    for sgn in (-1.0, 1.0):
        p.append(BX((0.72 * sgn, 1.35, 0.02), (0.16, 0.42, 0.16), 0.05, 0.04))
        p.append(BX((0.78 * sgn, 0.85, 0.08), (0.14, 0.18, 0.14), 0.04, 0.03))
        p.append(BX((0.28 * sgn, 0.40, 0.04), (0.20, 0.38, 0.20), 0.05, 0.04))
        p.append(BX((0.30 * sgn, 0.08, 0.06), (0.22, 0.08, 0.26), 0.03, 0.03))
    s.mc("Body", "iron", p, amp=0.006, freq=2.0, res=58)
    v, f, n = sphere((0, 1.62, 0.22), (0.22, 0.24, 0.08), 1)
    s.add("Core", "lava", v, f, vcol=np.ones((len(v), 3)))
    v, f, n = tube((0.0, 1.35, 0.40), (0.04, 0.55, 0.42), 0.04, 0.015, 5)
    s.add("Drip", "lava", v, f, vcol=np.ones((len(v), 3)))
    v, f, n = tube((0.7, 1.15, 0.2), (0.95, 0.55, 0.25), 0.02, 0.015, 4)
    s.add("Chain", "iron", v, f)
    return s


def build_cultist():
    s = Sculpt()
    p = [
        E((0, 0.95, 0.08), (0.26, 0.32, 0.16), 0.06),
        E((0, 1.45, 0.16), (0.13, 0.16, 0.13), 0.045),
        E((0, 0.7, 0.18), (0.22, 0.18, 0.16), 0.05),  # crouched thigh mass
    ]
    # reaching arms
    p.append(C((0.2, 1.15, 0.1), (0.55, 0.85, 0.45), 0.07, 0.035, 0.04))
    p.append(C((-0.18, 1.2, 0.08), (-0.15, 0.7, 0.35), 0.07, 0.04, 0.04))
    for sgn, z in ((1.0, 0.45), (-1.0, 0.35)):
        p.append(E((0.58 * sgn if sgn > 0 else -0.18, 0.78 if sgn > 0 else 0.62, z), (0.05, 0.03, 0.07), 0.02))
    for sgn in (-1.0, 1.0):
        p.append(C((0.08 * sgn, 0.55, 0.15), (0.16 * sgn, 0.06, 0.28), 0.08, 0.05, 0.04))
        p.append(E((0.18 * sgn, 0.04, 0.32), (0.07, 0.035, 0.14), 0.025))
    # kelp cloak
    p.append(E((0, 1.15, -0.08), (0.32, 0.45, 0.10), 0.08))
    for x in (-0.2, -0.05, 0.12, 0.24):
        p.append(C((x, 1.3, -0.02), (x * 1.1, 0.35, 0.05), 0.03, 0.01, 0.03))
    # coral on the shoulder
    p.append(C((0.12, 1.45, -0.06), (0.2, 1.95, -0.1), 0.04, 0.02, 0.03))
    p.append(C((0.05, 1.55, -0.02), (-0.05, 2.05, -0.08), 0.035, 0.015, 0.03))
    p.append(SUB((0, 1.42, 0.26), (0.05, 0.035, 0.03), 0.02))
    s.mc("Body", "flesh", p, amp=0.01, freq=4.0, res=64)
    v, f, n = sphere((0.12, 1.7, -0.08), (0.10, 0.16, 0.08), 1)
    s.add("Coral", "coral", v, f)
    v, f, n = sphere((0, 1.15, -0.12), (0.34, 0.40, 0.08), 1)
    s.add("Kelp", "kelp", v, f)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.04 * sgn, 1.50, 0.24), (0.016, 0.014, 0.01), 0)
        s.add("Eye", "water_l", v, f)
    return s


def build_harpy():
    s = Sculpt()
    p = [
        E((0, 0.95, 0.02), (0.16, 0.28, 0.12), 0.05),
        E((0, 1.32, 0.08), (0.10, 0.12, 0.11), 0.04),
        C((0, 1.28, 0.12), (0, 1.22, 0.28), 0.04, 0.015, 0.03),  # beak base in the body
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.08 * sgn, 0.75, 0.0), (0.12 * sgn, 0.15, 0.06), 0.07, 0.045, 0.04))
        # talons
        p.append(E((0.12 * sgn, 0.05, 0.10), (0.05, 0.03, 0.10), 0.02))
        p.append(C((0.14 * sgn, 1.05, 0.06), (0.28 * sgn, 0.85, 0.22), 0.045, 0.025, 0.03))
    # tail
    p.append(C((0, 0.8, -0.08), (0, 0.55, -0.55), 0.06, 0.02, 0.04))
    s.mc("Body", "feather", p, amp=0.006, freq=5.0, res=60)
    # crest
    v, f, n = cone((0, 1.40, 0.0), (0, 1.62, -0.08), 0.035, 5)
    s.add("Crest", "feather", v, f)
    v, f, n = cone((0, 1.26, 0.16), (0, 1.22, 0.34), 0.025, 5)
    s.add("Beak", "tooth", v, f)
    for sgn in (-1.0, 1.0):
        v, f, n = wing_blade(sgn)
        s.add("Wing" if sgn > 0 else "WingL", "feather", v, f, double=True)
    for i, x in enumerate(np.linspace(-0.12, 0.12, 4)):
        v, f, n = feather((x, 0.7, -0.15), (x * 1.8, 0.45, -0.7), 0.08)
        s.add(f"Tail{i}", "feather", v, f, double=True)
    for sgn in (-1.0, 1.0):
        v, f, n = sphere((0.035 * sgn, 1.36, 0.12), (0.014, 0.012, 0.01), 0)
        s.add("Eye", "char", v, f, vcol=np.ones((len(v), 3)) * 0.25)
    return s


def build_storm():
    s = Sculpt()
    # A crystal body: a fused core plus hard shards.
    p = [
        E((0, 1.15, 0.0), (0.28, 0.55, 0.22), 0.1),
        E((0, 1.85, 0.02), (0.18, 0.35, 0.16), 0.08),
    ]
    for sgn in (-1.0, 1.0):
        p.append(C((0.15 * sgn, 1.2, 0.05), (0.40 * sgn, 0.7, 0.1), 0.10, 0.06, 0.06))
        p.append(C((0.12 * sgn, 0.7, 0.02), (0.16 * sgn, 0.08, 0.04), 0.10, 0.07, 0.05))
    s.mc("Core", "crystal", p, amp=0.008, freq=2.5, res=52)
    rng = np.random.default_rng(5)
    for i in range(28):
        side = 1.0 if i % 2 == 0 else -1.0
        base = np.array([
            side * rng.uniform(0.0, 0.22),
            rng.uniform(0.35, 2.05),
            rng.uniform(-0.16, 0.16),
        ])
        tip = base + np.array([
            side * rng.uniform(0.25, 0.7),
            rng.uniform(0.15, 0.85),
            rng.uniform(-0.25, 0.25),
        ])
        v, f, n = cone(base, tip, rng.uniform(0.05, 0.12), 5)
        s.add(f"Shard{i}", "crystal", v, f)
    # crown shards
    for i, x in enumerate(np.linspace(-0.2, 0.2, 5)):
        v, f, n = cone((x, 2.05, 0.0), (x * 1.4, 2.55 + abs(x), -0.05), 0.07, 5)
        s.add(f"Crown{i}", "crystal", v, f)
    # wind ribbons
    for i, phase in enumerate((0.0, 1.2, 2.4)):
        pts = []
        for t in np.linspace(0, 1, 8):
            ang = phase + t * 3.2
            y = 0.4 + t * 1.8
            r = 0.45 + 0.15 * np.sin(t * np.pi)
            pts.append((np.cos(ang) * r, y, np.sin(ang) * r * 0.6))
        for a, b in zip(pts, pts[1:]):
            v, f, n = tube(a, b, 0.025, 0.018, 4)
            s.add(f"Wind{i}", "wind", v, f, vcol=np.ones((len(v), 3)), double=True)
    v, f, n = sphere((0, 1.55, 0.12), (0.10, 0.14, 0.08), 1)
    s.add("Heart", "eye_p", v, f, vcol=np.ones((len(v), 3)))
    return s


BUILDERS = {
    "goblin_grunt": build_goblin_grunt,
    "goblin_archer": build_goblin_archer,
    "goblin_shaman": build_goblin_shaman,
    "gnawer_mangy": lambda: build_gnawer(False),
    "gnawer_plague": lambda: build_gnawer(True),
    "heap": build_heap,
    "scorchling": build_scorchling,
    "ooze": build_ooze,
    "dummy_earth": lambda: build_dummy(False),
    "dummy_tidal": lambda: build_dummy(True),
    "spore_husk": build_husk,
    "mossbound_treant": build_treant,
    "spore_beast": build_beast,
    "branded_troll": build_troll,
    "forge_construct": build_forge,
    "drowned_cultist": build_cultist,
    "harpy": build_harpy,
    "storm_elemental": build_storm,
}

MATERIALS = {
    "goblin_skin": {"color": SKIN, "rough": 0.72, "metal": 0.0},
    "goblin_skin_y": {"color": SKIN_Y, "rough": 0.72, "metal": 0.0},
    "leather": {"color": LEATHER, "rough": 0.82, "metal": 0.0},
    "robe": {"color": ROBE, "rough": 0.8, "metal": 0.0},
    "bowwood": {"color": BOW, "rough": 0.7, "metal": 0.0},
    "rust": {"color": RUST, "rough": 0.48, "metal": 0.45},
    "bone": {"color": BONE, "rough": 0.55, "metal": 0.0},
    "eye_g": {"color": EYE_G, "rough": 0.25, "metal": 0.0, "emit": EYE_G, "strength": 1.6},
    "plate": {"color": PLATE, "rough": 0.62, "metal": 0.08},
    "plate_g": {"color": (0.42, 0.44, 0.40), "rough": 0.6, "metal": 0.05},
    "snout": {"color": SNOUT, "rough": 0.55, "metal": 0.0},
    "char": {"color": CHAR, "rough": 0.85, "metal": 0.0},
    "rubble": {"color": RUBBLE, "rough": 0.9, "metal": 0.0},
    "violet": {"color": VIOLET, "rough": 0.3, "metal": 0.0, "emit": VIOLET, "strength": 0.9},
    "ember": {"color": EMBER, "rough": 0.4, "metal": 0.0, "emit": EMBER, "strength": 1.1},
    "flame": {"color": (1.0, 0.72, 0.25), "rough": 0.35, "metal": 0.0, "emit": EMBER, "strength": 1.2},
    "moss": {"color": MOSS, "rough": 0.45, "metal": 0.0},
    "earth": {"color": EARTH, "rough": 0.92, "metal": 0.0},
    "water": {"color": WATER, "rough": 0.22, "metal": 0.04},
    "water_l": {"color": WATER_L, "rough": 0.18, "metal": 0.0},
    "cap": {"color": CAP, "rough": 0.7, "metal": 0.0},
    "cap_s": {"color": CAP_S, "rough": 0.55, "metal": 0.0},
    "bark": {"color": BARK, "rough": 0.86, "metal": 0.0},
    "fungus": {"color": FUNGUS, "rough": 0.7, "metal": 0.0},
    "eye_p": {"color": EYE_P, "rough": 0.25, "metal": 0.0, "emit": EYE_P, "strength": 2.2},
    "tooth": {"color": TOOTH, "rough": 0.4, "metal": 0.05},
    "troll": {"color": TROLL, "rough": 0.78, "metal": 0.02},
    "lava": {"color": LAVA, "rough": 0.35, "metal": 0.0, "emit": LAVA, "strength": 1.0},
    "iron": {"color": IRON, "rough": 0.42, "metal": 0.72},
    "flesh": {"color": FLESH, "rough": 0.7, "metal": 0.0},
    "kelp": {"color": KELP, "rough": 0.55, "metal": 0.0},
    "coral": {"color": CORAL, "rough": 0.6, "metal": 0.0},
    "feather": {"color": FEATHER, "rough": 0.68, "metal": 0.0},
    "crystal": {"color": CRYSTAL, "rough": 0.18, "metal": 0.12, "emit": (0.45, 0.40, 0.7), "strength": 0.6},
    "wind": {"color": (0.75, 0.72, 0.95), "rough": 0.2, "metal": 0.0, "emit": (0.55, 0.5, 0.85), "strength": 0.5, "alpha": 0.55},
}


class Blob:
    def __init__(self):
        self.buf = bytearray()

    def pad(self, n=4):
        while len(self.buf) % n:
            self.buf.append(0)

    def add(self, data: bytes) -> int:
        self.pad(4)
        off = len(self.buf)
        self.buf += data
        return off


def export_glb(path: Path, sculpt: Sculpt) -> None:
    used = []
    for part in sculpt.parts:
        if part[1] not in used:
            used.append(part[1])
    materials = []
    for name in used:
        spec = MATERIALS[name]
        color = [float(x) for x in lin(spec["color"])]
        alpha = float(spec.get("alpha", 1.0))
        mat = {
            "name": name,
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": color + [alpha],
                "metallicFactor": float(spec["metal"]),
                "roughnessFactor": float(spec["rough"]),
            },
        }
        if alpha < 1.0:
            mat["alphaMode"] = "BLEND"
        if "emit" in spec:
            mat["emissiveFactor"] = [float(x) for x in lin(spec["emit"])]
            mat["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": float(spec["strength"])}}
        materials.append(mat)
    blob = Blob()
    views = []
    accessors = []
    meshes = []
    nodes = []
    for name, mat_name, verts, faces, normals, vcol, _double in sculpt.parts:
        # drop degenerate
        if len(faces) == 0:
            continue
        idx = faces.reshape(-1).astype(np.uint32)
        v = verts.astype(np.float32)
        n = normals.astype(np.float32)
        c = np.clip(vcol, 0, 1).astype(np.float32)
        if c.shape[1] == 1:
            c = np.repeat(c, 3, axis=1)
        attr = {}
        for key, arr, typ, comps in (
            ("POSITION", v, "VEC3", 3),
            ("NORMAL", n, "VEC3", 3),
            ("COLOR_0", c, "VEC3", 3),
        ):
            raw = arr.tobytes()
            off = blob.add(raw)
            views.append({"buffer": 0, "byteOffset": off, "byteLength": len(raw), "target": 34962})
            acc = {
                "bufferView": len(views) - 1,
                "componentType": 5126,
                "count": len(arr),
                "type": typ,
            }
            if key == "POSITION":
                acc["min"] = v.min(0).tolist()
                acc["max"] = v.max(0).tolist()
            attr[key] = len(accessors)
            accessors.append(acc)
        raw = idx.tobytes()
        off = blob.add(raw)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(raw), "target": 34963})
        accessors.append({
            "bufferView": len(views) - 1,
            "componentType": 5125,
            "count": int(idx.size),
            "type": "SCALAR",
        })
        meshes.append({
            "name": name,
            "primitives": [{
                "attributes": attr,
                "indices": len(accessors) - 1,
                "material": used.index(mat_name),
            }],
        })
        nodes.append({"name": name, "mesh": len(meshes) - 1})
    root_i = len(nodes)
    nodes.append({"name": path.stem, "children": list(range(root_i))})
    blob.pad(4)
    gltf = {
        "asset": {"version": "2.0", "generator": "tools/build_regular_enemies.py"},
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "scene": 0,
        "scenes": [{"nodes": [root_i]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
        "accessors": accessors,
        "bufferViews": views,
        "buffers": [{"byteLength": len(blob.buf)}],
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


def preview(sculpt: Sculpt, path: Path, height_hint: float) -> None:
    from PIL import Image
    w, h = 640, 480
    img = np.zeros((h, w, 3), np.float32)
    img[:] = (0.79, 0.68, 0.50)
    zbuf = np.full((h, w), np.inf, np.float32)
    # metres to pixels. Leave room for a 1.8 m post on the left.
    margin = 36
    usable_h = h - 2 * margin
    scale = usable_h / max(height_hint, 1.8) * 0.92
    feet_y = h - margin
    # creature centred right, figure at x = 70
    def project(verts, x_shift):
        sx = w * 0.62 + (verts[:, 0] + x_shift) * scale
        sy = feet_y - verts[:, 1] * scale
        return sx, sy
    # 1.8 m figure: a simple posts-and-shoulders silhouette
    fig = [
        ((-0.18, 0.0), (0.18, 0.0), (0.16, 1.45), (-0.16, 1.45)),
        ((-0.16, 1.45), (0.16, 1.45), (0.13, 1.8), (-0.13, 1.8)),
    ]
    def paint_tri(p0, p1, p2, color, light):
        xs = np.array([p0[0], p1[0], p2[0]])
        ys = np.array([p0[1], p1[1], p2[1]])
        zs = np.array([p0[2], p1[2], p2[2]])
        minx = max(int(np.floor(xs.min())), 0)
        maxx = min(int(np.ceil(xs.max())), w - 1)
        miny = max(int(np.floor(ys.min())), 0)
        maxy = min(int(np.ceil(ys.max())), h - 1)
        if minx >= maxx or miny >= maxy:
            return
        area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
        if abs(area) < 1e-6:
            return
        ys_i, xs_i = np.mgrid[miny:maxy + 1, minx:maxx + 1]
        x = xs_i + 0.5
        y = ys_i + 0.5
        w0 = (xs[1] - x) * (ys[2] - y) - (xs[2] - x) * (ys[1] - y)
        w1 = (xs[2] - x) * (ys[0] - y) - (xs[0] - x) * (ys[2] - y)
        w2 = (xs[0] - x) * (ys[1] - y) - (xs[1] - x) * (ys[0] - y)
        if area < 0:
            w0, w1, w2 = -w0, -w1, -w2
            area = -area
        mask = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not np.any(mask):
            return
        z = (w0 * zs[0] + w1 * zs[1] + w2 * zs[2]) / area
        dest_z = zbuf[miny:maxy + 1, minx:maxx + 1]
        hit = mask & (z < dest_z)
        if not np.any(hit):
            return
        dest_z[hit] = z[hit]
        zbuf[miny:maxy + 1, minx:maxx + 1] = dest_z
        pix = img[miny:maxy + 1, minx:maxx + 1]
        pix[hit] = color * light
        img[miny:maxy + 1, minx:maxx + 1] = pix
    # figure on the left, same scale, feet aligned
    fig_cx = w * 0.16
    def px(x, y):
        return (fig_cx + x * scale, feet_y - y * scale, 0.0)
    for quad in fig:
        a, b, c, d = [px(*p) for p in quad]
        paint_tri(a, b, c, np.array((0.25, 0.18, 0.12)), 0.9)
        paint_tri(a, c, d, np.array((0.25, 0.18, 0.12)), 0.9)
    # A point splat is enough to judge silhouette and scale before the Godot turntable.
    order = np.argsort(np.concatenate([p[2][:, 2] for p in sculpt.parts]))
    # draw far vertices first by walking parts sorted on mean z
    parts_sorted = sorted(sculpt.parts, key=lambda p: float(p[2][:, 2].mean()))
    for name, mat, verts, faces, normals, vcol, _d in parts_sorted:
        base = np.asarray(lin(MATERIALS[mat]["color"]), np.float32)
        sx, sy = project(verts, 0.0)
        light = 0.45 + 0.55 * np.clip(normals @ np.array([0.2, 0.6, 0.7]), 0, 1)
        col = (base * vcol.mean(axis=1)[:, None]) * light[:, None]
        xi = np.clip(sx.astype(np.int32), 0, w - 1)
        yi = np.clip(sy.astype(np.int32), 0, h - 1)
        img[yi, xi] = col
        img[np.clip(yi + 1, 0, h - 1), xi] = col
        img[yi, np.clip(xi + 1, 0, w - 1)] = col
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(img * 255, 0, 255).astype(np.uint8), "RGB").save(path)


def main() -> int:
    only = ""
    preview_dir = ""
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--only":
            only = args[i + 1]
            i += 2
        elif args[i] == "--preview":
            preview_dir = args[i + 1]
            i += 2
        else:
            print("unknown", args[i])
            return 2
    for name, fn in BUILDERS.items():
        if only and only not in name:
            continue
        sculpt = fn()
        path = OUT / f"{name}.glb"
        export_glb(path, sculpt)
        heights = {
            "goblin_grunt": 1.42, "goblin_archer": 1.46, "goblin_shaman": 1.7,
            "gnawer_mangy": 0.45, "gnawer_plague": 0.45, "heap": 2.55,
            "scorchling": 1.05, "ooze": 1.0, "dummy_earth": 1.8, "dummy_tidal": 1.8,
            "spore_husk": 2.2, "mossbound_treant": 3.4, "spore_beast": 2.4,
            "branded_troll": 2.7, "forge_construct": 2.9, "drowned_cultist": 2.15,
            "harpy": 2.4, "storm_elemental": 2.8,
        }
        ys = []
        for part in sculpt.parts:
            ys.append(part[2][:, 1].min())
            ys.append(part[2][:, 1].max())
        print(f"{name:20s} tris {sculpt.tris():6d}  y {min(ys):.2f}..{max(ys):.2f}  -> {path.name}")
        if name == "scorchling" and sculpt.tris() >= 1500:
            print("scorchling over the tri budget", sculpt.tris())
            return 1
        if preview_dir:
            preview(sculpt, Path(preview_dir) / f"{name}.png", heights[name])
    return 0


if __name__ == "__main__":
    sys.exit(main())
