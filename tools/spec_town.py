#!/usr/bin/env python3
"""Eldoria laid out on docs/maps/levels/town.jpg.

Normalized painting coordinates (x west to east, y north to south) map onto a
square so a circle on the page is a circle in the world. The south gate is 160 m
from the wall centre. tools/dress_levels.py pulls the prop block from here.

  python3 tools/spec_town.py
  python3 tools/dress_levels.py
  python3 tools/toml_to_scene.py
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

S = 160.0 / math.hypot(0.50 - 0.52, 0.80 - 0.52)  # metres per painting unit
TOP = 2.0  # street surface, metres
WALL_R = 160.0
SEG = 5.0


def world(nx: float, ny: float) -> tuple[float, float]:
    return ((nx - 0.5) * S, (ny - 0.5) * S)


def _f(n: float) -> str:
    return f"{round(n, 3)}"


def prop(name, model, pos, rot=0.0, scale=1.0, count=1, step=(0, 0, 0), snap=False) -> str:
    sc = f"{scale}" if not isinstance(scale, (list, tuple)) else "[%s]" % ", ".join(_f(s) for s in scale)
    s = (f'[[prop]]\nname = "{name}"\nmodel = "{model}"\n'
         f"position = [{', '.join(_f(p) for p in pos)}]\n"
         f"rotation_deg = [0.0, {_f(rot)}, 0.0]\nscale = {sc}\n")
    if count > 1:
        s += f"count = {count}\nstep = [{', '.join(_f(p) for p in step)}]\n"
    if snap:
        s += "snap = true\n"
    return s


def ground(name: str, x: float, z: float, sx: float, sz: float, top: float = TOP) -> str:
    return (f'[[box]]\nname = "{name}"\nkind = "ground"\n'
            f"center = [{_f(x)}, {_f(top - 0.1)}, {_f(z)}]\n"
            f"size = [{_f(sx)}, 0.2, {_f(sz)}]\n"
            f"color = [0.36, 0.34, 0.31]\n")


def collider(name: str, x: float, y: float, z: float, sx: float, sy: float, sz: float, yaw: float = 0.0) -> str:
    return (f'[[box]]\nname = "{name}"\nkind = "wall"\n'
            f"center = [{_f(x)}, {_f(y)}, {_f(z)}]\n"
            f"size = [{_f(sx)}, {_f(sy)}, {_f(sz)}]\n"
            f"rotation_deg = [0.0, {_f(yaw)}, 0.0]\n"
            f"color = [0.42, 0.4, 0.37]\n")


def _wall_center() -> tuple[float, float]:
    return world(0.52, 0.52)


def _lobe() -> tuple[float, float, float, float]:
    """East lobe that wraps the oak, a little outside the painted box."""
    x0, z0 = world(0.70, 0.28)
    x1, z1 = world(0.95, 0.67)
    return min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)


def _in_lobe(x: float, z: float, pad: float = 0.0) -> bool:
    x0, x1, z0, z1 = _lobe()
    return x0 - pad <= x <= x1 + pad and z0 - pad <= z <= z1 + pad


def wall_points() -> list[tuple[float, float, float]]:
    """(x, z, yaw degrees). Yaw points the segment's length along the wall."""
    cx, cz = _wall_center()
    pts: list[tuple[float, float, float]] = []
    steps = max(8, round(2 * math.pi * WALL_R / SEG))
    for i in range(steps):
        a = 2 * math.pi * i / steps
        x, z = cx + WALL_R * math.sin(a), cz + WALL_R * math.cos(a)
        if _in_lobe(x, z, 3.0):
            continue
        tx, tz = math.cos(a), -math.sin(a)
        pts.append((x, z, math.degrees(math.atan2(tx, tz))))
    x0, x1, z0, z1 = _lobe()
    per = [(x0, z0, x1, z0), (x1, z0, x1, z1), (x1, z1, x0, z1), (x0, z1, x0, z0)]
    for ax, az, bx, bz in per:
        length = math.hypot(bx - ax, bz - az)
        n = max(1, round(length / SEG))
        tx, tz = (bx - ax) / length, (bz - az) / length
        yaw = math.degrees(math.atan2(tx, tz))
        for i in range(n):
            t = (i + 0.5) / n
            x, z = ax + (bx - ax) * t, az + (bz - az) * t
            if math.hypot(x - cx, z - cz) < WALL_R - 3.0:
                continue
            pts.append((x, z, yaw))
    return pts


def _near(x: float, z: float, gates: list[tuple[float, float]], gap: float) -> bool:
    return any(math.hypot(x - gx, z - gz) < gap for gx, gz in gates)


def path_boxes() -> list[str]:
    """Cobbled ribbons. Square pads, so a diagonal still paints cobble."""
    square = world(0.50, 0.55)
    gate = world(0.50, 0.80)
    assoc = (world(0.50, 0.22)[0], world(0.50, 0.22)[1] + 16.0)
    flagon = world(0.24, 0.53)
    garden = world(0.30, 0.32)
    market_e = world(0.61, 0.45)
    east = world(0.71, 0.66)
    oak = (world(0.82, 0.38)[0] - 14.0, world(0.82, 0.38)[1] + 12.0)
    lines = [
        ("road_s", [gate, square], None),
        ("road_n", [square, assoc], None),
        ("road_w", [square, flagon], None),
        ("road_nw", [flagon, garden], None),
        ("road_e", [square, market_e, (market_e[0] + 30, market_e[1] + 40), east], None),
        ("road_oak", [market_e, ((market_e[0] + oak[0]) * 0.5, (market_e[1] + oak[1]) * 0.5), oak], None),
    ]
    out = [ground("square", square[0], square[1], 60.0, 60.0)]
    n = 0
    for _name, pts, _drop in lines:
        for x, z in _samples(pts, 5.5):
            out.append(ground(f"path_{n}", x, z, 6.0, 6.0))
            n += 1
    # The south road leaves the gate and steps down the hill.
    gx, gz = gate
    for i, z in enumerate(_steps(gz + 8.0, gz + 70.0, 6.0)):
        top = TOP - (i + 1) * 1.15
        out.append(ground(f"slope_s_{i}", gx, z, 7.0, 6.0, top))
    ex, ez = east
    for i, (x, z) in enumerate(_samples([(ex, ez + 6), (ex + 28, ez + 40), (ex + 46, ez + 78)], 6.0)):
        top = TOP - (i + 1) * 0.9
        out.append(ground(f"slope_e_{i}", x, z, 6.0, 6.0, top))
    return out


def _steps(a: float, b: float, step: float) -> list[float]:
    n = max(1, round(abs(b - a) / step))
    return [a + (b - a) * (i + 0.5) / n for i in range(n)]


def _samples(pts: list[tuple[float, float]], step: float) -> list[tuple[float, float]]:
    out: list[tuple[float, float]] = []
    for (ax, az), (bx, bz) in zip(pts, pts[1:]):
        length = math.hypot(bx - ax, bz - az)
        n = max(1, round(length / step))
        for i in range(n):
            t = (i + 0.5) / n
            out.append((ax + (bx - ax) * t, az + (bz - az) * t))
    return out


def curtain() -> list[tuple[str, float, float, float]]:
    gates = [world(0.50, 0.80), world(0.71, 0.66)]
    out = []
    for i, (x, z, yaw) in enumerate(wall_points()):
        if _near(x, z, gates, 9.0):
            continue
        out.append((f"col_{i}", x, z, yaw))
    return out


def hide_names() -> set[str]:
    names = {name for name, _x, _z, _yaw in curtain()}
    names.update({"col_cathedral", "col_library", "col_flagon", "col_oak", "col_tower_w", "col_tower_e"})
    return names


def structure_text() -> str:
    cx, cz = _wall_center()
    gate = world(0.50, 0.80)
    oak = world(0.82, 0.38)
    door = (oak[0] - 14.0, oak[1] + 12.0)
    assoc = world(0.50, 0.22)
    doors = (assoc[0], assoc[1] + 18.0)
    flagon = world(0.24, 0.53)
    market_w = world(0.42, 0.43)
    market_e = world(0.61, 0.45)
    library = world(0.64, 0.22)
    boxes = path_boxes()
    for name, x, z, yaw in curtain():
        boxes.append(collider(name, x, TOP + 3.2, z, 1.2, 7.2, 4.6, yaw))
    boxes.append(collider("col_cathedral", assoc[0], TOP + 6.0, assoc[1], 34.0, 14.0, 26.0))
    boxes.append(collider("col_library", library[0], TOP + 4.0, library[1] + 4.0, 38.0, 10.0, 16.0))
    boxes.append(collider("col_flagon", flagon[0], TOP + 3.5, flagon[1], 16.0, 8.0, 12.0))
    boxes.append(collider("col_oak", oak[0], TOP + 6.0, oak[1], 10.0, 14.0, 10.0))
    boxes.append(collider("col_tower_w", gate[0] - 9.0, TOP + 6.0, gate[1] - 2.0, 3.2, 14.0, 3.2))
    boxes.append(collider("col_tower_e", gate[0] + 9.0, TOP + 6.0, gate[1] - 2.0, 3.2, 14.0, 3.2))
    # The south-gate pad has to hold the spawn, the guard, and the waystone.
    boxes.append(ground("gate_pad", gate[0], gate[1] - 8.0, 16.0, 18.0))
    boxes.append(ground("oak_pad", door[0], door[1], 8.0, 8.0))
    boxes.append(ground("door_pad", doors[0], doors[1], 10.0, 8.0))
    boxes.append(ground("flagon_pad", flagon[0] + 12.0, flagon[1], 8.0, 8.0))
    boxes.append(ground("market_w_pad", market_w[0], market_w[1], 18.0, 12.0))
    boxes.append(ground("market_e_pad", market_e[0], market_e[1], 20.0, 12.0))
    carves = [
        [-230.0, 10.0, 70.0, -14.0],
        [-40.0, -250.0, 60.0, -12.0],
        [80.0, -240.0, 55.0, -12.0],
        [-90.0, 230.0, 55.0, -11.0],
        [90.0, 240.0, 55.0, -11.0],
        [330.0, -10.0, 60.0, -12.0],
        [-180.0, -160.0, 50.0, -10.0],
        [200.0, 180.0, 50.0, -10.0],
    ]
    carve = ", ".join("[%s]" % ", ".join(_f(n) for n in c) for c in carves)
    gx, gz = world(0.28, 0.32)
    body = f"""# Eldoria, 0.11.3. Laid out on docs/maps/levels/town.jpg.
# One painting unit is {_f(S)} m. The wall centre is the painted (0.52, 0.52).

[level]
id = "town_square"
name = "Eldoria - Town Square"
world_offset = [0.0, 0.0]

[materials]
ground = "assets/ambientcg/PavingStones131"
uv_scale = 0.4

[environment]
sky_color = [0.55, 0.62, 0.86]
ambient_color = [0.46, 0.4, 0.34]
fog_density = 0.0016
sky = true
grade = [1.04, 1.06, 1.12]
dome = 310.0

[sun]
to_light = [0.62, 0.7, 0.22]
color = [1.0, 0.84, 0.62]

[player_start]
position = [{_f(gate[0])}, {_f(TOP)}, {_f(gate[1] - 14.0)}]
yaw_deg = 0.0

[underlay]
image = "docs/maps/levels/town.jpg"
center = [0.0, -3.0, 0.0]
size = [{_f(S)}, {_f(S)}]

[terrain]
size = [680, 680]
center = [40, 16]
height = 1.2
seed = 113
rim = 0
cliff = 28
blend = 18
spacing = 2
map_version = 4
pad_y = 1.95
pad_margin = 0.4
stepped = true
foliage = 6000
layers = ["grass", "rock", "path_cobble"]
carves = [{carve}]

"""
    actors = f"""[[exit]]
name = "to_association"
to = "mage_association"
position = [{_f(doors[0])}, {_f(TOP)}, {_f(doors[1])}]
[[exit]]
name = "to_landfill"
to = "midden"
position = [{_f(gate[0])}, {_f(TOP)}, {_f(gate[1])}]
[[exit]]
name = "to_old_oak"
to = "old_oak"
position = [{_f(door[0])}, {_f(TOP)}, {_f(door[1])}]
[[npc]]
name = "guard_gate"
speaker = "Bored Guard"
position = [{_f(gate[0] + 6.0)}, {_f(TOP)}, {_f(gate[1] - 6.0)}]
yaw_deg = 180.0
[[npc]]
name = "merchant"
speaker = "Potion Merchant"
position = [{_f(market_w[0] - 4.0)}, {_f(TOP)}, {_f(market_w[1])}]
yaw_deg = 90.0
[[npc]]
name = "tailor"
speaker = "Tailor"
position = [{_f(market_w[0] + 4.0)}, {_f(TOP)}, {_f(market_w[1] + 3.0)}]
yaw_deg = 180.0
[[npc]]
name = "runesmith"
speaker = "Runesmith"
position = [{_f(market_e[0])}, {_f(TOP)}, {_f(market_e[1] + 4.0)}]
yaw_deg = 200.0
[[npc]]
name = "patron"
speaker = "Grizzled Patron"
position = [{_f(flagon[0] + 12.0)}, {_f(TOP)}, {_f(flagon[1])}]
yaw_deg = 90.0

[[waystone]]
point = "town_gate"
position = [{_f(gate[0] - 6.0)}, {_f(TOP)}, {_f(gate[1] - 12.0)}]
yaw_deg = 0.0

# ---- EXPAND_BEGIN (generated by tools/expand_maps.py; edit that, not this) ----
# ---- EXPAND_END ----
"""
    # A garden mound, recorded as a comment for the dress props. The carve list is the escarpment.
    _ = (cx, cz, gx, gz)
    return body + "".join(boxes) + "\n" + actors


def dress_block() -> str:
    cx, cz = _wall_center()
    _ = (cx, cz)
    gate = world(0.50, 0.80)
    east = world(0.71, 0.66)
    oak = world(0.82, 0.38)
    assoc = world(0.50, 0.22)
    library = world(0.64, 0.22)
    flagon = world(0.24, 0.53)
    garden = world(0.30, 0.35)
    square = world(0.50, 0.55)
    market_w = world(0.425, 0.43)
    market_e = world(0.61, 0.45)
    p: list[str] = []
    for name, x, z, yaw in curtain():
        p.append(prop(f"curtain_{name[4:]}", TOWN + "wall-curved.glb", (x, 0.0, z), yaw, (1.5, 7.5, 5.2), snap=True))
    # Gatehouses.
    p.append(prop("gate_s", TOWN + "wall-doorway-square-wide.glb", (gate[0], 0.0, gate[1]), 90.0, (8.0, 9.0, 16.0), snap=True))
    p.append(prop("gate_e", TOWN + "wall-doorway-round.glb", (east[0], 0.0, east[1]), 0.0, (8.0, 7.0, 12.0), snap=True))
    for side, dx in (("w", -9.0), ("e", 9.0)):
        p.append(prop(f"tower_{side}", TOWN + "pillar-stone.glb", (gate[0] + dx, 0.0, gate[1] - 2.0), 0.0, (18.0, 16.0, 18.0), snap=True))
        p.append(prop(f"tower_gem_{side}", CRYSTAL, (gate[0] + dx, 16.0, gate[1] - 2.0), 0.0, 1.6, snap=True))
    # Cathedral, doors facing south, and the library wing on its east.
    p.append(prop("cathedral_front", TOWN + "wall-window-stone.glb", (assoc[0] - 16.0, 0.0, assoc[1] + 13.0), 90.0, (6.0, 12.0, 8.0), 4, (8.0, 0.0, 0.0), True))
    p.append(prop("cathedral_door", TOWN + "wall-doorway-round.glb", (assoc[0], 0.0, assoc[1] + 13.0), 90.0, (6.0, 12.0, 8.0), snap=True))
    p.append(prop("cathedral_roof", TOWN + "roof-high-point.glb", (assoc[0], 12.0, assoc[1]), 0.0, (36.0, 8.0, 28.0), snap=True))
    for side, dx in (("w", -16.0), ("e", 16.0)):
        p.append(prop(f"spire_{side}", TOWN + "pillar-stone.glb", (assoc[0] + dx, 0.0, assoc[1] + 12.0), 0.0, (16.0, 22.0, 16.0), snap=True))
    p.append(prop("library_wall", TOWN + "wall-window-stone.glb", (library[0] - 16.0, 0.0, library[1] + 6.0), 90.0, (5.0, 8.0, 6.0), 6, (6.0, 0.0, 0.0), True))
    p.append(prop("library_roof", TOWN + "roof-high-flat.glb", (library[0], 8.0, library[1]), 0.0, (40.0, 6.0, 18.0), snap=True))
    # Plaza fountain and lamps.
    p.append(prop("fountain", TOWN + "fountain-round-detail.glb", (square[0], 0.0, square[1]), 0.0, (4.0, 6.0, 4.0), snap=True))
    for i in range(8):
        a = 2 * math.pi * i / 8
        p.append(prop(f"plaza_lamp_{i}", TOWN + "lantern.glb",
                      (square[0] + 28.0 * math.sin(a), 0.0, square[1] + 28.0 * math.cos(a)), 0.0, 1.8, snap=True))
    # Markets.
    for i, dx in enumerate((-6.0, 0.0)):
        p.append(prop(f"stall_w_{i}", TOWN + "stall-red.glb", (market_w[0] + dx, 0.0, market_w[1]), 20.0, (4.5, 3.2, 3.6), snap=True))
    for i, dx in enumerate((-6.0, 0.0, 6.0)):
        piece = "stall-red.glb" if i != 1 else "stall-green.glb"
        p.append(prop(f"stall_e_{i}", TOWN + piece, (market_e[0] + dx, 0.0, market_e[1]), -15.0, (4.2, 3.0, 3.4), snap=True))
    p.append(prop("market_crates", CRATE, (market_w[0] + 6.0, 0.0, market_w[1] + 3.0), 30.0, 2.2, snap=True))
    p.append(prop("market_cart", TOWN + "cart.glb", (market_e[0] + 8.0, 0.0, market_e[1] - 4.0), 40.0, 2.4, snap=True))
    # The Flagon, door toward the square (east).
    p.append(prop("flagon_n", TOWN + "wall-wood-window-shutters.glb", (flagon[0] - 6.0, 0.0, flagon[1] - 5.0), 90.0, (4.0, 5.0, 4.0), 3, (4.0, 0.0, 0.0), True))
    p.append(prop("flagon_s", TOWN + "wall-wood-window-glass.glb", (flagon[0] - 6.0, 0.0, flagon[1] + 5.0), -90.0, (4.0, 5.0, 4.0), 3, (4.0, 0.0, 0.0), True))
    p.append(prop("flagon_w", TOWN + "wall-wood.glb", (flagon[0] - 7.0, 0.0, flagon[1] - 4.0), 0.0, (4.0, 5.0, 4.0), 2, (0.0, 0.0, 4.0), True))
    p.append(prop("flagon_door", TOWN + "wall-wood-door.glb", (flagon[0] + 6.0, 0.0, flagon[1] - 2.0), 180.0, (4.0, 5.0, 5.0), snap=True))
    p.append(prop("flagon_roof", TOWN + "roof-high-point.glb", (flagon[0], 5.0, flagon[1]), 0.0, (16.0, 4.0, 14.0), snap=True))
    p.append(prop("flagon_chimney", TOWN + "chimney.glb", (flagon[0] - 4.0, 8.0, flagon[1] - 2.0), 0.0, (3.0, 3.0, 3.0), snap=True))
    p.append(prop("flagon_sign", TOWN + "banner-red.glb", (flagon[0] + 7.0, 3.0, flagon[1] + 2.0), 90.0, 2.4, snap=True))
    # Garden terrace: trees, a small fountain. The grass is the terrain.
    p.append(prop("garden_fountain", TOWN + "fountain-round.glb", (garden[0], 0.0, garden[1]), 0.0, (3.5, 3.0, 3.5), snap=True))
    for i in range(6):
        a = 2 * math.pi * i / 6
        p.append(prop(f"garden_tree_{i}", NATURE + "tree_oak.glb",
                      (garden[0] + 16.0 * math.sin(a), 0.0, garden[1] + 14.0 * math.cos(a)), float(i * 40), 2.4, snap=True))
        p.append(prop(f"garden_flower_{i}", NATURE + "flower_redA.glb",
                      (garden[0] + 8.0 * math.sin(a + 0.4), 0.0, garden[1] + 7.0 * math.cos(a + 0.4)), 0.0, 2.0, snap=True))
    # The Old Oak. The mesh origin sits in the trunk, so the extra height puts the roots on the ground.
    # Named oak_landmark: the grove level owns Props/old_oak.
    # Scale 3.2 makes the canopy about 45 m. Snap y 0 plants the root flare; the mesh extends below its origin.
    p.append(prop("oak_landmark", OAK, (oak[0], 0.0, oak[1]), 40.0, 3.2, snap=True))
    p.append(prop("oak_door", TOWN + "wall-wood-arch.glb", (oak[0] - 8.0, 0.0, oak[1] + 7.0), 40.0, (6.0, 5.0, 6.0), snap=True))
    for i, (dx, dz) in enumerate(((-7, -4), (6, -5), (-5, 6), (7, 4), (2, -8), (-8, 2))):
        p.append(prop(f"oak_gem_{i}", CRYSTAL, (oak[0] + dx, 0.0, oak[1] + dz), float(i * 30), 1.3, snap=True))
    # Ward crystals on the painted plinths.
    wards = [(0.33, 0.42), (0.35, 0.60), (0.38, 0.68), (0.62, 0.66), (0.69, 0.40), (0.34, 0.27), (0.18, 0.38), (0.70, 0.30)]
    for i, (nx, ny) in enumerate(wards):
        x, z = world(nx, ny)
        p.append(prop(f"ward_plinth_{i}", TOWN + "pillar-stone.glb", (x, 0.0, z), 0.0, (8.0, 3.0, 8.0), snap=True))
        p.append(prop(f"ward_{i}", CRYSTAL, (x, 3.0, z), 0.0, 1.4, snap=True))
    # Lamps along the streets, about every 16 m.
    for name, pts in (
        ("ln", [gate, square, assoc]),
        ("le", [square, market_e, east]),
        ("lw", [square, flagon, garden]),
    ):
        for i, (x, z) in enumerate(_samples(pts, 16.0)):
            p.append(prop(f"lamp_{name}_{i}", TOWN + "lantern.glb", (x + 3.0, 0.0, z), 0.0, 1.6, snap=True))
    return "".join(p)


def main() -> None:
    path = ROOT / "data/levels/town_square.toml"
    path.write_text(structure_text(), encoding="utf-8")
    print(f"[spec_town] wrote {path} (scale {_f(S)} m)")


if __name__ == "__main__":
    main()
