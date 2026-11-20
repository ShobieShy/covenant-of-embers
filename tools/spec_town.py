#!/usr/bin/env python3
"""Eldoria packed onto docs/maps/levels/town.jpg.

The painting is the plan. Buildings are sized so their footprints fill the ring:
a cathedral about 45 m tall inside the north wall, 9 m stone walls with round
towers, and an oak whose canopy is about 70 m. Roofs use CC0 textures, not the
kit's pink placeholder.
"""
from __future__ import annotations

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOWN = "assets/kenney/fantasy-town-kit/"
NATURE = "assets/kenney/nature-kit/"
OAK = "assets/original/old_oak/OldOak_Giant.glb"
CRYSTAL = "assets/original/ember_art/props/ward_crystal.gltf"
CRATE = "assets/original/ember_art/warrens/crate_stack.glb"
BRICK = "assets/ambientcg/Bricks076C"
ROCK = "assets/ambientcg/Rock030"
WOOD = "assets/ambientcg/Wood049"

S = 160.0 / math.hypot(0.50 - 0.52, 0.80 - 0.52)
TOP = 12.0
SLATE = (0.34, 0.45, 0.62)
SHINGLE = (0.18, 0.16, 0.15)
BLUE_SLATE = (0.26, 0.36, 0.55)


def world(nx: float, ny: float) -> tuple[float, float]:
    return ((nx - 0.5) * S, (ny - 0.5) * S)


def _f(n: float) -> str:
    return f"{round(n, 3)}"


def center() -> tuple[float, float]:
    return world(0.52, 0.52)


def _ray(a: float, cx: float, cz: float, rx: float, rz: float) -> float:
    """Distance along a ray from the town centre (angle 0 = south) to an ellipse."""
    ox, oz = center()
    dx, dz = ox - cx, oz - cz
    sx, sz = math.sin(a), math.cos(a)
    aa = (sx * sx) / (rx * rx) + (sz * sz) / (rz * rz)
    bb = 2.0 * (dx * sx / (rx * rx) + dz * sz / (rz * rz))
    cc = (dx * dx) / (rx * rx) + (dz * dz) / (rz * rz) - 1.0
    disc = bb * bb - 4.0 * aa * cc
    if disc < 0.0 or aa == 0.0:
        return 0.0
    root = math.sqrt(disc)
    hits = [t for t in ((-bb + root) / (2.0 * aa), (-bb - root) / (2.0 * aa)) if t > 2.0]
    return max(hits) if hits else 0.0


def wall_r(a: float) -> float:
    """Outer wall distance from the town centre. South gate sits on it; north and east bulge."""
    ox, oz = center()
    oak = world(0.82, 0.38)
    r = 166.0
    r = max(r, _ray(a, ox, oz - 55.0, 78.0, 95.0))
    r = max(r, _ray(a, oak[0], oak[1], 62.0, 54.0))
    return r


def inward(p: tuple[float, float], pad: float) -> tuple[float, float]:
    x, z = p
    ox, oz = center()
    dx, dz = x - ox, z - oz
    dist = math.hypot(dx, dz) or 1.0
    limit = wall_r(math.atan2(dx, dz)) - pad
    if dist <= limit:
        return x, z
    s = limit / dist
    return ox + dx * s, oz + dz * s


def prop(name, model, pos, rot=0.0, scale=1.0, count=1, step=(0, 0, 0), snap=False, tint=None, tex=""):
    sc = f"{scale}" if not isinstance(scale, (list, tuple)) else "[%s]" % ", ".join(_f(s) for s in scale)
    s = (f'[[prop]]\nname = "{name}"\nmodel = "{model}"\n'
         f"position = [{', '.join(_f(p) for p in pos)}]\n"
         f"rotation_deg = [0.0, {_f(rot)}, 0.0]\nscale = {sc}\n")
    if count > 1:
        s += f"count = {count}\nstep = [{', '.join(_f(p) for p in step)}]\n"
    if snap:
        s += "snap = true\n"
    if tint:
        s += "tint = [%s]\n" % ", ".join(_f(c) for c in tint)
        s += f'tex = "{tex}"\n'
    return s


def ground(name, x, z, sx, sz, top=TOP) -> str:
    return (f'[[box]]\nname = "{name}"\nkind = "ground"\n'
            f"center = [{_f(x)}, {_f(top - 0.1)}, {_f(z)}]\n"
            f"size = [{_f(sx)}, 0.2, {_f(sz)}]\ncolor = [0.36, 0.34, 0.31]\n")


def collider(name, x, y, z, sx, sy, sz, yaw=0.0) -> str:
    return (f'[[box]]\nname = "{name}"\nkind = "wall"\n'
            f"center = [{_f(x)}, {_f(y)}, {_f(z)}]\n"
            f"size = [{_f(sx)}, {_f(sy)}, {_f(sz)}]\n"
            f"rotation_deg = [0.0, {_f(yaw)}, 0.0]\ncolor = [0.42, 0.4, 0.37]\n")


def _samples(pts, step):
    out = []
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        length = math.hypot(bx - ax, bz - az)
        n = max(1, round(length / step))
        for i in range(n):
            t = (i + 0.5) / n
            out.append((ax + (bx - ax) * t, az + (bz - az) * t))
    return out


def _bezier(a, b, c, step):
    n = max(2, round((math.hypot(b[0] - a[0], b[1] - a[1]) + math.hypot(c[0] - b[0], c[1] - b[1])) / step))
    pts = []
    for i in range(n):
        t = (i + 0.5) / n
        u = 1.0 - t
        pts.append((u * u * a[0] + 2 * u * t * b[0] + t * t * c[0], u * u * a[1] + 2 * u * t * b[1] + t * t * c[1]))
    return pts


def landmarks() -> dict:
    square = world(0.50, 0.55)
    gate = world(0.50, 0.80)
    east = inward(world(0.71, 0.66), 8.0)
    oak = world(0.82, 0.38)
    door = (oak[0] - 16.0, oak[1] + 14.0)
    assoc = inward(world(0.50, 0.22), 36.0)
    library = (assoc[0] + 58.0, assoc[1] + 6.0)
    flagon = inward(world(0.24, 0.53), 18.0)
    garden = inward(world(0.30, 0.32), 20.0)
    market_w = inward(world(0.42, 0.43), 12.0)
    market_e = inward(world(0.61, 0.45), 12.0)
    return locals()


def curtain() -> list[tuple]:
    """(name, x, z, yaw) for the stone curtain, gaps at the two gates."""
    ox, oz = center()
    g = landmarks()
    gates = [g["gate"], g["east"]]
    out = []
    steps = 210
    for i in range(steps):
        a = 2.0 * math.pi * i / steps
        r = wall_r(a) - 4.0
        x, z = ox + r * math.sin(a), oz + r * math.cos(a)
        if any(math.hypot(x - gx, z - gz) < 12.0 for gx, gz in gates):
            continue
        # Tangent (cos a, -sin a). Yaw maps the panel's length onto it.
        yaw = math.degrees(math.atan2(math.cos(a), -math.sin(a)))
        out.append((f"col_{i}", x, z, yaw, a))
    return out


def hide_names() -> set[str]:
    names = {n for n, *_ in curtain()}
    names.update({f"col_h{i}" for i in range(len(_houses()))})
    names.update({"col_cathedral", "col_library", "col_flagon", "col_oak", "col_tower_w", "col_tower_e"})
    return names


def _houses() -> list[tuple]:
    """Houses packed along the wall and a second row closer to the square."""
    ox, oz = center()
    spots = []
    outer = (18, 36, 54, 72, 96, 118, 142, 198, 218, 238, 258, 286, 312, 334, 352)
    inner = (24, 64, 100, 150, 210, 250, 300, 346)
    n = 0
    for deg in outer:
        a = math.radians(deg)
        r = wall_r(a) * 0.8
        spots.append((f"h{n}", ox + r * math.sin(a), oz + r * math.cos(a), deg))
        n += 1
    for deg in inner:
        a = math.radians(deg)
        r = wall_r(a) * 0.5
        spots.append((f"h{n}", ox + r * math.sin(a), oz + r * math.cos(a), deg))
        n += 1
    return spots


def path_boxes() -> list[str]:
    g = landmarks()
    sq, gate = g["square"], g["gate"]
    boxes = []
    # Round plaza, not a square cross.
    boxes.append(ground("square", sq[0], sq[1], 18.0, 18.0))
    for i in range(18):
        a = 2.0 * math.pi * i / 18.0
        boxes.append(ground(f"plaza_{i}", sq[0] + 16.0 * math.sin(a), sq[1] + 16.0 * math.cos(a), 12.0, 12.0))
    lanes = [
        _bezier(gate, (sq[0] + 18.0, (gate[1] + sq[1]) * 0.55), sq, 6.5),
        _bezier(sq, (sq[0] - 28.0, sq[1] - 36.0), g["assoc"], 6.5),
        _bezier(sq, (sq[0] - 40.0, sq[1] + 10.0), g["flagon"], 6.5),
        _bezier(g["flagon"], (g["garden"][0] + 10.0, g["flagon"][1] - 20.0), g["garden"], 6.5),
        _bezier(g["garden"], (g["assoc"][0] - 24.0, g["garden"][1] - 10.0), g["assoc"], 6.5),
        _bezier(sq, (g["market_e"][0], sq[1] - 8.0), g["market_e"], 6.5),
        _bezier(g["market_e"], (g["east"][0] - 10.0, g["market_e"][1] + 30.0), g["east"], 6.5),
        _bezier(g["market_e"], ((g["market_e"][0] + g["door"][0]) * 0.5, (g["market_e"][1] + g["door"][1]) * 0.5 - 12.0), g["door"], 6.5),
        _bezier(sq, (g["market_w"][0], sq[1] - 6.0), g["market_w"], 6.5),
    ]
    # Inner lane follows the wall, so it curves.
    ox, oz = center()
    ring = []
    for i in range(36):
        a = 2.0 * math.pi * i / 36.0
        r = wall_r(a) * 0.62
        ring.append((ox + r * math.sin(a), oz + r * math.cos(a)))
    ring.append(ring[0])
    lanes.append(ring)
    n = 0
    for lane in lanes:
        for x, z in lane:
            boxes.append(ground(f"path_{n}", x, z, 8.0, 8.0))
            n += 1
    gx, gz = gate
    for i, z in enumerate(_samples([(gx, gz + 6.0), (gx + 8.0, gz + 40.0), (gx - 6.0, gz + 78.0)], 7.0)):
        boxes.append(ground(f"slope_s_{i}", z[0], z[1], 8.0, 7.0, TOP - (i + 1) * 1.6))
    ex, ez = g["east"]
    for i, p in enumerate(_samples([(ex, ez + 8.0), (ex + 22.0, ez + 36.0), (ex + 40.0, ez + 70.0)], 7.0)):
        boxes.append(ground(f"slope_e_{i}", p[0], p[1], 7.0, 7.0, TOP - (i + 1) * 1.4))
    boxes.append(ground("gate_pad", gx, gz - 6.0, 20.0, 16.0))
    boxes.append(ground("oak_pad", g["door"][0], g["door"][1], 10.0, 10.0))
    boxes.append(ground("door_pad", g["assoc"][0], g["assoc"][1] + 24.0, 14.0, 10.0))
    boxes.append(ground("flagon_pad", g["flagon"][0] + 14.0, g["flagon"][1], 10.0, 10.0))
    boxes.append(ground("market_w_pad", g["market_w"][0], g["market_w"][1], 22.0, 14.0))
    boxes.append(ground("market_e_pad", g["market_e"][0], g["market_e"][1], 26.0, 14.0))
    return boxes


def structure_text() -> str:
    g = landmarks()
    ox, oz = center()
    oak, gate, assoc = g["oak"], g["gate"], g["assoc"]
    boxes = path_boxes()
    for name, x, z, yaw, _a in curtain():
        boxes.append(collider(name, x, TOP + 4.5, z, 2.4, 9.2, 3.6, yaw))
    boxes.append(collider("col_cathedral", assoc[0], TOP + 14.0, assoc[1], 62.0, 28.0, 44.0))
    boxes.append(collider("col_library", g["library"][0], TOP + 8.0, g["library"][1], 52.0, 16.0, 20.0))
    boxes.append(collider("col_flagon", g["flagon"][0], TOP + 6.0, g["flagon"][1], 22.0, 14.0, 16.0))
    boxes.append(collider("col_oak", oak[0], TOP + 16.0, oak[1], 14.0, 30.0, 14.0))
    boxes.append(collider("col_tower_w", gate[0] - 12.0, TOP + 9.0, gate[1] - 2.0, 3.4, 18.0, 3.4))
    boxes.append(collider("col_tower_e", gate[0] + 12.0, TOP + 9.0, gate[1] - 2.0, 3.4, 18.0, 3.4))
    for name, x, z, _yaw in _houses():
        boxes.append(collider(f"col_{name}", x, TOP + 6.0, z, 16.0, 12.0, 14.0))
    body = f"""# Eldoria, 0.11.3. Packed onto the town painting. Streets sit on a plateau.

[level]
id = "town_square"
name = "Eldoria - Town Square"
world_offset = [0.0, 0.0]

[materials]
ground = "assets/ambientcg/PavingStones131"
uv_scale = 0.25

[environment]
sky_color = [0.55, 0.62, 0.86]
ambient_color = [0.48, 0.42, 0.36]
fog_density = 0.0014
sky = true
grade = [1.05, 1.08, 1.14]
dome = 250.0

[sun]
to_light = [0.62, 0.68, 0.24]
color = [1.0, 0.82, 0.58]

[player_start]
position = [{_f(gate[0])}, {_f(TOP)}, {_f(gate[1] - 10.0)}]
yaw_deg = 0.0

[underlay]
image = "docs/maps/levels/town.jpg"
center = [0.0, -4.0, 0.0]
size = [{_f(S)}, {_f(S)}]

[terrain]
size = [780, 780]
center = [30, 0]
height = 1.4
seed = 113
rim = 0
cliff = 24
blend = 12
spacing = 2
map_version = 5
pad_y = 11.95
pad_margin = 0.6
stepped = true
foliage = 7000
layers = ["grass", "rock", "path_cobble"]
plateau = [{_f(ox)}, {_f(oz)}, 176.0, 14.0]
lobe = [{_f(oak[0])}, {_f(oak[1])}, 78.0, 66.0]
keep = [{_f(ox)}, {_f(oz - 70.0)}, 96.0, 110.0]

"""
    actors = f"""[[exit]]
name = "to_association"
to = "mage_association"
position = [{_f(assoc[0])}, {_f(TOP)}, {_f(assoc[1] + 26.0)}]
[[exit]]
name = "to_landfill"
to = "midden"
position = [{_f(gate[0])}, {_f(TOP)}, {_f(gate[1])}]
[[exit]]
name = "to_old_oak"
to = "old_oak"
position = [{_f(g['door'][0])}, {_f(TOP)}, {_f(g['door'][1])}]
[[npc]]
name = "guard_gate"
speaker = "Bored Guard"
position = [{_f(gate[0] + 7.0)}, {_f(TOP)}, {_f(gate[1] - 4.0)}]
yaw_deg = 180.0
[[npc]]
name = "merchant"
speaker = "Potion Merchant"
position = [{_f(g['market_w'][0] - 6.0)}, {_f(TOP)}, {_f(g['market_w'][1])}]
yaw_deg = 90.0
[[npc]]
name = "tailor"
speaker = "Tailor"
position = [{_f(g['market_w'][0] + 6.0)}, {_f(TOP)}, {_f(g['market_w'][1] + 3.0)}]
yaw_deg = 180.0
[[npc]]
name = "runesmith"
speaker = "Runesmith"
position = [{_f(g['market_e'][0])}, {_f(TOP)}, {_f(g['market_e'][1] + 4.0)}]
yaw_deg = 200.0
[[npc]]
name = "patron"
speaker = "Grizzled Patron"
position = [{_f(g['flagon'][0] + 14.0)}, {_f(TOP)}, {_f(g['flagon'][1])}]
yaw_deg = 90.0

[[waystone]]
point = "town_gate"
position = [{_f(gate[0] - 7.0)}, {_f(TOP)}, {_f(gate[1] - 8.0)}]
yaw_deg = 0.0

# ---- EXPAND_BEGIN (generated by tools/expand_maps.py; edit that, not this) ----
# ---- EXPAND_END ----
"""
    return body + "".join(boxes) + "\n" + actors


def _wall_run(name, model, x0, z0, x1, z1, height, thick_scale, y=0.0):
    length = math.hypot(x1 - x0, z1 - z0)
    n = max(1, round(length / 4.0))
    yaw = math.degrees(math.atan2((x1 - x0) / length, (z1 - z0) / length))
    sx = (x1 - x0) / n
    sz = (z1 - z0) / n
    return prop(name, model, (x0 + sx * 0.5, y, z0 + sz * 0.5), yaw, (thick_scale, height, 4.0), n, (sx, 0.0, sz), True)


def dress_block() -> str:
    g = landmarks()
    ox, oz = center()
    p = []
    # Thick stone curtain and a round tower about every 25 m.
    for i, (name, x, z, yaw, a) in enumerate(curtain()):
        # A textured masonry block, centred, so the curtain reads as a wall and not a gap-toothed palisade.
        p.append(prop(f"curtain_{name[4:]}", "generated:block", (x, 4.6, z), yaw, (3.6, 9.2, 6.6), snap=True,
                      tint=(0.72, 0.66, 0.58), tex=BRICK))
        if i % 5 == 0:
            p.append(prop(f"tower_{name[4:]}", TOWN + "pillar-stone.glb", (x, 0.0, z), 0.0, (32.0, 16.0, 32.0), snap=True))
            p.append(prop(f"gem_{name[4:]}", CRYSTAL, (x, 16.0, z), float(i * 20), 2.4, snap=True))
    gate, east = g["gate"], g["east"]
    p.append(prop("gate_s", TOWN + "wall-doorway-square-wide.glb", (gate[0], 0.0, gate[1]), 90.0, (14.0, 11.0, 20.0), snap=True))
    p.append(prop("gate_e", TOWN + "wall-doorway-round.glb", (east[0], 0.0, east[1]), 0.0, (12.0, 9.0, 16.0), snap=True))
    for side, dx in (("w", -12.0), ("e", 12.0)):
        p.append(prop(f"gatetower_{side}", TOWN + "pillar-stone.glb", (gate[0] + dx, 0.0, gate[1] - 1.0), 0.0, (36.0, 20.0, 36.0), snap=True))
        p.append(prop(f"gategem_{side}", CRYSTAL, (gate[0] + dx, 20.0, gate[1] - 1.0), 0.0, 2.8, snap=True))
    # Cathedral, inside the north bulge. Blue slate, not the kit pink.
    a = g["assoc"]
    p.append(_wall_run("cathedral_front", TOWN + "wall-window-stone.glb", a[0] - 28.0, a[1] + 20.0, a[0] + 28.0, a[1] + 20.0, 24.0, 18.0))
    p.append(prop("cathedral_door", TOWN + "wall-doorway-round.glb", (a[0], 0.0, a[1] + 20.0), 90.0, (16.0, 22.0, 12.0), snap=True))
    p.append(_wall_run("cathedral_west", TOWN + "wall-window-stone.glb", a[0] - 28.0, a[1] - 18.0, a[0] - 28.0, a[1] + 18.0, 24.0, 18.0))
    p.append(_wall_run("cathedral_east", TOWN + "wall-window-stone.glb", a[0] + 28.0, a[1] - 18.0, a[0] + 28.0, a[1] + 18.0, 24.0, 18.0))
    p.append(prop("cathedral_roof", "generated:block", (a[0], 28.0, a[1]), 0.0, (60.0, 8.0, 42.0), snap=True, tint=BLUE_SLATE, tex=BRICK))
    for side, dx in (("w", -26.0), ("e", 26.0)):
        p.append(prop(f"spire_{side}", TOWN + "pillar-stone.glb", (a[0] + dx, 0.0, a[1] + 16.0), 0.0, (40.0, 50.0, 40.0), snap=True))
        p.append(prop(f"spire_cap_{side}", "generated:block", (a[0] + dx, 52.0, a[1] + 16.0), 0.0, (8.0, 6.0, 8.0), snap=True, tint=BLUE_SLATE, tex=BRICK))
    lib = g["library"]
    p.append(_wall_run("library_front", TOWN + "wall-window-stone.glb", lib[0] - 24.0, lib[1] + 9.0, lib[0] + 24.0, lib[1] + 9.0, 14.0, 14.0))
    p.append(prop("library_roof", "generated:block", (lib[0], 16.0, lib[1]), 0.0, (50.0, 4.0, 18.0), snap=True, tint=BLUE_SLATE, tex=BRICK))
    # Houses packed along the inner lane.
    for name, x, z, yaw in _houses():
        wood = int(name[1:]) % 2 == 0
        piece = TOWN + ("wall-wood.glb" if wood else "wall.glb")
        p.append(_wall_run(f"{name}_n", piece, x - 8.0, z - 6.0, x + 8.0, z - 6.0, 10.0, 16.0))
        p.append(_wall_run(f"{name}_s", piece, x - 8.0, z + 6.0, x + 8.0, z + 6.0, 10.0, 16.0))
        tint = SHINGLE if wood else SLATE
        tex = ROCK if wood else BRICK
        p.append(prop(f"{name}_roof", "generated:block", (x, 12.0, z), float(yaw), (16.0, 4.0, 13.0), snap=True, tint=tint, tex=tex))
    # Flagon, timber, dark roof, door toward the square.
    f = g["flagon"]
    p.append(_wall_run("flagon_n", TOWN + "wall-wood-window-shutters.glb", f[0] - 10.0, f[1] - 7.0, f[0] + 10.0, f[1] - 7.0, 12.0, 16.0))
    p.append(_wall_run("flagon_s", TOWN + "wall-wood-window-glass.glb", f[0] - 10.0, f[1] + 7.0, f[0] + 10.0, f[1] + 7.0, 12.0, 16.0))
    p.append(prop("flagon_door", TOWN + "wall-wood-door.glb", (f[0] + 10.0, 0.0, f[1]), 180.0, (8.0, 12.0, 8.0), snap=True))
    p.append(prop("flagon_roof", "generated:block", (f[0], 14.0, f[1]), 0.0, (22.0, 4.0, 16.0), snap=True, tint=SHINGLE, tex=ROCK))
    p.append(prop("flagon_chimney", TOWN + "chimney.glb", (f[0] - 4.0, 16.0, f[1] - 2.0), 0.0, (4.0, 4.0, 4.0), snap=True))
    p.append(prop("flagon_sign", TOWN + "banner-red.glb", (f[0] + 11.0, 6.0, f[1] + 2.0), 90.0, 3.0, snap=True))
    # Tiered fountain: three basins.
    sq = g["square"]
    for i, (sc, y) in enumerate(((6.5, 0.0), (4.2, 2.2), (2.4, 4.0))):
        p.append(prop(f"fountain_{i}", TOWN + "fountain-round-detail.glb", (sq[0], y, sq[1]), float(i * 30), (sc, 6.0, sc), snap=True))
    for i in range(10):
        ang = 2.0 * math.pi * i / 10.0
        p.append(prop(f"plaza_lamp_{i}", TOWN + "lantern.glb", (sq[0] + 24.0 * math.sin(ang), 0.0, sq[1] + 24.0 * math.cos(ang)), 0.0, 2.2, snap=True))
    # Market clusters.
    for i, dx in enumerate((-8.0, -2.0, 4.0)):
        p.append(prop(f"stall_w_{i}", TOWN + "stall-red.glb", (g["market_w"][0] + dx, 0.0, g["market_w"][1]), 15.0, (5.5, 4.0, 4.5), snap=True))
    for i, dx in enumerate((-8.0, -2.0, 4.0, 10.0)):
        piece = "stall-red.glb" if i % 2 == 0 else "stall-green.glb"
        p.append(prop(f"stall_e_{i}", TOWN + piece, (g["market_e"][0] + dx, 0.0, g["market_e"][1]), -20.0, (5.2, 3.8, 4.2), snap=True))
    p.append(prop("market_crates", CRATE, (g["market_w"][0] + 8.0, 0.0, g["market_w"][1] + 4.0), 20.0, 2.6, snap=True))
    p.append(prop("market_cart", TOWN + "cart.glb", (g["market_e"][0] + 12.0, 0.0, g["market_e"][1] - 5.0), 30.0, 2.8, snap=True))
    # Garden.
    gd = g["garden"]
    p.append(prop("garden_fountain", TOWN + "fountain-round.glb", (gd[0], 0.0, gd[1]), 0.0, (4.5, 4.0, 4.5), snap=True))
    for i in range(7):
        ang = 2.0 * math.pi * i / 7.0
        p.append(prop(f"garden_tree_{i}", NATURE + "tree_oak.glb", (gd[0] + 18.0 * math.sin(ang), 0.0, gd[1] + 16.0 * math.cos(ang)), float(i * 40), 3.2, snap=True))
        p.append(prop(f"garden_flower_{i}", NATURE + "flower_redA.glb", (gd[0] + 8.0 * math.sin(ang + 0.4), 0.0, gd[1] + 7.0 * math.cos(ang + 0.4)), 0.0, 2.4, snap=True))
    # The oak dwarfs the wall. Scale 4.8 on a ~14 m mesh is about a 70 m canopy.
    p.append(prop("oak_landmark", OAK, (g["oak"][0], 0.0, g["oak"][1]), 30.0, 4.8, snap=True))
    p.append(prop("oak_door", TOWN + "wall-wood-arch.glb", (g["door"][0] + 6.0, 0.0, g["door"][1] - 4.0), 40.0, (8.0, 7.0, 8.0), snap=True))
    for i, (dx, dz) in enumerate(((-10, -6), (9, -7), (-8, 8), (11, 5), (0, -12), (-12, 1))):
        p.append(prop(f"oak_gem_{i}", CRYSTAL, (g["oak"][0] + dx, 0.0, g["oak"][1] + dz), float(i * 25), 2.2, snap=True))
    wards = [(0.33, 0.42), (0.35, 0.60), (0.38, 0.68), (0.62, 0.66), (0.69, 0.40), (0.34, 0.27), (0.18, 0.38), (0.70, 0.30)]
    for i, (nx, ny) in enumerate(wards):
        x, z = inward(world(nx, ny), 6.0)
        p.append(prop(f"ward_plinth_{i}", TOWN + "pillar-stone.glb", (x, 0.0, z), 0.0, (14.0, 6.0, 14.0), snap=True))
        p.append(prop(f"ward_{i}", CRYSTAL, (x, 6.0, z), 0.0, 2.6, snap=True))
    # Lamps along the curved lanes.
    for name, pts in (
        ("s", [gate, (sq[0] + 10, (gate[1] + sq[1]) * 0.5), sq]),
        ("n", [sq, g["assoc"]]),
        ("w", [sq, g["flagon"], g["garden"]]),
        ("e", [sq, g["market_e"], east]),
    ):
        for i, (x, z) in enumerate(_samples(pts, 18.0)):
            p.append(prop(f"lamp_{name}_{i}", TOWN + "lantern.glb", (x + 4.0, 0.0, z), 0.0, 2.0, snap=True))
    return "".join(p)


def main() -> None:
    g = landmarks()
    north = g["assoc"][1] + 26.0
    south = g["gate"][1]
    print(f"[spec_town] scale {_f(S)} across {south - north:.1f} oak {_f(g['oak'][0])} {_f(g['oak'][1])}")
    path = ROOT / "data/levels/town_square.toml"
    path.write_text(structure_text(), encoding="utf-8")
    print(f"[spec_town] wrote {path}")


if __name__ == "__main__":
    main()
