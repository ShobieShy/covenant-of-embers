"""Volumetric boss sculpts for Blender 4.2. Paintings are reference only.

Run:
    blender -b -P tools/sculpt_bosses.py -- forgemaw
    blender -b -P tools/sculpt_bosses.py
"""
from __future__ import annotations

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

OUT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "assets", "original", "ember_art", "bosses")
)

HEIGHTS = {
    "the_filth": 5.6,
    "breach_warden": 6.4,
    "goblin_king": 2.45,
    "blightmaw_matriarch": 5.4,
    "forgemaw": 5.8,
    "drowned_choir": 5.0,
    "storm_warden": 4.8,
}


def argv_after() -> list[str]:
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1 :]
    return []


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def activate(ob: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def apply_transforms(ob: bpy.types.Object) -> None:
    activate(ob)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)


def shade(ob: bpy.types.Object) -> None:
    activate(ob)
    bpy.ops.object.shade_smooth()


def primitive(kind: str, name: str, loc, scale, rot=(0, 0, 0), seg=20) -> bpy.types.Object:
    if kind == "sphere":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(8, seg // 2), location=loc)
    elif kind == "cube":
        bpy.ops.mesh.primitive_cube_add(location=loc)
    elif kind == "cyl":
        bpy.ops.mesh.primitive_cylinder_add(vertices=seg, location=loc)
    elif kind == "cone":
        bpy.ops.mesh.primitive_cone_add(vertices=seg, location=loc)
    else:
        raise ValueError(kind)
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = rot
    ob.scale = scale
    apply_transforms(ob)
    return ob


def join(obs: list, name: str) -> bpy.types.Object:
    obs = [o for o in obs if o is not None]
    if len(obs) == 1:
        obs[0].name = name
        return obs[0]
    activate(obs[0])
    for o in obs:
        o.select_set(True)
    bpy.ops.object.join()
    obs[0].name = name
    return obs[0]


def remesh(ob: bpy.types.Object, voxel: float) -> None:
    activate(ob)
    mod = ob.modifiers.new("Remesh", "REMESH")
    mod.mode = "VOXEL"
    mod.voxel_size = voxel
    mod.use_smooth_shade = True
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod = ob.modifiers.new("Smooth", "SMOOTH")
    mod.iterations = 3
    mod.factor = 0.45
    bpy.ops.object.modifier_apply(modifier=mod.name)
    activate(ob)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    shade(ob)


def decimate_to(ob: bpy.types.Object, target: int) -> None:
    faces = len(ob.data.polygons)
    if faces <= target:
        return
    activate(ob)
    mod = ob.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = max(0.08, target / float(faces))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    shade(ob)


def tube(points: list, radius: float, name: str) -> bpy.types.Object:
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for i, p in enumerate(points):
        spline.points[i].co = (p[0], p[1], p[2], 1.0)
    ob = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(ob)
    activate(ob)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.active_object


def boolean_diff(ob: bpy.types.Object, cutter: bpy.types.Object) -> None:
    activate(ob)
    mod = ob.modifiers.new("Cut", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


def bounds(ob: bpy.types.Object) -> tuple[Vector, Vector]:
    bpy.context.view_layer.update()
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def lay_upright(obs: list) -> None:
    """The sculpt is authored with Y as height. Blender is Z-up, and glTF export keeps that."""
    for ob in obs:
        ob.rotation_euler.x -= math.pi / 2.0
        apply_transforms(ob)


def fit_height(obs: list, height: float) -> None:
    bpy.context.view_layer.update()
    los, his = [], []
    for ob in obs:
        lo, hi = bounds(ob)
        los.append(lo)
        his.append(hi)
    lo = Vector((min(v.x for v in los), min(v.y for v in los), min(v.z for v in los)))
    hi = Vector((max(v.x for v in his), max(v.y for v in his), max(v.z for v in his)))
    h = max(hi.z - lo.z, 1e-4)
    s = height / h
    for ob in obs:
        ob.location = (ob.location - lo) * s
        ob.scale *= s
        apply_transforms(ob)
    bpy.context.view_layer.update()
    zmin = min(bounds(ob)[0].z for ob in obs)
    for ob in obs:
        ob.location.z -= zmin
        apply_transforms(ob)


def noise(p: Vector) -> float:
    return (
        math.sin(p.x * 3.1 + p.y * 0.7)
        + math.sin(p.z * 2.6 + p.x * 1.4)
        + math.sin(p.y * 4.2 + p.z * 1.1)
    ) / 3.0


def paint(ob: bpy.types.Object, base: tuple, crack: tuple | None = None) -> None:
    """Flat PBR colours plus crack faces. The 3D noise only picks faces, so every side
    carries the same palette and nothing is projected from the painting."""
    mesh = ob.data
    mesh.materials.clear()
    mesh.materials.append(material(ob.name + "_body", base, 0.78, 0.0))
    if crack is None:
        return
    mesh.materials.append(material(ob.name + "_crack", crack, 0.4, 1.6))
    for poly in mesh.polygons:
        if noise(poly.center) > 0.45:
            poly.material_index = 1


def material(name: str, color: tuple, rough: float, emit: float) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.04 if emit == 0 else 0.0
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = (color[0], color[1], color[2], 1)
        bsdf.inputs["Emission Strength"].default_value = emit
    return mat


def emissive_object(ob: bpy.types.Object, color: tuple, strength: float) -> None:
    mat = material(ob.name + "_emit", color, 0.3, strength)
    ob.data.materials.clear()
    ob.data.materials.append(mat)


def arm_chain(prefix: str, shoulder, hand, thick: float) -> list:
    mid = (Vector(shoulder) + Vector(hand)) * 0.5
    mid.y -= thick * 0.15
    upper = primitive("sphere", prefix + "_u", shoulder, (thick, thick * 0.85, thick), seg=12)
    elbow = primitive("sphere", prefix + "_e", mid, (thick * 0.85, thick * 0.7, thick * 0.85), seg=12)
    fist = primitive("sphere", prefix + "_h", hand, (thick * 0.95, thick * 0.7, thick * 0.8), seg=12)
    return [upper, elbow, fist]


def leg_chain(prefix: str, hip, foot, thick: float) -> list:
    knee = (Vector(hip) + Vector(foot)) * 0.5
    knee.z += thick * 0.25
    thigh = primitive("sphere", prefix + "_t", hip, (thick, thick * 1.1, thick), seg=12)
    kn = primitive("sphere", prefix + "_k", knee, (thick * 0.85, thick * 0.7, thick * 0.9), seg=12)
    ft = primitive("sphere", prefix + "_f", foot, (thick * 0.9, thick * 0.45, thick * 1.3), seg=12)
    return [thigh, kn, ft]


def build_forgemaw() -> dict:
    parts = []
    parts.append(primitive("sphere", "gut", (0, 2.05, 0.25), (1.15, 1.0, 0.95)))
    parts.append(primitive("sphere", "chest", (0, 3.45, 0.1), (1.05, 0.95, 0.85)))
    parts.append(primitive("sphere", "head", (0, 4.7, 0.35), (0.72, 0.62, 0.68)))
    parts.append(primitive("cone", "hornL", (-0.32, 5.25, 0.2), (0.16, 0.45, 0.16), rot=(0.3, 0, 0.4), seg=8))
    parts.append(primitive("cone", "hornR", (0.32, 5.25, 0.2), (0.16, 0.45, 0.16), rot=(0.3, 0, -0.4), seg=8))
    parts += arm_chain("aL", (-1.15, 4.05, 0.2), (-1.7, 2.55, 0.95), 0.38)
    parts += arm_chain("aR", (1.15, 4.05, 0.2), (1.55, 2.05, 0.75), 0.36)
    parts += leg_chain("lL", (-0.45, 1.35, 0.05), (-0.55, 0.2, 0.15), 0.48)
    parts += leg_chain("lR", (0.45, 1.35, 0.05), (0.55, 0.2, 0.15), 0.48)
    for i in range(6):
        y = 2.4 + i * 0.45
        parts.append(primitive("cone", f"sp{i}", (0, y, -0.95), (0.12, 0.32, 0.12), rot=(1.2, 0, 0), seg=6))
    body = join(parts, "Body")
    remesh(body, 0.07)
    # Hammer in the character's right hand (local -X, screen left) and tongs in the left.
    # Added after the remesh so the head stays a block, not a melted blob.
    hammer = join(
        [
            primitive("cube", "hhead", (-1.95, 3.05, 1.05), (0.42, 0.36, 0.36)),
            primitive("cyl", "hhaft", (-1.7, 2.55, 0.85), (0.1, 0.55, 0.1), rot=(0.6, 0, 0.5), seg=8),
        ],
        "hammer",
    )
    tongs = join(
        [
            primitive("cube", "t1", (1.35, 1.15, 0.85), (0.08, 0.55, 0.08)),
            primitive("cube", "t2", (1.55, 0.7, 1.05), (0.28, 0.08, 0.08)),
        ],
        "tongs",
    )
    body = join([body, hammer, tongs], "Body")
    paint(body, (0.42, 0.18, 0.08), (1.0, 0.32, 0.08))
    core = primitive("sphere", "Phase3_Core", (0.0, 3.3, 0.85), (0.28, 0.32, 0.16), seg=12)
    emissive_object(core, (1.0, 0.45, 0.08), 3.0)
    return {"body": body, "phases": [core], "height": HEIGHTS["forgemaw"]}


def build_filth() -> dict:
    parts = []
    parts.append(primitive("sphere", "base", (0, 1.15, 0), (3.1, 1.25, 2.7)))
    parts.append(primitive("sphere", "mid", (0, 2.7, 0.1), (2.3, 1.35, 2.05)))
    parts.append(primitive("sphere", "top", (0, 4.15, 0), (1.25, 1.05, 1.15)))
    for i, (x, y, z, s) in enumerate(
        [(-1.6, 1.4, 1.4, 0.45), (1.5, 1.1, 1.2, 0.4), (0.4, 2.2, 1.6, 0.32), (-0.8, 3.2, 0.9, 0.28)]
    ):
        parts.append(primitive("cyl", f"barrel{i}", (x, y, z), (s, s * 1.3, s), rot=(0.6, i, 0.4), seg=10))
        parts.append(primitive("sphere", f"bag{i}", (x * 0.5, y * 0.8, z + 0.4), (s * 1.1, s * 0.7, s)))
    body = join(parts, "Body")
    remesh(body, 0.14)
    cutter = primitive("sphere", "cave", (0.0, 2.15, 1.55), (1.15, 0.85, 0.9))
    boolean_diff(body, cutter)
    drips = []
    for i in range(8):
        ang = -0.9 + i * 0.25
        drips.append(
            primitive(
                "cone",
                f"drip{i}",
                (math.sin(ang) * 1.3, 2.55, 1.15),
                (0.08, 0.45, 0.08),
                rot=(0, 0, 0),
                seg=6,
            )
        )
    body = join([body] + drips, "Body")
    paint(body, (0.36, 0.45, 0.16), (0.75, 0.82, 0.2))
    debris = []
    for i in range(3):
        debris.append(primitive("sphere", f"scrap{i}", (-0.8 + i * 0.7, 3.4, 0.6), (0.28, 0.18, 0.22)))
    debris_ob = join(debris, "Phase2_Debris")
    paint(debris_ob, (0.45, 0.32, 0.16))
    core = primitive("sphere", "Phase3_Core", (0.0, 2.05, 0.85), (0.55, 0.28, 0.22), seg=16)
    emissive_object(core, (0.85, 0.9, 0.25), 3.2)
    return {"body": body, "phases": [debris_ob, core], "height": HEIGHTS["the_filth"]}


def build_breach() -> dict:
    parts = []
    parts.append(primitive("sphere", "torso", (0, 3.5, 0), (1.7, 1.45, 1.15)))
    parts.append(primitive("sphere", "shoulder", (0, 4.55, 0), (2.05, 0.7, 1.0)))
    parts.append(primitive("sphere", "head", (0, 5.35, 0.15), (0.7, 0.55, 0.65)))
    parts.append(primitive("sphere", "pelvis", (0, 2.15, 0), (1.15, 0.7, 0.9)))
    parts += arm_chain("aL", (-1.5, 4.4, 0.15), (-1.7, 1.7, 0.45), 0.55)
    parts += arm_chain("aR", (1.5, 4.4, 0.15), (1.7, 1.7, 0.45), 0.55)
    parts += leg_chain("lL", (-0.55, 1.7, 0), (-0.6, 0.25, 0.1), 0.55)
    parts += leg_chain("lR", (0.55, 1.7, 0), (0.6, 0.25, 0.1), 0.55)
    body = join(parts, "Body")
    remesh(body, 0.09)
    paint(body, (0.22, 0.16, 0.24), (0.55, 0.28, 0.95))
    seam_bits = []
    for i in range(5):
        seam_bits.append(primitive("cube", f"seam{i}", (0, 2.4 + i * 0.55, -1.05), (0.08, 0.22, 0.06)))
    seam = join(seam_bits, "WardenEye")
    emissive_object(seam, (0.62, 0.28, 1.0), 3.5)
    cracks = primitive("sphere", "Phase2_Enrage", (0, 3.6, 0), (1.5, 1.3, 1.0), seg=10)
    emissive_object(cracks, (0.7, 0.35, 1.0), 1.2)
    # Keep the enrage mesh as a few ridges, not a second body. Shrink it into the back.
    cracks.scale = (0.35, 1.1, 0.15)
    cracks.location = (0, 3.6, -0.9)
    apply_transforms(cracks)
    return {"body": body, "extra": [seam], "phases": [cracks], "height": HEIGHTS["breach_warden"]}


def build_king() -> dict:
    parts = []
    parts.append(primitive("sphere", "belly", (0, 1.05, 0.08), (0.72, 0.48, 0.55)))
    parts.append(primitive("sphere", "chest", (0, 1.55, 0.02), (0.78, 0.42, 0.48)))
    parts.append(primitive("sphere", "head", (0, 2.05, 0.06), (0.38, 0.32, 0.34)))
    parts.append(primitive("cone", "earL", (-0.38, 2.15, 0.0), (0.16, 0.22, 0.08), rot=(0, 0.2, 1.2), seg=6))
    parts.append(primitive("cone", "earR", (0.38, 2.15, 0.0), (0.16, 0.22, 0.08), rot=(0, -0.2, -1.2), seg=6))
    parts.append(primitive("cone", "tuskL", (-0.12, 1.88, 0.32), (0.05, 0.16, 0.05), rot=(1.1, 0, 0.2), seg=6))
    parts.append(primitive("cone", "tuskR", (0.12, 1.88, 0.32), (0.05, 0.16, 0.05), rot=(1.1, 0, -0.2), seg=6))
    parts.append(primitive("sphere", "paulL", (-0.55, 1.75, 0.0), (0.28, 0.16, 0.22)))
    parts.append(primitive("sphere", "paulR", (0.55, 1.75, 0.0), (0.28, 0.16, 0.22)))
    parts += arm_chain("aR", (-0.6, 1.65, 0.05), (-0.85, 1.05, 0.45), 0.2)
    parts += arm_chain("aL", (0.6, 1.65, 0.05), (0.72, 0.85, 0.25), 0.18)
    parts += leg_chain("lL", (-0.22, 0.7, 0), (-0.24, 0.12, 0.06), 0.2)
    parts += leg_chain("lR", (0.22, 0.7, 0), (0.24, 0.12, 0.06), 0.2)
    body = join(parts, "Body")
    remesh(body, 0.045)
    mace = join(
        [
            primitive("cyl", "haft", (-0.95, 1.35, 0.55), (0.06, 0.42, 0.06), rot=(0.8, 0, 0.3), seg=8),
            primitive("sphere", "headm", (-1.15, 1.85, 0.75), (0.22, 0.2, 0.22), seg=10),
        ],
        "mace",
    )
    for i in range(5):
        ang = i / 5 * math.tau
        mace = join(
            [
                mace,
                primitive(
                    "cone",
                    f"spike{i}",
                    (-1.15 + math.cos(ang) * 0.18, 1.85 + math.sin(ang) * 0.12, 0.75),
                    (0.04, 0.12, 0.04),
                    seg=5,
                ),
            ],
            "mace",
        )
    body = join([body, mace], "Body")
    paint(body, (0.32, 0.48, 0.18), None)
    crown_bits = [primitive("cyl", "band", (0, 2.32, 0.02), (0.28, 0.06, 0.26), seg=12)]
    for i in range(7):
        ang = -0.9 + i * 0.3
        crown_bits.append(
            primitive(
                "cone",
                f"c{i}",
                (math.sin(ang) * 0.22, 2.48, math.cos(ang) * 0.18),
                (0.04, 0.16, 0.04),
                seg=5,
            )
        )
    crown = join(crown_bits, "Crown")
    paint(crown, (0.72, 0.58, 0.28))
    eyes = join(
        [
            primitive("sphere", "eL", (-0.1, 2.08, 0.28), (0.04, 0.03, 0.03), seg=8),
            primitive("sphere", "eR", (0.1, 2.08, 0.28), (0.04, 0.03, 0.03), seg=8),
        ],
        "Phase2_Enrage",
    )
    emissive_object(eyes, (1.0, 0.35, 0.1), 2.5)
    return {"body": body, "crown": crown, "phases": [eyes], "height": HEIGHTS["goblin_king"], "crown_bone": "Head"}


def build_matriarch() -> dict:
    parts = []
    parts.append(primitive("sphere", "torso", (0, 2.7, 0.1), (1.35, 1.25, 1.05)))
    parts.append(primitive("sphere", "head", (0, 4.15, 0.15), (0.7, 0.55, 0.6)))
    parts += arm_chain("aL", (-1.05, 3.5, 0.2), (-1.7, 1.6, 0.7), 0.38)
    parts += arm_chain("aR", (1.05, 3.5, 0.2), (1.7, 1.55, 0.75), 0.38)
    parts += leg_chain("lL", (-0.45, 1.5, 0), (-0.55, 0.2, 0.15), 0.42)
    parts += leg_chain("lR", (0.45, 1.5, 0), (0.55, 0.2, 0.15), 0.42)
    # Claws
    for side in (-1, 1):
        for c in range(3):
            parts.append(
                primitive(
                    "cone",
                    f"claw{side}{c}",
                    (side * 1.85, 1.35, 0.85 + c * 0.08),
                    (0.05, 0.22, 0.05),
                    rot=(1.2, 0, side * 0.4),
                    seg=5,
                )
            )
    # Mushroom caps on the back, part of phase 1.
    for i, (x, z) in enumerate([(-0.45, -0.7), (0.4, -0.85), (0.0, -0.45), (0.7, -0.4)]):
        parts.append(primitive("sphere", f"cap{i}", (x, 4.3 + i * 0.08, z), (0.38, 0.12, 0.38), seg=12))
        parts.append(primitive("cyl", f"stem{i}", (x, 3.9, z), (0.08, 0.35, 0.08), seg=6))
    body = join(parts, "Body")
    remesh(body, 0.08)
    # Open maw: a cavity in the upper chest / face.
    cutter = primitive("sphere", "maw", (0.0, 3.55, 0.75), (0.55, 0.42, 0.4))
    boolean_diff(body, cutter)
    paint(body, (0.24, 0.32, 0.14), (0.55, 0.22, 0.72))
    spines = []
    for i in range(7):
        spines.append(
            primitive(
                "cone",
                f"sp{i}",
                (-0.5 + i * 0.16, 3.6 + (i % 3) * 0.15, -0.95),
                (0.08, 0.4, 0.08),
                rot=(1.3, 0, 0),
                seg=5,
            )
        )
    spine = join(spines, "Phase2_Spines")
    paint(spine, (0.45, 0.22, 0.7))
    heart = primitive("sphere", "Phase3_Heart", (0.0, 2.55, 0.72), (0.38, 0.42, 0.22), seg=14)
    emissive_object(heart, (0.75, 0.28, 0.42), 1.8)
    return {"body": body, "phases": [spine, heart], "height": HEIGHTS["blightmaw_matriarch"]}


def build_choir() -> dict:
    parts = []
    # Several singers in a ring, fused into one volume. Front of the cluster is +Z.
    for i in range(8):
        ang = i / 8 * math.tau
        rad = 0.85 + (0.25 if i % 2 else 0.0)
        x = math.sin(ang) * rad
        z = math.cos(ang) * rad * 0.85
        y = 1.3 + (i % 3) * 0.85
        h = 1.5 + (i % 2) * 0.35
        parts.append(primitive("cone", f"robe{i}", (x, y, z), (0.42, h, 0.38), seg=10))
        parts.append(primitive("sphere", f"hd{i}", (x, y + h * 0.55, z + 0.05), (0.22, 0.2, 0.2), seg=10))
        parts.append(
            primitive("sphere", f"arm{i}", (x + 0.25, y + 0.2, z + 0.15), (0.08, 0.28, 0.08), rot=(0.6, ang, 0), seg=6)
        )
    # A central column so they read as one mass, not eight actors.
    parts.append(primitive("cyl", "corecol", (0, 2.2, 0), (0.45, 2.0, 0.45), seg=12))
    body = join(parts, "Body")
    remesh(body, 0.1)
    kelp = []
    for i in range(6):
        ang = i / 6 * math.tau
        pts = []
        for t in range(6):
            pts.append(
                (
                    math.sin(ang) * (0.9 + t * 0.12),
                    1.2 + t * 0.55,
                    math.cos(ang) * (0.8 + t * 0.1),
                )
            )
        kelp.append(tube(pts, 0.045, f"kelp{i}"))
    body = join([body] + kelp, "Body")
    paint(body, (0.12, 0.32, 0.38), (0.75, 0.35, 0.95))
    water = primitive("cyl", "Phase2_Water", (0, 1.7, 0), (1.7, 0.18, 1.5), seg=20)
    emissive_object(water, (0.1, 0.45, 0.7), 0.6)
    return {"body": body, "phases": [water], "height": HEIGHTS["drowned_choir"]}


def build_storm() -> dict:
    parts = []
    # A cloak with real depth: wide at the hem, thick through the body, not a sheet.
    parts.append(primitive("cone", "cloak", (0, 2.2, 0), (1.35, 2.3, 1.05), seg=16))
    parts.append(primitive("sphere", "shoulders", (0, 3.7, 0), (1.15, 0.45, 0.85)))
    parts.append(primitive("sphere", "hood", (0, 4.25, 0.05), (0.55, 0.48, 0.5)))
    parts += arm_chain("aL", (-0.7, 3.5, 0.15), (-1.05, 2.1, 0.45), 0.22)
    parts += arm_chain("aR", (0.7, 3.5, 0.15), (0.95, 2.15, 0.5), 0.22)
    for side in (-1, 1):
        for c in range(3):
            parts.append(
                primitive(
                    "cone",
                    f"claw{side}{c}",
                    (side * 1.1, 1.85, 0.55),
                    (0.035, 0.16, 0.035),
                    rot=(1.1, 0, side * 0.3),
                    seg=5,
                )
            )
    body = join(parts, "Body")
    remesh(body, 0.08)
    crystals = []
    for i in range(9):
        ang = i / 9 * math.tau
        crystals.append(
            primitive(
                "cone",
                f"xt{i}",
                (math.sin(ang) * 0.28, 4.55 + (i % 3) * 0.12, math.cos(ang) * 0.22),
                (0.1, 0.38 + (i % 2) * 0.15, 0.1),
                rot=(0.2, ang, 0.15),
                seg=5,
            )
        )
    crystals.append(primitive("cone", "crownxt", (0, 5.05, 0), (0.16, 0.55, 0.16), seg=5))
    xt = join(crystals, "crystals")
    emissive_object(xt, (0.62, 0.48, 0.95), 1.6)
    wind = []
    for turn, rad, yy in ((0.0, 0.9, 1.2), (2.0, 1.15, 2.2)):
        pts = []
        for t in range(16):
            a = turn + t / 16 * math.tau * 1.2
            pts.append((math.cos(a) * rad, yy + t * 0.08, math.sin(a) * rad * 0.75))
        wind.append(tube(pts, 0.035, f"wind{turn}"))
    gust = join(wind, "wind")
    emissive_object(gust, (0.85, 0.88, 1.0), 1.4)
    body = join([body, xt, gust], "Body")
    gale_pts = []
    for t in range(14):
        a = t / 14 * math.tau
        gale_pts.append((math.cos(a) * 1.35, 1.5 + t * 0.12, math.sin(a) * 1.05))
    gale = tube(gale_pts, 0.04, "Phase2_Gale")
    emissive_object(gale, (0.75, 0.6, 1.0), 2.0)
    return {"body": body, "phases": [gale], "height": HEIGHTS["storm_warden"]}


BUILDERS = {
    "the_filth": build_filth,
    "breach_warden": build_breach,
    "goblin_king": build_king,
    "blightmaw_matriarch": build_matriarch,
    "forgemaw": build_forgemaw,
    "drowned_choir": build_choir,
    "storm_warden": build_storm,
}


def add_bone(arm, name, head, tail, parent):
    b = arm.edit_bones.new(name)
    b.head = Vector(head)
    b.tail = Vector(tail)
    if parent:
        b.parent = arm.edit_bones[parent]
    return b


def build_armature(body: bpy.types.Object) -> bpy.types.Object:
    lo, hi = bounds(body)
    h = hi.z - lo.z
    cx = (lo.x + hi.x) * 0.5
    w = max(hi.x - lo.x, 0.2)
    arm_data = bpy.data.armatures.new("Rig")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm)
    activate(arm)
    bpy.ops.object.mode_set(mode="EDIT")
    z0 = lo.z
    add_bone(arm_data, "Hips", (cx, 0, z0 + 0.38 * h), (cx, 0, z0 + 0.48 * h), None)
    add_bone(arm_data, "Spine", (cx, 0, z0 + 0.48 * h), (cx, 0, z0 + 0.62 * h), "Hips")
    add_bone(arm_data, "Chest", (cx, 0, z0 + 0.62 * h), (cx, 0, z0 + 0.78 * h), "Spine")
    add_bone(arm_data, "Head", (cx, -0.02 * h, z0 + 0.78 * h), (cx, -0.04 * h, z0 + 0.95 * h), "Chest")
    for sign, side in ((-1, "R"), (1, "L")):
        add_bone(
            arm_data,
            f"UpperArm.{side}",
            (cx + sign * 0.22 * w, -0.02 * h, z0 + 0.7 * h),
            (cx + sign * 0.38 * w, -0.08 * h, z0 + 0.55 * h),
            "Chest",
        )
        add_bone(
            arm_data,
            f"LowerArm.{side}",
            (cx + sign * 0.38 * w, -0.08 * h, z0 + 0.55 * h),
            (cx + sign * 0.46 * w, -0.12 * h, z0 + 0.4 * h),
            f"UpperArm.{side}",
        )
        add_bone(
            arm_data,
            f"Hand.{side}",
            (cx + sign * 0.46 * w, -0.12 * h, z0 + 0.4 * h),
            (cx + sign * 0.5 * w, -0.16 * h, z0 + 0.34 * h),
            f"LowerArm.{side}",
        )
    for sign, side in ((-1, "L"), (1, "R")):
        add_bone(
            arm_data,
            f"UpperLeg.{side}",
            (cx + sign * 0.12 * w, 0, z0 + 0.36 * h),
            (cx + sign * 0.14 * w, -0.02 * h, z0 + 0.18 * h),
            "Hips",
        )
        add_bone(
            arm_data,
            f"LowerLeg.{side}",
            (cx + sign * 0.14 * w, -0.02 * h, z0 + 0.18 * h),
            (cx + sign * 0.15 * w, -0.04 * h, z0 + 0.06 * h),
            f"UpperLeg.{side}",
        )
        add_bone(
            arm_data,
            f"Foot.{side}",
            (cx + sign * 0.15 * w, -0.02 * h, z0 + 0.02 * h),
            (cx + sign * 0.15 * w, -0.12 * h, z0 + 0.02 * h),
            f"LowerLeg.{side}",
        )
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def bind(body: bpy.types.Object, arm: bpy.types.Object) -> None:
    activate(body)
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")


def parent_bone(ob: bpy.types.Object, arm: bpy.types.Object, bone: str) -> None:
    mw = ob.matrix_world.copy()
    ob.parent = arm
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    bpy.context.view_layer.update()
    ob.matrix_world = mw


def quat_keys(arm: bpy.types.Object) -> None:
    arm.animation_data_create()
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"

    def clip(name: str, bones: dict, frames: int) -> None:
        action = bpy.data.actions.new(name)
        arm.animation_data.action = action
        for bone, keys in bones.items():
            if bone not in arm.pose.bones:
                continue
            path = f'pose.bones["{bone}"].rotation_euler'
            for axis in range(3):
                fc = action.fcurves.new(path, index=axis)
                for frame, rot in keys:
                    fc.keyframe_points.insert(frame, rot[axis])
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)
        arm.animation_data.action = None

    idle = {"Spine": [(1, (0, 0, 0)), (16, (0.06, 0, 0)), (32, (0, 0, 0))]}
    walk = {
        "UpperLeg.L": [(1, (0.3, 0, 0)), (12, (-0.3, 0, 0)), (24, (0.3, 0, 0))],
        "UpperLeg.R": [(1, (-0.3, 0, 0)), (12, (0.3, 0, 0)), (24, (-0.3, 0, 0))],
        "UpperArm.L": [(1, (0, 0, 0.25)), (12, (0, 0, -0.25)), (24, (0, 0, 0.25))],
        "UpperArm.R": [(1, (0, 0, -0.25)), (12, (0, 0, 0.25)), (24, (0, 0, -0.25))],
    }
    attack = {"UpperArm.R": [(1, (0, 0, 0)), (8, (-1.1, 0, 0)), (16, (0.4, 0, 0)), (24, (0, 0, 0))]}
    throw = {"UpperArm.R": [(1, (0.2, 0, 0)), (8, (-1.2, 0, 0)), (12, (0.8, 0, 0)), (20, (0, 0, 0))]}
    slam = {"Spine": [(1, (0, 0, 0)), (8, (0.45, 0, 0)), (16, (0, 0, 0))]}
    roar = {"Chest": [(1, (0, 0, 0)), (10, (-0.35, 0, 0)), (36, (-0.35, 0, 0)), (48, (0, 0, 0))]}
    hurt = {"Spine": [(1, (0, 0, 0)), (4, (0, 0, 0.25)), (10, (0, 0, 0))]}
    death = {"Hips": [(1, (0, 0, 0)), (12, (0.9, 0, 0)), (24, (1.3, 0, 0))]}
    spore = {"Chest": [(1, (0, 0, 0)), (8, (0.35, 0, 0)), (18, (0, 0, 0))]}
    for name, keys in (
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
    ):
        clip(name, keys, 24)
    bpy.ops.object.mode_set(mode="OBJECT")


def export(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_skins=True,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
        export_materials="EXPORT",
    )


def sculpt(boss_id: str) -> None:
    reset()
    built = BUILDERS[boss_id]()
    body = built["body"]
    extras = list(built.get("phases", [])) + list(built.get("extra", []))
    if built.get("crown"):
        extras.append(built["crown"])
    lay_upright([body] + extras)
    fit_height([body] + extras, built["height"])
    decimate_to(body, 9000)
    lo, hi = bounds(body)
    size = hi - lo
    # Z is up in Blender. Depth is Y. A relief slab fails this.
    if size.y < size.z * 0.35:
        raise SystemExit(f"{boss_id} is still a slab: {size.x:.2f} x {size.y:.2f} x {size.z:.2f}")
    arm = build_armature(body)
    bind(body, arm)
    bone_for = {"Phase3_Core": "Chest", "Phase3_Heart": "Chest", "Phase2_Spines": "Chest", "Phase2_Debris": "Chest", "Phase2_Water": "Hips", "Phase2_Enrage": "Chest", "Phase2_Gale": "Chest", "WardenEye": "Chest", "Crown": "Head"}
    for ob in extras:
        parent_bone(ob, arm, bone_for.get(ob.name, "Chest"))
    quat_keys(arm)
    path = os.path.join(OUT, boss_id + ".glb")
    export(path)
    print(f"{boss_id}: {len(body.data.polygons)} tris, size {size.x:.2f} x {size.y:.2f} x {size.z:.2f} -> {path}")


def main() -> None:
    want = argv_after()
    ids = want or list(BUILDERS)
    for boss_id in ids:
        if boss_id not in BUILDERS:
            raise SystemExit(f"unknown boss {boss_id}")
        sculpt(boss_id)


if __name__ == "__main__":
    main()
