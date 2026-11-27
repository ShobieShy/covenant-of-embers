class_name SpireKit
extends RefCounted
## Act V tiles. Shelves, the hanging tower, crystal bridges and the false sky.
## Walk collision stays on SpireFloor. These meshes do not block.

const DIR := "res://assets/spire/meshes/"
const ROCK := "res://assets/kenney/fantasy-town-kit/rock-large.glb"
const LAYOUT := "res://data/labyrinth/spire.toml"

static var _cache := {}


static func layout() -> Dictionary:
	var doc := LevelToml.load_file(LAYOUT)
	return doc if not doc.has("error") else {}


static func piece(id: String) -> Node3D:
	if not _cache.has(id):
		var path := DIR + id + ".glb"
		_cache[id] = load(path) if ResourceLoader.exists(path) else null
	var ps: PackedScene = _cache[id]
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = id
	return n


static func paint(root: Node, mat: Material, glass: Material = null) -> void:
	var meshes: Array[Node] = []
	if root is MeshInstance3D:
		meshes.append(root)
	meshes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for n in meshes:
		var mi := n as MeshInstance3D
		var glass_named := glass != null and String(mi.name).to_lower().contains("glass")
		mi.material_override = glass if glass_named else mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func dress(floor: Node3D, floor_no: int) -> void:
	var doc := layout()
	if doc.is_empty():
		return
	_atmosphere(floor)
	_sky(floor, doc)
	_wall(floor, doc)
	_tower(floor, doc)
	for pad in doc.get("pad", []):
		var body := floor.get_node_or_null(String(pad["name"])) as StaticBody3D
		if body:
			_on_pad(body, pad, floor_no)
	for ledge in doc.get("ledge", []):
		_ledge(floor, ledge)
	for br in doc.get("bridge", []):
		_bridge_mesh(floor, doc, br)
	_column(floor, doc)
	if floor_no == 21:
		_gust(floor)
	var lit := floor.get_node_or_null("LitPath") as Node3D
	if lit:
		_span(lit, Vector3(-1.2, 0.2, 0), Vector3(1.2, 0.2, 6), 1.4, "violet")


static func dress_arena(anchor: Node3D, host: Node3D) -> void:
	var low := host.get_node_or_null("Low") as Node3D
	if low == null:
		return
	var centre := low.position + Vector3(0, 0.5, 0)
	for i in 8:
		var ang := float(i) / 8.0 * TAU
		var kind := "blue" if i % 2 == 0 else "violet"
		_gem(anchor, centre + Vector3(cos(ang) * 8.5, 0, sin(ang) * 6.5), kind, 1.1 + float(i % 3) * 0.25)
	var glyph := MeshInstance3D.new()
	glyph.name = "Glyph"
	glyph.mesh = _ring_mesh(5.5, 6.3, 28)
	glyph.position = centre + Vector3(0, 0.15, 0)
	glyph.material_override = SpireTheme.ribbon("violet")
	anchor.add_child(glyph)


static func hide_stair_box(stairs: Node) -> void:
	for c in stairs.get_children():
		if c is CSGShape3D:
			(c as CSGShape3D).visible = false
	var pad := piece("crystal_cluster")
	if pad == null:
		return
	pad.name = "StairMark"
	pad.position = Vector3(0, 0.15, 0)
	pad.scale = Vector3(0.55, 0.4, 0.55)
	paint(pad, SpireTheme.gem("violet"))
	stairs.add_child(pad)


static func _atmosphere(floor: Node3D) -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = SpireTheme.environment()
	floor.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58, 28, 0)
	sun.light_color = Color(0.62, 0.58, 0.82)
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	floor.add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "VoidFill"
	fill.position = Vector3(0, 24, -8)
	fill.light_color = Color(0.45, 0.35, 0.75)
	fill.light_energy = 1.4
	fill.omni_range = 70.0
	fill.shadow_enabled = false
	floor.add_child(fill)


static func _sky(floor: Node3D, doc: Dictionary) -> void:
	var chasm: Dictionary = doc["void"]
	var disc := piece("sky_disc")
	if disc:
		disc.name = "FalseSky"
		var r := float(chasm["sky_radius"])
		var lip := float(chasm["sky_y"]) - 2.0
		disc.position = Vector3(0, lip, 0)
		disc.scale = Vector3(r, r * 0.42, r)
		paint(disc, SpireTheme.sky())
		floor.add_child(disc)
	var ring := piece("sky_ring")
	if ring:
		ring.name = "SkyRing"
		var radius := float(chasm["radius"])
		ring.position = Vector3(0, float(chasm["sky_y"]) - 2.0, 0)
		ring.scale = Vector3(radius, 1, radius)
		paint(ring, SpireTheme.tower_stone())
		floor.add_child(ring)


static func _wall(floor: Node3D, doc: Dictionary) -> void:
	var chasm: Dictionary = doc["void"]
	var wall := piece("void_wall")
	if wall == null:
		return
	wall.name = "VoidWall"
	var radius := float(chasm["radius"])
	var h := float(chasm["wall_height"])
	wall.position = Vector3(0, float(chasm["wall_bottom"]), 0)
	wall.scale = Vector3(radius, h, radius)
	paint(wall, SpireTheme.wall())
	floor.add_child(wall)


static func _tower(floor: Node3D, doc: Dictionary) -> void:
	var tower := piece("inverted_tower")
	if tower == null:
		return
	var spec: Dictionary = doc["tower"]
	tower.name = "InvertedTower"
	tower.position = LevelToml.vec3(spec["tip"])
	var fit := float(spec["height"]) / 32.0
	tower.scale = Vector3(fit, fit, fit)
	paint(tower, SpireTheme.tower_stone(), SpireTheme.glass())
	floor.add_child(tower)
	var lamp := OmniLight3D.new()
	lamp.name = "TipLight"
	lamp.position = tower.position + Vector3(0, 1.2, 0)
	lamp.light_color = Color(0.75, 0.6, 1.0)
	lamp.light_energy = 6.0
	lamp.omni_range = 22.0
	lamp.shadow_enabled = false
	floor.add_child(lamp)


static func _on_pad(body: StaticBody3D, pad: Dictionary, floor_no: int) -> void:
	var shelf := piece(String(pad["mesh"]))
	if shelf:
		shelf.name = "Shelf"
		var size := LevelToml.vec3(pad["size"])
		shelf.position = Vector3(0, size.y * 0.5, 0)
		shelf.scale = LevelToml.vec3(pad["scale"])
		paint(shelf, SpireTheme.rock())
		body.add_child(shelf)
	_scatter(body, pad, floor_no)


static func _ledge(floor: Node3D, ledge: Dictionary) -> void:
	var n := piece(String(ledge["mesh"]))
	if n == null:
		return
	n.name = "Ledge"
	n.position = LevelToml.vec3(ledge["at"])
	n.scale = LevelToml.vec3(ledge["scale"])
	paint(n, SpireTheme.rock())
	floor.add_child(n)
	_gems_at(n, ledge, Vector3.ZERO, 1.0)


static func _scatter(body: Node3D, pad: Dictionary, floor_no: int) -> void:
	var size := LevelToml.vec3(pad["size"])
	var y := size.y * 0.5
	_gems_at(body, pad, Vector3(0, y, 0), 1.0 + float(floor_no % 3) * 0.15)
	if bool(pad.get("nest", false)):
		var nest := piece("nest")
		if nest:
			nest.name = "HarpyNest"
			nest.position = Vector3(size.x * 0.18, y, size.z * 0.12)
			nest.scale = Vector3(3.2, 2.4, 3.2)
			paint(nest, SpireTheme.wood())
			body.add_child(nest)
	_boulders(body, size, y)


static func _gems_at(parent: Node3D, spec: Dictionary, origin: Vector3, boost: float) -> void:
	var gems: Array = spec.get("gems", [])
	var i := 0
	for kind in gems:
		var ox := -1.6 if i % 2 == 0 else 1.8
		var oz := 1.1 if i < 2 else -1.4
		_gem(parent, origin + Vector3(ox * boost, 0, oz), String(kind), 0.9 + float(i) * 0.2)
		i += 1


static func _gem(parent: Node3D, at: Vector3, kind: String, scale: float) -> void:
	var id := "crystal_cluster_blue" if kind == "blue" else "crystal_cluster"
	var n := piece(id)
	if n == null:
		return
	n.name = "Crystals"
	n.position = at
	n.scale = Vector3(scale, scale, scale)
	paint(n, SpireTheme.gem(kind))
	parent.add_child(n)
	var lamp := OmniLight3D.new()
	lamp.position = at + Vector3(0, 1.4 * scale, 0)
	lamp.light_color = Color(0.55, 0.75, 1.0) if kind == "blue" else Color(0.7, 0.4, 1.0)
	lamp.light_energy = 1.6
	lamp.omni_range = 7.0
	lamp.shadow_enabled = false
	parent.add_child(lamp)


static func _boulders(body: Node3D, size: Vector3, y: float) -> void:
	if not ResourceLoader.exists(ROCK):
		return
	var ps := load(ROCK) as PackedScene
	if ps == null:
		return
	var spots := [Vector3(-size.x * 0.32, y, size.z * 0.2), Vector3(size.x * 0.28, y, -size.z * 0.22)]
	var i := 0
	for at in spots:
		var rock := ps.instantiate() as Node3D
		if rock == null:
			continue
		rock.name = "Boulder"
		rock.position = at
		rock.rotation.y = float(i) * 1.7
		rock.scale = Vector3(2.4, 1.8, 2.4)
		paint(rock, SpireTheme.rock())
		body.add_child(rock)
		i += 1


static func _bridge_mesh(floor: Node3D, doc: Dictionary, br: Dictionary) -> void:
	var a := _pad(doc, String(br["a"]))
	var b := _pad(doc, String(br["b"]))
	if a.is_empty() or b.is_empty():
		return
	var fr := _lip(a, LevelToml.vec3(b["at"]))
	var to := _lip(b, LevelToml.vec3(a["at"]))
	var hue := String(br["hue"])
	var lift := Vector3(0, 0.18, 0)
	_span(floor, fr + lift, to + lift, 0.55, hue)
	_span(floor, fr + lift + Vector3(0, 0.05, 0), to + lift + Vector3(0, 0.05, 0), 0.16, hue)


static func _span(parent: Node3D, fr: Vector3, to: Vector3, width: float, hue: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "LightBridge"
	mi.mesh = _ribbon(fr, to, width)
	mi.material_override = SpireTheme.ribbon(hue)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _column(floor: Node3D, doc: Dictionary) -> void:
	var mid := _pad(doc, "Mid")
	if mid.is_empty():
		return
	var tip := LevelToml.vec3(doc["tower"]["tip"])
	var land := _top(mid)
	var beam := piece("light_column")
	if beam == null:
		return
	beam.name = "LightColumn"
	var h := maxf(tip.y - land.y, 0.5)
	beam.position = Vector3(tip.x, land.y, tip.z)
	beam.scale = Vector3(1.4, h, 1.4)
	paint(beam, SpireTheme.column())
	floor.add_child(beam)


static func _gust(floor: Node3D) -> void:
	var wind := floor.get_node_or_null("Wind") as Node3D
	if wind == null:
		return
	var streaks := piece("wind_streak")
	if streaks == null:
		return
	var mesh := _first_mesh(streaks)
	if mesh == null:
		return
	var p := GPUParticles3D.new()
	p.name = "Gust"
	p.amount = 40
	p.lifetime = 1.4
	p.visibility_aabb = AABB(Vector3(-24, -3, -16), Vector3(48, 8, 32))
	p.draw_pass_1 = mesh
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(16, 1.5, 8)
	mat.direction = Vector3(1, 0, 0.1)
	mat.spread = 12.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 18.0
	mat.gravity = Vector3.ZERO
	mat.color = Color(0.7, 0.85, 1.0, 0.45)
	p.process_material = mat
	wind.add_child(p)


static func _pad(doc: Dictionary, name: String) -> Dictionary:
	for pad in doc.get("pad", []):
		if String(pad["name"]) == name:
			return pad
	return {}


static func _top(pad: Dictionary) -> Vector3:
	var at := LevelToml.vec3(pad["at"])
	var size := LevelToml.vec3(pad["size"])
	return at + Vector3(0, size.y * 0.5, 0)


static func _lip(pad: Dictionary, toward: Vector3) -> Vector3:
	var at := LevelToml.vec3(pad["at"])
	var size := LevelToml.vec3(pad["size"])
	var top := _top(pad)
	var flat := Vector3(toward.x - at.x, 0, toward.z - at.z)
	if flat.length() < 0.05:
		return top
	var n := flat.normalized()
	var tx := INF
	var tz := INF
	if absf(n.x) > 0.001:
		tx = (size.x * 0.5) / absf(n.x)
	if absf(n.z) > 0.001:
		tz = (size.z * 0.5) / absf(n.z)
	return top + n * maxf(minf(tx, tz) - 0.7, 0.4)


static func _ribbon(fr: Vector3, to: Vector3, width: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var steps := 8
	var dir := to - fr
	var side := Vector3.UP.cross(dir.normalized()) if dir.length() > 0.01 else Vector3.RIGHT
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized() * width
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := fr.lerp(to, t)
		var fade := 0.55 + 0.45 * sin(t * PI)
		verts.append(p - side)
		verts.append(p + side)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		cols.append(Color(1, 1, 1, fade))
		cols.append(Color(1, 1, 1, fade))
		if i < steps:
			var a := i * 2
			idx.append_array(
				PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3, a, a + 1, a + 2, a + 1, a + 3, a + 2])
			)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _ring_mesh(inner: float, outer: float, sides: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var normals := PackedVector3Array()
	for i in sides:
		var a0 := float(i) / float(sides) * TAU
		var a1 := float(i + 1) / float(sides) * TAU
		var b := verts.size()
		verts.append(Vector3(cos(a0) * inner, 0, sin(a0) * inner))
		verts.append(Vector3(cos(a0) * outer, 0, sin(a0) * outer))
		verts.append(Vector3(cos(a1) * outer, 0, sin(a1) * outer))
		verts.append(Vector3(cos(a1) * inner, 0, sin(a1) * inner))
		for _k in 4:
			normals.append(Vector3.UP)
		idx.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _first_mesh(root: Node) -> Mesh:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh:
		return (root as MeshInstance3D).mesh
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh:
			return mi.mesh
	return null
