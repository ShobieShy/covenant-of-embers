#!/usr/bin/env python3
"""Clean a Hunyuan3D shape into a crowd mesh.

Blender, headless:

    blender -b -P tools/finish_regular_enemy.py -- \
        --src /tmp/enemy_raw/goblin_grunt_hy_0.glb \
        --ref /tmp/enemy_crops/goblin_grunt.png \
        --out assets/original/ember_art/regular_enemies/goblin_grunt.glb \
        --part Club --tris 6500

The shape is Z-up and should face -Y before export. Hunyuan already does.
TripoSR faces the other way, so pass --yaw 180 --mirror x. The floor sheet
under the feet is cut away. The concept crop is projected on as the albedo,
with paper-white texels replaced by the nearest paint. A thin rig (Idle /
Walk, foot bones) is exported so Godot can plant and play it. glTF Y-up
turns the -Y face into +Z, which CharacterModel then turns to Godot's -Z.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
import bmesh
import mathutils
import numpy as np
from PIL import Image

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(flag: str, default: str = "") -> str:
    if flag in argv:
        return argv[argv.index(flag) + 1]
    return default


SRC = Path(arg("--src"))
REF = Path(arg("--ref"))
OUT = Path(arg("--out"))
PART = arg("--part")  # Club / Bow / Staff / Flame, or empty
TRIS = int(arg("--tris", "6500"))
TINT = arg("--tint", "")  # "r,g,b" multipliers, 0..1+
METALLIC = float(arg("--metallic", "0"))
YAW = float(arg("--yaw", "0"))  # degrees around Z, applied before the floor cut
MIRROR = arg("--mirror", "") == "x"


def world_verts(obj):
    mw = obj.matrix_world
    return np.array([mw @ v.co for v in obj.data.vertices], dtype=np.float64)


def apply_world(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def drop_floor(obj):
    """Delete the wide sheet Hunyuan lays under the feet. Z is up."""
    vs = world_verts(obj)
    z = vs[:, 2]
    body = vs[z > z.min() + 0.12]
    if len(body) < 100:
        body = vs[z > z.min() + 0.05]
    x0, x1 = np.percentile(body[:, 0], [1, 99])
    y0, y1 = np.percentile(body[:, 1], [1, 99])
    pad = 0.06 * max(x1 - x0, y1 - y0, 0.1)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.transform(bm, matrix=obj.matrix_world, verts=bm.verts)
    kill = []
    for v in bm.verts:
        c = v.co
        inside = (x0 - pad) <= c.x <= (x1 + pad) and (y0 - pad) <= c.y <= (y1 + pad)
        # A low percentile is still the floor, because the sheet holds most vertices.
        if (not inside) and c.z < float(z.min() + 0.05):
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    # The sheet under the soles is inside the footprint. Drop faces that lie flat on it.
    low = float(z.min() + 0.04)
    flat = []
    for f in bm.faces:
        if f.normal.z > 0.82 and f.calc_center_median().z < low:
            flat.append(f)
    bmesh.ops.delete(bm, geom=flat, context="FACES")
    loose = [v for v in bm.verts if len(v.link_faces) == 0]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.matrix_world = mathutils.Matrix.Identity(4)
    obj.data.update()


def largest_island(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    islands = []
    seen = set()
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        seen.add(v.index)
        group = [v]
        while stack:
            cur = stack.pop()
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
                    group.append(o)
        islands.append(group)
    if not islands:
        bm.free()
        return
    islands.sort(key=len, reverse=True)
    kill = [v for group in islands[1:] if len(group) < len(islands[0]) * 0.15 for v in group]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def decimate_to(obj, target):
    faces = len(obj.data.polygons)
    if faces <= target * 1.05:
        return
    ratio = max(target / float(faces), 0.002)
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.ratio = ratio
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # one light smooth so the decimated surface doesn't sparkle
    smod = obj.modifiers.new("Smooth", "SMOOTH")
    smod.factor = 0.2
    smod.iterations = 1
    bpy.ops.object.modifier_apply(modifier=smod.name)


def clip_plate(obj):
    """Drop the flat sheet the generator leaves under the soles."""
    vs = world_verts(obj)
    if len(vs) < 50:
        return
    z0 = float(vs[:, 2].min())
    z1 = float(vs[:, 2].max())
    zcut = z0 + 0.06 * max(z1 - z0, 1e-4)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    flat = [f for f in bm.faces if f.calc_center_median().z < zcut and f.normal.z > 0.55]
    bmesh.ops.delete(bm, geom=flat, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def ground_and_center(obj):
    vs = world_verts(obj)
    obj.location.x -= float(np.median(vs[:, 0]))
    obj.location.y -= float(np.median(vs[:, 1]))
    obj.location.z -= float(vs[:, 2].min())
    apply_world(obj)


def _tint_rgb():
    if not TINT:
        return np.ones(3, dtype=np.float64)
    parts = [float(p) for p in TINT.split(",")]
    if len(parts) != 3:
        raise SystemExit("--tint needs r,g,b")
    return np.array(parts, dtype=np.float64)


def bake_albedo(obj, image_path: Path):
    """Project the sheet from the front. Paper-white texels become the nearest paint.

    Side faces keep that albedo, so a 3/4 view still reads as the sheet instead of
    showing the white background through gaps.
    """
    from scipy.ndimage import binary_erosion, distance_transform_edt

    im = Image.open(image_path).convert("RGB")
    arr = np.asarray(im)
    # Pale paper and the anti-aliased fringe are not paint. A looser cut leaves
    # white shells wherever the mesh sticks past the silhouette.
    # Colour comes from the painted body, not the pale paper fringe. The shell
    # around the silhouette then picks up hide and rust instead of white.
    ink = binary_erosion(arr.min(axis=2) < 150, iterations=1)
    if int(ink.sum()) < 10:
        ink = arr.min(axis=2) < 190
    if int(ink.sum()) < 10:
        ink = np.ones(arr.shape[:2], dtype=bool)
    _, (iy, ix) = distance_transform_edt(np.where(ink, 0, 1), return_indices=True)
    paint = arr[iy, ix]
    tint = _tint_rgb()
    if not np.allclose(tint, 1.0):
        paint = np.clip(paint.astype(np.float64) * tint, 0, 255).astype(np.uint8)
    ys, xs = np.where(ink)
    ix0, ix1 = int(xs.min()), int(xs.max())
    iy0, iy1 = int(ys.min()), int(ys.max())
    vs = world_verts(obj)
    x0, x1 = float(vs[:, 0].min()), float(vs[:, 0].max())
    z0, z1 = float(vs[:, 2].min()), float(vs[:, 2].max())
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    span_x = max(x1 - x0, 1e-6)
    span_z = max(z1 - z0, 1e-6)
    # Front is -Y. Image left is -X, image top is +Z.
    u0 = ix0 / arr.shape[1]
    u1 = (ix1 + 1) / arr.shape[1]
    v_top = 1.0 - iy0 / arr.shape[0]
    v_bot = 1.0 - (iy1 + 1) / arr.shape[0]
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co
        u = u0 + (co.x - x0) / span_x * (u1 - u0)
        v = v_bot + (co.z - z0) / span_z * (v_top - v_bot)
        uv[loop.index].uv = (float(u), float(v))
    tex_path = Path("/tmp/enemy_bake") / f"{OUT.stem}.png"
    tex_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(paint).save(tex_path)
    mat = bpy.data.materials.new("Albedo")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    loaded = bpy.data.images.load(str(tex_path))
    tex.image = loaded
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.62
    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = METALLIC
    if mesh.materials:
        mesh.materials[0] = mat
    else:
        mesh.materials.append(mat)
    return tex_path


def split_part(obj, part_name: str):
    """Duplicate the protruding prop (or the flame crown) into a named mesh."""
    if not part_name:
        return None
    vs = world_verts(obj)
    z0, z1 = float(vs[:, 2].min()), float(vs[:, 2].max())
    height = max(z1 - z0, 1e-4)
    if part_name == "Flame":
        chosen = vs[:, 2] > z0 + 0.72 * height
    else:
        # the weapon is the horizontal extreme, above the knees and below the ears
        mid = (z0 + 0.25 * height < vs[:, 2]) & (vs[:, 2] < z0 + 0.85 * height)
        if mid.sum() < 20:
            mid = np.ones(len(vs), dtype=bool)
        left = float(vs[mid, 0].min())
        right = float(vs[mid, 0].max())
        center = float(np.median(vs[mid, 0]))
        reach_l = center - left
        reach_r = right - center
        if reach_l >= reach_r:
            thresh = center - 0.55 * reach_l
            side = vs[:, 0] < thresh
        else:
            thresh = center + 0.55 * reach_r
            side = vs[:, 0] > thresh
        # The blade tip sits above the hand band. Keep every connected vertex
        # on that side so the weapon stays one piece.
        seed = side & mid
        chosen = seed.copy()
        adj = [[] for _ in range(len(vs))]
        for e in obj.data.edges:
            a, b = int(e.vertices[0]), int(e.vertices[1])
            adj[a].append(b)
            adj[b].append(a)
        stack = list(np.nonzero(seed)[0])
        while stack:
            i = int(stack.pop())
            for j in adj[i]:
                if side[j] and not chosen[j]:
                    chosen[j] = True
                    stack.append(j)
    if int(chosen.sum()) < 12:
        return None
    # Copy first, then take the prop off the body so the two meshes do not z-fight.
    dup = obj.copy()
    dup.data = obj.data.copy()
    dup.name = part_name
    bpy.context.collection.objects.link(dup)
    src_bm = bmesh.new()
    src_bm.from_mesh(obj.data)
    src_kill = [v for v in src_bm.verts if chosen[v.index]]
    bmesh.ops.delete(src_bm, geom=src_kill, context="VERTS")
    src_bm.to_mesh(obj.data)
    src_bm.free()
    obj.data.update()
    bm = bmesh.new()
    bm.from_mesh(dup.data)
    kill = [v for v in bm.verts if not chosen[v.index]]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(dup.data)
    bm.free()
    dup.data.update()
    return dup


def add_rig(obj):
    vs = world_verts(obj)
    z0, z1 = float(vs[:, 2].min()), float(vs[:, 2].max())
    h = max(z1 - z0, 1e-4)
    x_span = float(np.percentile(vs[:, 0], 90) - np.percentile(vs[:, 0], 10))
    arm_data = bpy.data.armatures.new("Armature")
    arm = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    def bone(name, head, tail, parent=None):
        b = eb.new(name)
        b.head = mathutils.Vector(head)
        b.tail = mathutils.Vector(tail)
        if parent:
            b.parent = parent
        return b

    root = bone("Root", (0, 0, 0.02 * h), (0, 0, 0.18 * h))
    spine = bone("Spine", (0, 0, 0.35 * h), (0, 0, 0.62 * h), root)
    bone("Head", (0, 0, 0.62 * h), (0, 0, 0.92 * h), spine)
    hip = x_span * 0.18
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bone(f"Leg.{side}", (sign * hip, 0, 0.34 * h), (sign * hip, 0, 0.08 * h), root)
        bone(f"Foot.{side}", (sign * hip, 0.02 * h, 0.02 * h), (sign * hip, -0.08 * h, 0.0), root)
    bpy.ops.object.mode_set(mode="OBJECT")

    # parent with empty groups so the mesh follows the root without a weight explosion
    obj.parent = arm
    obj.parent_type = "ARMATURE"
    vg = obj.vertex_groups.new(name="Root")
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm

    def clip(name, bob):
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="POSE")
        if arm.animation_data is None:
            arm.animation_data_create()
        action = bpy.data.actions.new(name)
        arm.animation_data.action = action
        pb = arm.pose.bones["Root"]
        pb.rotation_mode = "XYZ"
        for frame, z in ((1, 0.0), (8, bob), (16, 0.0)):
            pb.location = (0.0, 0.0, z)
            pb.keyframe_insert(data_path="location", frame=frame)
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 1, action)
        bpy.ops.object.mode_set(mode="OBJECT")

    clip("Idle", 0.012 * h)
    # a second action: clear the active one before recording Walk
    arm.animation_data.action = None
    clip("Walk", 0.035 * h)
    arm.animation_data.action = None
    return arm


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(SRC))
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        raise SystemExit("no mesh in " + str(SRC))
    # join every imported mesh into one
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "Body"
    apply_world(obj)
    if YAW or MIRROR:
        obj.rotation_mode = "XYZ"
        if YAW:
            obj.rotation_euler[2] = math.radians(YAW)
        if MIRROR:
            obj.scale.x *= -1
        apply_world(obj)
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.normals_make_consistent(inside=False)
        bpy.ops.object.mode_set(mode="OBJECT")
    drop_floor(obj)
    largest_island(obj)
    decimate_to(obj, TRIS)
    ground_and_center(obj)
    clip_plate(obj)
    ground_and_center(obj)
    bake_albedo(obj, REF)
    part = split_part(obj, PART)
    if part is not None:
        # the part shares the body's material and UVs
        part.parent = obj.parent
    arm = add_rig(obj)
    if part is not None:
        part.parent = arm
        part.parent_type = "ARMATURE"
        if "Root" not in [g.name for g in part.vertex_groups]:
            part.vertex_groups.new(name="Root").add(list(range(len(part.data.vertices))), 1.0, "REPLACE")
        pmod = part.modifiers.new("Armature", "ARMATURE")
        pmod.object = arm
    OUT.parent.mkdir(parents=True, exist_ok=True)
    keep = {arm, obj}
    if part is not None:
        keep.add(part)
    for stray in list(bpy.data.objects):
        if stray not in keep:
            bpy.data.objects.remove(stray, do_unlink=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    obj.select_set(True)
    if part is not None:
        part.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=False,
        export_animations=True,
        export_nla_strips=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"wrote {OUT} tris {len(obj.data.polygons)} part {PART or '-'}")


if __name__ == "__main__":
    main()
