class_name SlagworksDress
extends RefCounted
## Act III look. Collision stays on the floor's boxes. These meshes are original
## geometry with CC0 ambientCG materials (Rock035, Lava004, Metal034, Wood049).
## The crucible is the painted bowl: rails, furnace, arena, lift, slag cast, door.

const DIR := "res://assets/original/slagworks/"
const SPAN_X := 210.0
const SPAN_Z := 157.5

static var _mats := {}
static var _meshes := {}


static func paint(nx: float, ny: float, y := 0.0) -> Vector3:
	return Vector3((nx - 0.5) * SPAN_X, y, (ny - 0.5) * SPAN_Z)


static func dress_kit(floor: SlagworksFloor) -> void:
	add_atmosphere(floor)
	_kit_bowl(floor)
	_kit_rails(floor)
	_kit_ore(floor)
	_kit_lights(floor)


static func build_crucible(floor: SlagworksFloor, arena: Node3D) -> void:
	var bowl := MeshInstance3D.new()
	bowl.name = "BowlShell"
	bowl.mesh = _bowl_mesh()
	bowl.material_override = mat_rock()
	arena.add_child(bowl)
	_bowl_collision(floor, arena)
	var furnace := paint(0.42, 0.25)
	var arena_c := paint(0.65, 0.30)
	var lift_at := paint(0.52, 0.47)
	var slag_at := paint(0.50, 0.75)
	var door_at := paint(0.50, 0.90)
	var entry := paint(0.17, 0.16)
	var plat := paint(0.35, 0.42)
	var to_arena := arena_c - furnace
	to_arena.y = 0.0
	var dir := to_arena.normalized()
	var pad_at := furnace + dir * 26.0 + Vector3(0, 3.0, 0)
	_stone_path(arena, [entry, paint(0.12, 0.28), paint(0.11, 0.46), paint(0.15, 0.64), paint(0.28, 0.74), paint(0.42, 0.80), paint(0.50, 0.84), door_at])
	_stone_path(arena, [paint(0.58, 0.80), paint(0.72, 0.70), paint(0.82, 0.55), paint(0.78, 0.40), arena_c + Vector3(0, 0, 16)])
	_stone_path(arena, [entry, paint(0.28, 0.18), furnace + Vector3(0, 0, 6), plat, lift_at, slag_at + Vector3(0, 0, -8)])
	_lava_run(floor, arena, [paint(0.16, 0.26), paint(0.14, 0.40), paint(0.18, 0.55), paint(0.24, 0.66)], 5.5)
	_lava_run(floor, arena, [paint(0.78, 0.36), paint(0.86, 0.48), paint(0.84, 0.62)], 5.5)
	_arena(floor, arena, arena_c)
	var anvil := floor._anvil(arena, dir)
	anvil.position = furnace
	anvil.scale = Vector3(2.6, 2.6, 2.6)
	floor._solid(arena, furnace + Vector3(0, 2.2, 0.4), Vector3(8.0, 4.4, 8.0), "FurnaceCore", "wall", true, false)
	var deck := floor._walk_box(arena, Vector3(pad_at.x, 2.8, pad_at.z), Vector3(5.0, 0.4, 5.0), "PadDeck", "gantry")
	deck.set_meta(&"deck_top", 3.0)
	floor._add_ramp(arena, Vector3(pad_at.x, 0, pad_at.z) - dir * 6.0, dir * 6.0)
	floor._pad(pad_at)
	floor._segment(arena, "GantryA", arena_c + Vector3(-12, 2.8, 0), Vector3(3.6, 0.4, 8.0), arena_c + Vector3(-18, 0, 0), Vector3(6, 0, 0))
	floor._segment(arena, "GantryB", arena_c + Vector3(12, 2.8, 0), Vector3(3.6, 0.4, 8.0), arena_c + Vector3(18, 0, 0), Vector3(-6, 0, 0))
	floor._segment(arena, "GantryC", arena_c + Vector3(0, 2.8, 12), Vector3(8.0, 0.4, 3.6), arena_c + Vector3(0, 0, 18), Vector3(0, 0, -6))
	floor._stairs("StairsUp", LabyrinthStairs.UP, entry + Vector3(0, 0, 1.2))
	floor._shrine(lift_at + Vector3(3.2, 0, 1.4))
	floor._place_boss(arena_c + Vector3(0, 0.1, 11))
	floor._slag_prop(arena, "MainLift", "lift", lift_at)
	floor._slag_cast(arena, slag_at)
	floor._slag_prop(arena, "SunkenDoor", "sunken", door_at)
	var rail := Node3D.new()
	rail.name = "RailProp"
	rail.position = paint(0.13, 0.42, 0.4)
	arena.add_child(rail)
	_rails_along(arena, [paint(0.14, 0.20), paint(0.11, 0.36), paint(0.12, 0.52), paint(0.18, 0.68), paint(0.36, 0.78)])
	_dress_entry(arena, entry)
	_pillars(arena, arena_c, 14.5)
	_scatter_rim(arena)
	_ore_field(arena)
	add_atmosphere(floor)
	_glow(arena, furnace + Vector3(0, 4.5, -2), 10.0, 32.0)
	_glow(arena, arena_c + Vector3(0, 2.0, 0), 7.0, 26.0)
	_glow(arena, paint(0.20, 0.48, 1.2), 5.0, 18.0)
	_glow(arena, paint(0.84, 0.50, 1.2), 5.0, 18.0)
	_glow(arena, door_at + Vector3(0, 2.2, 0), 3.0, 12.0)
	_glow(arena, lift_at + Vector3(0, 5.0, 0), 2.4, 14.0)
	var route: Array[Vector3] = []
	route.append(pad_at - dir * 3.0 + Vector3(0, -1.4, 0))
	route.append(pad_at - dir * 6.0 + Vector3(0, -2.95, 0))
	route.append(arena_c + Vector3(-14, 0.05, 0))
	route.append(arena_c + Vector3(0, 0.05, 14))
	route.append(arena_c + Vector3(14, 0.05, 0))
	route.append(lift_at + Vector3(0, 0.05, 0))
	route.append(slag_at + Vector3(0, 0.05, -8))
	route.append(door_at + Vector3(0, 0.05, -2))
	route.append(entry + Vector3(0, 0.05, 2))
	floor.nav_points = route


static func clothe(body: StaticBody3D, size: Vector3, kind: String, nm: String) -> void:
	if nm == "GreyRail" or nm == "FurnaceCore":
		return
	if nm.begins_with("Ramp") or nm.begins_with("Gantry") or nm == "PadDeck" or kind == "gantry":
		var iron := mesh_node("gantry.glb", mat_metal())
		iron.scale = Vector3(size.x / 4.0, maxf(size.y / 0.35, 0.35), size.z / 3.0)
		body.add_child(iron)
		return
	if nm.begins_with("Wall") or nm.begins_with("Lip"):
		_cliff_wall(body, size)
		return
	var slab := mesh_node("stone.glb", _stone_mat(size))
	slab.scale = Vector3(maxf(size.x, 0.4) / 4.0, 1.0, maxf(size.z, 0.4) / 4.0)
	slab.position.y = size.y * 0.5 - 0.2
	body.add_child(slab)


static func clothe_volume(area: Area3D, size: Vector3, kind: String) -> void:
	if kind == "shimmer":
		var heat := MeshInstance3D.new()
		heat.name = "Heat"
		heat.mesh = _sheet(size.x, size.z)
		heat.material_override = mat_shimmer()
		area.add_child(heat)
		return
	var skin := mesh_node("lava.glb", mat_lava())
	skin.name = "LavaVisual"
	skin.scale = Vector3(maxf(size.x, 0.4) / 4.0, 1.0, maxf(size.z, 0.4) / 4.0)
	skin.position.y = size.y * 0.42
	area.add_child(skin)
	area.set_meta(&"visual_base_scale_z", skin.scale.z)


static func attach_furnace(anvil: Node3D) -> void:
	var body := mesh_node("furnace.glb", mat_rock())
	body.name = "FurnaceMesh"
	anvil.add_child(body)
	var mouth := mesh_node("lava.glb", mat_lava())
	mouth.name = "MouthGlow"
	mouth.position = Vector3(0, 1.55, -3.05)
	mouth.scale = Vector3(0.42, 0.7, 0.18)
	anvil.add_child(mouth)


static func attach_cast(cast: Node3D) -> void:
	var pit := mesh_node("slag_cast.glb", mat_rock())
	pit.name = "CastMesh"
	pit.scale = Vector3(2.4, 1.6, 2.4)
	cast.add_child(pit)
	var mark := MeshInstance3D.new()
	mark.name = "Negative"
	mark.mesh = _figure_mark()
	mark.position = Vector3(0, 0.05, 0)
	mark.scale = Vector3(2.4, 1.0, 2.4)
	var cooled := mat_lava().duplicate() as StandardMaterial3D
	cooled.albedo_color = Color(0.05, 0.025, 0.02)
	cooled.emission_energy_multiplier = 0.06
	mark.material_override = cooled
	cast.add_child(mark)


static func attach_role(prop: Node3D, role: String) -> void:
	if role == "lift":
		var tower := mesh_node("lift.glb", mat_rock())
		prop.add_child(tower)
		var links := mesh_node("chain.glb", mat_metal())
		links.position = Vector3(0.15, 7.6, 0.15)
		prop.add_child(links)
		return
	var gate := mesh_node("arch.glb", mat_rock())
	prop.add_child(gate)
	var leaf := mesh_node("door.glb", mat_wood())
	leaf.position = Vector3(0, 0, 0.15)
	prop.add_child(leaf)


static func attach_cart(cart: Node3D) -> void:
	if cart.get_node_or_null("CartMesh"):
		return
	var body := mesh_node("cart.glb", mat_metal())
	body.name = "CartMesh"
	body.position.y = -0.15
	cart.add_child(body)


static func add_atmosphere(floor: Node3D) -> void:
	if floor.get_node_or_null("MineAir"):
		return
	var we := WorldEnvironment.new()
	we.name = "MineAir"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.035, 0.02, 0.015)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.38, 0.2)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.12
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.0045
	e.fog_light_color = Color(0.42, 0.14, 0.05)
	e.fog_aerial_perspective = 0.25
	we.environment = e
	floor.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -36, 0)
	sun.light_color = Color(1.0, 0.74, 0.5)
	sun.light_energy = 0.42
	sun.shadow_enabled = false
	floor.add_child(sun)


static func mat_rock() -> StandardMaterial3D:
	return _mat("rock", "res://assets/ambientcg/Rock035/", Color(1.05, 0.78, 0.58), 0.0, false)


static func mat_lava() -> StandardMaterial3D:
	if _mats.has("lava"):
		return _mats["lava"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/ambientcg/Lava004/color.jpg")
	m.albedo_color = Color(1.0, 0.42, 0.12)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/ambientcg/Lava004/normal.jpg")
	m.roughness_texture = load("res://assets/ambientcg/Lava004/roughness.jpg")
	m.emission_enabled = true
	m.emission = Color(1.0, 0.32, 0.05)
	m.emission_energy_multiplier = 0.85
	m.uv1_scale = Vector3(1, 1, 1)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["lava"] = m
	return m


static func mat_metal() -> StandardMaterial3D:
	if _mats.has("metal"):
		return _mats["metal"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/ambientcg/Metal034/color.jpg")
	m.albedo_color = Color(0.16, 0.12, 0.1)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/ambientcg/Metal034/normal.jpg")
	m.roughness_texture = load("res://assets/ambientcg/Metal034/roughness.jpg")
	m.metallic = 0.65
	m.metallic_texture = load("res://assets/ambientcg/Metal034/metalness.jpg")
	m.uv1_scale = Vector3(2, 2, 2)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["metal"] = m
	return m


static func mat_wood() -> StandardMaterial3D:
	return _mat("wood", "res://assets/ambientcg/Wood049/", Color(0.55, 0.32, 0.18), 0.0, false)


static func mat_shimmer() -> StandardMaterial3D:
	if _mats.has("shimmer"):
		return _mats["shimmer"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.42, 0.12, 0.22)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.05)
	m.emission_energy_multiplier = 1.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["shimmer"] = m
	return m


static func mesh_node(file: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = source_mesh(DIR + file)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func source_mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var packed := load(path) as PackedScene
	var node := packed.instantiate()
	var mesh: Mesh = null
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		mesh = (node as MeshInstance3D).mesh
	else:
		for child in node.find_children("*", "MeshInstance3D", true, false):
			mesh = (child as MeshInstance3D).mesh
			if mesh:
				break
	node.free()
	_meshes[path] = mesh
	return mesh


static func _mat(key: String, dir: String, tint: Color, metallic: float, emissive: bool) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "color.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.jpg")
	m.roughness_texture = load(dir + "roughness.jpg")
	m.metallic = metallic
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emissive:
		m.emission_enabled = true
	_mats[key] = m
	return m


static func _stone_mat(size: Vector3) -> StandardMaterial3D:
	var m := mat_rock().duplicate() as StandardMaterial3D
	m.uv1_scale = Vector3(maxf(size.x, 1.0) / 4.0, maxf(size.z, 1.0) / 4.0, 1.0)
	m.albedo_color = Color(1.15, 0.9, 0.7)
	return m


static func _cliff_wall(body: StaticBody3D, size: Vector3) -> void:
	var along_x := size.x >= size.z
	var length := size.x if along_x else size.z
	var height := maxf(size.y, 0.5)
	var count := maxi(1, int(round(length / 4.0)))
	var seg := length / float(count)
	for i in count:
		var mi := mesh_node("cliff.glb", mat_rock())
		var along := -length * 0.5 + seg * (float(i) + 0.5)
		mi.position = Vector3(along, -height * 0.5, 0) if along_x else Vector3(0, -height * 0.5, along)
		mi.scale = Vector3(seg / 4.0, height / 6.0, 1.0)
		if not along_x:
			mi.rotate_y(PI * 0.5)
		body.add_child(mi)


static func _bowl_collision(floor: SlagworksFloor, arena: Node3D) -> void:
	var step := 18.0
	var hx := SPAN_X * 0.46
	var hz := SPAN_Z * 0.46
	var x := -hx
	while x <= hx:
		var z := -hz
		while z <= hz:
			var nx := x / hx
			var nz := z / hz
			if nx * nx + nz * nz <= 1.0:
				floor._walk_box(arena, Vector3(x, -0.25, z), Vector3(step + 0.6, 0.5, step + 0.6), "Bowl", "boss", false)
			z += step
		x += step


static func _bowl_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 56
	var rows := 42
	for j in rows + 1:
		for i in cols + 1:
			var u := float(i) / float(cols)
			var v := float(j) / float(rows)
			var x := (u - 0.5) * SPAN_X
			var z := (v - 0.5) * SPAN_Z
			var ex := x / (SPAN_X * 0.46)
			var ez := z / (SPAN_Z * 0.46)
			var radial := sqrt(ex * ex + ez * ez)
			var n := sin(x * 0.11) * cos(z * 0.13) + 0.45 * sin(x * 0.31 + z * 0.27)
			var y := n * 0.28
			if radial > 0.8:
				var w := clampf((radial - 0.8) / 0.24, 0.0, 1.35)
				y += pow(w, 1.25) * 13.5 + n * w * 1.4
			st.set_uv(Vector2(u * 10.0, v * 7.5))
			st.add_vertex(Vector3(x, y, z))
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var b := a + 1
			var c := a + cols + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	st.generate_normals()
	return st.commit()


static func _stone_path(parent: Node3D, pts: Array) -> void:
	if pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := 2.6
	var verts: Array[Vector3] = []
	for i in pts.size():
		var p: Vector3 = pts[i]
		var ahead: Vector3 = (pts[i + 1] if i + 1 < pts.size() else pts[i]) - (pts[i - 1] if i > 0 else pts[i])
		ahead.y = 0.0
		if ahead.length() < 0.01:
			ahead = Vector3(1, 0, 0)
		var side := Vector3(-ahead.z, 0, ahead.x).normalized() * half
		verts.append(p + side + Vector3(0, 0.08, 0))
		verts.append(p - side + Vector3(0, 0.08, 0))
	for v in verts:
		st.set_uv(Vector2(v.x * 0.08, v.z * 0.08))
		st.add_vertex(v)
	for i in pts.size() - 1:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 3)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "StonePath"
	mi.mesh = st.commit()
	var mat := mat_rock().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.95, 0.78, 0.58)
	mat.uv1_scale = Vector3(1, 1, 1)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _lava_run(floor: SlagworksFloor, arena: Node3D, pts: Array, width: float) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var delta := b - a
		delta.y = 0.0
		var at := (a + b) * 0.5
		at.y = 0.4
		var area := floor._volume(arena, at, Vector3(width, 1.0, delta.length() + 0.6), "lava")
		area.basis = Basis(Vector3(delta.z, 0, -delta.x).normalized(), Vector3.UP, delta.normalized()).orthonormalized()
		var skin := area.get_node_or_null("LavaVisual")
		if skin:
			skin.visible = false
	_lava_ribbon(arena, pts, width)


static func _lava_ribbon(parent: Node3D, pts: Array, width: float) -> void:
	if pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width * 0.5
	for i in pts.size():
		var p: Vector3 = pts[i]
		var step: Vector3 = (pts[i + 1] if i + 1 < pts.size() else pts[i]) - (pts[i - 1] if i > 0 else pts[i])
		step.y = 0.0
		if step.length() < 0.01:
			step = Vector3(0, 0, 1)
		var side := Vector3(-step.z, 0, step.x).normalized() * half
		for v in [p + side, p - side]:
			st.set_uv(Vector2(v.x * 0.12, v.z * 0.12))
			st.add_vertex(v + Vector3(0, 0.12, 0))
	for i in pts.size() - 1:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 3)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "LavaRibbon"
	mi.mesh = st.commit()
	mi.material_override = mat_lava()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _figure_mark() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cursor: Array = [0]
	_fan(st, cursor, Vector3(0, 0.06, -1.7), 0.55, 0.62)
	_fan(st, cursor, Vector3(0, 0.06, -0.3), 0.78, 1.15)
	_lozenge(st, cursor, Vector3(-0.45, 0.06, -0.7), Vector3(-1.7, 0.06, -0.15), 0.26)
	_lozenge(st, cursor, Vector3(0.45, 0.06, -0.7), Vector3(1.7, 0.06, -0.15), 0.26)
	_lozenge(st, cursor, Vector3(-0.28, 0.06, 0.55), Vector3(-0.42, 0.06, 1.9), 0.28)
	_lozenge(st, cursor, Vector3(0.28, 0.06, 0.55), Vector3(0.42, 0.06, 1.9), 0.28)
	st.generate_normals()
	return st.commit()


static func _fan(st: SurfaceTool, cursor: Array, c: Vector3, rx: float, rz: float) -> void:
	var base: int = cursor[0]
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(c)
	var segs := 14
	for i in segs:
		var a := TAU * float(i) / float(segs)
		st.set_uv(Vector2(cos(a), sin(a)))
		st.add_vertex(c + Vector3(cos(a) * rx, 0, sin(a) * rz))
	cursor[0] = base + 1 + segs
	for i in segs:
		st.add_index(base)
		st.add_index(base + 1 + i)
		st.add_index(base + 1 + (i + 1) % segs)


static func _lozenge(st: SurfaceTool, cursor: Array, a: Vector3, b: Vector3, r: float) -> void:
	var dir := b - a
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var side := Vector3(-dir.z, 0, dir.x).normalized() * r
	var base: int = cursor[0]
	for p in [a + side, a - side, b - side, b + side]:
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)
	cursor[0] = base + 4
	st.add_index(base)
	st.add_index(base + 1)
	st.add_index(base + 2)
	st.add_index(base)
	st.add_index(base + 2)
	st.add_index(base + 3)


static func _arena(floor: SlagworksFloor, arena: Node3D, centre: Vector3) -> void:
	var ring := MeshInstance3D.new()
	ring.name = "ArenaRing"
	ring.mesh = _ring_mesh(16.5, 6.2)
	ring.position = centre
	ring.material_override = _stone_mat(Vector3(16, 1, 16))
	arena.add_child(ring)
	var pool := floor._volume(arena, centre + Vector3(0, 0.35, 0), Vector3(10.5, 1.0, 10.5), "lava")
	pool.name = "ArenaPool"
	floor._lava_strip(arena, "LavaStrip0", centre + Vector3(0, 0.55, -7.5))
	floor._lava_strip(arena, "LavaStrip1", centre + Vector3(0, 0.55, 7.5))


static func _ring_mesh(outer: float, inner: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 48
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var heights := [0.15, 0.55, 1.05]
		var radii := [outer, (outer + inner) * 0.5 + 1.2, inner + 0.4]
		for s in 2:
			var r0: float = radii[s]
			var r1: float = radii[s + 1]
			var y: float = heights[s]
			var y2: float = heights[s + 1]
			var p0 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
			var p1 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
			var p2 := Vector3(cos(a0) * r1, y2, sin(a0) * r1)
			var p3 := Vector3(cos(a1) * r1, y2, sin(a1) * r1)
			for p in [p0, p1, p3, p0, p3, p2]:
				st.set_uv(Vector2(p.x * 0.08, p.z * 0.08))
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()


static func _rails_along(parent: Node3D, pts: Array) -> void:
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var delta := b - a
		delta.y = 0.0
		if delta.length() < 0.4:
			continue
		var mi := mesh_node("rail.glb", mat_metal())
		mi.name = "Track"
		mi.position = (a + b) * 0.5
		mi.position.y = 0.05
		var along := delta.normalized()
		mi.basis = Basis(along, Vector3.UP, along.cross(Vector3.UP)).orthonormalized()
		mi.scale = Vector3(delta.length() / 4.0, 1.0, 1.0)
		parent.add_child(mi)


static func _dress_entry(arena: Node3D, entry: Vector3) -> void:
	var gate := mesh_node("arch.glb", mat_rock())
	gate.position = entry
	gate.basis = Basis.looking_at(paint(0.5, 0.5) - entry, Vector3.UP)
	arena.add_child(gate)
	var leaf := mesh_node("door.glb", mat_wood())
	leaf.position = entry + Vector3(0, 0, 0.4)
	leaf.basis = gate.basis
	arena.add_child(leaf)


static func _pillars(arena: Node3D, centre: Vector3, radius: float) -> void:
	for i in 10:
		var a := TAU * float(i) / 10.0
		var mi := mesh_node("pillar.glb", mat_rock())
		mi.position = centre + Vector3(cos(a) * radius, 0, sin(a) * radius)
		arena.add_child(mi)


static func _scatter_rim(arena: Node3D) -> void:
	var xforms: Array[Transform3D] = []
	for i in 36:
		var a := TAU * float(i) / 36.0 + sin(float(i) * 2.3) * 0.08
		var t := 0.9 + 0.06 * sin(float(i) * 1.7)
		var p := Vector3(cos(a) * SPAN_X * 0.42 * t, 0.0, sin(a) * SPAN_Z * 0.42 * t)
		var s := 1.4 + float(i % 5) * 0.35
		var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 0.8, s)), p)
		xf.basis = xf.basis.rotated(Vector3.UP, a)
		xforms.append(xf)
	_multi(arena, "boulder.glb", mat_rock(), xforms)


static func _ore_field(arena: Node3D) -> void:
	var spots: Array[Vector3] = [
		paint(0.34, 0.14, 1.2),
		paint(0.48, 0.12, 1.6),
		paint(0.62, 0.15, 1.1),
		paint(0.88, 0.46, 1.4),
		paint(0.16, 0.58, 1.3),
	]
	for at in spots:
		var mi := mesh_node("ore.glb", mat_lava())
		mi.position = at
		mi.scale = Vector3(2.2, 2.2, 2.2)
		arena.add_child(mi)
	var chain := mesh_node("chain.glb", mat_metal())
	chain.position = paint(0.86, 0.48, 4.5)
	chain.scale = Vector3(2.4, 2.4, 2.4)
	arena.add_child(chain)


static func _multi(parent: Node3D, file: String, mat: Material, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = source_mesh(DIR + file)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)


static func _kit_bowl(floor: SlagworksFloor) -> void:
	var min_x := 1e9
	var max_x := -1e9
	var min_z := 1e9
	var max_z := -1e9
	for room in floor.rooms:
		var sz: Vector2 = room.get_meta(&"size", Vector2(12, 12))
		min_x = minf(min_x, room.position.x - sz.x * 0.5)
		max_x = maxf(max_x, room.position.x + sz.x * 0.5)
		min_z = minf(min_z, room.position.z - sz.y * 0.5)
		max_z = maxf(max_z, room.position.z + sz.y * 0.5)
	var centre := Vector3((min_x + max_x) * 0.5, 0, (min_z + max_z) * 0.5)
	var rx := (max_x - min_x) * 0.5 + 10.0
	var rz := (max_z - min_z) * 0.5 + 10.0
	var disc := MeshInstance3D.new()
	disc.name = "CavernFloor"
	disc.mesh = _disc(rx, rz)
	disc.position = centre + Vector3(0, -0.45, 0)
	disc.material_override = mat_rock()
	floor.add_child(disc)
	var xforms: Array[Transform3D] = []
	var count := 48
	for i in count:
		var a := TAU * float(i) / float(count)
		var p := centre + Vector3(cos(a) * rx, 0, sin(a) * rz)
		var xf := Transform3D(Basis(Vector3.UP, a + PI), p)
		xf.basis = xf.basis.scaled(Vector3(1.35, 1.15, 1.0))
		xforms.append(xf)
	_multi(floor, "cliff.glb", mat_rock(), xforms)


static func _disc(rx: float, rz: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 40
	st.set_uv(Vector2(0.5, 0.5))
	st.add_vertex(Vector3.ZERO)
	for i in segs:
		var a := TAU * float(i) / float(segs)
		st.set_uv(Vector2(cos(a) * 0.5 + 0.5, sin(a) * 0.5 + 0.5))
		st.add_vertex(Vector3(cos(a) * rx, 0, sin(a) * rz))
	for i in segs:
		st.add_index(0)
		st.add_index(1 + i)
		st.add_index(1 + (i + 1) % segs)
	st.generate_normals()
	return st.commit()


static func _kit_rails(floor: SlagworksFloor) -> void:
	for n in floor.find_children("*", "Node3D", true, false):
		if String(n.name) != "Rail" or not n.has_meta(&"loop"):
			continue
		var pts: Array = n.get_meta(&"loop")
		var room := n.get_parent() as Node3D
		var local: Array = []
		for p in pts:
			local.append((p as Vector3) - room.position)
		_rails_along(n, local)


static func _kit_ore(floor: SlagworksFloor) -> void:
	var placed := 0
	for n in floor.find_children("*", "StaticBody3D", true, false):
		if not String(n.name).begins_with("Wall") or placed >= 4:
			continue
		var ore := mesh_node("ore.glb", mat_lava())
		ore.position = Vector3(0, 1.4, 0.4)
		ore.scale = Vector3(1.4, 1.4, 1.4)
		n.add_child(ore)
		placed += 1


static func _kit_lights(floor: SlagworksFloor) -> void:
	var lights := 0
	for n in floor.find_children("*", "Area3D", true, false):
		if String(n.get_meta(&"kind", "")) != "lava" or lights >= 5:
			continue
		_glow(floor, (n as Node3D).position + Vector3(0, 2.2, 0), 4.5, 14.0)
		lights += 1
	var anvil := floor.find_child("FurnaceAnvil", true, false) as Node3D
	if anvil:
		_glow(anvil, Vector3(0, 3.2, -1.5), 6.0, 16.0)


static func _glow(parent: Node3D, at: Vector3, energy: float, radius: float) -> void:
	var light := OmniLight3D.new()
	light.position = at
	light.light_color = Color(1.0, 0.45, 0.12)
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	parent.add_child(light)


static func _sheet(w: float, d: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := w * 0.5
	var hz := d * 0.5
	for p in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)
	st.generate_normals()
	return st.commit()
