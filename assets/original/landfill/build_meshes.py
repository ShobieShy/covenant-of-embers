#!/usr/bin/env python3
"""CC0 landfill hero meshes. Textures are the ambientCG sets already in the repo.

Writes glTF + bin next to this file. Run from anywhere:
  python3 assets/original/landfill/build_meshes.py
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TEX = "../../ambientcg"

PIT = (0.0, -40.0)
INNER = 80.0
OUTER = 104.0
RIM = 12.0


def dist_seg(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
    abx, abz = bx - ax, bz - az
    den = abx * abx + abz * abz
    t = 0.0 if den < 1e-8 else max(0.0, min(1.0, ((px - ax) * abx + (pz - az) * abz) / den))
    return math.hypot(px - (ax + abx * t), pz - (az + abz * t))


def terrace(x: float, z: float) -> float:
    """Just under the tutorial slab and the bowl floor the colliders use."""
    if abs(x) <= 15.2 and -21.0 <= z <= 38.0:
        if z >= -6.0:
            return -0.05
        u = max(0.0, min(1.0, (-6.0 - z) / 15.0))
        s = u * u * (3.0 - 2.0 * u)
        return -0.05 + (-2.05 - -0.05) * s
    return -2.05


def clean_lane(x: float, z: float) -> bool:
    if abs(x) < 7.0 and -70.0 < z < 38.0:
        return True
    if dist_seg(x, z, -28.0, -30.0, -120.0, -14.0) < 7.0:
        return True
    return False


def height_at(x: float, z: float) -> float:
    r = math.hypot(x - PIT[0], z - PIT[1])
    base = terrace(x, z)
    if r <= INNER:
        h = base
    elif r >= OUTER:
        h = RIM
    else:
        u = (r - INNER) / (OUTER - INNER)
        s = u * u * (3.0 - 2.0 * u)
        h = base + (RIM - base) * s
    d = dist_seg(x, z, -28.0, -30.0, -120.0, -14.0)
    if d < 14.0:
        u = d / 14.0
        s = u * u * (3.0 - 2.0 * u)
        h = -2.05 + (h - -2.05) * s
    if not clean_lane(x, z) and r < OUTER + 8.0:
        h += 0.45 * math.sin(x * 0.21) * math.cos(z * 0.17)
        h += 0.22 * math.sin(x * 0.53 + z * 0.4)
    return h


class Prim:
    def __init__(self) -> None:
        self.pos: list[float] = []
        self.nrm: list[float] = []
        self.uv: list[float] = []
        self.idx: list[int] = []

    def add(self, p, n, uv) -> int:
        self.pos += list(p)
        self.nrm += list(n)
        self.uv += list(uv)
        return len(self.pos) // 3 - 1

    def tri(self, a, b, c, n, uva, uvb, uvc) -> None:
        ia, ib, ic = self.add(a, n, uva), self.add(b, n, uvb), self.add(c, n, uvc)
        self.idx += [ia, ib, ic]

    def quad(self, a, b, c, d, uv_fn) -> None:
        n = normal(a, b, c)
        self.tri(a, b, c, n, uv_fn(a), uv_fn(b), uv_fn(c))
        self.tri(a, c, d, n, uv_fn(a), uv_fn(c), uv_fn(d))


def normal(a, b, c) -> tuple[float, float, float]:
    ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
    nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    l = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / l, ny / l, nz / l)


def xz_uv(p, scale=0.18):
    return (p[0] * scale, p[2] * scale)


def write_gltf(name: str, prims: list[tuple[Prim, dict]], lights: list[dict] | None = None) -> None:
    blob = bytearray()
    views = []
    accessors = []
    meshes = []
    materials = []

    def pack(data: bytes, target: int | None) -> int:
        while len(blob) % 4:
            blob.append(0)
        start = len(blob)
        blob.extend(data)
        view = {"buffer": 0, "byteOffset": start, "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        return len(views) - 1

    kept = [(prim, mat) for prim, mat in prims if prim.idx]
    prims = kept
    for prim, _mat in prims:
        p = struct.pack("<" + "f" * len(prim.pos), *prim.pos)
        n = struct.pack("<" + "f" * len(prim.nrm), *prim.nrm)
        u = struct.pack("<" + "f" * len(prim.uv), *prim.uv)
        ix = struct.pack("<" + "I" * len(prim.idx), *prim.idx)
        vp, vn, vu, vi = pack(p, 34962), pack(n, 34962), pack(u, 34962), pack(ix, 34963)
        xs = prim.pos[0::3]
        ys = prim.pos[1::3]
        zs = prim.pos[2::3]

        def acc(view, ctype, count, atype, mn=None, mx=None):
            a = {"bufferView": view, "componentType": ctype, "count": count, "type": atype}
            if mn is not None:
                a["min"] = mn
                a["max"] = mx
            accessors.append(a)
            return len(accessors) - 1

        ip = acc(vp, 5126, len(prim.pos) // 3, "VEC3", [min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)])
        inn = acc(vn, 5126, len(prim.nrm) // 3, "VEC3")
        iu = acc(vu, 5126, len(prim.uv) // 2, "VEC2")
        ii = acc(vi, 5125, len(prim.idx), "SCALAR")
        meshes.append({"primitives": [{
            "attributes": {"POSITION": ip, "NORMAL": inn, "TEXCOORD_0": iu},
            "indices": ii,
            "material": len(materials),
        }]})
        materials.append(_mat)

    images = []
    textures = []
    image_ids: dict[str, int] = {}

    def image(uri: str) -> int:
        if uri not in image_ids:
            image_ids[uri] = len(images)
            images.append({"uri": uri})
            textures.append({"source": image_ids[uri]})
        return image_ids[uri]

    for mat in materials:
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        if "baseColorTexture" in mat:
            uri = mat.pop("baseColorTexture")
            pbr["baseColorTexture"] = {"index": image(uri)}
        if "normalTexture" in mat:
            uri = mat.pop("normalTexture")
            mat["normalTexture"] = {"index": image(uri)}

    gltf: dict = {
        "asset": {"version": "2.0", "generator": "covenant-of-embers landfill"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(meshes) + (1 if lights else 0)))}],
        "nodes": [{"mesh": i} for i in range(len(meshes))],
        "meshes": meshes,
        "materials": materials,
        "buffers": [{"byteLength": len(blob), "uri": name + ".bin"}],
        "bufferViews": views,
        "accessors": accessors,
    }
    if images:
        gltf["images"] = images
        gltf["textures"] = textures
    if lights:
        gltf["extensionsUsed"] = ["KHR_lights_punctual"]
        gltf["extensions"] = {"KHR_lights_punctual": {"lights": [
            {k: v for k, v in light.items() if k != "node"} for light in lights
        ]}}
        for i, light in enumerate(lights):
            node = {"extensions": {"KHR_lights_punctual": {"light": i}}}
            if "translation" in light:
                node["translation"] = light["translation"]
            gltf["nodes"].append(node)
    (ROOT / f"{name}.gltf").write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")
    (ROOT / f"{name}.bin").write_bytes(blob)


def pbr(folder: str, tint=None, rough=0.92, metal=0.0, emissive=None, strength=1.0, double=False) -> dict:
    # Albedo only. Generated tangents plus these normal maps were turning
    # scattered faces black under the landfill sun.
    mat = {
        "baseColorTexture": f"{TEX}/{folder}/color.jpg",
        "pbrMetallicRoughness": {"metallicFactor": metal, "roughnessFactor": rough},
        "doubleSided": double,
    }
    if tint:
        mat["pbrMetallicRoughness"]["baseColorFactor"] = tint
    if emissive:
        mat["emissiveFactor"] = emissive
        mat["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": strength}}
    return mat


def flat(color, rough=0.4, metal=0.0, emissive=None, strength=2.0) -> dict:
    mat = {"pbrMetallicRoughness": {
        "baseColorFactor": color, "metallicFactor": metal, "roughnessFactor": rough,
    }}
    if emissive:
        mat["emissiveFactor"] = emissive
        mat["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": strength}}
    return mat


def build_pit() -> None:
    dirt, rock = Prim(), Prim()
    step = 2.5
    xs = [i * step for i in range(int(-145 / step), int(145 / step) + 1)]
    zs = [i * step for i in range(int(-155 / step), int(80 / step) + 1)]
    h = {(ix, iz): height_at(xs[ix], zs[iz]) for iz in range(len(zs)) for ix in range(len(xs))}

    def vert(ix, iz):
        return (xs[ix], h[(ix, iz)], zs[iz])

    for iz in range(len(zs) - 1):
        for ix in range(len(xs) - 1):
            a, b = vert(ix, iz), vert(ix + 1, iz)
            c, d = vert(ix + 1, iz + 1), vert(ix, iz + 1)
            # a-d-c-b winds so the normal points up (Godot is Y-up).
            n = normal(a, d, c)
            target = rock if n[1] < 0.9 else dirt
            target.quad(a, d, c, b, xz_uv)
    # Worn S path, a few centimetres proud of the floor so the curve reads.
    path = [(-1.0, 22.0), (7.0, 4.0), (-2.0, -12.0), (5.0, -26.0), (0.0, -30.0)]
    ribbon = Prim()
    half = 2.6
    for i in range(len(path) - 1):
        x0, z0 = path[i]
        x1, z1 = path[i + 1]
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz) or 1.0
        px, pz = -dz / ln * half, dx / ln * half
        y0, y1 = height_at(x0, z0) + 0.08, height_at(x1, z1) + 0.08
        a = (x0 + px, y0, z0 + pz)
        b = (x0 - px, y0, z0 - pz)
        c = (x1 - px, y1, z1 - pz)
        d = (x1 + px, y1, z1 + pz)
        ribbon.quad(a, b, c, d, lambda p: xz_uv(p, 0.22))
    write_gltf("pit", [
        (dirt, pbr("Ground037", [0.78, 0.7, 0.55, 1], rough=0.96, double=True)),
        (rock, pbr("Rock030", [0.85, 0.8, 0.72, 1], rough=0.9, double=True)),
        (ribbon, pbr("Ground037", [0.7, 0.6, 0.42, 1], rough=0.88, double=True)),
    ])


def build_pool() -> None:
    mud, slime = Prim(), Prim()

    def disc(prim, radius, y, sag, segs, uv_scale):
        ring = []
        for i in range(segs):
            a = (i / segs) * math.tau
            ring.append((math.cos(a) * radius, y, math.sin(a) * radius))
        center = (0.0, y - sag, 0.0)
        for i in range(segs):
            b, c = ring[i], ring[(i + 1) % segs]
            n = normal(center, c, b)
            prim.tri(center, c, b, n, (0.5, 0.5), xz_uv(c, uv_scale), xz_uv(b, uv_scale))

    # Stay above the pit floor. A deep sag sank through the ground and read as a crescent.
    disc(mud, 20.0, 0.04, 0.0, 48, 0.08)
    disc(slime, 11.5, 0.1, 0.04, 40, 0.12)
    mud_mat = pbr("Ground037", [0.45, 0.62, 0.22, 1], rough=0.84, double=True)
    slime_mat = flat([0.25, 0.55, 0.08, 1], 0.12, 0.04, [0.35, 0.9, 0.12], 4.0)
    slime_mat["doubleSided"] = True
    write_gltf("pool", [
        (mud, mud_mat),
        (slime, slime_mat),
    ], [{"type": "point", "color": [0.55, 1.0, 0.25], "intensity": 30, "range": 16, "translation": [0, 1.2, 0]}])


def crystal_prim(prim: Prim, origin, yaw, height, radius) -> None:
    cy, sy = math.cos(yaw), math.sin(yaw)

    def rot(p):
        x, z = p[0] * cy - p[2] * sy, p[0] * sy + p[2] * cy
        return (origin[0] + x, origin[1] + p[1], origin[2] + z)

    sides = 6
    ring = []
    for i in range(sides):
        a = (i / sides) * math.tau
        ring.append(rot((math.cos(a) * radius, height * 0.25, math.sin(a) * radius)))
    tip = rot((0, height, 0))
    foot = rot((0, 0, 0))
    for i in range(sides):
        b, c = ring[i], ring[(i + 1) % sides]
        n = normal(foot, b, c)
        prim.tri(foot, b, c, n, (0, 0), (1, 0), (0.5, 1))
        n = normal(tip, c, b)
        prim.tri(tip, c, b, n, (0.5, 1), (1, 0), (0, 0))


def build_crystal() -> None:
    prim = Prim()
    crystal_prim(prim, (0, 0, 0), 0.2, 2.6, 0.38)
    crystal_prim(prim, (0.55, 0, 0.25), 1.1, 1.7, 0.26)
    crystal_prim(prim, (-0.4, 0, 0.35), 2.4, 1.4, 0.22)
    mat = flat([0.45, 0.2, 0.85, 1], 0.18, 0.05, [0.55, 0.15, 0.95], 6.0)
    write_gltf("crystal", [(prim, mat)], [
        {"type": "point", "color": [0.65, 0.25, 1.0], "intensity": 18, "range": 9, "translation": [0, 1.2, 0]},
    ])


def build_mound() -> None:
    prim = Prim()
    for i, (ox, oz, sy, rx, rz) in enumerate((
        (0, 0, 2.4, 3.2, 2.6), (1.6, 0.8, 1.5, 2.0, 1.7), (-1.4, 0.6, 1.3, 1.8, 1.6),
    )):
        steps = 8
        for a in range(steps):
            t0, t1 = a / steps * math.pi, (a + 1) / steps * math.pi
            for b in range(steps * 2):
                p0, p1 = b / (steps * 2) * math.tau, (b + 1) / (steps * 2) * math.tau

                def p(t, q, j=i):
                    wob = 1.0 + 0.12 * math.sin(q * 3 + j) 
                    return (
                        ox + math.sin(t) * math.cos(q) * rx * wob,
                        math.cos(t) * sy * (0.85 + 0.15 * math.sin(q * 2)),
                        oz + math.sin(t) * math.sin(q) * rz * wob,
                    )
                if t0 < 0.15:
                    continue
                prim.quad(p(t0, p0), p(t0, p1), p(t1, p1), p(t1, p0), lambda v: xz_uv(v, 0.3))
    write_gltf("mound", [(prim, pbr("Rock030", [0.62, 0.52, 0.38, 1], 0.95, double=True))])


def wall_quads(prim: Prim, x0, z0, x1, z1, y0, y1) -> None:
    a = (x0, y0, z0)
    b = (x1, y0, z1)
    c = (x1, y1, z1)
    d = (x0, y1, z0)
    prim.quad(a, b, c, d, lambda p: (p[0] * 0.25, p[1] * 0.25))
    prim.quad(b, a, d, c, lambda p: (p[0] * 0.25, p[1] * 0.25))


def build_shack(stilts: bool) -> None:
    prim = Prim()
    roof = Prim()
    y0 = 2.1 if stilts else 0.0
    # Floor and posts.
    prim.quad((-2.2, y0, -1.7), (2.2, y0, -1.7), (2.2, y0, 1.7), (-2.2, y0, 1.7), xz_uv)
    if stilts:
        for x, z in ((-2.0, -1.5), (2.0, -1.5), (-2.0, 1.5), (2.0, 1.5)):
            wall_quads(prim, x - 0.12, z - 0.12, x + 0.12, z + 0.12, 0.0, y0)
    # Walls. Front (+z is unused; the door faces -z, toward a path when yawed).
    wall_h = y0 + 2.2
    wall_quads(prim, -2.2, -1.7, 2.2, -1.55, y0, wall_h)  # back
    wall_quads(prim, -2.2, -1.7, -2.05, 1.7, y0, wall_h)
    wall_quads(prim, 2.05, -1.7, 2.2, 1.7, y0, wall_h)
    wall_quads(prim, -2.2, 1.55, -0.55, 1.7, y0, wall_h)
    wall_quads(prim, 0.55, 1.55, 2.2, 1.7, y0, wall_h)
    wall_quads(prim, -0.55, 1.55, 0.55, 1.7, y0 + 1.5, wall_h)
    # Pitched roof.
    eave = wall_h - 0.05
    peak = wall_h + 1.15
    roof.quad((-2.5, eave, -2.0), (0.0, peak, -2.0), (0.0, peak, 2.0), (-2.5, eave, 2.0), lambda p: (p[2] * 0.3, p[1] * 0.3))
    roof.quad((2.5, eave, -2.0), (2.5, eave, 2.0), (0.0, peak, 2.0), (0.0, peak, -2.0), lambda p: (p[2] * 0.3, p[1] * 0.3))
    # Gables.
    roof.tri((-2.5, eave, -2.0), (2.5, eave, -2.0), (0.0, peak, -2.0), (0, 0, -1), (0, 0), (1, 0), (0.5, 1))
    roof.tri((2.5, eave, 2.0), (-2.5, eave, 2.0), (0.0, peak, 2.0), (0, 0, 1), (0, 0), (1, 0), (0.5, 1))
    name = "shack_stilts" if stilts else "shack"
    write_gltf(name, [
        (prim, pbr("Wood049", rough=0.86)),
        (roof, pbr("Metal032", [0.55, 0.42, 0.32, 1], 0.72, 0.35)),
    ])


def build_gate() -> None:
    stone, glow = Prim(), Prim()

    def tower(x):
        stone.quad((x - 1.6, 0, -1.4), (x + 1.6, 0, -1.4), (x + 1.6, 0, 1.4), (x - 1.6, 0, 1.4), xz_uv)
        for (a, b, c, d) in (
            ((x - 1.6, 0, -1.4), (x + 1.6, 0, -1.4), (x + 1.6, 8.2, -1.4), (x - 1.6, 8.2, -1.4)),
            ((x + 1.6, 0, 1.4), (x - 1.6, 0, 1.4), (x - 1.6, 8.2, 1.4), (x + 1.6, 8.2, 1.4)),
            ((x - 1.6, 0, 1.4), (x - 1.6, 0, -1.4), (x - 1.6, 8.2, -1.4), (x - 1.6, 8.2, 1.4)),
            ((x + 1.6, 0, -1.4), (x + 1.6, 0, 1.4), (x + 1.6, 8.2, 1.4), (x + 1.6, 8.2, -1.4)),
        ):
            stone.quad(a, b, c, d, lambda p: (p[0] * 0.2, p[1] * 0.2))
        crystal_prim(glow, (x, 8.2, 0), 0.4, 2.2, 0.45)

    tower(-6.2)
    tower(6.2)
    # Lintel and curtain wings.
    stone.quad((-4.6, 5.6, -1.1), (4.6, 5.6, -1.1), (4.6, 7.0, -1.1), (-4.6, 7.0, -1.1), lambda p: (p[0] * 0.2, p[1] * 0.2))
    stone.quad((4.6, 5.6, 1.1), (-4.6, 5.6, 1.1), (-4.6, 7.0, 1.1), (4.6, 7.0, 1.1), lambda p: (p[0] * 0.2, p[1] * 0.2))
    stone.quad((-4.6, 5.6, -1.1), (-4.6, 5.6, 1.1), (4.6, 5.6, 1.1), (4.6, 5.6, -1.1), xz_uv)
    for x0, x1 in ((-14.0, -7.6), (7.6, 14.0)):
        stone.quad((x0, 0, -0.8), (x1, 0, -0.8), (x1, 4.6, -0.8), (x0, 4.6, -0.8), lambda p: (p[0] * 0.18, p[1] * 0.18))
        stone.quad((x1, 0, 0.8), (x0, 0, 0.8), (x0, 4.6, 0.8), (x1, 4.6, 0.8), lambda p: (p[0] * 0.18, p[1] * 0.18))
    write_gltf("gate", [
        (stone, pbr("Bricks076C", rough=0.82)),
        (glow, flat([0.5, 0.22, 0.9, 1], 0.2, 0.0, [0.6, 0.2, 1.0], 5.0)),
    ], [
        {"type": "point", "color": [0.7, 0.3, 1.0], "intensity": 14, "range": 10, "translation": [-6.2, 9.2, 0]},
        {"type": "point", "color": [0.7, 0.3, 1.0], "intensity": 14, "range": 10, "translation": [6.2, 9.2, 0]},
        {"type": "point", "color": [1.0, 0.72, 0.35], "intensity": 10, "range": 8, "translation": [0, 4.2, 1.6]},
    ])


def build_crater() -> None:
    rock, glow = Prim(), Prim()
    for i in range(12):
        a = (i / 12) * math.tau
        rad = 6.2 + (i % 3) * 0.7
        h = 2.4 + (i % 4) * 0.7
        x, z = math.cos(a) * rad, math.sin(a) * rad
        tip = (x * 0.75, h, z * 0.75)
        w = 1.5
        tang = (-math.sin(a) * w, 0, math.cos(a) * w)
        foot_a = (x + tang[0], 0, z + tang[2])
        foot_b = (x - tang[0], 0, z - tang[2])
        inner = (math.cos(a) * 3.2, 0.2, math.sin(a) * 3.2)
        rock.tri(foot_a, foot_b, tip, normal(foot_a, foot_b, tip), (0, 0), (1, 0), (0.5, 1))
        rock.tri(foot_b, inner, tip, normal(foot_b, inner, tip), (0, 0), (1, 0), (0.5, 1))
    crystal_prim(glow, (0, 0.2, 0), 0.5, 6.5, 0.7)
    crystal_prim(glow, (1.1, 0.2, -0.4), 1.2, 3.4, 0.4)
    write_gltf("crater", [
        (rock, pbr("Rock030", [0.75, 0.7, 0.85, 1], 0.88)),
        (glow, flat([0.35, 0.1, 0.7, 1], 0.15, 0.0, [0.7, 0.2, 1.0], 8.0)),
    ], [{"type": "point", "color": [0.6, 0.15, 1.0], "intensity": 80, "range": 28, "translation": [0, 3, 0]}])


def main() -> None:
    build_pit()
    build_pool()
    build_crystal()
    build_mound()
    build_shack(False)
    build_shack(True)
    build_gate()
    build_crater()
    print("wrote landfill meshes")


if __name__ == "__main__":
    main()
