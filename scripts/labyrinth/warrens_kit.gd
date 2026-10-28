class_name WarrensKit
extends RefCounted
## Labyrinth L3 (Ember Art batch 08a, CC0): dresses LabyrinthFloor's greybox with the Act I
## Goblin Warrens tile kit. The greybox boxes stay as the collision (and navmesh source);
## their meshes hide once a room is dressed. Walls: 4 m modules from each corner, a 2 m
## piece beside the centred 4 m door (wall_door_4m, 3.6 x 3.0 m opening), and a 2 m piece
## stretched over any odd remainder (kit rooms are even, not all multiples of 4).
## The throne hall (floor 5) brings its own trimesh collision and LOD visibility ranges.

const DIR := "res://assets/original/ember_art/warrens/"
const MODULE := 4.0
const HALL_LOD := [30.0, 70.0]  ## LOD0 -> LOD1 -> LOD2 switch distances (m)
const LIGHT := Color(1.0, 0.62, 0.3)

static var _cache := {}


static func available() -> bool:
	return ResourceLoader.exists(DIR + "wall_4m.glb")


static func piece(id: String) -> Node3D:
	if not _cache.has(id):
		var p := DIR + id + ".glb"
		_cache[id] = load(p) as PackedScene if ResourceLoader.exists(p) else null
	var ps: PackedScene = _cache[id]
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = id
	return n


static func _put(
	parent: Node3D, id: String, at: Vector3, yaw := 0.0, sx := 1.0, sz := 1.0
) -> Node3D:
	var n := piece(id)
	if n == null:
		return null
	parent.add_child(n)
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3(sx, 1.0, sz)
	return n


## [centre, width] runs filling `length` m from one end with 4 m modules then one remainder.
static func fill(length: float) -> Array:
	var out := []
	var x := 0.0
	while length - x >= MODULE - 0.01:
		out.append([x + MODULE / 2, MODULE])
		x += MODULE
	if length - x > 0.01:
		out.append([x + (length - x) / 2, length - x])
	return out


## Wall pieces along local X from -length/2 to +length/2 (a centred door when `door`).
static func wall_line(
	parent: Node3D, origin: Vector3, yaw: float, length: float, door: bool
) -> int:
	var dirv := Vector3(cos(yaw), 0, -sin(yaw))
	var n := 0
	var spans := []
	if door:
		var half := (length - MODULE) / 2.0
		for seg: Array in fill(half):
			# mirrored so the remainder (the 2 m piece) sits beside the door
			var c := MODULE / 2 + half - float(seg[0])
			spans.append([c, seg[1]])
			spans.append([-c, seg[1]])
		_put(parent, "wall_door_4m", origin, yaw)
		n += 1
	else:
		for seg: Array in fill(length):
			spans.append([-length / 2 + float(seg[0]), seg[1]])
	for s: Array in spans:
		var w := float(s[1])
		var id := "wall_4m" if is_equal_approx(w, MODULE) else "wall_2m"
		var k := 1.0 if id == "wall_4m" else w / 2.0
		_put(parent, id, origin + dirv * float(s[0]), yaw, k)
		n += 1
	return n


## Floor tiles over a size.x x size.y rectangle centred on `centre` (edge tiles scaled).
static func floor_tiles(parent: Node3D, centre: Vector3, size: Vector2) -> int:
	var n := 0
	for a: Array in fill(size.x):
		for b: Array in fill(size.y):
			var at := centre + Vector3(-size.x / 2 + float(a[0]), 0, -size.y / 2 + float(b[0]))
			_put(parent, "floor_4m", at, 0.0, float(a[1]) / MODULE, float(b[1]) / MODULE)
			n += 1
	return n


## Dresses one greybox room built by LabyrinthFloor._room (walls, floor, corridors, props).
static func dress_room(r: Node3D, size: Vector2, open: Array[int], slot: float) -> void:
	var d := Node3D.new()
	d.name = "Dress"
	r.add_child(d)
	floor_tiles(d, Vector3.ZERO, size)
	for side in 4:
		var horiz := side == 0 or side == 2
		var sgn := -1.0 if side == 0 or side == 3 else 1.0
		var at := Vector3(0, 0, sgn * size.y / 2) if horiz else Vector3(sgn * size.x / 2, 0, 0)
		wall_line(d, at, 0.0 if horiz else PI / 2, size.x if horiz else size.y, open.has(side))
		if not open.has(side):
			continue
		var run := slot / 2.0 - (size.y if horiz else size.x) / 2.0
		if run <= 0.01:
			continue
		var mid := (size.y if horiz else size.x) / 2.0 + run / 2.0
		var dirv := Vector3(0, 0, sgn) if horiz else Vector3(sgn, 0, 0)
		var side_v := Vector3(1, 0, 0) if horiz else Vector3(0, 0, 1)
		floor_tiles(d, dirv * mid, Vector2(MODULE, run) if horiz else Vector2(run, MODULE))
		for k: float in [-1.0, 1.0]:
			wall_line(d, dirv * mid + side_v * k * 2.25, PI / 2 if horiz else 0.0, run, false)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_put(d, "pillar", Vector3(c.x * size.x / 2, 0, c.y * size.y / 2))
	_hide_greybox(r)


## A torch sconce with a warm light on a wall face (local -Z points into the room).
static func torch(parent: Node3D, at: Vector3, yaw: float) -> void:
	var t := _put(parent, "torch_sconce", at, yaw)
	if t == null:
		return
	var l := OmniLight3D.new()
	l.name = "TorchLight"
	l.light_color = LIGHT
	l.light_energy = 1.6
	l.omni_range = 9.0
	var emit := t.get_node_or_null("Emit") as Node3D
	l.position = emit.position if emit else Vector3(0, 2.5, -0.58)
	t.add_child(l)


## Room set dressing by kind (the rest room gets the fungus-cellar set).
static func props(r: Node3D, kind: String, size: Vector2) -> void:
	var d := r.get_node_or_null("Dress") as Node3D
	if d == null:
		return
	torch(d, Vector3(-size.x / 4, 0, -size.y / 2 + 0.3), PI)
	torch(d, Vector3(size.x / 4, 0, size.y / 2 - 0.3), 0.0)
	match kind:
		"rest":
			_put(d, "bedroll", Vector3(-size.x / 2 + 2.0, 0, size.y / 2 - 2.0), PI / 2)
			var f := _put(d, "cook_fire", Vector3(-2.0, 0, 2.0))
			if f:
				var l := OmniLight3D.new()
				l.name = "FireLight"
				l.light_color = LIGHT
				l.light_energy = 2.0
				l.omni_range = 8.0
				var e := f.get_node_or_null("Emit") as Node3D
				l.position = (e.position if e else Vector3(0, 0.5, 0)) + Vector3(0, 0.4, 0)
				f.add_child(l)
			_put(d, "mushroom_cluster", Vector3(size.x / 2 - 1.5, 0, -size.y / 2 + 1.5))
		"elite":
			_put(d, "goblin_banner", Vector3(0, 0, -size.y / 2 + 1.0))
			_put(d, "bone_pile", Vector3(size.x / 2 - 2.0, 0, size.y / 2 - 2.0))
		"secret":
			_put(d, "crate_stack", Vector3(-size.x / 2 + 1.5, 0, -size.y / 2 + 1.5))
		"normal":
			_put(d, "crate_stack", Vector3(size.x / 2 - 1.5, 0, -size.y / 2 + 1.5), PI / 2)
			_put(d, "bone_pile", Vector3(-size.x / 2 + 1.8, 0, size.y / 2 - 1.8))


## The craft bench at the rest room's station marker (faces the room centre).
static func bench(parent: Node3D, at: Vector3) -> Node3D:
	return _put(parent, "craft_bench", at, PI / 2)


## Floor 5's throne hall: LOD visibility ranges, LOD0 trimesh collision, LOD1/2 none.
static func throne_hall() -> Node3D:
	var h := piece("throne_hall")
	if h == null:
		return null
	var bands := {
		"_LOD0": [0.0, HALL_LOD[0]],
		"_LOD1": [HALL_LOD[0], HALL_LOD[1]],
		"_LOD2": [HALL_LOD[1], 0.0]
	}
	for mi in h.find_children("*", "MeshInstance3D", true, false):
		for suf: String in bands:
			if String(mi.name).ends_with(suf):
				var b: Array = bands[suf]
				(mi as MeshInstance3D).visibility_range_begin = float(b[0])
				(mi as MeshInstance3D).visibility_range_end = float(b[1])
		if String(mi.name).ends_with("_LOD0"):
			(mi as MeshInstance3D).create_trimesh_collision()
	return h


static func _hide_greybox(r: Node3D) -> void:
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		if not (mi as Node).get_parent().name.begins_with("Dress") and not _in_dress(mi):
			(mi as MeshInstance3D).visible = false


static func _in_dress(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p.name == "Dress":
			return true
		p = p.get_parent()
	return false
