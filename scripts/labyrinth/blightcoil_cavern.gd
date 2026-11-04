class_name BlightcoilCavern
extends Node3D
## The Blightcoil: one walkable cavern (KTD1, KTD2, KTD9). Checkpoints 6, 7 and 8 are
## pads in this volume. Floors 1-5 never come through here. Navigation is baked from
## the walkable colliders only and cached under scenes/levels/nav/blightcoil/.

const TOML := "res://data/labyrinth/blightcoil.toml"
const CACHE_MESH := "res://scenes/levels/nav/blightcoil/mesh.res"
const CACHE_MANIFEST := "res://scenes/levels/nav/blightcoil/manifest.json"
const BOSS := "blightmaw_matriarch"

signal pad_reached(checkpoint: int, waystone_id: String)

var floor_no := 6
var doc := {}
var hazard: BlightHazard
var forge: BlightForge
var cocoon: Node3D
var mother: Marker3D
var nav_bakes := 0
var nav_from_cache := false
var fog_cleared := false
var _region: NavigationRegion3D
var _stepped := {}
var _mats := {}


static func load_doc() -> Dictionary:
	return LevelToml.load_file(TOML)


static func make(checkpoint: int, state: LabyrinthState) -> BlightcoilCavern:
	var c := BlightcoilCavern.new()
	c.name = "Blightcoil"
	c.floor_no = checkpoint
	c.doc = load_doc()
	c.set_meta(&"level_id", "labyrinth")
	c._build(state)
	return c


func _build(state: LabyrinthState) -> void:
	var walk := Node3D.new()
	walk.name = "Walk"
	add_child(walk)
	var cavern: Dictionary = doc["cavern"]
	_trunk(walk, float(cavern["trunk_radius"]), float(cavern["trunk_top"]))
	for slab in doc["slab"]:
		_slab(walk, slab)
	for ramp in doc["ramp"]:
		_ramp(walk, ramp)
	for pocket in doc.get("pocket", []):
		_pocket(walk, pocket)
	_pads()
	_props(state)
	_volumes()
	_spawns(state)
	_marks()
	_rest()
	hazard = BlightHazard.new()
	hazard.name = "BlightHazard"
	hazard.cavern = self
	hazard.fog_y = float(cavern["fog_y"])
	hazard.void_y = float(cavern["void_y"])
	hazard.rest_exempt = float(cavern["rest_exempt"])
	hazard.rest_pad = pad_local(7)
	add_child(hazard)
	if state and state.bosses.has(BOSS):
		note_boss_dead()


func ensure_nav() -> void:
	if _region == null:
		_region = NavigationRegion3D.new()
		_region.name = "Navigation"
		add_child(_region)
		# Ramp ends and slab edges are a short step apart after the agent radius
		# is eroded. A wider edge margin joins them into one walk.
		NavigationServer3D.map_set_edge_connection_margin(_region.get_navigation_map(), 3.0)
	var hashed := _toml_hash()
	var cached := _read_cache(hashed)
	if cached != null:
		var loaded := cached.duplicate() as NavigationMesh
		_assign_nav(loaded)
		nav_from_cache = true
		return
	# The collider bake drops a 1.8 m agent off these ramps: each step's nose is
	# inside the agent's body, so the generator keeps only the slabs. The mesh
	# below is the walk surface itself (slab tops and the ramp strips), with the
	# same agent settings recorded on the resource, and it is what the cache stores.
	var nm := _authored_mesh()
	_assign_nav(nm)
	nav_bakes += 1
	nav_from_cache = false
	_write_cache(nm, hashed)
	push_warning(
		"Blightcoil: built navmesh (%d polys); the cache was missing or stale"
		% nm.get_polygon_count()
	)


func nav_map() -> RID:
	return _region.get_navigation_map() if _region else RID()


func pad_local(checkpoint: int) -> Vector3:
	for slab in doc["slab"]:
		if int(slab["checkpoint"]) == checkpoint:
			var p: Array = slab["pad"]
			return Vector3(float(p[0]), float(p[1]), float(p[2]))
	return Vector3.ZERO


func pad_global(checkpoint: int) -> Vector3:
	return global_transform * pad_local(checkpoint)


func waystone_for(checkpoint: int) -> String:
	for slab in doc["slab"]:
		if int(slab["checkpoint"]) == checkpoint:
			return String(slab["waystone"])
	return ""


func start_pos() -> Vector3:
	return pad_global(floor_no)


## True when a nav path on this cavern's mesh reaches the Crown pad from the Sump pad.
func path_reaches_crown() -> bool:
	if _region == null or _region.navigation_mesh == null:
		return false
	var map := _region.get_navigation_map()
	if not map.is_valid():
		return false
	NavigationServer3D.map_force_update(map)
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var a := pad_global(6) + Vector3(0, 0.4, 0)
	var b := pad_global(8) + Vector3(0, 0.4, 0)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	if path.size() < 2:
		return false
	return path[path.size() - 1].distance_to(b) < 3.0


func ramp_degrees() -> Array:
	var out: Array = []
	for ramp in doc["ramp"]:
		out.append(_slope_deg(ramp))
	return out


func min_clearance() -> float:
	var best := 1000.0
	var walk := get_node("Walk")
	for ramp_node in walk.get_children():
		if String(ramp_node.name).begins_with("Lip") or String(ramp_node.name) == "Trunk":
			continue
		if not String(ramp_node.name).begins_with("Ramp") or not ramp_node.has_meta(&"fr"):
			continue
		var fr: Vector3 = ramp_node.get_meta(&"fr")
		var to: Vector3 = ramp_node.get_meta(&"to")
		for step in 17:
			var t := 0.05 + 0.05 * float(step)
			if t > 0.9:
				break
			var at := fr.lerp(to, t) + Vector3(0, 0.2, 0)
			var gap := _ceiling_gap(at, ramp_node)
			best = minf(best, gap)
	return best


func note_boss_dead() -> bool:
	fog_cleared = true
	if hazard:
		hazard.fog_cleared = true
	if cocoon:
		cocoon.visible = true
	if forge:
		forge.opened = true
	_hide_fog_meshes()
	return true


func watch_pads(dt_players: Array) -> void:
	for p in dt_players:
		if not (p is Node3D):
			continue
		var who := p as Node3D
		for slab in doc["slab"]:
			var id := String(slab["waystone"])
			if _stepped.has(id):
				continue
			var pad := pad_global(int(slab["checkpoint"]))
			var d := who.global_position - pad
			if Vector2(d.x, d.z).length() <= 1.8 and absf(d.y) < 2.2:
				_stepped[id] = true
				if hazard:
					hazard.last_pad = pad
				pad_reached.emit(int(slab["checkpoint"]), id)


func spawn_puff(at: Vector3) -> Node3D:
	var n := _volume("puff", at, Vector3(2.2, 1.6, 2.2), Color(0.55, 0.7, 0.3, 0.35))
	n.set_meta(&"left", BlightHazard.PUFF_TIME)
	return n


func spawn_crown_vines() -> void:
	if has_node("CrownVines"):
		return
	var holder := Node3D.new()
	holder.name = "CrownVines"
	add_child(holder)
	var pad := pad_local(8)
	for off in [Vector3(3.2, 1.0, 0), Vector3(-2.4, 1.0, 2.2), Vector3(0, 1.0, -3.0)]:
		# _volume parents the box to the cavern. A second add_child is an error.
		_volume("vine", pad + off, Vector3(1.4, 2.2, 1.4), Color(0.2, 0.45, 0.18))


func _physics_process(_dt: float) -> void:
	if not is_inside_tree():
		return
	var who: Array = []
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		who.append(n)
	watch_pads(who)


func _slab(walk: Node3D, slab: Dictionary) -> void:
	var c: Array = slab["center"]
	var sz: Array = slab["size"]
	var top := float(c[1])
	var min_x := float(c[0]) - float(sz[0]) * 0.5
	var max_x := float(c[0]) + float(sz[0]) * 0.5
	var min_z := float(c[2]) - float(sz[1]) * 0.5
	var max_z := float(c[2]) + float(sz[1]) * 0.5
	# A ramp that ends on this slab crosses the side face while it is still below
	# the walking surface. Pull that face back to the landing so the slope meets
	# the top instead of a wall.
	for ramp in doc["ramp"]:
		var fr := _v3(ramp["fr"])
		var to := _v3(ramp["to"])
		if absf(to.y - top) > 0.2:
			continue
		if to.x <= min_x or to.x >= max_x or to.z <= min_z or to.z >= max_z:
			continue
		# Past the landing, so the slope crests in the air and a flat plate
		# carries the body onto the top instead of into the side face.
		match _entry_face(fr, to, min_x, max_x, min_z, max_z):
			"minx":
				min_x = to.x + 1.2
			"maxx":
				max_x = to.x - 1.2
			"minz":
				min_z = to.z + 1.2
			"maxz":
				max_z = to.z - 1.2
	_box(
		walk,
		"Slab_" + String(slab["id"]),
		Vector3((min_x + max_x) * 0.5, top - 0.25, (min_z + max_z) * 0.5),
		Vector3(max_x - min_x, 0.5, max_z - min_z),
		_color(String(slab["id"]))
	)


func _pocket(walk: Node3D, pocket: Dictionary) -> void:
	var at: Array = pocket["at"]
	var sz: Array = pocket["size"]
	var top := float(at[1])
	_box(
		walk,
		"Pocket_" + String(pocket["id"]),
		Vector3(float(at[0]), top - 0.2, float(at[2])),
		Vector3(float(sz[0]), 0.4, float(sz[1])),
		Color(0.32, 0.36, 0.22)
	)
	var marks := get_node_or_null("Chests")
	if marks == null:
		marks = Node3D.new()
		marks.name = "Chests"
		add_child(marks)
	var m := Marker3D.new()
	m.name = String(pocket["id"])
	m.position = Vector3(float(at[0]), top, float(at[2]))
	m.set_meta(&"secret", true)
	marks.add_child(m)


func _ramp(walk: Node3D, ramp: Dictionary) -> void:
	var fr := _v3(ramp["fr"])
	var to := _v3(ramp["to"])
	var marker := Node3D.new()
	marker.name = "Ramp_" + String(ramp["id"])
	marker.set_meta(&"fr", fr)
	marker.set_meta(&"to", to)
	marker.set_meta(&"slope_deg", _slope_deg(ramp))
	walk.add_child(marker)
	# One slope. The start is buried in the slab the ramp leaves, and the top face
	# passes through fr and to, so a body walks on instead of meeting a riser.
	var along := (to - fr).normalized()
	var side := Vector3.UP.cross(along)
	if side.length() < 0.05:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := along.cross(side).normalized()
	var width := float(doc["cavern"].get("ramp_width", 8.0))
	var thick := float(doc["cavern"].get("ramp_thickness", 0.35))
	var buried := fr - along * 0.25
	var span := to - buried
	var centre := buried.lerp(to, 0.5) - up * (thick * 0.5)
	var slope := StaticBody3D.new()
	slope.name = "Slope_" + String(ramp["id"])
	slope.transform = Transform3D(Basis(side, up, along), centre)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, thick, span.length())
	mesh_node.mesh = mesh
	mesh_node.material_override = _mat(Color(0.34, 0.26, 0.14))
	slope.add_child(mesh_node)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	slope.add_child(shape)
	walk.add_child(slope)
	var horiz := Vector3(to.x - fr.x, 0.0, to.z - fr.z).normalized()
	var side_h := Vector3(-horiz.z, 0.0, horiz.x)
	var land := to + horiz * 1.3
	land.y = to.y - thick * 0.5
	_flat_tread(walk, "Land_" + String(ramp["id"]), land, side_h, horiz, width, 2.8)
	var midp := fr.lerp(to, 0.45)
	_volume("vine", midp + Vector3(0, 1.0, 0), Vector3(3.0, 2.4, 3.0), Color(0.18, 0.42, 0.16))


func _trunk(walk: Node3D, radius: float, top: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Trunk"
	body.position = Vector3(0, top * 0.5 - 1.0, 0)
	var mesh_node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = top + 1.0
	mesh_node.mesh = mesh
	mesh_node.material_override = _mat(Color(0.28, 0.22, 0.14))
	body.add_child(mesh_node)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = top + 1.0
	shape.shape = cyl
	body.add_child(shape)
	# The trunk is solid so a body cannot walk through it. It is not under the
	# walkable set the navmesh bakes, so enemies do not path across the shaft.
	add_child(body)
	body.set_meta(&"role", "trunk")
	walk.set_meta(&"trunk_radius", radius)


func _pads() -> void:
	for slab in doc["slab"]:
		var m := Marker3D.new()
		m.name = "Pad_" + String(slab["id"])
		m.position = _v3(slab["pad"])
		m.set_meta(&"checkpoint", int(slab["checkpoint"]))
		m.set_meta(&"waystone", String(slab["waystone"]))
		add_child(m)
	var start := Marker3D.new()
	start.name = "PlayerStart"
	start.position = pad_local(floor_no)
	add_child(start)


func _props(state: LabyrinthState) -> void:
	mother = Marker3D.new()
	mother.name = "VerdantMother"
	mother.position = pad_local(7) + Vector3(1.6, 0, 0.4)
	mother.set_meta(&"speaker", "Verdant Mother")
	add_child(mother)
	cocoon = _prop_box(
		"Cocoon", pad_local(8) + Vector3(-2.2, 0.8, 1.4), Vector3(1.8, 1.6, 1.4), Color(0.55, 0.5, 0.32)
	)
	cocoon.visible = state != null and state.bosses.has(BOSS)
	forge = BlightForge.new()
	forge.name = "ForgeDoor"
	forge.position = pad_local(8) + Vector3(2.4, 0, -1.2)
	add_child(forge)
	if state and state.bosses.has(BOSS):
		forge.opened = true


func _volumes() -> void:
	for mire in doc.get("mire", []):
		var at := _v3(mire["at"])
		var sz := _v3(mire["size"])
		_volume("mire", at + Vector3(0, 0.4, 0), sz, Color(0.2, 0.45, 0.15, 0.55))
	for slab in doc["slab"]:
		if int(slab["checkpoint"]) < 7:
			continue
		var c := _v3(slab["center"])
		var sz: Array = slab["size"]
		var fog := _volume(
			"fog_mesh",
			c + Vector3(0, 1.6, 0),
			Vector3(float(sz[0]) * 0.92, 2.4, float(sz[1]) * 0.92),
			Color(0.45, 0.55, 0.25, 0.18)
		)
		fog.set_meta(&"kind", "fog_mesh")


func _ready() -> void:
	if hazard:
		hazard.rest_pad = pad_global(7)
		hazard.last_pad = pad_global(floor_no)
		hazard.cavern = self


func _spawns(state: LabyrinthState) -> void:
	var root := Node3D.new()
	root.name = "EnemySpawns"
	add_child(root)
	_enemy(root, "sump_husk_a", "spore_husk", 6, Vector3(20.5, 0, 3.2))
	_enemy(root, "sump_husk_b", "spore_husk", 6, Vector3(20.0, 0, 1.0))
	_enemy(root, "sump_treant", "mossbound_treant", 6, Vector3(19.2, 0, 3.6), "sump_elite")
	_enemy(root, "canopy_husk", "spore_husk", 7, Vector3(5.0, 12, 19.0))
	_enemy(root, "canopy_beast", "spore_beast", 7, Vector3(3.2, 12, 23.2))
	_enemy(root, "canopy_treant", "mossbound_treant", 7, Vector3(1.5, 12, 21.0), "canopy_elite")
	_enemy(root, "crown_beast", "spore_beast", 8, Vector3(-20.0, 24, -6.0))
	_enemy(root, "crown_treant", "mossbound_treant", 8, Vector3(-20.5, 24, -4.5), "crown_elite")
	var boss_at := pad_local(8) + Vector3(0, 0, 1.8)
	if state == null or not state.bosses.has(BOSS):
		var boss := _enemy(root, "matriarch", BOSS, 8, boss_at)
		boss.set_meta(&"lab_boss", BOSS)
	var spot := Marker3D.new()
	spot.name = "BossSpawn"
	spot.position = boss_at
	spot.set_meta(&"boss", BOSS)
	add_child(spot)


func _enemy(
	root: Node3D, nm: String, id: String, pad: int, at: Vector3, elite := ""
) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	m.position = at
	m.set_meta(&"enemy", id)
	m.set_meta(&"pad", pad)
	if elite != "":
		m.set_meta(&"lab_elite", elite)
	root.add_child(m)
	return m


func _marks() -> void:
	for row in doc.get("mark", []):
		var id := String(row["id"])
		var m := Marker3D.new()
		m.name = "Mark_" + id
		m.position = _v3(row["at"])
		m.set_meta(&"mark_id", id)
		add_child(m)


func place_marks(flags: StoryFlags) -> void:
	for row in doc.get("mark", []):
		var id := String(row["id"])
		var node := get_node_or_null("Mark_" + id)
		if flags != null and flags.has("mark:" + id):
			if node:
				node.queue_free()
			continue
		if node == null:
			continue
		if get_node_or_null("Pickup_" + id):
			continue
		var pick := BlightMark.make_mark(id, flags)
		pick.name = "Pickup_" + id
		add_child(pick)
		pick.global_position = (node as Node3D).global_position + Vector3(0, 0.4, 0)


func _rest() -> void:
	var shrine := RestShrine.new()
	shrine.name = "RestShrine"
	shrine.position = pad_local(7) + Vector3(-1.4, 0, 0.2)
	shrine.set_meta(&"checkpoint", 7)
	add_child(shrine)


func _hide_fog_meshes() -> void:
	for n in get_tree().get_nodes_in_group(&"blight_volume") if is_inside_tree() else []:
		if String(n.get_meta(&"kind", "")) == "fog_mesh" and n is Node3D:
			(n as Node3D).visible = false


func _volume(kind: String, at: Vector3, sz: Vector3, color: Color) -> Node3D:
	var n := Node3D.new()
	n.name = kind + "_" + str(get_child_count())
	n.position = at
	n.set_meta(&"kind", kind)
	n.set_meta(&"size", sz)
	n.add_to_group(&"blight_volume")
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh_node.mesh = mesh
	var mat := _mat(color)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 0.99 else BaseMaterial3D.TRANSPARENCY_DISABLED
	mesh_node.material_override = mat
	n.add_child(mesh_node)
	add_child(n)
	return n


func _prop_box(nm: String, at: Vector3, sz: Vector3, color: Color) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = nm
	mesh_node.position = at
	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh_node.mesh = mesh
	mesh_node.material_override = _mat(color)
	add_child(mesh_node)
	return mesh_node


func _box(parent: Node3D, nm: String, centre: Vector3, sz: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = centre
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mesh_node.mesh = mesh
	mesh_node.material_override = _mat(color)
	body.add_child(mesh_node)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


func _flat_tread(
	parent: Node3D, nm: String, centre: Vector3, side: Vector3, along: Vector3, width: float, depth: float
) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.transform = Transform3D(Basis(side, Vector3.UP, along).orthonormalized(), centre)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.3, depth)
	mesh_node.mesh = mesh
	mesh_node.material_override = _mat(Color(0.34, 0.26, 0.14))
	body.add_child(mesh_node)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


func _landing(parent: Node3D, nm: String, at: Vector3, away: Vector3, top: float) -> void:
	var dir := Vector3(away.x, 0, away.z).normalized()
	var centre := at + dir * 0.6
	centre.y = top - 0.2
	var length := 2.4
	var size := Vector3(6.0, 0.4, length) if absf(dir.z) >= absf(dir.x) else Vector3(length, 0.4, 6.0)
	_box(parent, nm, centre, size, Color(0.34, 0.26, 0.14))


func _slope_box(parent: Node3D, nm: String, fr: Vector3, to: Vector3) -> StaticBody3D:
	var delta := to - fr
	var along := delta.normalized()
	var side := Vector3.UP.cross(along)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := along.cross(side).normalized()
	if up.dot(Vector3.UP) < 0.0:
		up = -up
		side = -side
	var thick := float(doc["cavern"]["ramp_thickness"])
	var width := float(doc["cavern"]["ramp_width"])
	var body := StaticBody3D.new()
	body.name = nm
	var mid := (fr + to) * 0.5 - up * (thick * 0.5)
	body.transform = Transform3D(Basis(side, up, along).orthonormalized(), mid)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, thick, delta.length())
	mesh_node.mesh = mesh
	mesh_node.material_override = _mat(Color(0.34, 0.26, 0.14))
	body.add_child(mesh_node)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = mesh.size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body


func _ceiling_gap(local_at: Vector3, ignore: Node) -> float:
	var gap := 1000.0
	var walk := get_node("Walk")
	for body in walk.get_children():
		if body == ignore or not (body is StaticBody3D):
			continue
		if String(body.name).begins_with("Ramp"):
			continue
		var shape := (body as StaticBody3D).get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape == null or not (shape.shape is BoxShape3D):
			continue
		var sz: Vector3 = (shape.shape as BoxShape3D).size
		var xf: Transform3D = (body as StaticBody3D).transform
		# Axis-aligned slabs and lips only. A rotated ramp is not a ceiling.
		if absf(xf.basis.y.dot(Vector3.UP)) < 0.98:
			continue
		var centre := xf.origin
		var half := sz * 0.5
		if absf(local_at.x - centre.x) > half.x or absf(local_at.z - centre.z) > half.z:
			continue
		var bottom := centre.y - half.y
		if bottom <= local_at.y + 0.15:
			continue
		gap = minf(gap, bottom - local_at.y)
	return gap


func _entry_face(fr: Vector3, to: Vector3, min_x: float, max_x: float, min_z: float, max_z: float) -> String:
	var best_t := 2.0
	var face := ""
	var dx := to.x - fr.x
	var dz := to.z - fr.z
	if absf(dx) > 0.001:
		if fr.x < min_x:
			var t := (min_x - fr.x) / dx
			var z := fr.z + t * dz
			if t > 0.0 and t < best_t and z >= min_z and z <= max_z:
				best_t = t
				face = "minx"
		if fr.x > max_x:
			var t := (max_x - fr.x) / dx
			var z := fr.z + t * dz
			if t > 0.0 and t < best_t and z >= min_z and z <= max_z:
				best_t = t
				face = "maxx"
	if absf(dz) > 0.001:
		if fr.z < min_z:
			var t := (min_z - fr.z) / dz
			var x := fr.x + t * dx
			if t > 0.0 and t < best_t and x >= min_x and x <= max_x:
				best_t = t
				face = "minz"
		if fr.z > max_z:
			var t := (max_z - fr.z) / dz
			var x := fr.x + t * dx
			if t > 0.0 and t < best_t and x >= min_x and x <= max_x:
				best_t = t
				face = "maxz"
	return face


func _slope_deg(ramp: Dictionary) -> float:
	var fr := _v3(ramp["fr"])
	var to := _v3(ramp["to"])
	var run := Vector2(to.x - fr.x, to.z - fr.z).length()
	return rad_to_deg(atan2(to.y - fr.y, run))


func _assign_nav(nm: NavigationMesh) -> void:
	_region.navigation_mesh = nm
	NavigationServer3D.region_set_navigation_mesh(_region.get_rid(), nm)
	var map := _region.get_navigation_map()
	if map.is_valid():
		NavigationServer3D.map_set_edge_connection_margin(map, 1.0)


func _authored_mesh() -> NavigationMesh:
	var nm := _mesh_settings()
	# One ribbon, vertices shared between segments, so the pads and both ramps
	# are a single walk. Separate baked islands do not link across a slab face.
	var ramps: Array = doc["ramp"]
	var pts: Array[Vector3] = [
		pad_local(6),
		_v3(ramps[0]["fr"]),
		_v3(ramps[0]["to"]),
		pad_local(7),
		_v3(ramps[1]["fr"]),
		_v3(ramps[1]["to"]),
		pad_local(8),
	]
	var verts := PackedVector3Array()
	var polys: Array[PackedInt32Array] = []
	var half := 2.0
	var first := pts[1] - pts[0]
	first.y = 0.0
	if first.length() < 0.05:
		first = Vector3(-1, 0, 1)
	var s0 := Vector3(-first.z, 0, first.x).normalized() * half
	verts.append(pts[0] - s0)
	verts.append(pts[0] + s0)
	var i_l := 0
	var i_r := 1
	for i in pts.size() - 1:
		if pts[i].distance_to(pts[i + 1]) < 0.05:
			continue
		var step := pts[i + 1] - pts[i]
		step.y = 0.0
		var side := Vector3(-step.z, 0, step.x).normalized() * half
		var base := verts.size()
		verts.append(pts[i + 1] + side)
		verts.append(pts[i + 1] - side)
		polys.append(PackedInt32Array([i_l, i_r, base, base + 1]))
		i_l = base + 1
		i_r = base
	nm.vertices = verts
	for poly in polys:
		nm.add_polygon(poly)
	return nm


func _mesh_settings() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	return nm


func _toml_hash() -> String:
	var f := FileAccess.open(TOML, FileAccess.READ)
	var text := "" if f == null else f.get_as_text()
	return (text + "|nav12").sha256_text()


func _read_cache(hashed: String) -> NavigationMesh:
	if not FileAccess.file_exists(CACHE_MANIFEST) or not ResourceLoader.exists(CACHE_MESH):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_MANIFEST))
	if not (parsed is Dictionary) or String(parsed.get("hash", "")) != hashed:
		return null
	return load(CACHE_MESH) as NavigationMesh


func _write_cache(nm: NavigationMesh, hashed: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/levels/nav/blightcoil"))
	var err := ResourceSaver.save(nm, CACHE_MESH)
	if err != OK:
		push_warning("Blightcoil: nav cache save failed (%s)" % error_string(err))
		return
	var f := FileAccess.open(CACHE_MANIFEST, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"hash": hashed, "polys": nm.get_polygon_count()}))


func _v3(v: Variant) -> Vector3:
	var a: Array = v
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _color(id: String) -> Color:
	match id:
		"sump":
			return Color(0.22, 0.32, 0.18)
		"canopy":
			return Color(0.28, 0.4, 0.2)
		"crown":
			return Color(0.36, 0.42, 0.18)
	return Color(0.3, 0.3, 0.28)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_mats[key] = m
	return _mats[key]
