# Blender 4 headless. Town heroes for the 0.12.0 slice.
# Blender Z-up. glTF export is Y-up, so Blender +Y becomes Godot -Z.
#
#   blender --background --python tools/build_town_heroes.py
import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ACG = os.path.join(ROOT, "assets", "ambientcg")
OUT = os.path.join(ROOT, "assets", "original", "ember_art", "town")
os.makedirs(OUT, exist_ok=True)


def clear():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()


def load_img(folder, fname, color=True):
    img = bpy.data.images.load(os.path.join(ACG, folder, fname))
    img.pack()
    if not color:
        img.colorspace_settings.name = "Non-Color"
    return img


def pbr(name, folder, repeats=1.0, tint=(1, 1, 1), rough_mul=1.0):
    """ambientCG color + normal + roughness. repeats is the UV scale."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*tint, 1)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (repeats, repeats, repeats)
    nt.links.new(coord.outputs["UV"], mapping.inputs["Vector"])

    def tex(fname, is_color):
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = load_img(folder, fname, is_color)
        nt.links.new(mapping.outputs["Vector"], node.inputs["Vector"])
        return node

    albedo = tex("color.jpg", True)
    if tint != (1, 1, 1):
        mix = nt.nodes.new("ShaderNodeMixRGB")
        mix.blend_type = "MULTIPLY"
        mix.inputs["Fac"].default_value = 1.0
        mix.inputs["Color2"].default_value = (*tint, 1)
        nt.links.new(albedo.outputs["Color"], mix.inputs["Color1"])
        nt.links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        nt.links.new(albedo.outputs["Color"], bsdf.inputs["Base Color"])
    normal = tex("normal.jpg", False)
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nmap.inputs["Strength"].default_value = 1.1
    nt.links.new(normal.outputs["Color"], nmap.inputs["Color"])
    nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    rough = tex("roughness.jpg", False)
    if abs(rough_mul - 1.0) > 0.01:
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = rough_mul
        nt.links.new(rough.outputs["Color"], mul.inputs[0])
        nt.links.new(mul.outputs["Value"], bsdf.inputs["Roughness"])
    else:
        nt.links.new(rough.outputs["Color"], bsdf.inputs["Roughness"])
    return m


def stripe_tex():
    img = bpy.data.images.new("stripe", 128, 32, alpha=True)
    px = [0.0] * (128 * 32 * 4)
    for y in range(32):
        for x in range(128):
            red = (x // 16) % 2 == 0
            i = (y * 128 + x) * 4
            px[i : i + 4] = (0.62, 0.12, 0.1, 1) if red else (0.93, 0.9, 0.82, 1)
    img.pixels.foreach_set(px)
    img.pack()
    return img


def blossom_tex():
    img = bpy.data.images.new("blossom", 64, 64, alpha=True)
    px = [0.0] * (64 * 64 * 4)
    for y in range(64):
        for x in range(64):
            d = math.sqrt((x - 32) ** 2 + (y - 32) ** 2) / 30.0
            a = max(0.0, 1.0 - d * d)
            i = (y * 64 + x) * 4
            px[i : i + 4] = (0.62, 0.32, 0.9, a * a)
    img.pixels.foreach_set(px)
    img.pack()
    return img


def flat(name, color, rough=0.5, emit=None, strength=0.0, alpha=1.0, tex=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    if alpha < 1 or tex is not None:
        m.blend_method = "BLEND"
        m.use_backface_culling = False
        if tex is not None:
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = tex
            m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            m.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
        else:
            bsdf.inputs["Alpha"].default_value = alpha
    return m


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def tile(obj, repeats):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.15, island_margin=0.0)
    bpy.ops.object.mode_set(mode="OBJECT")
    uv = obj.data.uv_layers.active
    if uv:
        for d in uv.data:
            d.uv[0] *= repeats
            d.uv[1] *= repeats
    obj.select_set(False)


def cube(name, loc, scale, mat, repeats=2.0):
    bpy.ops.mesh.primitive_cube_add(location=loc, scale=scale)
    ob = bpy.context.active_object
    ob.name = name
    assign(ob, mat)
    tile(ob, repeats)
    return ob


def cyl(name, loc, radius, depth, mat, verts=20, rot=(0, 0, 0), repeats=2.0):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot
    )
    ob = bpy.context.active_object
    ob.name = name
    assign(ob, mat)
    tile(ob, repeats)
    return ob


def join(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.select_set(False)
    return ob


def export(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_yup=True, export_apply=True, use_selection=False
    )
    print("wrote", path)


def crenels(parts, z, xs, mat, depth=0.9):
    for x in xs:
        parts.append(cube("merlon", (x, 0, z), (0.42, depth * 0.5, 0.38), mat, 1.5))


def build_wall(stone, moss, slate):
    clear()
    parts = [
        cube("body", (0, 0, 3.7), (4.0, 1.15, 3.7), stone, 3.0),
        cube("moss", (0, 0.15, 0.45), (4.1, 1.25, 0.45), moss, 2.0),
    ]
    crenels(parts, 7.7, [i * 1.45 - 2.9 for i in range(5)], slate, 2.2)
    join("wall_segment", parts)
    export("wall_segment")


def build_tower(stone, slate):
    clear()
    parts = [cyl("shaft", (0, 0, 5.2), 2.5, 10.4, stone, 24, repeats=3.0)]
    parts.append(cyl("lip", (0, 0, 10.6), 2.9, 0.35, slate, 24, repeats=2.0))
    for i in range(8):
        a = i * math.tau / 8
        parts.append(
            cube("merlon", (math.cos(a) * 2.3, math.sin(a) * 2.3, 11.15), (0.38, 0.38, 0.4), slate, 1.2)
        )
    join("wall_tower", parts)
    export("wall_tower")


def build_gate(stone, slate, wood):
    clear()
    parts = []
    for sx in (-5.4, 5.4):
        parts.append(cyl("pier", (sx, 0, 6.0), 2.5, 12.0, stone, 20, repeats=3.0))
        parts.append(cyl("cap", (sx, 0, 12.2), 2.9, 0.4, slate, 20, repeats=2.0))
    bpy.ops.mesh.primitive_cube_add(location=(0, 0, 8.4), scale=(3.4, 1.6, 2.2))
    lintel = bpy.context.active_object
    assign(lintel, stone)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=28, radius=2.9, depth=6.0, location=(0, 0, 6.2), rotation=(math.pi / 2, 0, 0)
    )
    cutter = bpy.context.active_object
    mod = lintel.modifiers.new("Arch", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = lintel
    bpy.ops.object.modifier_apply(modifier="Arch")
    bpy.data.objects.remove(cutter, do_unlink=True)
    tile(lintel, 2.5)
    parts.append(lintel)
    parts.append(cube("jamb_l", (-2.7, 0.3, 3.1), (0.16, 0.2, 3.1), wood, 2.0))
    parts.append(cube("jamb_r", (2.7, 0.3, 3.1), (0.16, 0.2, 3.1), wood, 2.0))
    parts.append(cube("head", (0, 0.3, 6.3), (2.8, 0.2, 0.16), wood, 2.0))
    join("gatehouse", parts)
    export("gatehouse")


def build_crystal(stone):
    clear()
    gem_m = flat("gem", (0.45, 0.22, 0.82), 0.15, (0.55, 0.28, 0.95), 1.1, 0.9)
    parts = [
        cube("plinth", (0, 0, 1.3), (0.85, 0.85, 1.3), stone, 1.5),
        cube("cap", (0, 0, 2.7), (1.0, 1.0, 0.12), stone, 1.0),
    ]
    for loc, sc in (
        ((0, 0, 4.3), (0.55, 0.55, 1.5)),
        ((0.38, 0.1, 3.6), (0.32, 0.32, 0.9)),
        ((-0.32, 0.18, 3.5), (0.28, 0.28, 0.85)),
        ((0.05, -0.36, 3.4), (0.26, 0.26, 0.7)),
    ):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.45, location=loc)
        ob = bpy.context.active_object
        ob.scale = sc
        assign(ob, gem_m)
        parts.append(ob)
    join("crystal_pylon", parts)
    export("crystal_pylon")


def build_fountain(stone):
    clear()
    water = flat("water", (0.25, 0.55, 0.58), 0.08, (0.15, 0.4, 0.45), 0.25)
    parts = []
    for rad, z, h in ((4.4, 0.7, 0.7), (2.7, 2.05, 0.55), (1.4, 3.15, 0.4)):
        parts.append(cyl("bowl", (0, 0, z), rad, h * 2, stone, 40, repeats=3.0))
        parts.append(cyl("lip", (0, 0, z + h), rad * 1.05, 0.14, stone, 40, repeats=2.0))
        parts.append(cyl("pool", (0, 0, z + h * 0.72), rad * 0.78, 0.08, water, 28))
    parts.append(cyl("jet", (0, 0, 4.0), 0.12, 0.55, water, 8))
    join("fountain", parts)
    export("fountain")


def build_stall(wood, stripe_img):
    clear()
    cloth = flat("awning", (0.7, 0.15, 0.12), 0.55, tex=stripe_img)
    parts = []
    for x in (-1.5, 1.5):
        for y in (-0.75, 0.75):
            parts.append(cube("post", (x, y, 1.2), (0.09, 0.09, 1.2), wood, 2.0))
    parts.append(cube("counter", (0, 0.2, 1.0), (1.5, 0.5, 0.08), wood, 2.0))
    for sign, tilt in ((-0.55, 0.45), (0.55, -0.45)):
        bpy.ops.mesh.primitive_cube_add(location=(0, sign, 2.55), scale=(1.7, 0.65, 0.035))
        ob = bpy.context.active_object
        ob.rotation_euler[0] = tilt
        assign(ob, cloth)
        parts.append(ob)
    join("stall_striped", parts)
    export("stall_striped")


def build_lantern(wood):
    clear()
    iron = flat("iron", (0.12, 0.1, 0.09), 0.35)
    glow = flat("glow", (1.0, 0.75, 0.4), 0.2, (1.0, 0.7, 0.3), 3.0)
    parts = [
        cyl("pole", (0, 0, 1.45), 0.07, 2.9, iron, 8),
        cube("head", (0, 0, 2.85), (0.18, 0.18, 0.24), iron, 1.0),
        cube("flame", (0, 0, 2.85), (0.09, 0.09, 0.12), glow, 1.0),
        cube("cap", (0, 0, 3.15), (0.22, 0.22, 0.05), iron, 1.0),
    ]
    join("lantern_post", parts)
    export("lantern_post")


def build_hedge():
    clear()
    leaf = flat("leaf", (0.18, 0.4, 0.14), 0.85)
    parts = []
    for x in (-0.8, 0.0, 0.8):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.6, location=(x, 0, 0.75))
        ob = bpy.context.active_object
        ob.scale = (1.0, 0.75, 0.9)
        assign(ob, leaf)
        parts.append(ob)
    join("hedge", parts)
    export("hedge")


def build_tree():
    clear()
    bark = pbr("bark", "Wood049", 2.0, (0.45, 0.32, 0.22))
    leaf = flat("canopy", (0.16, 0.38, 0.12), 0.8)
    parts = [cyl("trunk", (0, 0, 1.6), 0.28, 3.2, bark, 8, repeats=1.5)]
    for loc, sc in (((0, 0, 3.6), (1.7, 1.7, 1.2)), ((0.8, 0.2, 4.1), (1.2, 1.1, 0.9)), ((-0.7, -0.3, 3.9), (1.3, 1.1, 0.85))):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0, location=loc)
        ob = bpy.context.active_object
        ob.scale = sc
        assign(ob, leaf)
        parts.append(ob)
    join("town_tree", parts)
    export("town_tree")


def radial_cobble():
    w = 512
    img = bpy.data.images.new("radial_cobble", w, w, alpha=True)
    px = [0.0] * (w * w * 4)
    for y in range(w):
        fy = (y + 0.5) / w * 2.0 - 1.0
        for x in range(w):
            fx = (x + 0.5) / w * 2.0 - 1.0
            rad = math.sqrt(fx * fx + fy * fy)
            ang = math.atan2(fy, fx)
            if rad > 1.0:
                col = (0.62, 0.58, 0.5, 1.0)
            else:
                rings = 16.0
                segs = 12.0 + rad * 36.0
                fr = (rad * rings) % 1.0
                fa = ((ang / math.tau) * segs) % 1.0
                edge = fr < 0.07 or fa < 0.07
                n = int(rad * rings) * 5 + int(((ang / math.tau) % 1.0) * segs)
                shade = 0.78 + (n % 5) * 0.035
                col = (0.5, 0.46, 0.38, 1.0) if edge else (shade, shade * 0.96, shade * 0.86, 1.0)
            i = (y * w + x) * 4
            px[i : i + 4] = col
    img.pixels.foreach_set(px)
    img.pack()
    return img


def build_plaza(_mat):
    clear()
    mat = flat("plaza_stones", (0.75, 0.7, 0.6), 0.9, tex=radial_cobble())
    # flat() with tex hooks alpha. Force opaque by not using the tex alpha path.
    # Rebuild a simple opaque image material.
    m = bpy.data.materials.new("plaza_opaque")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9
    node = m.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = radial_cobble()
    m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    bpy.ops.mesh.primitive_circle_add(vertices=80, radius=22.0, fill_type="NGON", location=(0, 0, 0))
    ob = bpy.context.active_object
    assign(ob, m)
    mesh = ob.data
    if not mesh.uv_layers:
        mesh.uv_layers.new()
    uv = mesh.uv_layers.active.data
    for loop in mesh.loops:
        v = mesh.vertices[loop.vertex_index].co
        uv[loop.index].uv = ((v.x / 22.0 + 1.0) * 0.5, (v.y / 22.0 + 1.0) * 0.5)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    export("plaza_cobble")


def build_path(mat):
    clear()
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, 0))
    ob = bpy.context.active_object
    ob.scale = (9.0, 72.0, 1)
    assign(ob, mat)
    tile(ob, 1.0)
    # Plane UVs are 0-1; stretch so the long axis repeats.
    uv = ob.data.uv_layers.active.data
    for d in uv:
        d.uv[0] *= 4.0
        d.uv[1] *= 18.0
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    export("gate_path")


def build_association(stone, slate):
    clear()
    parts = [cube("nave", (0, 0, 7.0), (8.0, 14.0, 7.0), stone, 3.0)]
    for sx in (-7.2, 7.2):
        parts.append(cyl("spire", (sx, 10.0, 11.0), 2.2, 22.0, stone, 12, repeats=2.0))
        parts.append(cyl("cap", (sx, 10.0, 22.2), 2.5, 0.4, slate, 12))
    parts.append(cube("roof", (0, 0, 15.5), (8.4, 14.2, 0.5), slate, 2.0))
    parts.append(cube("steps", (0, 15.5, 0.4), (6.0, 2.0, 0.4), stone, 2.0))
    join("association", parts)
    export("association")


def build_flagon(wood, slate):
    clear()
    parts = [
        cube("body", (0, 0, 3.2), (4.2, 3.2, 3.2), wood, 2.5),
        cube("roof", (0, 0, 6.8), (4.8, 3.6, 0.35), slate, 2.0),
        cube("chimney", (2.4, -1.6, 8.0), (0.45, 0.45, 1.2), stone_cached, 1.5),
    ]
    join("flagon", parts)
    export("flagon")


def build_garden(stone):
    clear()
    parts = [cyl("ring", (0, 0, 0.7), 12.0, 1.4, stone, 40, repeats=4.0)]
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=10.6, depth=3.0, location=(0, 0, 0.7))
    cutter = bpy.context.active_object
    wall = parts[0]
    mod = wall.modifiers.new("Hole", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    bpy.context.view_layer.objects.active = wall
    bpy.ops.object.modifier_apply(modifier="Hole")
    bpy.data.objects.remove(cutter, do_unlink=True)
    parts.append(cyl("basin", (0, 0, 0.35), 1.6, 0.5, stone, 16, repeats=1.5))
    join("garden", parts)
    export("garden")


def build_blossom(img):
    clear()
    mat = flat("petal", (0.6, 0.3, 0.9), 0.4, (0.55, 0.25, 0.85), 0.8, tex=img)
    parts = []
    for rot in ((0, 0, 0), (0, 0, math.pi / 3), (math.pi / 2, 0, 0)):
        bpy.ops.mesh.primitive_plane_add(size=0.28, location=(0, 0, 0), rotation=rot)
        ob = bpy.context.active_object
        assign(ob, mat)
        parts.append(ob)
    join("blossom", parts)
    export("blossom")


def build_door(wood):
    clear()
    iron = flat("iron", (0.14, 0.12, 0.1), 0.4)
    glow = flat("glow", (1, 0.72, 0.35), 0.2, (1, 0.65, 0.3), 2.5)
    parts = [
        cube("left", (-0.85, 0, 1.5), (0.12, 0.14, 1.5), wood, 2.0),
        cube("right", (0.85, 0, 1.5), (0.12, 0.14, 1.5), wood, 2.0),
        cube("head", (0, 0, 3.05), (0.95, 0.14, 0.14), wood, 2.0),
        cube("sill", (0, 0, 0.08), (1.0, 0.2, 0.08), wood, 1.5),
        cube("lantern", (1.15, 0.2, 2.2), (0.1, 0.1, 0.14), iron, 1.0),
        cube("flame", (1.15, 0.2, 2.2), (0.05, 0.05, 0.07), glow, 1.0),
    ]
    join("door_frame", parts)
    export("door_frame")


def build_bed():
    clear()
    leaf = flat("bed", (0.25, 0.45, 0.18), 0.8)
    bloom = flat("bloom", (0.75, 0.35, 0.55), 0.5)
    parts = [cyl("soil", (0, 0, 0.08), 1.3, 0.16, leaf, 16)]
    for i in range(7):
        a = i * math.tau / 7
        bpy.ops.mesh.primitive_ico_sphere_add(
            subdivisions=1, radius=0.16, location=(math.cos(a) * 0.7, math.sin(a) * 0.7, 0.22)
        )
        ob = bpy.context.active_object
        assign(ob, bloom)
        parts.append(ob)
    join("flower_bed", parts)
    export("flower_bed")


def build_dome():
    clear()
    mat = flat("haze", (0.65, 0.45, 0.85), 0.3, (0.45, 0.28, 0.7), 0.35, 0.16)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=155.0, location=(0, 0, 0))
    ob = bpy.context.active_object
    assign(ob, mat)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in ob.data.vertices:
        v.select = v.co.z < 8.0
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    export("dome_haze")


def main():
    global stone_cached
    stone = pbr("fieldstone", "Rock030", 1.0)
    stone_cached = stone
    moss = pbr("moss", "Rock030", 1.0, (0.55, 0.75, 0.45))
    slate = pbr("slate", "Bricks076C", 1.0, (0.55, 0.52, 0.5))
    timber = pbr("timber", "Wood049", 1.0, (0.42, 0.28, 0.18))
    grey = pbr("grey_stone", "Rock030", 1.0, (0.85, 0.88, 0.9))
    road = pbr("flagstone", "PavingStones131", 1.0, (1.15, 1.12, 1.05))
    build_wall(stone, moss, slate)
    build_tower(stone, slate)
    build_gate(stone, slate, timber)
    build_crystal(stone)
    build_fountain(grey)
    build_stall(timber, stripe_tex())
    build_lantern(timber)
    build_hedge()
    build_tree()
    build_plaza(road)
    build_path(road)
    build_association(stone, slate)
    build_flagon(timber, slate)
    build_garden(stone)
    build_blossom(blossom_tex())
    build_door(timber)
    build_bed()
    build_dome()


if __name__ == "__main__":
    main()
