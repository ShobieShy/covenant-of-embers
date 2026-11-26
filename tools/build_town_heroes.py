# Blender 4 headless. Ember Art town heroes for the 0.12.0 slice.
# Units are metres. Blender Z-up; glTF export is Y-up, so Blender +Y
# (the outside face of a wall, the outside of the gate) becomes Godot -Z.
#
#   blender --background --python tools/build_town_heroes.py
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "assets", "original", "ember_art", "town")
os.makedirs(OUT, exist_ok=True)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def pix_image(name, w, h, fn):
    img = bpy.data.images.new(name, w, h, alpha=True)
    px = [0.0] * (w * h * 4)
    for y in range(h):
        for x in range(w):
            r, g, b, a = fn(x, y, w, h)
            i = (y * w + x) * 4
            px[i : i + 4] = (r, g, b, a)
    img.pixels.foreach_set(px)
    img.pack()
    return img


def stone_tex():
    def fn(x, y, w, h):
        bx, by = x // 32, y // 16
        mortar = x % 32 < 2 or y % 16 < 2
        n = ((bx * 17 + by * 31) % 9) / 9.0
        if mortar:
            return (0.45, 0.40, 0.34, 1)
        return (0.62 + n * 0.12, 0.56 + n * 0.08, 0.46 + n * 0.05, 1)

    return pix_image("stone", 256, 256, fn)


def stripe_tex():
    def fn(x, y, w, h):
        if (x // 16) % 2 == 0:
            return (0.72, 0.16, 0.14, 1)
        return (0.93, 0.88, 0.78, 1)

    return pix_image("stripe", 128, 32, fn)


def cobble_tex():
    def fn(x, y, w, h):
        # Irregular stones in a 20 px cell.
        cx, cy = (x % 20) / 20.0, (y % 20) / 20.0
        edge = cx < 0.08 or cy < 0.08 or cx > 0.92 or cy > 0.92
        n = ((x // 20) * 13 + (y // 20) * 7) % 5
        if edge:
            return (0.42, 0.38, 0.32, 1)
        return (0.70 + n * 0.03, 0.64 + n * 0.02, 0.52, 1)

    return pix_image("cobble", 256, 256, fn)


def leaf_tex():
    def fn(x, y, w, h):
        n = ((x * 3 + y * 5) % 7) / 7.0
        return (0.22 + n * 0.08, 0.42 + n * 0.12, 0.18, 1)

    return pix_image("leaf", 64, 64, fn)


def principled(name, color, rough=0.85, emit=None, emit_strength=0.0, alpha=1.0, tex=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if "Emission Color" in bsdf.inputs and emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    if alpha < 1.0:
        m.blend_method = "BLEND"
        bsdf.inputs["Alpha"].default_value = alpha
        m.use_backface_culling = False
    if tex is not None:
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = tex
        nt.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def assign(obj, mat):
    if obj.data.materials:
        obj.data.materials[0] = mat
    else:
        obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()


def finish(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def cube(name, loc, scale, mat):
    bpy.ops.mesh.primitive_cube_add(location=loc, scale=scale)
    ob = bpy.context.active_object
    ob.name = name
    assign(ob, mat)
    return ob


def cyl(name, loc, radius, depth, mat, verts=16, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot
    )
    ob = bpy.context.active_object
    ob.name = name
    assign(ob, mat)
    return ob


def join(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    finish(ob)
    return ob


def export(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        use_selection=False,
    )
    print("wrote", path)


def build_wall(stone):
    clear()
    parts = []
    parts.append(cube("body", (0, 0, 2.3), (4.0, 0.65, 2.3), stone))
    parts.append(cube("base", (0, 0, 0.35), (4.15, 0.8, 0.35), stone))
    for i in range(5):
        x = -3.2 + i * 1.6
        parts.append(cube("merlon", (x, 0, 4.85), (0.45, 0.7, 0.4), stone))
    join("wall_segment", parts)
    export("wall_segment")


def build_tower(stone):
    clear()
    parts = [cube("shaft", (0, 0, 4.2), (1.7, 1.7, 4.2), stone)]
    parts.append(cube("lip", (0, 0, 8.5), (2.0, 2.0, 0.25), stone))
    for sx in (-1.5, 1.5):
        for sy in (-1.5, 1.5):
            parts.append(cube("cap", (sx, sy, 9.0), (0.35, 0.35, 0.4), stone))
    join("wall_tower", parts)
    export("wall_tower")


def build_gate(stone, wood):
    clear()
    parts = []
    for sx in (-4.6, 4.6):
        parts.append(cube("pier", (sx, 0, 4.0), (1.5, 1.8, 4.0), stone))
        parts.append(cube("cap", (sx, 0, 8.3), (1.8, 2.05, 0.35), stone))
    # Arch mass, then a cylinder cutter along Y.
    bpy.ops.mesh.primitive_cube_add(location=(0, 0, 6.3), scale=(3.2, 1.5, 1.5))
    lintel = bpy.context.active_object
    assign(lintel, stone)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=24, radius=2.7, depth=5.0, location=(0, 0, 4.6), rotation=(math.pi / 2, 0, 0)
    )
    cutter = bpy.context.active_object
    mod = lintel.modifiers.new("Arch", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = lintel
    bpy.ops.object.modifier_apply(modifier="Arch")
    bpy.data.objects.remove(cutter, do_unlink=True)
    parts.append(lintel)
    # Wooden frame just inside the opening.
    parts.append(cube("jamb_l", (-2.5, 0.2, 2.6), (0.18, 0.22, 2.6), wood))
    parts.append(cube("jamb_r", (2.5, 0.2, 2.6), (0.18, 0.22, 2.6), wood))
    parts.append(cube("head", (0, 0.2, 5.3), (2.6, 0.22, 0.18), wood))
    join("gatehouse", parts)
    export("gatehouse")


def build_crystal(stone):
    clear()
    parts = [cube("plinth", (0, 0, 0.7), (0.7, 0.7, 0.7), stone)]
    parts.append(cube("step", (0, 0, 1.45), (0.5, 0.5, 0.12), stone))
    crystal = principled("crystal", (0.42, 0.22, 0.78), 0.25, (0.5, 0.25, 0.9), 0.45, 0.92)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.45, location=(0, 0, 2.7))
    gem = bpy.context.active_object
    gem.scale = (0.7, 0.7, 2.2)
    assign(gem, crystal)
    parts.append(gem)
    join("crystal_pylon", parts)
    export("crystal_pylon")


def build_fountain(stone):
    clear()
    water = principled("water", (0.15, 0.45, 0.48), 0.15, (0.1, 0.35, 0.4), 0.15)
    parts = []
    tiers = [(4.2, 0.55, 0.55), (2.6, 1.55, 0.42), (1.35, 2.45, 0.32)]
    for i, (rad, z, h) in enumerate(tiers):
        parts.append(cyl("bowl", (0, 0, z), rad, h * 2, stone, 32))
        parts.append(cyl("lip", (0, 0, z + h), rad * 1.04, 0.12, stone, 32))
        parts.append(cyl("pool", (0, 0, z + h * 0.85), rad * 0.78, 0.06, water, 24))
    parts.append(cyl("spout", (0, 0, 3.15), 0.18, 0.7, stone, 10))
    join("fountain", parts)
    export("fountain")


def build_stall(wood, stripe):
    clear()
    cloth = principled("awning", (0.7, 0.2, 0.15), 0.6, tex=stripe)
    parts = []
    for x in (-1.4, 1.4):
        for y in (-0.7, 0.7):
            parts.append(cube("post", (x, y, 1.15), (0.08, 0.08, 1.15), wood))
    parts.append(cube("counter", (0, 0.15, 0.95), (1.45, 0.45, 0.08), wood))
    # Peaked awning: two slanted boards.
    for sign, tilt in ((-0.55, 0.5), (0.55, -0.5)):
        bpy.ops.mesh.primitive_cube_add(location=(0, sign, 2.45), scale=(1.6, 0.62, 0.04))
        ob = bpy.context.active_object
        ob.rotation_euler[0] = tilt
        assign(ob, cloth)
        parts.append(ob)
    parts.append(cube("ridge", (0, 0, 2.72), (1.6, 0.08, 0.06), wood))
    join("stall_striped", parts)
    export("stall_striped")


def build_lantern(wood):
    clear()
    iron = principled("iron", (0.15, 0.13, 0.12), 0.4)
    glow = principled("glow", (1.0, 0.78, 0.4), 0.3, (1.0, 0.72, 0.35), 4.0)
    parts = [cyl("pole", (0, 0, 1.3), 0.06, 2.6, iron, 8)]
    parts.append(cube("head", (0, 0, 2.55), (0.16, 0.16, 0.22), iron))
    parts.append(cube("flame", (0, 0, 2.55), (0.08, 0.08, 0.12), glow))
    parts.append(cube("cap", (0, 0, 2.82), (0.2, 0.2, 0.04), iron))
    join("lantern_post", parts)
    export("lantern_post")


def build_hedge(leaf):
    clear()
    mat = principled("hedge", (0.2, 0.42, 0.16), 0.9, tex=leaf)
    parts = []
    for x in (-0.7, 0.0, 0.7):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.55, location=(x, 0, 0.7))
        ob = bpy.context.active_object
        ob.scale = (0.9, 0.7, 0.85)
        assign(ob, mat)
        parts.append(ob)
    join("hedge", parts)
    export("hedge")


def build_tree(leaf):
    clear()
    bark = principled("bark", (0.32, 0.22, 0.14), 0.9)
    mat = principled("canopy", (0.18, 0.4, 0.14), 0.85, tex=leaf)
    parts = [cyl("trunk", (0, 0, 1.4), 0.22, 2.8, bark, 8)]
    for loc, sc in (
        ((0, 0, 3.3), (1.5, 1.5, 1.1)),
        ((0.7, 0.3, 3.8), (1.1, 1.1, 0.9)),
        ((-0.6, -0.2, 3.6), (1.2, 1.0, 0.85)),
    ):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0, location=loc)
        ob = bpy.context.active_object
        ob.scale = sc
        assign(ob, mat)
        parts.append(ob)
    join("town_tree", parts)
    export("town_tree")


def build_plaza(cobble):
    clear()
    mat = principled("plaza", (0.7, 0.64, 0.52), 0.9, tex=cobble)
    bpy.ops.mesh.primitive_circle_add(vertices=64, radius=22.0, fill_type="NGON", location=(0, 0, 0))
    ob = bpy.context.active_object
    # Circle is in XY; rotate so it lies in Blender XY which is Godot XZ after yup? 
    # A flat circle in Blender XY (Z=0) exports to Godot XZ. Good, it's a ground disc.
    ob.rotation_euler = (0, 0, 0)
    assign(ob, mat)
    # Repeat the cobble across the disc.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = ob.data.uv_layers.active.data
    for loop in uv:
        loop.uv[0] *= 8.0
        loop.uv[1] *= 8.0
    finish(ob)
    export("plaza_cobble")


def build_path(cobble):
    clear()
    mat = principled("path", (0.68, 0.62, 0.5), 0.92, tex=cobble)
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.scale = (8.0, 70.0, 1.0)
    assign(ob, mat)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = ob.data.uv_layers.active.data
    for loop in uv:
        loop.uv[0] *= 4.0
        loop.uv[1] *= 20.0
    finish(ob)
    export("gate_path")


def build_dome():
    clear()
    mat = principled("haze", (0.72, 0.55, 0.85), 0.4, (0.55, 0.35, 0.8), 0.4, 0.12)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=150.0, location=(0, 0, 20))
    ob = bpy.context.active_object
    assign(ob, mat)
    # Drop the lower half so it reads as a dome.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in ob.data.vertices:
        v.select = v.co.z < 0
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    finish(ob)
    export("dome_haze")


def main():
    stone_img = stone_tex()
    stone = principled("stone", (0.62, 0.56, 0.46), 0.88, tex=stone_img)
    wood = principled("wood", (0.38, 0.24, 0.14), 0.8)
    stripe = stripe_tex()
    cobble = cobble_tex()
    leaf = leaf_tex()
    build_wall(stone)
    build_tower(stone)
    build_gate(stone, wood)
    build_crystal(stone)
    build_fountain(stone)
    build_stall(wood, stripe)
    build_lantern(wood)
    build_hedge(leaf)
    build_tree(leaf)
    build_plaza(cobble)
    build_path(cobble)
    build_dome()


if __name__ == "__main__":
    main()
