#!/usr/bin/env python3
"""Build the Mage Association kit: gothic hall, library wing, round precinct.

Meshes are glTF with CC0 ambientCG PBR (Rock030, PavingStones131, Wood049,
Grass004, Metal032) plus original slate, glass, and circle maps. Collision
stays in the level TOML. Run from the repo root:

  python3 tools/build_association_kit.py
"""
from __future__ import annotations

import json
import math
import random
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/original/ember_art/association"
TEX = "../../../ambientcg"

# Precinct ellipse, metres. North is -Z. The south gate sits on +Z.
CX, CZ = -1.0, 6.0
RX, RZ = 42.0, 38.0
SEGMENTS = 24


def _uri(set_name: str, kind: str) -> str:
    return f"{TEX}/{set_name}/{kind}.jpg"


class Mesh:
    def __init__(self) -> None:
        self.positions: list[float] = []
        self.normals: list[float] = []
        self.uvs: list[float] = []
        self.indices: dict[int, list[int]] = {}
        self.materials: list[dict] = []

    def mat(self, spec: dict) -> int:
        self.materials.append(spec)
        idx = len(self.materials) - 1
        self.indices[idx] = []
        return idx

    def quad(self, pts: list[tuple[float, float, float]], normal: tuple[float, float, float],
             mat: int, uvs: list[tuple[float, float]]) -> None:
        base = len(self.positions) // 3
        for p, uv in zip(pts, uvs):
            self.positions.extend(p)
            self.normals.extend(normal)
            self.uvs.extend(uv)
        self.indices[mat].extend([base, base + 1, base + 2, base, base + 2, base + 3])

    def tri(self, pts: list[tuple[float, float, float]], normal: tuple[float, float, float],
            mat: int, uvs: list[tuple[float, float]]) -> None:
        base = len(self.positions) // 3
        for p, uv in zip(pts, uvs):
            self.positions.extend(p)
            self.normals.extend(normal)
            self.uvs.extend(uv)
        self.indices[mat].extend([base, base + 1, base + 2])

    def box(self, c: tuple[float, float, float], size: tuple[float, float, float], mat: int,
            uv: float = 0.35) -> None:
        hx, hy, hz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        x0, x1 = c[0] - hx, c[0] + hx
        y0, y1 = c[1] - hy, c[1] + hy
        z0, z1 = c[2] - hz, c[2] + hz
        s = uv
        self.quad([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0), mat,
                  [(x0 * s, z0 * s), (x1 * s, z0 * s), (x1 * s, z1 * s), (x0 * s, z1 * s)])
        self.quad([(x0, y0, z1), (x1, y0, z1), (x1, y0, z0), (x0, y0, z0)], (0, -1, 0), mat,
                  [(x0 * s, z1 * s), (x1 * s, z1 * s), (x1 * s, z0 * s), (x0 * s, z0 * s)])
        self.quad([(x1, y0, z1), (x1, y1, z1), (x1, y1, z0), (x1, y0, z0)], (1, 0, 0), mat,
                  [(z1 * s, y0 * s), (z1 * s, y1 * s), (z0 * s, y1 * s), (z0 * s, y0 * s)])
        self.quad([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-1, 0, 0), mat,
                  [(z0 * s, y0 * s), (z0 * s, y1 * s), (z1 * s, y1 * s), (z1 * s, y0 * s)])
        self.quad([(x0, y0, z1), (x0, y1, z1), (x1, y1, z1), (x1, y0, z1)], (0, 0, 1), mat,
                  [(x0 * s, y0 * s), (x0 * s, y1 * s), (x1 * s, y1 * s), (x1 * s, y0 * s)])
        self.quad([(x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z0)], (0, 0, -1), mat,
                  [(x1 * s, y0 * s), (x1 * s, y1 * s), (x0 * s, y1 * s), (x0 * s, y0 * s)])

    def cylinder(self, x: float, z: float, r: float, y0: float, y1: float, mat: int,
                 seg: int = 12, uv: float = 0.35) -> None:
        for i in range(seg):
            a0 = math.tau * i / seg
            a1 = math.tau * (i + 1) / seg
            c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
            n = (c0 + c1, 0.0, s0 + s1)
            ln = math.hypot(n[0], n[2]) or 1.0
            n = (n[0] / ln, 0.0, n[2] / ln)
            p0 = (x + r * c0, y0, z + r * s0)
            p1 = (x + r * c1, y0, z + r * s1)
            p2 = (x + r * c1, y1, z + r * s1)
            p3 = (x + r * c0, y1, z + r * s0)
            self.quad([p0, p1, p2, p3], n, mat,
                      [(a0 * r * uv, y0 * uv), (a1 * r * uv, y0 * uv), (a1 * r * uv, y1 * uv), (a0 * r * uv, y1 * uv)])
        # caps
        for y, ny in ((y1, 1.0), (y0, -1.0)):
            for i in range(1, seg - 1):
                a0 = 0.0
                a1 = math.tau * i / seg
                a2 = math.tau * (i + 1) / seg
                pts = [(x + r * math.cos(a), y, z + r * math.sin(a)) for a in (a0, a1, a2)]
                if ny < 0:
                    pts = [pts[0], pts[2], pts[1]]
                self.tri(pts, (0, ny, 0), mat, [(p[0] * uv, p[2] * uv) for p in pts])

    def cone(self, x: float, z: float, r: float, y0: float, y1: float, mat: int, seg: int = 12) -> None:
        apex = (x, y1, z)
        for i in range(seg):
            a0 = math.tau * i / seg
            a1 = math.tau * (i + 1) / seg
            p0 = (x + r * math.cos(a0), y0, z + r * math.sin(a0))
            p1 = (x + r * math.cos(a1), y0, z + r * math.sin(a1))
            n = ((math.cos(a0) + math.cos(a1)) * 0.5, (y1 - y0) * 0.15, (math.sin(a0) + math.sin(a1)) * 0.5)
            ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + n[2] ** 2) or 1.0
            n = (n[0] / ln, n[1] / ln, n[2] / ln)
            self.tri([p0, p1, apex], n, mat, [(0, 0), (1, 0), (0.5, 1)])

    def slope(self, x0: float, z0: float, x1: float, z1: float, y0: float, y1: float, mat: int,
              uv: float = 0.45) -> None:
        """Quad rising from y0 at x0 to y1 at x1, spanning z0..z1. Normal points upward."""
        dx = x1 - x0
        dy = y1 - y0
        length = math.hypot(dx, dy) or 1.0
        n = (-dy / length, dx / length, 0.0) if dx >= 0 else (dy / length, -dx / length, 0.0)
        if n[1] < 0:
            n = (-n[0], -n[1], -n[2])
        self.quad([(x0, y0, z0), (x1, y1, z0), (x1, y1, z1), (x0, y0, z1)], n, mat,
                  [(0, z0 * uv), (abs(dx) * uv, z0 * uv), (abs(dx) * uv, z1 * uv), (0, z1 * uv)])


def pbr(name: str, folder: str, tint: list[float] | None = None, roughness: float = 1.0) -> dict:
    spec = {
        "name": name,
        "doubleSided": True,
        "pbrMetallicRoughness": {
            "baseColorFactor": (tint or [1, 1, 1]) + [1],
            "metallicFactor": 0.0,
            "roughnessFactor": roughness,
            "baseColorTexture": {"index": folder + ":color"},
            "metallicRoughnessTexture": {"index": folder + ":roughness"},
        },
        "normalTexture": {"index": folder + ":normal"},
    }
    return spec


def flat(name: str, color: list[float], rough: float = 0.6, emissive: list[float] | None = None,
         strength: float = 1.0, alpha: float | None = None, tex: str | None = None) -> dict:
    pbr_block: dict = {
        "baseColorFactor": color + ([alpha] if alpha is not None else [1.0]),
        "metallicFactor": 0.0,
        "roughnessFactor": rough,
    }
    if tex:
        pbr_block["baseColorTexture"] = {"index": tex}
    spec: dict = {"name": name, "doubleSided": True, "pbrMetallicRoughness": pbr_block}
    if alpha is not None and alpha < 1.0:
        spec["alphaMode"] = "BLEND"
    if emissive is not None:
        spec["emissiveFactor"] = emissive
        if tex:
            spec["emissiveTexture"] = {"index": tex}
        if strength != 1.0:
            spec["extensions"] = {"KHR_materials_emissive_strength": {"emissiveStrength": strength}}
    return spec


def write_gltf(mesh: Mesh, path: Path, images: dict[str, str]) -> None:
    """images maps a logical id ('Rock030:color') to a uri."""
    blobs: list[bytes] = []
    buffer_views = []
    accessors = []

    def push(data: bytes, target: int | None = None) -> int:
        # 4-byte align
        while sum(len(b) for b in blobs) % 4:
            blobs.append(b"\x00")
        offset = sum(len(b) for b in blobs)
        blobs.append(data)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data)}
        if target:
            view["target"] = target
        buffer_views.append(view)
        return len(buffer_views) - 1

    pos = struct.pack("<" + "f" * len(mesh.positions), *mesh.positions)
    nor = struct.pack("<" + "f" * len(mesh.normals), *mesh.normals)
    uv = struct.pack("<" + "f" * len(mesh.uvs), *mesh.uvs)
    nverts = len(mesh.positions) // 3
    xs = mesh.positions[0::3]
    ys = mesh.positions[1::3]
    zs = mesh.positions[2::3]
    pos_view = push(pos, 34962)
    accessors.append({
        "bufferView": pos_view, "componentType": 5126, "count": nverts, "type": "VEC3",
        "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)],
    })
    nor_view = push(nor, 34962)
    accessors.append({"bufferView": nor_view, "componentType": 5126, "count": nverts, "type": "VEC3"})
    uv_view = push(uv, 34962)
    accessors.append({"bufferView": uv_view, "componentType": 5126, "count": nverts, "type": "VEC2"})

    # resolve texture tokens to image indices
    image_ids: dict[str, int] = {}
    images_json = []
    for key, uri in images.items():
        if key not in image_ids and any(
            (m.get("pbrMetallicRoughness", {}).get("baseColorTexture", {}).get("index") == key)
            or (m.get("pbrMetallicRoughness", {}).get("metallicRoughnessTexture", {}).get("index") == key)
            or (m.get("normalTexture", {}).get("index") == key)
            or (m.get("emissiveTexture", {}).get("index") == key)
            for m in mesh.materials
        ):
            image_ids[key] = len(images_json)
            images_json.append({"uri": uri})

    def remap(node: dict) -> None:
        for k, v in list(node.items()):
            if k in ("baseColorTexture", "metallicRoughnessTexture", "normalTexture", "emissiveTexture") and isinstance(v, dict):
                token = v.get("index")
                if isinstance(token, str):
                    v["index"] = image_ids[token]
            elif isinstance(v, dict):
                remap(v)

    materials = []
    for m in mesh.materials:
        mc = json.loads(json.dumps(m))
        remap(mc)
        materials.append(mc)

    primitives = []
    for mi, inds in mesh.indices.items():
        if not inds:
            continue
        raw = struct.pack("<" + "I" * len(inds), *inds)
        view = push(raw, 34963)
        acc = len(accessors)
        accessors.append({
            "bufferView": view, "componentType": 5125, "count": len(inds), "type": "SCALAR",
        })
        primitives.append({
            "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
            "indices": acc,
            "material": mi,
        })
    blob = b"".join(blobs)
    bin_name = path.stem + ".bin"
    (path.parent / bin_name).write_bytes(blob)
    gltf = {
        "asset": {"version": "2.0", "generator": "build_association_kit.py"},
        "extensionsUsed": ["KHR_materials_emissive_strength"],
        "buffers": [{"uri": bin_name, "byteLength": len(blob)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
        "images": images_json,
        "textures": [{"source": i} for i in range(len(images_json))],
        "materials": materials,
        "meshes": [{"name": path.stem, "primitives": primitives}],
        "nodes": [{"name": path.stem, "mesh": 0}],
        "scenes": [{"nodes": [0]}],
        "scene": 0,
    }
    # drop the extension flag when nothing uses it
    if not any("extensions" in m for m in materials):
        gltf.pop("extensionsUsed")
    path.write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {path.relative_to(ROOT)}  verts={nverts} tris={sum(len(v) for v in mesh.indices.values()) // 3}")


def make_textures() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    slate = Image.new("RGB", (512, 512), (78, 108, 158))
    draw = ImageDraw.Draw(slate)
    rng = random.Random(7)
    for row in range(16):
        shift = 16 if row % 2 else 0
        y0 = row * 32
        for col in range(-1, 17):
            x0 = col * 32 + shift
            shade = rng.randint(-16, 18)
            color = (92 + shade, 122 + shade, 176 + shade // 2)
            draw.rectangle([x0 + 1, y0 + 1, x0 + 30, y0 + 28], fill=color)
            draw.line([(x0, y0 + 30), (x0 + 32, y0 + 30)], fill=(48, 64, 96))
    slate.filter(ImageFilter.SMOOTH).save(OUT / "slate.jpg", quality=90)

    glass = Image.new("RGBA", (256, 512), (20, 40, 80, 230))
    g = ImageDraw.Draw(glass)
    panes = [
        ((12, 24, 120, 160), (70, 120, 210, 240)),
        ((136, 24, 244, 160), (210, 180, 80, 230)),
        ((12, 176, 120, 320), (90, 160, 230, 230)),
        ((136, 176, 244, 320), (40, 70, 150, 240)),
        ((70, 336, 186, 470), (230, 220, 170, 240)),
    ]
    for rect, color in panes:
        g.rectangle(rect, fill=color)
    for x in (8, 128, 248):
        g.line([(x, 8), (x, 500)], fill=(30, 24, 16, 255), width=6)
    for y in (8, 168, 328, 500):
        g.line([(8, y), (248, y)], fill=(30, 24, 16, 255), width=6)
    g.polygon([(128, 40), (70, 150), (186, 150)], outline=(240, 210, 120, 255))
    g.line([(128, 40), (128, 490)], fill=(240, 210, 120, 255), width=3)
    glass.save(OUT / "glass.png")

    circle = Image.new("RGBA", (512, 512), (8, 12, 28, 255))
    c = ImageDraw.Draw(circle)
    cx = cy = 256
    for r, col, w in (
        (230, (150, 190, 255, 255), 10),
        (190, (90, 140, 255, 255), 6),
        (150, (220, 230, 255, 255), 8),
        (110, (80, 120, 230, 255), 5),
        (70, (255, 255, 255, 255), 6),
    ):
        c.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=w)
    for i in range(12):
        a = math.tau * i / 12
        c.line([(cx + 70 * math.cos(a), cy + 70 * math.sin(a)),
                (cx + 230 * math.cos(a), cy + 230 * math.sin(a))],
               fill=(180, 210, 255, 255), width=3)
    c.regular_polygon((cx, cy, 48), 6, rotation=30, outline=(255, 255, 255, 255), width=4)
    circle.save(OUT / "circle.png")
    print("textures")


def std_images() -> dict[str, str]:
    imgs = {}
    for folder in ("Rock030", "PavingStones131", "Wood049", "Grass004", "Metal032"):
        for kind in ("color", "normal", "roughness"):
            imgs[f"{folder}:{kind}"] = _uri(folder, kind)
    imgs["slate:color"] = "slate.jpg"
    # slate borrows the rock normal and roughness so the tiles catch light
    imgs["Rock030:normal"] = _uri("Rock030", "normal")
    imgs["Rock030:roughness"] = _uri("Rock030", "roughness")
    imgs["glass"] = "glass.png"
    imgs["circle"] = "circle.png"
    return imgs


def stone_mat(mesh: Mesh, name: str = "stone") -> int:
    return mesh.mat(pbr(name, "Rock030", [1.0, 0.98, 0.94], 0.88))


def cobble_mat(mesh: Mesh) -> int:
    return mesh.mat(pbr("cobble", "PavingStones131", [0.85, 0.84, 0.80], 0.95))


def wood_mat(mesh: Mesh, tint: list[float] | None = None, name: str = "wood") -> int:
    return mesh.mat(pbr(name, "Wood049", tint or [0.85, 0.72, 0.5], 0.8))


def grass_mat(mesh: Mesh) -> int:
    return mesh.mat(pbr("grass", "Grass004", [0.75, 0.9, 0.65], 1.0))


def roof_mat(mesh: Mesh) -> int:
    spec = pbr("slate", "Rock030", [1.0, 1.0, 1.0], 0.62)
    spec["pbrMetallicRoughness"]["baseColorTexture"] = {"index": "slate:color"}
    spec["name"] = "slate"
    return mesh.mat(spec)


def metal_mat(mesh: Mesh) -> int:
    return mesh.mat(pbr("iron", "Metal032", [0.55, 0.5, 0.42], 0.45))


def glass_mat(mesh: Mesh) -> int:
    return mesh.mat(flat("glass", [0.55, 0.7, 1.0], 0.15, [0.45, 0.65, 1.0], 3.5, 0.86, "glass"))


def circle_mat(mesh: Mesh) -> int:
    return mesh.mat(flat("circle", [0.35, 0.5, 0.9], 0.4, [0.25, 0.45, 1.0], 2.2, tex="circle"))


def water_mat(mesh: Mesh) -> int:
    return mesh.mat(flat("water", [0.35, 0.62, 0.78], 0.12, [0.15, 0.35, 0.5], 1.4, 0.82))


def _lancet(mesh: Mesh, a: float, b: float, y0: float, y1: float, half: float, mat: int, axis: str) -> None:
    """Pointed window. axis 'x' puts the glass on a constant-x wall (a is x, b is z)."""
    spring = y0 + (y1 - y0) * 0.62
    if axis == "x":
        mesh.quad([(a, y0, b - half), (a, y0, b + half), (a, spring, b + half), (a, spring, b - half)],
                  (1, 0, 0), mat, [(0, 0), (1, 0), (1, 0.7), (0, 0.7)])
        mesh.tri([(a, spring, b - half), (a, spring, b + half), (a, y1, b)], (1, 0, 0), mat,
                 [(0, 0.7), (1, 0.7), (0.5, 1)])
    else:
        nz = 1.0 if b >= 0.0 else -1.0
        mesh.quad([(a - half, y0, b), (a + half, y0, b), (a + half, spring, b), (a - half, spring, b)],
                  (0, 0, nz), mat, [(0, 0), (1, 0), (1, 0.7), (0, 0.7)])
        mesh.tri([(a - half, spring, b), (a + half, spring, b), (a, y1, b)], (0, 0, nz), mat,
                 [(0, 0.7), (1, 0.7), (0.5, 1)])


def add_turret(mesh: Mesh, x: float, z: float, stone: int, roof: int, height: float, cap: float) -> None:
    mesh.cylinder(x, z, 1.55, 0.0, height, stone, 10, 0.4)
    mesh.cone(x, z, 1.85, height - 0.15, height + cap, roof, 10)
    mesh.cylinder(x, z, 1.7, height - 0.35, height + 0.05, stone, 10, 0.5)


def build_hall() -> Mesh:
    m = Mesh()
    stone = stone_mat(m)
    floor = cobble_mat(m)
    glass = glass_mat(m)
    roof = roof_mat(m)
    wood = wood_mat(m)
    iron = metal_mat(m)
    # nave floor, stopped at the spire's south face (z -9) so the tower reads as the sanctuary
    m.box((0, 0.04, 3.2), (21.6, 0.08, 24.4), floor, 0.5)
    # side chapels beside the spire, and the sanctuary floor under the spire
    m.box((-8.6, 0.04, -12.2), (6.4, 0.08, 6.4), floor, 0.5)
    m.box((8.6, 0.04, -12.2), (6.4, 0.08, 6.4), floor, 0.5)
    m.box((0.0, 0.04, -12.1), (11.2, 0.08, 6.8), floor, 0.5)
    # west wall, split around the courtyard door (z -2.4..2.4)
    for zc, zs in ((-9.0, 13.0), (9.0, 13.0)):
        m.box((-11.5, 3.7, zc), (1.0, 7.4, zs), stone, 0.32)
    # east wall, split around the library door
    for zc, zs in ((-9.0, 13.0), (9.0, 13.0)):
        m.box((11.5, 3.7, zc), (1.0, 7.4, zs), stone, 0.32)
    # south wall, split around the town door (x -2.6..2.6)
    m.box((-7.2, 3.7, 15.5), (9.2, 7.4, 1.0), stone, 0.32)
    m.box((7.2, 3.7, 15.5), (9.2, 7.4, 1.0), stone, 0.32)
    # door lintel
    m.box((0, 6.55, 15.5), (5.2, 1.3, 1.0), stone, 0.4)
    # north return walls beside the spire (x beyond ±6)
    m.box((-9.0, 3.7, -15.5), (6.0, 7.4, 1.0), stone, 0.32)
    m.box((9.0, 3.7, -15.5), (6.0, 7.4, 1.0), stone, 0.32)
    # south gable
    m.tri([(-12.2, 7.4, 15.7), (12.2, 7.4, 15.7), (0, 13.6, 15.7)], (0, 0, 1), stone,
          [(0, 0), (1, 0), (0.5, 1)])
    # pointed glass in the south gable and above the door
    m.tri([(-1.3, 8.0, 15.75), (1.3, 8.0, 15.75), (0, 12.4, 15.75)], (0, 0, 1), glass,
          [(0, 0), (1, 0), (0.5, 1)])
    m.tri([(-1.6, 1.2, 16.05), (1.6, 1.2, 16.05), (0, 5.6, 16.05)], (0, 0, 1), glass,
          [(0, 0), (1, 0), (0.5, 1)])
    # sanctuary glass, seen through the spire door, on the north wall line
    m.tri([(-2.2, 1.4, -15.15), (2.2, 1.4, -15.15), (0, 8.6, -15.15)], (0, 0, -1), glass,
          [(0, 0), (1, 0), (0.5, 1)])
    # lancet windows on the courtyard wall
    for z in (-8.5, -4.6, 4.6, 8.5):
        _lancet(m, -12.05, z, 1.5, 5.6, 0.95, glass, axis="x")
    # buttresses on the courtyard side only (the library occupies the east)
    for z in (-13.2, -8.6, -4.2, 4.2, 8.6, 13.2):
        m.box((-12.7, 2.2, z), (1.5, 4.4, 0.7), stone, 0.4)
        m.box((-12.35, 4.8, z), (0.9, 1.6, 0.55), stone, 0.4)
    # south buttresses flanking the door
    for x in (-3.4, 3.4):
        m.box((x, 3.2, 16.3), (0.7, 6.4, 1.3), stone, 0.4)
    # columns
    for x in (-5.0, 5.0):
        for z in (-8.0, -2.0, 4.0):
            m.cylinder(x, z, 0.42, 0.0, 6.6, stone, 8, 0.5)
            m.box((x, 6.85, z), (1.15, 0.4, 1.15), stone, 0.5)
    # timber ties between the capitals, not solid gables
    for z in (-8.0, -2.0, 4.0):
        m.box((0.0, 6.85, z), (9.2, 0.22, 0.28), wood, 0.7)
    # dais and steps (the collider is the same footprint)
    m.box((0, 0.2, -10.0), (6.0, 0.28, 4.0), floor, 0.6)
    m.box((0, 0.1, -7.7), (6.0, 0.14, 0.7), floor, 0.6)
    m.box((0, 0.04, -7.2), (6.4, 0.08, 0.55), floor, 0.6)
    # lectern so the open book has a stand
    m.box((0, 0.62, -10.0), (0.7, 0.7, 0.45), wood, 0.8)
    m.box((0, 1.0, -10.15), (0.9, 0.08, 0.55), wood, 0.8)
    # iron candle stands
    for x, z in ((-2.2, -9.2), (2.2, -9.2), (-3.2, 2.0), (3.2, 2.0)):
        m.cylinder(x, z, 0.08, 0.0, 1.15, iron, 6, 1.0)
        m.cylinder(x, z, 0.14, 1.1, 1.25, iron, 6, 1.0)
    # corner spires. South pair frames the town door. North pair flanks the great spire.
    add_turret(m, -11.6, 15.6, stone, roof, 16.5, 6.5)
    add_turret(m, 11.6, 15.6, stone, roof, 16.5, 6.5)
    add_turret(m, -11.6, -15.4, stone, roof, 12.0, 4.5)
    add_turret(m, 11.6, -15.4, stone, roof, 12.0, 4.5)
    return m


def build_hall_roof() -> Mesh:
    m = Mesh()
    roof = roof_mat(m)
    # ridge along Z, eaves at the side walls, stopped before the spire (z -8.4)
    m.slope(-12.6, -8.4, 0.0, 16.4, 7.25, 13.7, roof)
    m.slope(12.6, -8.4, 0.0, 16.4, 7.25, 13.7, roof)
    # ridge cap
    iron = metal_mat(m)
    m.box((0, 13.85, 4.0), (0.35, 0.22, 25.0), iron, 0.3)
    return m


def build_library() -> Mesh:
    m = Mesh()
    stone = stone_mat(m)
    wood = wood_mat(m)
    floor = wood_mat(m, [0.7, 0.55, 0.38], "library_floor")
    glass = glass_mat(m)
    book_a = wood_mat(m, [0.55, 0.22, 0.16], "book_red")
    book_b = wood_mat(m, [0.18, 0.22, 0.4], "book_blue")
    book_c = wood_mat(m, [0.35, 0.26, 0.14], "book_brown")
    books = (book_a, book_b, book_c)
    # floor x 12.4..35.6, z -12.6..12.6
    m.box((24.0, 0.04, 0.0), (23.2, 0.08, 25.2), floor, 0.55)
    # outer walls. The west side is the hall's east wall, already built, with its door.
    m.box((35.7, 3.3, 0.0), (0.8, 6.6, 26.0), stone, 0.32)
    m.box((24.0, 3.3, -13.1), (23.4, 6.6, 0.8), stone, 0.32)
    m.box((24.0, 3.3, 13.1), (23.4, 6.6, 0.8), stone, 0.32)
    for z in (-8.0, -2.5, 3.0, 8.5):
        _lancet(m, 36.15, z, 1.4, 5.0, 0.85, glass, axis="x")
    for x in (18.0, 24.0, 30.0):
        _lancet(m, x, 13.55, 1.4, 4.8, 0.8, glass, axis="z")
        _lancet(m, x, -13.55, 1.4, 4.8, 0.8, glass, axis="z")
    rng = random.Random(3)

    def shelf_run(x: float, z0: float, z1: float, depth: float, face: float) -> None:
        length = abs(z1 - z0)
        zc = (z0 + z1) * 0.5
        m.box((x, 2.55, zc), (depth, 5.1, length), wood, 0.6)
        # shelf lips
        for y in (0.9, 1.8, 2.7, 3.6, 4.5):
            m.box((x + face * 0.08, y, zc), (depth + 0.12, 0.06, length), wood, 0.8)
            z = z0 + 0.3
            while z < z1 - 0.3:
                h = rng.uniform(0.28, 0.55)
                w = rng.uniform(0.08, 0.16)
                mat = books[rng.randrange(3)]
                m.box((x + face * (depth * 0.55), y + 0.05 + h * 0.5, z), (0.22, h, w), mat, 1.2)
                z += w + 0.02

    shelf_run(34.3, -11.2, -1.2, 1.15, -1)
    shelf_run(34.3, 1.2, 11.2, 1.15, -1)
    shelf_run(27.2, -11.0, -2.2, 1.05, 1)
    shelf_run(27.2, 2.2, 11.0, 1.05, -1)
    shelf_run(19.4, -11.0, -2.6, 0.9, 1)
    shelf_run(19.4, 2.6, 5.2, 0.9, -1)
    shelf_run(19.4, 8.6, 11.2, 0.9, -1)
    # reading tables
    for z in (-6.5, 0.0, 6.5):
        m.box((23.2, 0.4, z), (1.8, 0.08, 1.05), wood, 0.8)
        m.box((22.55, 0.2, z), (0.12, 0.4, 1.0), wood, 0.8)
        m.box((23.85, 0.2, z), (0.12, 0.4, 1.0), wood, 0.8)
    return m


def build_library_roof() -> Mesh:
    m = Mesh()
    roof = roof_mat(m)
    # ridge along Z at x 24
    m.slope(12.3, -13.6, 24.0, 13.6, 6.5, 10.4, roof)
    m.slope(36.4, -13.6, 24.0, 13.6, 6.5, 10.4, roof)
    iron = metal_mat(m)
    m.box((24.0, 10.5, 0.0), (0.28, 0.16, 27.4), iron, 0.3)
    return m


def _ellipse(i: int, n: int = SEGMENTS) -> tuple[float, float]:
    th = math.tau * i / n
    return (CX + RX * math.cos(th), CZ + RZ * math.sin(th))


def _gate_segment(p0: tuple[float, float], p1: tuple[float, float]) -> bool:
    mx = (p0[0] + p1[0]) * 0.5
    mz = (p0[1] + p1[1]) * 0.5
    return mz > CZ + RZ * 0.86 and abs(mx - CX) < 4.2


def build_precinct() -> Mesh:
    m = Mesh()
    stone = stone_mat(m)
    roof = roof_mat(m)
    grass = grass_mat(m)
    cobble = cobble_mat(m)
    iron = metal_mat(m)
    # lawn covers the flat close, including the corners outside the round wall,
    # so the rectangular terrain pad does not show as a brown frame
    cy = 0.012
    step = 4.0
    x = CX - RX - 8.0
    while x < CX + RX + 8.0:
        z = CZ - RZ - 8.0
        while z < CZ + RZ + 8.0:
            corners = ((x, z), (x + step, z), (x + step, z + step), (x, z + step))
            m.quad(
                [(px, cy, pz) for px, pz in corners],
                (0, 1, 0), grass,
                [(px * 0.22, pz * 0.22) for px, pz in corners],
            )
            z += step
        x += step
    # curtain wall
    pts = [_ellipse(i) for i in range(SEGMENTS)]
    gap_pts = []
    for i in range(SEGMENTS):
        p0 = pts[i]
        p1 = pts[(i + 1) % SEGMENTS]
        if _gate_segment(p0, p1):
            gap_pts.extend((p0, p1))
            continue
        _segment_wall(m, p0, p1, 2.55, 0.85, stone)
    # towers on every third vertex, skipping the gate
    for i in range(0, SEGMENTS, 3):
        p = pts[i]
        nxt = pts[(i + 1) % SEGMENTS]
        if _gate_segment(p, nxt) or _gate_segment(pts[(i - 1) % SEGMENTS], p):
            continue
        add_turret(m, p[0], p[1], stone, roof, 5.4, 2.6)
    # south gatehouse
    gz = CZ + RZ
    for x in (CX - 3.6, CX + 3.6):
        add_turret(m, x, gz - 0.4, stone, roof, 6.2, 2.8)
    # arch between the gate towers
    m.tri([(CX - 2.3, 2.4, gz), (CX + 2.3, 2.4, gz), (CX, 5.3, gz)], (0, 0, 1), stone,
          [(0, 0), (1, 0), (0.5, 1)])
    m.box((CX, 2.5, gz), (0.12, 2.6, 0.12), iron, 1.0)  # gate leaf hinge post, open
    # open iron leaves swung back
    m.box((CX - 2.0, 1.4, gz - 1.3), (0.08, 2.5, 1.6), iron, 0.8)
    m.box((CX + 2.0, 1.4, gz - 1.3), (0.08, 2.5, 1.6), iron, 0.8)
    # cobble avenue from the hall door to the gate, and a loop inside the wall
    _ribbon(m, [(0.0, 16.4), (0.0, 30.0), (CX, gz - 2.4)], 5.2, 0.03, cobble)
    _ribbon(m, [(-12.4, 0.2), (-20.0, 3.0), (-26.0, 6.0)], 2.6, 0.03, cobble)
    loop = []
    seg = 28
    for i in range(seg):
        th = math.tau * i / seg
        loop.append((CX + (RX - 4.2) * math.cos(th), CZ + (RZ - 4.0) * math.sin(th)))
    for i in range(seg):
        _ribbon(m, [loop[i], loop[(i + 1) % seg]], 2.3, 0.025, cobble)
    # front stair, three shallow treads outside the town door
    for i, z in enumerate((16.5, 17.15, 17.8)):
        m.box((0, 0.045 + i * 0.012, z), (8.5 - i * 0.4, 0.06, 0.62), cobble, 0.5)
    return m


def _segment_wall(m: Mesh, p0: tuple[float, float], p1: tuple[float, float],
                  height: float, thick: float, mat: int) -> None:
    dx, dz = p1[0] - p0[0], p1[1] - p0[1]
    length = math.hypot(dx, dz) or 1.0
    tx, tz = dx / length, dz / length
    # left normal, thickness centered on the segment
    nx, nz = -tz, tx
    h = height
    y0, y1 = 0.0, h

    def v(s: float, u: float, y: float) -> tuple[float, float, float]:
        # s along segment 0..1, u across -0.5..0.5
        px = p0[0] + dx * s + nx * thick * u
        pz = p0[1] + dz * s + nz * thick * u
        return (px, y, pz)

    # four sides + top
    m.quad([v(0, -0.5, y0), v(1, -0.5, y0), v(1, -0.5, y1), v(0, -0.5, y1)],
           (-nx, 0, -nz), mat, [(0, 0), (length * 0.35, 0), (length * 0.35, y1 * 0.35), (0, y1 * 0.35)])
    m.quad([v(1, 0.5, y0), v(0, 0.5, y0), v(0, 0.5, y1), v(1, 0.5, y1)],
           (nx, 0, nz), mat, [(0, 0), (length * 0.35, 0), (length * 0.35, y1 * 0.35), (0, y1 * 0.35)])
    m.quad([v(0, 0.5, y0), v(0, -0.5, y0), v(0, -0.5, y1), v(0, 0.5, y1)],
           (-tx, 0, -tz), mat, [(0, 0), (thick * 0.35, 0), (thick * 0.35, y1 * 0.35), (0, y1 * 0.35)])
    m.quad([v(1, -0.5, y0), v(1, 0.5, y0), v(1, 0.5, y1), v(1, -0.5, y1)],
           (tx, 0, tz), mat, [(0, 0), (thick * 0.35, 0), (thick * 0.35, y1 * 0.35), (0, y1 * 0.35)])
    m.quad([v(0, -0.5, y1), v(1, -0.5, y1), v(1, 0.5, y1), v(0, 0.5, y1)],
           (0, 1, 0), mat, [(0, 0), (length * 0.35, 0), (length * 0.35, thick * 0.35), (0, thick * 0.35)])
    # merlons
    steps = max(1, int(length / 1.7))
    for k in range(steps):
        if k % 2:
            continue
        s = (k + 0.5) / steps
        c = v(s, 0.0, y1 + 0.28)
        # orient a small box in world; approximate with an axis box (merlons read at this size)
        m.box(c, (0.7, 0.56, 0.7), mat, 0.6)


def _ribbon(m: Mesh, pts: list[tuple[float, float]], width: float, y: float, mat: int) -> None:
    half = width * 0.5
    for i in range(len(pts) - 1):
        x0, z0 = pts[i]
        x1, z1 = pts[i + 1]
        dx, dz = x1 - x0, z1 - z0
        ln = math.hypot(dx, dz) or 1.0
        nx, nz = -dz / ln, dx / ln
        a = (x0 + nx * half, y, z0 + nz * half)
        b = (x1 + nx * half, y, z1 + nz * half)
        c = (x1 - nx * half, y, z1 - nz * half)
        d = (x0 - nx * half, y, z0 - nz * half)
        m.quad([a, b, c, d], (0, 1, 0), mat,
               [(a[0] * 0.4, a[2] * 0.4), (b[0] * 0.4, b[2] * 0.4), (c[0] * 0.4, c[2] * 0.4), (d[0] * 0.4, d[2] * 0.4)])


def build_circle() -> Mesh:
    m = Mesh()
    mat = circle_mat(m)
    y = 0.09
    r = 3.35
    seg = 32
    for i in range(seg):
        a0 = math.tau * i / seg
        a1 = math.tau * (i + 1) / seg
        p0 = (r * math.cos(a0), y, r * math.sin(a0))
        p1 = (r * math.cos(a1), y, r * math.sin(a1))
        m.tri([(0, y, 0), p0, p1], (0, 1, 0), mat,
              [(0.5, 0.5), (0.5 + 0.5 * math.cos(a0), 0.5 + 0.5 * math.sin(a0)),
               (0.5 + 0.5 * math.cos(a1), 0.5 + 0.5 * math.sin(a1))])
    return m


def build_fountain() -> Mesh:
    m = Mesh()
    stone = stone_mat(m)
    water = water_mat(m)
    m.cylinder(0, 0, 3.15, 0.0, 0.72, stone, 16, 0.35)
    m.cylinder(0, 0, 2.55, 0.62, 0.68, water, 16, 0.4)
    m.cylinder(0, 0, 0.42, 0.7, 1.85, stone, 8, 0.5)
    m.cylinder(0, 0, 1.55, 1.7, 2.15, stone, 14, 0.4)
    m.cylinder(0, 0, 1.15, 2.05, 2.12, water, 14, 0.4)
    m.cylinder(0, 0, 0.22, 2.1, 2.85, stone, 8, 0.6)
    m.cylinder(0, 0, 0.62, 2.7, 3.05, stone, 12, 0.5)
    m.cylinder(0, 0, 0.4, 2.95, 3.02, water, 10, 0.5)
    return m


def build_table() -> Mesh:
    m = Mesh()
    wood = wood_mat(m)
    # along local X, benches on ±Z, so a yaw of 90 seats them toward the aisle
    m.box((0, 0.78, 0), (2.1, 0.08, 0.85), wood, 0.9)
    for x in (-0.9, 0.9):
        m.box((x, 0.38, 0), (0.1, 0.76, 0.7), wood, 0.8)
    for z in (-0.72, 0.72):
        m.box((0, 0.42, z), (1.7, 0.08, 0.32), wood, 0.9)
        m.box((0, 0.22, z), (1.5, 0.08, 0.28), wood, 0.9)
    return m


def curtain_boxes() -> str:
    lines = []
    pts = [_ellipse(i) for i in range(SEGMENTS)]
    for i in range(SEGMENTS):
        p0 = pts[i]
        p1 = pts[(i + 1) % SEGMENTS]
        if _gate_segment(p0, p1):
            continue
        dx, dz = p1[0] - p0[0], p1[1] - p0[1]
        length = math.hypot(dx, dz) + 0.35
        yaw = math.degrees(math.atan2(dz, dx))
        mx, mz = (p0[0] + p1[0]) * 0.5, (p0[1] + p1[1]) * 0.5
        lines.append(
            "[[box]]\n"
            f'name = "curtain_{i:02d}"\n'
            'kind = "wall"\n'
            f"center = [{mx:.2f}, 1.45, {mz:.2f}]\n"
            f"size = [{length:.2f}, 2.9, 0.8]\n"
            f"rotation_deg = [0.0, {yaw:.2f}, 0.0]\n"
            "color = [0.45, 0.44, 0.42]\n"
            "hidden = true\n"
        )
    # gate towers block the shoulders of the opening but leave a 5 m walk
    gz = CZ + RZ
    for side, x in (("w", CX - 3.6), ("e", CX + 3.6)):
        lines.append(
            "[[box]]\n"
            f'name = "gate_tower_{side}"\n'
            'kind = "wall"\n'
            f"center = [{x:.2f}, 2.4, {gz - 0.4:.2f}]\n"
            "size = [2.4, 4.8, 2.4]\n"
            "color = [0.45, 0.44, 0.42]\n"
            "hidden = true\n"
        )
    return "\n".join(lines)


def build_flames() -> Mesh:
    m = Mesh()
    warm = m.mat(flat("flame", [1.0, 0.72, 0.38], 0.4, [1.0, 0.55, 0.22], 5.0))
    blue = m.mat(flat("arc", [0.45, 0.65, 1.0], 0.25, [0.35, 0.6, 1.0], 6.0))
    for x, z, y in (
        (-2.2, -9.2, 1.22), (2.2, -9.2, 1.22), (-3.2, 2.0, 1.22), (3.2, 2.0, 1.22),
        (-10.2, -6.0, 1.7), (10.2, -6.0, 1.7), (0.0, 14.2, 2.4),
        (24.0, -6.0, 1.5), (24.0, 6.0, 1.5),
    ):
        m.cylinder(x, z, 0.1, y, y + 0.22, warm, 6, 1.0)
    m.cylinder(0.0, 0.8, 1.55, 0.1, 0.16, blue, 12, 1.0)
    return m


def attach_lights(path: Path) -> None:
    gltf = json.loads(path.read_text(encoding="utf-8"))
    used = gltf.setdefault("extensionsUsed", [])
    if "KHR_lights_punctual" not in used:
        used.append("KHR_lights_punctual")
    spec = [
        ([0.0, 4.2, 2.0], [1.0, 0.72, 0.45], 160.0, 18.0),
        ([0.0, 3.2, 0.8], [0.45, 0.65, 1.0], 220.0, 14.0),
        ([0.0, 3.4, -10.0], [1.0, 0.78, 0.5], 90.0, 10.0),
        ([24.0, 3.4, 0.0], [1.0, 0.7, 0.42], 140.0, 16.0),
        ([-26.0, 2.4, 6.0], [0.7, 0.85, 1.0], 40.0, 8.0),
        ([CX, 3.2, CZ + RZ - 1.0], [1.0, 0.7, 0.4], 70.0, 12.0),
    ]
    gltf["extensions"] = {"KHR_lights_punctual": {"lights": [
        {"type": "point", "color": color, "intensity": intensity, "range": radius}
        for _pos, color, intensity, radius in spec
    ]}}
    nodes = gltf["nodes"]
    scene_nodes = gltf["scenes"][0]["nodes"]
    for i, (pos, _c, _i, _r) in enumerate(spec):
        nodes.append({
            "name": f"lamp_{i}",
            "translation": pos,
            "extensions": {"KHR_lights_punctual": {"light": i}},
        })
        scene_nodes.append(len(nodes) - 1)
    path.write_text(json.dumps(gltf, separators=(",", ":")), encoding="utf-8")


def main() -> None:
    make_textures()
    images = std_images()
    write_gltf(build_hall(), OUT / "hall.gltf", images)
    write_gltf(build_hall_roof(), OUT / "hall_roof.gltf", images)
    write_gltf(build_library(), OUT / "library.gltf", images)
    write_gltf(build_library_roof(), OUT / "library_roof.gltf", images)
    write_gltf(build_precinct(), OUT / "precinct.gltf", images)
    write_gltf(build_circle(), OUT / "circle.gltf", images)
    write_gltf(build_fountain(), OUT / "fountain.gltf", images)
    write_gltf(build_table(), OUT / "table.gltf", images)
    flames = OUT / "flames.gltf"
    write_gltf(build_flames(), flames, images)
    attach_lights(flames)
    (OUT / "curtain_boxes.toml").write_text(curtain_boxes(), encoding="utf-8")
    print("curtain boxes", curtain_boxes().count("[[box]]"))


if __name__ == "__main__":
    main()
