#!/usr/bin/env python3
"""Hero meshes for the seven bosses (phase 0.14.0).

Each sheet is masked, inflated to a solid, and projected back onto the mesh so the
front view keeps the painting's silhouette and palette. The result is one skinned
glTF with a rig and the phase nodes the bosses already look for. Original geometry,
CC0. Not a Godot primitive.

    python3 tools/build_boss_meshes.py
    python3 tools/build_boss_meshes.py the_filth
"""
from __future__ import annotations

import io
import json
import struct
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import binary_closing, binary_dilation, binary_fill_holes, binary_opening, distance_transform_edt, uniform_filter
from skimage.measure import marching_cubes
from skimage.transform import resize

ROOT = Path(__file__).resolve().parent.parent
SHEETS = ROOT / "docs" / "concepts" / "creatures"
OUT = ROOT / "assets" / "original" / "ember_art" / "bosses"
CROP_JSON = ROOT / "tools" / "boss_crops.json"

# crop is x0,y0,x1,y1 of the sheet. erase rects are fractions of that crop.
# height is metres, feet to the top of the silhouette, beside a 1.8 m figure.
BOSSES = [
    {"id": "the_filth", "file": "boss_the_filth.jpg", "crop": (0.15, 0.18, 0.64, 0.88), "back": None, "height": 5.6, "erase": []},
    {"id": "breach_warden", "file": "boss_breach_warden.jpg", "crop": (0.14, 0.17, 0.62, 0.88), "back": (0.66, 0.36, 0.98, 0.90), "height": 6.4, "erase": [(0.0, 0.0, 0.16, 0.28)]},
    {"id": "goblin_king", "file": "boss_goblin_king.jpg", "crop": (0.07, 0.15, 0.60, 0.70), "back": (0.63, 0.16, 0.93, 0.68), "height": 2.45, "erase": [(0.55, 0.0, 1.0, 0.10)]},
    {"id": "blightmaw_matriarch", "file": "boss_blightmaw_matriarch.jpg", "crop": (0.12, 0.15, 0.72, 0.88), "back": (0.72, 0.15, 0.98, 0.72), "height": 5.4, "erase": [(0.0, 0.0, 0.18, 0.16), (0.72, 0.0, 1.0, 0.18)]},
    {"id": "forgemaw", "file": "boss_forgemaw.jpg", "crop": (0.08, 0.14, 0.70, 0.86), "back": (0.74, 0.40, 0.98, 0.88), "height": 5.8, "erase": [(0.0, 0.62, 0.16, 1.0)]},
    {"id": "drowned_choir", "file": "boss_drowned_choir.jpg", "crop": (0.12, 0.13, 0.66, 0.90), "back": None, "height": 5.0, "erase": [(0.0, 0.0, 0.22, 0.16)]},
    {"id": "storm_warden", "file": "boss_storm_warden.jpg", "crop": (0.18, 0.13, 0.64, 0.88), "back": (0.62, 0.14, 0.94, 0.84), "height": 4.8, "erase": [(0.0, 0.0, 0.28, 0.22), (0.0, 0.55, 0.16, 0.78)]},
]


def _disk(r: int) -> np.ndarray:
    yy, xx = np.ogrid[-r : r + 1, -r : r + 1]
    return (yy * yy + xx * xx) <= r * r


def ink_mask(im: np.ndarray) -> np.ndarray:
    lum = im @ np.array([0.2126, 0.7152, 0.0722])
    blur = uniform_filter(lum, 21)
    ink = (blur - lum) > 0.075
    ink |= lum < 0.34
    disk = _disk(5)
    closed = binary_fill_holes(binary_closing(ink, structure=disk))
    core = binary_opening(closed, structure=disk)
    near = binary_dilation(core, structure=_disk(13))
    return closed & near


def shave(mask: np.ndarray) -> np.ndarray:
    """Drop leader lines: thin strokes that leave the solid body."""
    dist = distance_transform_edt(mask)
    core = dist >= 2.4
    near = binary_dilation(core, structure=_disk(8))
    return mask & near


def largest(mask: np.ndarray) -> np.ndarray:
    from scipy.ndimage import label

    lab, n = label(mask)
    if n == 0:
        return mask
    sizes = np.bincount(lab.ravel())
    sizes[0] = 0
    keep = lab == int(sizes.argmax())
    return binary_fill_holes(keep)


def crop_sheet(spec: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray | None]:
    im = np.asarray(Image.open(SHEETS / spec["file"]).convert("RGB")).astype(np.float32) / 255.0
    h, w, _ = im.shape
    x0, y0, x1, y1 = spec["crop"]
    sub = im[int(y0 * h) : int(y1 * h), int(x0 * w) : int(x1 * w)].copy()
    mask = ink_mask(sub)
    sh, sw = mask.shape
    for ex0, ey0, ex1, ey1 in spec.get("erase", []):
        mask[int(ey0 * sh) : int(ey1 * sh), int(ex0 * sw) : int(ex1 * sw)] = False
    mask = shave(largest(mask))
    back = None
    if spec.get("back"):
        bx0, by0, bx1, by1 = spec["back"]
        back = im[int(by0 * h) : int(by1 * h), int(bx0 * w) : int(bx1 * w)].copy()
    return sub, mask, back


def inpaint(img: np.ndarray, mask: np.ndarray) -> np.ndarray:
    if mask.all():
        return img
    _dist, inds = distance_transform_edt(~mask, return_indices=True)
    out = img.copy()
    holes = ~mask
    out[holes] = img[inds[0][holes], inds[1][holes]]
    return out


def glow_image(img: np.ndarray) -> np.ndarray:
    r, g, b = img[:, :, 0], img[:, :, 1], img[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    sat = img.max(-1) - img.min(-1)
    hot = ((r > 0.45) & (g > 0.28) & (b < 0.35) & (lum > 0.35)) | ((b > r + 0.05) & (b > 0.28) & (sat > 0.12))
    hot |= (r > 0.55) & (g < 0.35) & (lum > 0.3)
    em = np.zeros_like(img)
    em[hot] = np.clip(img[hot] * 1.4, 0, 1)
    return em


def build_volume(mask: np.ndarray, res_y: int = 168) -> tuple[np.ndarray, float]:
    h, w = mask.shape
    dist = distance_transform_edt(mask)
    scale = res_y / float(h)
    rw = max(16, int(round(w * scale)))
    mask_s = resize(mask.astype(np.float32), (res_y, rw), order=0, anti_aliasing=False) > 0.5
    dist_s = resize(dist.astype(np.float32), (res_y, rw), order=1, anti_aliasing=False) * scale
    # y = 0 at the feet
    mask_s = mask_s[::-1]
    dist_s = dist_s[::-1]
    depth = np.minimum(dist_s * 1.35, 0.5 * rw)
    zmax = int(np.ceil(depth.max())) + 2
    zs = np.arange(-zmax, zmax + 1)
    vol = (depth[None, :, :] >= np.abs(zs)[:, None, None]) & mask_s[None, :, :]
    vol = np.pad(vol.astype(np.float32), 1, constant_values=0)
    return vol, zmax


def mesh_from_mask(mask: np.ndarray, height: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    vol, zmax = build_volume(mask)
    verts, faces, _normals, _vals = marching_cubes(vol, level=0.5)
    # index order is (z, y, x), and the pad is 1
    z_i = verts[:, 0] - 1.0
    y_i = verts[:, 1] - 1.0
    x_i = verts[:, 2] - 1.0
    rh = vol.shape[1] - 2
    rw = vol.shape[2] - 2
    m_per = height / float(rh)
    # Image-left is local -X. After CharacterModel's 180 degree yaw, that lands on screen left.
    x = (x_i - 0.5 * rw) * m_per
    y = y_i * m_per
    z = (z_i - zmax) * m_per
    v = np.stack([x, y, z], axis=1).astype(np.float32)
    f = faces.astype(np.int32)
    y0 = float(v[:, 1].min())
    v[:, 1] -= y0
    span = float(v[:, 1].max())
    if span > 1e-4:
        v *= height / span
    center = v.mean(axis=0)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    outward = float(((v[f[:, 0]] - center) * fn).sum(axis=1).mean())
    if outward < 0:
        f = f[:, ::-1]
    n = recompute_normals(v, f)
    return v, f, n


def recompute_normals(v: np.ndarray, f: np.ndarray) -> np.ndarray:
    n = np.zeros_like(v)
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    for k in range(3):
        np.add.at(n, f[:, k], fn)
    lens = np.linalg.norm(n, axis=1, keepdims=True)
    lens[lens < 1e-8] = 1.0
    return (n / lens).astype(np.float32)


def uvs_for(v: np.ndarray, _span_x: float, height: float) -> np.ndarray:
    xmin = float(v[:, 0].min()) if len(v) else 0.0
    xmax = float(v[:, 0].max()) if len(v) else 1.0
    u = (v[:, 0] - xmin) / max(xmax - xmin, 1e-4)
    vv = 1.0 - np.clip(v[:, 1] / max(height, 1e-4), 0.0, 1.0)
    return np.stack([np.clip(u, 0, 1), vv], axis=1).astype(np.float32)


def displace(v: np.ndarray, f: np.ndarray, img: np.ndarray, mask: np.ndarray, height: float) -> tuple[np.ndarray, np.ndarray]:
    span_x = float(v[:, 0].max() - v[:, 0].min())
    uv = uvs_for(v, span_x, height)
    h, w, _ = img.shape
    lum = img @ np.array([0.2126, 0.7152, 0.0722])
    dist = distance_transform_edt(mask)
    cols = np.clip((uv[:, 0] * (w - 1)).astype(np.int32), 0, w - 1)
    rows = np.clip((uv[:, 1] * (h - 1)).astype(np.int32), 0, h - 1)
    sample = lum[rows, cols]
    edge = dist[rows, cols] < 2.5
    n = recompute_normals(v, f)
    # Bright paint comes forward; dark cracks sink. The silhouette edge stays put.
    delta = (sample - float(sample.mean())) * height * 0.035
    delta[edge] = 0.0
    v = v + n * delta[:, None].astype(np.float32)
    y0 = float(v[:, 1].min())
    v[:, 1] -= y0
    return v.astype(np.float32), recompute_normals(v, f)


def split_faces(v: np.ndarray, f: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    fn = np.cross(v[f[:, 1]] - v[f[:, 0]], v[f[:, 2]] - v[f[:, 0]])
    nz = fn[:, 2]
    return f[nz >= -0.02], f[nz < -0.02]


def compact(v: np.ndarray, f: np.ndarray, extra: list[np.ndarray]) -> tuple[np.ndarray, np.ndarray, list[np.ndarray]]:
    if len(f) == 0:
        empty = [np.zeros((0, a.shape[1]), dtype=a.dtype) for a in extra]
        return v[:0], f, empty
    used = np.unique(f.ravel())
    remap = np.full(len(v), -1, dtype=np.int32)
    remap[used] = np.arange(len(used), dtype=np.int32)
    return v[used], remap[f], [a[used] for a in extra]


def bones_for(v: np.ndarray) -> list[dict]:
    xmin, ymin, _zmin = v.min(axis=0)
    xmax, ymax, _zmax = v.max(axis=0)
    cx = float((xmin + xmax) * 0.5)
    h = float(ymax - ymin)
    w = float(max(xmax - xmin, 0.2))
    bones: list[dict] = []

    def add(name: str, parent: int, world: np.ndarray) -> int:
        local = world if parent < 0 else world - bones[parent]["world"]
        bones.append({"name": name, "parent": parent, "local": local.astype(np.float64), "world": world.astype(np.float64)})
        return len(bones) - 1

    hips = add("Hips", -1, np.array([cx, ymin + 0.40 * h, 0.0]))
    spine = add("Spine", hips, np.array([cx, ymin + 0.55 * h, 0.0]))
    chest = add("Chest", spine, np.array([cx, ymin + 0.70 * h, 0.0]))
    add("Head", chest, np.array([cx, ymin + 0.86 * h, 0.02 * h]))
    for sign, side in ((-1.0, "L"), (1.0, "R")):
        shoulder = add(f"UpperArm.{side}", chest, np.array([cx + sign * 0.28 * w, ymin + 0.66 * h, 0.04 * h]))
        elbow = add(f"LowerArm.{side}", shoulder, np.array([cx + sign * 0.40 * w, ymin + 0.52 * h, 0.08 * h]))
        add(f"Hand.{side}", elbow, np.array([cx + sign * 0.46 * w, ymin + 0.40 * h, 0.10 * h]))
    for sign, side in ((-1.0, "L"), (1.0, "R")):
        thigh = add(f"UpperLeg.{side}", hips, np.array([cx + sign * 0.12 * w, ymin + 0.26 * h, 0.0]))
        knee = add(f"LowerLeg.{side}", thigh, np.array([cx + sign * 0.12 * w, ymin + 0.13 * h, 0.01 * h]))
        add(f"Foot.{side}", knee, np.array([cx + sign * 0.13 * w, ymin + 0.0, 0.04 * h]))
    return bones


def bind_weights(v: np.ndarray, bones: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    centers = np.stack([b["world"] for b in bones], axis=0)
    d = np.linalg.norm(v[:, None, :] - centers[None, :, :], axis=2)
    nearest = np.argpartition(d, 2, axis=1)[:, :2]
    joints = nearest.astype(np.uint16)
    w = np.zeros((len(v), 2), dtype=np.float32)
    for i in range(len(v)):
        ds = d[i, nearest[i]]
        inv = 1.0 / np.maximum(ds, 1e-3)
        w[i] = inv / inv.sum()
    joints4 = np.zeros((len(v), 4), dtype=np.uint16)
    weights4 = np.zeros((len(v), 4), dtype=np.float32)
    joints4[:, :2] = joints
    weights4[:, :2] = w
    return joints4, weights4


def quat(axis: str, ang: float) -> list[float]:
    s = np.sin(ang * 0.5)
    c = float(np.cos(ang * 0.5))
    xyz = {"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis]
    return [xyz[0] * s, xyz[1] * s, xyz[2] * s, c]


def clips() -> list[dict]:
    idle = {"Spine": [(0, quat("x", 0)), (1.0, quat("x", 0.05)), (2.0, quat("x", 0))]}
    walk = {
        "UpperLeg.L": [(0, quat("x", 0.25)), (0.5, quat("x", -0.25)), (1.0, quat("x", 0.25))],
        "UpperLeg.R": [(0, quat("x", -0.25)), (0.5, quat("x", 0.25)), (1.0, quat("x", -0.25))],
        "UpperArm.L": [(0, quat("y", -0.2)), (0.5, quat("y", 0.2)), (1.0, quat("y", -0.2))],
        "UpperArm.R": [(0, quat("y", 0.2)), (0.5, quat("y", -0.2)), (1.0, quat("y", 0.2))],
    }
    attack = {"UpperArm.R": [(0, quat("y", 0)), (0.25, quat("y", -0.9)), (0.55, quat("y", 0.4)), (0.8, quat("y", 0))]}
    throw = {"UpperArm.R": [(0, quat("y", 0.2)), (0.25, quat("y", -1.0)), (0.4, quat("y", 0.7)), (0.8, quat("y", 0.1))]}
    slam = {"Spine": [(0, quat("x", 0)), (0.35, quat("x", 0.35)), (0.7, quat("x", 0))]}
    roar = {"Chest": [(0, quat("x", 0)), (0.4, quat("x", -0.25)), (1.6, quat("x", -0.25)), (2.0, quat("x", 0))]}
    hurt = {"Spine": [(0, quat("z", 0)), (0.12, quat("z", 0.18)), (0.3, quat("z", 0))]}
    death = {"Hips": [(0, quat("x", 0)), (0.5, quat("x", 0.7)), (1.1, quat("x", 1.1))]}
    spore = {"Chest": [(0, quat("x", 0)), (0.3, quat("x", 0.3)), (0.8, quat("x", 0))]}
    named = [
        ("Idle", idle),
        ("Walk", walk),
        ("Run", walk),
        ("Attack", attack),
        ("Throw", throw),
        ("Slam", slam),
        ("Roar", roar),
        ("HitReact", hurt),
        ("Death", death),
        ("SporeSpray", spore),
    ]
    out = []
    for name, tracks in named:
        length = 0.0
        for keys in tracks.values():
            length = max(length, keys[-1][0])
        out.append({"name": name, "length": length, "tracks": tracks})
    return out


def ellipsoid(center, radii, seg=10) -> tuple[np.ndarray, np.ndarray]:
    verts = []
    for i in range(seg // 2 + 1):
        v = i / (seg // 2) * np.pi
        for j in range(seg):
            u = j / seg * 2 * np.pi
            verts.append(center + radii * np.array([np.sin(v) * np.cos(u), np.cos(v), np.sin(v) * np.sin(u)]))
    v = np.array(verts, dtype=np.float32)
    faces = []
    cols = seg
    rows = seg // 2
    for i in range(rows):
        for j in range(cols):
            a = i * cols + j
            b = i * cols + (j + 1) % cols
            c = (i + 1) * cols + j
            d = (i + 1) * cols + (j + 1) % cols
            faces.append((a, c, b))
            faces.append((b, c, d))
    return v, np.array(faces, dtype=np.int32)


def cone(base, tip, radius, seg=8) -> tuple[np.ndarray, np.ndarray]:
    base = np.asarray(base, dtype=np.float64)
    tip = np.asarray(tip, dtype=np.float64)
    axis = tip - base
    axis = axis / (np.linalg.norm(axis) + 1e-8)
    helper = np.array([0.0, 1.0, 0.0]) if abs(axis[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    side = np.cross(axis, helper)
    side = side / (np.linalg.norm(side) + 1e-8)
    up = np.cross(axis, side)
    ring = []
    for i in range(seg):
        a = i / seg * 2 * np.pi
        ring.append(base + radius * (np.cos(a) * side + np.sin(a) * up))
    v = np.array(ring + [tip, base], dtype=np.float32)
    tip_i = seg
    base_i = seg + 1
    faces = []
    for i in range(seg):
        j = (i + 1) % seg
        faces.append((i, j, tip_i))
        faces.append((j, i, base_i))
    return v, np.array(faces, dtype=np.int32)


def tube(points: np.ndarray, radius: float, seg: int = 6) -> tuple[np.ndarray, np.ndarray]:
    verts = []
    frames = []
    for i, p in enumerate(points):
        if i == len(points) - 1:
            t = points[i] - points[i - 1]
        else:
            t = points[i + 1] - points[i]
        t = t / (np.linalg.norm(t) + 1e-8)
        helper = np.array([0.0, 1.0, 0.0]) if abs(t[1]) < 0.85 else np.array([1.0, 0.0, 0.0])
        s = np.cross(t, helper)
        s = s / (np.linalg.norm(s) + 1e-8)
        u = np.cross(t, s)
        frames.append((s, u))
        for k in range(seg):
            a = k / seg * 2 * np.pi
            verts.append(p + radius * (np.cos(a) * s + np.sin(a) * u))
    v = np.array(verts, dtype=np.float32)
    faces = []
    n = len(points)
    for i in range(n - 1):
        for k in range(seg):
            a = i * seg + k
            b = i * seg + (k + 1) % seg
            c = (i + 1) * seg + k
            d = (i + 1) * seg + (k + 1) % seg
            faces.append((a, c, b))
            faces.append((b, c, d))
    return v, np.array(faces, dtype=np.int32)


def merge(parts: list[tuple[np.ndarray, np.ndarray]]) -> tuple[np.ndarray, np.ndarray]:
    verts = []
    faces = []
    offset = 0
    for v, f in parts:
        if len(f) == 0:
            continue
        verts.append(v)
        faces.append(f + offset)
        offset += len(v)
    if not verts:
        return np.zeros((0, 3), dtype=np.float32), np.zeros((0, 3), dtype=np.int32)
    return np.concatenate(verts, axis=0), np.concatenate(faces, axis=0)


def crown_split(v, f, extra):
    """Pull the spiked circlet off the head. The mace sits off to +X and stays on the body."""
    if len(v) == 0:
        return v, f, extra, np.zeros((0, 3), np.float32), np.zeros((0, 3), np.int32), []
    ymin, ymax = float(v[:, 1].min()), float(v[:, 1].max())
    xmin, xmax = float(v[:, 0].min()), float(v[:, 0].max())
    cx = 0.5 * (xmin + xmax)
    width = xmax - xmin
    top = v[:, 1] > ymin + 0.84 * (ymax - ymin)
    central = np.abs(v[:, 0] - cx) < 0.16 * width
    mark = top & central
    if mark.sum() < 30:
        return v, f, extra, np.zeros((0, 3), np.float32), np.zeros((0, 3), np.int32), []
    face_mark = mark[f].all(axis=1)
    crown_f = f[face_mark]
    body_f = f[~face_mark]
    cv, cf, cextra = compact(v, crown_f, extra)
    bv, bf, bextra = compact(v, body_f, extra)
    return bv, bf, bextra, cv, cf, cextra


def phase_parts(boss_id: str, v: np.ndarray, img: np.ndarray, mask: np.ndarray) -> list[tuple[str, np.ndarray, np.ndarray, str]]:
    ymin, ymax = float(v[:, 1].min()), float(v[:, 1].max())
    xmin, xmax = float(v[:, 0].min()), float(v[:, 0].max())
    h = ymax - ymin
    w = xmax - xmin
    cx = 0.5 * (xmin + xmax)
    parts: list[tuple[str, np.ndarray, np.ndarray, str]] = []
    rng = np.random.default_rng(zlib.crc32(boss_id.encode()) & 0xFFFFFFFF)
    if boss_id == "the_filth":
        bits = []
        for i in range(4):
            center = np.array([
                cx + float(rng.uniform(-0.22, 0.22)) * w,
                ymin + float(rng.uniform(0.45, 0.75)) * h,
                float(rng.uniform(0.02, 0.12)) * h,
            ])
            radii = np.array([0.045, 0.03, 0.04]) * h * float(rng.uniform(0.7, 1.0))
            bits.append(ellipsoid(center, radii, 8))
        mv, mf = merge(bits)
        parts.append(("Phase2_Debris", mv, mf, "debris"))
        core = ellipsoid(np.array([cx, ymin + 0.42 * h, 0.12 * h]), np.array([0.16, 0.10, 0.08]) * h, 12)
        parts.append(("Phase3_Core", core[0], core[1], "core"))
    elif boss_id == "breach_warden":
        seam = []
        for i, t in enumerate(np.linspace(0.35, 0.78, 6)):
            c = np.array([cx, ymin + t * h, -0.12 * h])
            seam.append(ellipsoid(c, np.array([0.03, 0.06, 0.02]) * h, 8))
        sv, sf = merge(seam)
        parts.append(("WardenEye", sv, sf, "violet"))
        cracks = ellipsoid(np.array([cx, ymin + 0.6 * h, 0.02 * h]), np.array([0.22, 0.28, 0.18]) * h, 10)
        parts.append(("Phase2_Enrage", cracks[0], cracks[1], "violet"))
    elif boss_id == "goblin_king":
        eye_l = ellipsoid(np.array([cx + 0.04 * w, ymin + 0.78 * h, 0.10 * h]), np.array([0.02, 0.015, 0.015]) * h, 6)
        eye_r = ellipsoid(np.array([cx - 0.02 * w, ymin + 0.78 * h, 0.10 * h]), np.array([0.02, 0.015, 0.015]) * h, 6)
        ev, ef = merge([eye_l, eye_r])
        parts.append(("Phase2_Enrage", ev, ef, "core"))
    elif boss_id == "blightmaw_matriarch":
        spines = []
        for i in range(9):
            ang = -0.6 + i * 0.15
            base = np.array([cx + np.sin(ang) * 0.16 * w, ymin + (0.72 + 0.03 * np.cos(i)) * h, -0.08 * h])
            tip = base + np.array([np.sin(ang) * 0.08 * w, 0.16 * h, -0.04 * h])
            spines.append(cone(base, tip, 0.025 * h, 6))
        sv, sf = merge(spines)
        parts.append(("Phase2_Spines", sv, sf, "violet"))
        heart = ellipsoid(np.array([cx, ymin + 0.46 * h, 0.16 * h]), np.array([0.12, 0.14, 0.08]) * h, 12)
        parts.append(("Phase3_Heart", heart[0], heart[1], "heart"))
    elif boss_id == "forgemaw":
        core = ellipsoid(np.array([cx, ymin + 0.58 * h, 0.14 * h]), np.array([0.10, 0.12, 0.06]) * h, 10)
        parts.append(("Phase3_Core", core[0], core[1], "core"))
    elif boss_id == "drowned_choir":
        water = ellipsoid(np.array([cx, ymin + 0.46 * h, 0.0]), np.array([0.42 * w, 0.08 * h, 0.28 * w]), 14)
        bolts = []
        for i in range(4):
            pts = []
            for t in np.linspace(0, 1, 8):
                pts.append(np.array([
                    cx + np.sin(i + t * 3) * 0.08 * w,
                    ymin + (0.35 + t * 0.4) * h,
                    0.05 * h,
                ]))
            bolts.append(tube(np.array(pts), 0.012 * h, 5))
        mv, mf = merge([water, *bolts])
        parts.append(("Phase2_Water", mv, mf, "water"))
    elif boss_id == "storm_warden":
        ribbons = []
        for turn, rad in ((0.0, 0.22), (1.4, 0.30), (2.6, 0.16)):
            pts = []
            for t in np.linspace(0, 1, 28):
                a = turn + t * np.pi * 1.6
                pts.append(np.array([
                    cx + np.cos(a) * rad * w,
                    ymin + (0.15 + t * 0.7) * h,
                    np.sin(a) * rad * w * 0.8,
                ]))
            ribbons.append(tube(np.array(pts), 0.012 * h, 5))
        rv, rf = merge(ribbons)
        parts.append(("Phase2_Gale", rv, rf, "wind"))
    return parts


MATERIALS = {
    "front": {"color": [1, 1, 1, 1], "rough": 0.92, "metal": 0.0, "emit": 1.4, "tex": "front"},
    "back": {"color": [1, 1, 1, 1], "rough": 0.94, "metal": 0.0, "emit": 0.4, "tex": "back"},
    "debris": {"color": [0.42, 0.36, 0.24, 1], "rough": 0.85, "metal": 0.05, "emit": 0.0},
    "core": {"color": [1.0, 0.72, 0.2, 1], "rough": 0.4, "metal": 0.0, "emit": 2.2},
    "violet": {"color": [0.62, 0.35, 1.0, 1], "rough": 0.4, "metal": 0.0, "emit": 3.5},
    "heart": {"color": [0.75, 0.28, 0.42, 1], "rough": 0.45, "metal": 0.0, "emit": 2.2},
    "water": {"color": [0.15, 0.45, 0.7, 0.55], "rough": 0.15, "metal": 0.0, "emit": 1.2, "blend": True},
    "wind": {"color": [0.85, 0.88, 1.0, 0.55], "rough": 0.2, "metal": 0.0, "emit": 2.0, "blend": True},
}


class Bin:
    def __init__(self) -> None:
        self.blob = bytearray()
        self.views: list[dict] = []
        self.accessors: list[dict] = []

    def pad(self) -> None:
        while len(self.blob) % 4:
            self.blob.append(0)

    def view(self, data: bytes, target: int | None) -> int:
        self.pad()
        start = len(self.blob)
        self.blob.extend(data)
        item = {"buffer": 0, "byteOffset": start, "byteLength": len(data)}
        if target:
            item["target"] = target
        self.views.append(item)
        return len(self.views) - 1

    def acc(self, view: int, comp: str, ctype: int, count: int, mins=None, maxs=None) -> int:
        item = {"bufferView": view, "componentType": ctype, "count": count, "type": comp}
        if mins is not None:
            item["min"] = mins
            item["max"] = maxs
        self.accessors.append(item)
        return len(self.accessors) - 1


def png_bytes(img: np.ndarray) -> bytes:
    rgb = (np.clip(img, 0, 1) * 255).astype(np.uint8)
    if rgb.shape[2] == 3:
        im = Image.fromarray(rgb, "RGB")
    else:
        im = Image.fromarray(rgb, "RGBA")
    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def limit_tex(img: np.ndarray, size: int = 1024) -> np.ndarray:
    h, w, _ = img.shape
    scale = size / max(h, w)
    if scale >= 1:
        return img
    im = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB")
    im = im.resize((max(1, int(w * scale)), max(1, int(h * scale))), Image.Resampling.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255.0


def write_glb(path: Path, spec_id: str, body, bones, phases, images: dict[str, np.ndarray]) -> None:
    """body is (verts, front_faces, back_faces, normals, uv, joints, weights). phases are (name, v, f, mat)."""
    v, ff, bf, n, uv, joints, weights = body
    store = Bin()
    mat_names: list[str] = []
    mat_index: dict[str, int] = {}

    def mid(name: str) -> int:
        if name not in mat_index:
            mat_index[name] = len(mat_names)
            mat_names.append(name)
        return mat_index[name]

    def vec_acc(arr: np.ndarray, comp: str, ctype: int, target: int, mins=None, maxs=None) -> int:
        raw = arr.astype(np.float32).tobytes() if ctype == 5126 else arr.tobytes()
        return store.acc(store.view(raw, target), comp, ctype, len(arr), mins, maxs)

    def mesh_primitive(verts, faces, normals, texuv, skin, material: str) -> dict:
        if len(faces) == 0:
            return {}
        mn = [float(x) for x in verts.min(0)]
        mx = [float(x) for x in verts.max(0)]
        pa = vec_acc(verts.astype(np.float32), "VEC3", 5126, 34962, mn, mx)
        na = vec_acc(normals.astype(np.float32), "VEC3", 5126, 34962)
        ta = vec_acc(texuv.astype(np.float32), "VEC2", 5126, 34962)
        ja = vec_acc(skin[0].astype(np.uint16), "VEC4", 5123, 34962)
        wa = vec_acc(skin[1].astype(np.float32), "VEC4", 5126, 34962)
        idx = faces.astype(np.uint32).reshape(-1)
        ia = store.acc(store.view(idx.tobytes(), 34963), "SCALAR", 5125, len(idx))
        return {
            "attributes": {"POSITION": pa, "NORMAL": na, "TEXCOORD_0": ta, "JOINTS_0": ja, "WEIGHTS_0": wa},
            "indices": ia,
            "material": mid(material),
        }

    primitives = []
    front_p = mesh_primitive(v, ff, n, uv, (joints, weights), "front")
    if front_p:
        primitives.append(front_p)
    if len(bf):
        back_p = mesh_primitive(v, bf, n, uv, (joints, weights), "back")
        if back_p:
            primitives.append(back_p)
    meshes = [{"name": spec_id, "primitives": primitives}]
    mesh_nodes = [{"name": "Body", "mesh": 0, "skin": 0}]

    # Unskinned phase / crown meshes. A dummy skin weight is not used; these nodes have no skin.
    extra_nodes = []
    for item in phases:
        name, pv, pf, mat = item[0], item[1], item[2], item[3]
        if len(pf) == 0:
            continue
        pn = recompute_normals(pv, pf)
        if len(item) > 4 and item[4] is not None and len(item[4]) == len(pv):
            puv = item[4].astype(np.float32)
        else:
            puv = np.zeros((len(pv), 2), dtype=np.float32)
        # one-bone dummy so the accessor path stays shared; these nodes are not skinned
        pj = np.zeros((len(pv), 4), dtype=np.uint16)
        pw = np.zeros((len(pv), 4), dtype=np.float32)
        pw[:, 0] = 1.0
        prim = mesh_primitive(pv, pf, pn, puv, (pj, pw), mat)
        # drop skin attributes for a static mesh
        prim["attributes"].pop("JOINTS_0", None)
        prim["attributes"].pop("WEIGHTS_0", None)
        meshes.append({"name": name, "primitives": [prim]})
        extra_nodes.append({"name": name, "mesh": len(meshes) - 1})

    # Images
    image_nodes = []
    textures = []
    for key, img in images.items():
        raw = png_bytes(img)
        view = store.view(raw, None)
        image_nodes.append({"bufferView": view, "mimeType": "image/png", "name": key})
        textures.append({"source": len(image_nodes) - 1, "sampler": 0})
    tex_of = {key: i for i, key in enumerate(images)}

    materials = []
    for name in mat_names:
        info = MATERIALS[name]
        m = {
            "name": name,
            "doubleSided": True,
            "pbrMetallicRoughness": {
                "baseColorFactor": info["color"],
                "metallicFactor": info["metal"],
                "roughnessFactor": info["rough"],
            },
        }
        if info.get("blend"):
            m["alphaMode"] = "BLEND"
        if info.get("tex") and info["tex"] in tex_of:
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": tex_of[info["tex"]]}
        if info["emit"] > 0:
            if info.get("tex") == "front" and "emit" in tex_of:
                m["emissiveTexture"] = {"index": tex_of["emit"]}
                m["emissiveFactor"] = [1, 1, 1]
            else:
                m["emissiveFactor"] = [info["color"][0], info["color"][1], info["color"][2]]
            m["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": info["emit"]}}
        materials.append(m)

    # Nodes: root, armature, body, extras, then bones. Crown is reparented onto Head.
    bone_names = [b["name"] for b in bones]
    # IBM
    ibms = []
    for b in bones:
        m = np.eye(4)
        m[:3, 3] = b["world"]
        ibms.append(np.linalg.inv(m).astype(np.float32))
    # glTF matrices are column-major. numpy's tobytes() is row-major, so transpose first.
    ibm_blob = b"".join(np.ascontiguousarray(m.T, dtype=np.float32).tobytes() for m in ibms)
    ibm_acc = store.acc(store.view(ibm_blob, None), "MAT4", 5126, len(bones))

    nodes: list[dict] = []
    # filled after we know indices
    root = {"name": spec_id, "children": []}
    armature = {"name": "Armature", "children": []}
    nodes.extend([root, armature])
    body_node_index = len(nodes)
    nodes.append(mesh_nodes[0])
    extra_index = {}
    for node in extra_nodes:
        extra_index[node["name"]] = len(nodes)
        nodes.append(node)
    bone_index = {}
    bone_start = len(nodes)
    for b in bones:
        bone_index[b["name"]] = len(nodes)
        node = {"name": b["name"], "translation": [float(x) for x in b["local"]]}
        nodes.append(node)
    for i, b in enumerate(bones):
        kids = [bone_start + j for j, o in enumerate(bones) if o["parent"] == i]
        if kids:
            nodes[bone_start + i]["children"] = kids
    nodes[1]["children"] = [bone_start]  # Hips
    root_children = [1, body_node_index] + [extra_index[n] for n in extra_index if n != "Crown"]
    # Crown hangs off the head so it tracks the skull and can be hidden on death.
    if "Crown" in extra_index:
        head = bone_index["Head"]
        nodes[head].setdefault("children", []).append(extra_index["Crown"])
    nodes[0]["children"] = root_children

    skins = [{"name": "Rig", "inverseBindMatrices": ibm_acc, "joints": [bone_start + i for i in range(len(bones))], "skeleton": bone_start}]

    # Animations
    animations = []
    for clip in clips():
        samplers = []
        channels = []
        for bone_name, keys in clip["tracks"].items():
            if bone_name not in bone_index:
                continue
            times = np.array([k[0] for k in keys], dtype=np.float32)
            quats = np.array([k[1] for k in keys], dtype=np.float32)
            ta = store.acc(
                store.view(times.tobytes(), None),
                "SCALAR",
                5126,
                len(times),
                [float(times.min())],
                [float(times.max())],
            )
            qa = store.acc(store.view(quats.tobytes(), None), "VEC4", 5126, len(quats))
            samplers.append({"input": ta, "output": qa, "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": bone_index[bone_name], "path": "rotation"}})
        animations.append({"name": clip["name"], "samplers": samplers, "channels": channels})

    gltf = {
        "asset": {"version": "2.0", "generator": "tools/build_boss_meshes.py"},
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "scene": 0,
        "scenes": [{"name": spec_id, "nodes": [0]}],
        "nodes": nodes,
        "meshes": meshes,
        "skins": skins,
        "materials": materials,
        "animations": animations,
        "accessors": store.accessors,
        "bufferViews": store.views,
        "buffers": [{"byteLength": len(store.blob)}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
    }
    if image_nodes:
        gltf["images"] = image_nodes
        gltf["textures"] = textures
    js = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(js) % 4:
        js += b" "
    store.pad()
    data = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(store.blob))
    data += struct.pack("<I", len(js)) + b"JSON" + js
    data += struct.pack("<I", len(store.blob)) + b"BIN\x00" + bytes(store.blob)
    path.write_bytes(data)


def check_bind(v, joints, weights, bones) -> None:
    worlds = []
    ibms = []
    for b in bones:
        m = np.eye(4)
        m[:3, 3] = b["world"]
        worlds.append(m)
        ibms.append(np.linalg.inv(m))
    err = 0.0
    step = max(1, len(v) // 40)
    for i in range(0, len(v), step):
        acc = np.zeros(4)
        p = np.array([v[i, 0], v[i, 1], v[i, 2], 1.0])
        for k in range(4):
            acc += weights[i, k] * (worlds[int(joints[i, k])] @ ibms[int(joints[i, k])] @ p)
        err = max(err, float(np.linalg.norm(acc[:3] - v[i])))
    if err > 1e-3:
        raise SystemExit(f"bind pose drifted by {err}")


def build_one(spec: dict) -> dict:
    img, mask, back = crop_sheet(spec)
    if mask.mean() < 0.05:
        raise SystemExit(f"{spec['id']}: mask was empty")
    painted = inpaint(img, mask)
    emit = glow_image(painted)
    height = float(spec["height"])
    v, f, _n = mesh_from_mask(mask, height)
    v, n = displace(v, f, painted, mask, height)
    # Crown before the face split so both sides lose those faces.
    uv_span = float(v[:, 0].max() - v[:, 0].min())
    uv = uvs_for(v, uv_span, float(v[:, 1].max()))
    joints, weights = bind_weights(v, bones_for(v))
    # bones_for uses the mesh, then crown_split changes the mesh. Weights are by position,
    # so recompute bones and weights after the crown cut.
    crown_v = np.zeros((0, 3), np.float32)
    crown_f = np.zeros((0, 3), np.int32)
    crown_uv = np.zeros((0, 2), np.float32)
    if spec["id"] == "goblin_king":
        v, f, body_extra, crown_v, crown_f, crown_extra = crown_split(v, f, [n, uv])
        n, uv = body_extra
        if len(crown_extra) == 2:
            crown_uv = crown_extra[1]
    bones = bones_for(v)
    joints, weights = bind_weights(v, bones)
    check_bind(v, joints, weights, bones)
    front_f, back_f = split_faces(v, f)
    phases = phase_parts(spec["id"], v, painted, mask)
    if spec["id"] == "goblin_king" and len(crown_f):
        # Crown vertices are still in world space. Park them on the head bone.
        head = next(b for b in bones if b["name"] == "Head")
        crown_v = crown_v - head["world"].astype(np.float32)
        phases.insert(0, ("Crown", crown_v, crown_f, "front", crown_uv))
    images = {"front": limit_tex(painted), "emit": limit_tex(emit)}
    if back is not None:
        images["back"] = limit_tex(back)
    else:
        images["back"] = images["front"]
    OUT.mkdir(parents=True, exist_ok=True)
    dest = OUT / f"{spec['id']}.glb"
    write_glb(dest, spec["id"], (v, front_f, back_f, n, uv, joints, weights), bones, phases, images)
    debug = Path("/tmp/boss_build")
    debug.mkdir(exist_ok=True)
    Image.fromarray((painted * 255).astype(np.uint8)).save(debug / f"{spec['id']}_paint.png")
    shade = np.zeros((*mask.shape, 3), dtype=np.uint8)
    shade[mask] = (painted[mask] * 255).astype(np.uint8)
    Image.fromarray(shade).resize((512, int(512 * mask.shape[0] / mask.shape[1]))).save(debug / f"{spec['id']}_mask.png")
    print(
        f"{spec['id']}: {len(f)} tris, {dest.stat().st_size/1e6:.1f} MB, "
        f"h={v[:,1].max():.2f} w={v[:,0].max()-v[:,0].min():.2f}"
    )
    return {"crop": list(spec["crop"]), "height": height, "file": spec["file"]}


def main() -> None:
    want = set(sys.argv[1:])
    meta = {}
    if CROP_JSON.is_file() and want:
        meta = json.loads(CROP_JSON.read_text())
    for spec in BOSSES:
        if want and spec["id"] not in want:
            continue
        meta[spec["id"]] = build_one(spec)
    CROP_JSON.write_text(json.dumps(meta, indent=2) + "\n")
    print("wrote", CROP_JSON.relative_to(ROOT))


if __name__ == "__main__":
    main()
