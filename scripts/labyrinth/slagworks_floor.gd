class_name SlagworksFloor
extends Node3D
## Act III, the Slagworks (KTD1, KTD2, KTD9). Checkpoints 9-12 are one generated kit
## floor. Checkpoint 13 is the handmade crucible. Floors 1-8 never build here.
## Navigation is the top faces of the safe colliders (lava is an area, not a
## collider). A 1.8 m agent bake drops off the gantry ramps, the same failure the
## Blightcoil cavern already hit, so the mesh records the cavern agent settings
## and is cached under scenes/levels/nav/slagworks/.

signal pad_reached(checkpoint: int, waystone_id: String)
signal lift_home

const TOML := "res://data/labyrinth/slagworks.toml"
const CACHE_DIR := "res://scenes/levels/nav/slagworks"
const FIRST := 9
const LAST := 13
const EXEMPT := 2.5
const BOSS := "forgemaw"
const DOOR := 4.0
const STRIP := 4.0
const RAMP_RUN := 6.0
const RAMP_RISE := 3.0
const NAMES := {
	9: "Railhead",
	10: "Vein",
	11: "Overlook",
	12: "Furnace",
	13: "Crucible",
}
const WAYSTONES := {
	9: "slagworks_railhead",
	10: "slagworks_vein",
	11: "slagworks_overlook",
	12: "slagworks_furnace",
	13: "slagworks_crucible",
}
const COLORS := {
	"start": Color(0.46, 0.32, 0.22),
	"normal": Color(0.34, 0.26, 0.2),
	"elite": Color(0.55, 0.24, 0.12),
	"rest": Color(0.42, 0.3, 0.18),
	"secret": Color(0.28, 0.22, 0.2),
	"exit": Color(0.38, 0.22, 0.16),
	"boss": Color(0.48, 0.18, 0.1),
	"gantry": Color(0.4, 0.36, 0.32),
	"wall": Color(0.22, 0.16, 0.14),
}

var floor_no := 9
var waystone_id := ""
var seed_value := 1
var phase := 1
var weak_open := false
var layout := {}
var rooms: Array[Node3D] = []
var nav_bakes := 0
var nav_from_cache := false
var hazard: SlagHazard
var _state: LabyrinthState
var _region: NavigationRegion3D
var _mats := {}
var _ramp_i := 0
var _pad_at := Vector3.ZERO
var path_note := ""


static func is_floor(n: int) -> bool:
	return n >= FIRST and n <= LAST


static func load_kit() -> Dictionary:
	return FloorGen.load_kit(TOML)


static func make(checkpoint: int, state: LabyrinthState) -> SlagworksFloor:
	var f := SlagworksFloor.new()
	f.name = "SlagworksFloor"
	f.floor_no = checkpoint
	f._state = state
	f.seed_value = state.slag_seed(checkpoint) if state else FloorGen.floor_seed(1, "slagworks", checkpoint, 0)
	f.waystone_id = String(WAYSTONES.get(checkpoint, ""))
	f.set_meta(&"level_id", "labyrinth")
	f.add_to_group(&"slagworks_floor")
	var spawns := Node3D.new()
	spawns.name = "EnemySpawns"
	f.add_child(spawns)
	if checkpoint >= LAST:
		f._build_crucible()
	else:
		f._build_kit()
	f.hazard = SlagHazard.new()
	f.hazard.name = "SlagHazard"
	f.hazard.host = f
	f.add_child(f.hazard)
	return f


func _ready() -> void:
	var pad := get_node_or_null("Pad") as Area3D
	if pad and not pad.body_entered.is_connected(_on_pad_body):
		pad.body_entered.connect(_on_pad_body)
	var shrine := get_node_or_null("RestShrine") as RestShrine
	if shrine and hazard and not shrine.rested.is_connected(hazard.on_rest):
		shrine.rested.connect(hazard.on_rest)
	if hazard:
		hazard.last_pad = pad_global()


func _on_pad_body(b: Node3D) -> void:
	if b is Player and b.is_in_group(Player.GROUP):
		pad_reached.emit(floor_no, waystone_id)


func pad_local() -> Vector3:
	return _pad_at


func pad_global() -> Vector3:
	return global_transform * _pad_at


func on_pad(world: Vector3) -> bool:
	var p := pad_global()
	return Vector2(world.x - p.x, world.z - p.z).length() <= EXEMPT + 0.05


func start_pos() -> Vector3:
	var m := get_node_or_null("PlayerStart") as Node3D
	return m.global_position if m else pad_global()


func exit_local() -> Vector3:
	var s := get_node_or_null("StairsDown") as Node3D
	return s.position if s else _pad_at


func anvils() -> Array:
	var out: Array = []
	for n in find_children("*", "", true, false):
		if n.is_in_group(&"furnace_anvil"):
			out.append(n)
	return out


func ramp_degrees() -> Array:
	var out: Array = []
	for n in find_children("*", "StaticBody3D", true, false):
		if n.is_in_group(&"slag_ramp"):
			var up := (n as StaticBody3D).global_transform.basis.y
			out.append(rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))))
	return out


func entry_direction(index: int) -> Vector3:
	var best := -1
	var dir := Vector3(0, 0, -1)
	var rs: Array = layout.get("rooms", [])
	for e: Array in layout.get("edges", []):
		var other := -1
		if int(e[0]) == index:
			other = int(e[1])
		elif int(e[1]) == index:
			other = int(e[0])
		if other < 0 or other >= rs.size():
			continue
		if best >= 0 and other >= best:
			continue
		best = other
		var a: Vector2i = rs[index]["cell"]
		var b: Vector2i = rs[other]["cell"]
		dir = Vector3(b.x - a.x, 0, b.y - a.y)
	if dir.length() < 0.01:
		return Vector3(0, 0, -1)
	return dir.normalized()


func cache_stem() -> String:
	return "%d_%s" % [floor_no, _cache_hash().substr(0, 16)]


func cache_mesh_path() -> String:
	return "%s/mesh_%s.res" % [CACHE_DIR, cache_stem()]


func cache_manifest_path() -> String:
	return "%s/manifest_%s.json" % [CACHE_DIR, cache_stem()]


func ensure_nav() -> void:
	if _region != null and _region.navigation_mesh != null:
		return
	if _region == null:
		_region = NavigationRegion3D.new()
		_region.name = "Navigation"
		add_child(_region)
	var hashed := _cache_hash()
	var cached := _read_cache(hashed)
	if cached != null:
		_assign_nav(cached.duplicate())
		nav_from_cache = true
		return
	var nm := _mesh_from_walk()
	_assign_nav(nm)
	nav_bakes += 1
	nav_from_cache = false
	_write_cache(nm, hashed)


func path_reaches(to_local: Vector3) -> bool:
	path_note = "no mesh"
	if _region == null or _region.navigation_mesh == null:
		return false
	var map := _region.get_navigation_map()
	if not map.is_valid():
		path_note = "no map"
		return false
	NavigationServer3D.map_set_edge_connection_margin(map, 3.0)
	NavigationServer3D.map_force_update(map)
	var iter := NavigationServer3D.map_get_iteration_id(map)
	if iter == 0:
		path_note = "iter 0 polys %d" % _region.navigation_mesh.get_polygon_count()
		return false
	var a := pad_global() + Vector3(0, 0.45, 0)
	var b := to_global(to_local) + Vector3(0, 0.45, 0)
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	var end := path[path.size() - 1].distance_to(b) if path.size() else -1.0
	var lava := _path_in_lava(path)
	path_note = "iter %d points %d end %.2f lava %s" % [iter, path.size(), end, lava]
	if path.size() < 2 or end > 2.5:
		return false
	return not lava


func _build_kit() -> void:
	var kit := load_kit()
	layout = FloorGen.generate(kit, seed_value)
	if layout.has("error"):
		push_error("Slagworks: %s" % layout["error"])
		return
	var slot := float(kit["kit"]["slot"])
	var rs: Array = layout["rooms"]
	for i in rs.size():
		var rd: Dictionary = rs[i]
		var id := String(rd["room"])
		var kr := _kit_room(kit, id)
		var sz := Vector2(float(kr["size"][0]), float(kr["size"][1]))
		if int(rd["rot"]) % 2 == 1:
			sz = Vector2(sz.y, sz.x)
		var cell: Vector2i = rd["cell"]
		var kind := String(rd["kind"])
		var room := Node3D.new()
		room.name = "Room%d_%s" % [i, id]
		room.position = Vector3(cell.x * slot, 0, cell.y * slot)
		room.set_meta(&"kind", kind)
		room.set_meta(&"index", i)
		room.set_meta(&"room", id)
		room.set_meta(&"size", sz)
		room.set_meta(&"lava", _has_tag(kit, id, "lava"))
		add_child(room)
		rooms.append(room)
		var open: Array = FloorGen.doors(layout, i)
		_floor_slab(room, sz, _has_tag(kit, id, "lava"), kind)
		_walls(room, sz, open, kind)
		_corridors(room, sz, open, slot, kind)
		if _has_tag(kit, id, "gantry"):
			_add_gantry(room, sz)
		if _has_tag(kit, id, "rail"):
			_rail(room, sz, i)
		if _has_tag(kit, id, "furnace"):
			_anvil(room, entry_direction(i))
		if kind == "secret":
			var ch := _marker(_chests(), "secret%d" % i, room.position)
			ch.set_meta(&"secret", true)
		elif kind == "start":
			_stairs(
				"StairsUp",
				LabyrinthStairs.UP,
				room.position + Vector3(-sz.x * 0.5 + 2.0, 0.0, -sz.y * 0.5 + 2.0),
			)
		elif kind == "exit":
			_stairs("StairsDown", LabyrinthStairs.DOWN, room.position)
		elif kind == "rest":
			_pad(room.position)
			_shrine(room.position + Vector3(2.4, 0, 0))
		_place_pack(room, kind)


func _build_crucible() -> void:
	var arena := Node3D.new()
	arena.name = "Crucible"
	arena.set_meta(&"kind", "boss")
	add_child(arena)
	rooms.append(arena)
	_walk_box(arena, Vector3(0, -0.25, -16), Vector3(36, 0.5, 4), "RingN", "boss")
	_walk_box(arena, Vector3(0, -0.25, 16), Vector3(36, 0.5, 4), "RingS", "boss")
	_walk_box(arena, Vector3(16, -0.25, 0), Vector3(4, 0.5, 28.5), "RingE", "boss")
	_walk_box(arena, Vector3(-16, -0.25, 0), Vector3(4, 0.5, 28.5), "RingW", "boss")
	_lava_strip(arena, "LavaStrip0", Vector3(0, 0.6, -4))
	_lava_strip(arena, "LavaStrip1", Vector3(0, 0.6, 4))
	var pad_at := Vector3(0, 3.0, -12)
	var deck := _walk_box(arena, Vector3(0, 2.8, -12), Vector3(4.5, 0.4, 4.5), "PadDeck", "gantry")
	deck.set_meta(&"deck_top", 3.0)
	_add_ramp(arena, Vector3(0, 0, -17), Vector3(0, 0, RAMP_RUN))
	_pad(pad_at)
	_segment(arena, "GantryA", Vector3(-12, 2.8, 0), Vector3(3.4, 0.4, 8), Vector3(-17, 0, 0), Vector3(RAMP_RUN, 0, 0))
	_segment(arena, "GantryB", Vector3(12, 2.8, 0), Vector3(3.4, 0.4, 8), Vector3(17, 0, 0), Vector3(-RAMP_RUN, 0, 0))
	_segment(arena, "GantryC", Vector3(0, 2.8, 12), Vector3(8, 0.4, 3.4), Vector3(0, 0, 17), Vector3(0, 0, -RAMP_RUN))
	var anvil := _anvil(arena, Vector3(0, 0, -1))
	anvil.position = Vector3(0, 0, 0)
	_stairs("StairsUp", LabyrinthStairs.UP, Vector3(-14, 0, -16))
	_place_boss()
	_shrine(Vector3(6, 0, -16))
	_slag_prop(arena, "MainLift", "lift", Vector3(8, 1.0, -16))
	_slag_cast(arena)
	_slag_prop(arena, "SunkenDoor", "sunken", Vector3(0, 1.0, 16.5))
	var rail := Node3D.new()
	rail.name = "RailProp"
	rail.position = Vector3(-8, 0.4, 15)
	arena.add_child(rail)
	for side in 4:
		var horiz := side == 0 or side == 2
		var dir := _side_dir(side)
		var edge := dir * 18.3 + Vector3(0, 1.5, 0)
		var full := Vector3(36.6, 3.0, 0.4) if horiz else Vector3(0.4, 3.0, 36.6)
		_wall(arena, edge, full, "Lip%d" % side, "wall")


func _segment(parent: Node3D, nm: String, centre: Vector3, size: Vector3, ramp_start: Vector3, horiz: Vector3) -> void:
	var b := _walk_box(parent, centre, size, nm, "gantry")
	b.add_to_group(&"slag_gantry")
	b.set_meta(&"segment", nm.substr(6, 1))
	b.set_meta(&"deck_top", 3.0)
	_add_ramp(parent, ramp_start, horiz)


func _lava_strip(parent: Node3D, nm: String, at: Vector3) -> void:
	var a := _volume(parent, at, Vector3(16, 1.2, 2.2), "lava")
	a.name = nm
	a.set_meta(&"base_width", 2.2)
	a.set_meta(&"wide_width", 4.5)


func _floor_slab(room: Node3D, size: Vector2, lava: bool, kind: String) -> void:
	if not lava or size.x < 12.0 or size.y < 12.0:
		_walk_box(room, Vector3(0, -0.25, 0), Vector3(size.x, 0.5, size.y), "Slab", kind)
		return
	var m := STRIP
	_walk_box(room, Vector3(0, -0.25, -size.y * 0.5 + m * 0.5), Vector3(size.x, 0.5, m), "SlabN", kind)
	_walk_box(room, Vector3(0, -0.25, size.y * 0.5 - m * 0.5), Vector3(size.x, 0.5, m), "SlabS", kind)
	var inner := size.y - 2.0 * m + 0.3
	var ex := size.x * 0.5 - m * 0.5
	_walk_box(room, Vector3(-ex, -0.25, 0), Vector3(m, 0.5, inner), "SlabW", kind)
	_walk_box(room, Vector3(ex, -0.25, 0), Vector3(m, 0.5, inner), "SlabE", kind)
	var hole := Vector3(size.x - 2.0 * m - 0.6, 1.2, size.y - 2.0 * m - 0.6)
	_volume(room, Vector3(0, 0.6, 0), hole, "lava")


func _walls(room: Node3D, size: Vector2, open: Array, kind: String) -> void:
	var h := 4.0
	var w := 0.45
	for side in 4:
		var horiz := side == 0 or side == 2
		var length := size.x if horiz else size.y
		var edge := _side_dir(side) * ((size.y if horiz else size.x) * 0.5)
		edge.y = h * 0.5
		if not open.has(side):
			var full := Vector3(length, h, w) if horiz else Vector3(w, h, length)
			_wall(room, edge, full, "Wall%d" % side, kind)
			continue
		var seg := (length - DOOR) * 0.5
		if seg <= 0.05:
			continue
		for k in 2:
			var off := (DOOR * 0.5 + seg * 0.5) * (-1.0 if k == 0 else 1.0)
			var lateral := Vector3(off, 0, 0) if horiz else Vector3(0, 0, off)
			var sz := Vector3(seg, h, w) if horiz else Vector3(w, h, seg)
			_wall(room, edge + lateral, sz, "Wall%d_%d" % [side, k], kind)


func _corridors(room: Node3D, size: Vector2, open: Array, slot: float, kind: String) -> void:
	for side in open:
		var s := int(side)
		var horiz := s == 0 or s == 2
		var dir := _side_dir(s)
		var half := (size.y if horiz else size.x) * 0.5
		var inner := half - 0.6
		var outer := slot * 0.5 + 0.2
		if outer <= inner:
			continue
		var mid := (inner + outer) * 0.5
		var length := outer - inner
		var centre := dir * mid + Vector3(0, -0.25, 0)
		var box := Vector3(DOOR, 0.5, length) if horiz else Vector3(length, 0.5, DOOR)
		_walk_box(room, centre, box, "Corridor%d" % s, kind)


func _add_gantry(room: Node3D, size: Vector2) -> void:
	if size.y < 13.0:
		return
	var start := Vector3(0, 0, size.y * 0.5 - 0.8)
	var horiz := Vector3(0, 0, -RAMP_RUN)
	_add_ramp(room, start, horiz)
	var end_z := start.z + horiz.z
	var deck := _walk_box(room, Vector3(0, 2.8, end_z - 1.5), Vector3(5.5, 0.4, 3.8), "GantryDeck", "gantry")
	deck.set_meta(&"deck_top", 3.0)


func _add_ramp(parent: Node3D, start: Vector3, horiz: Vector3) -> StaticBody3D:
	var run := horiz.length()
	var end := start + horiz + Vector3(0, RAMP_RISE, 0)
	var along := end - start
	var basis := Basis.looking_at(along, Vector3.UP)
	var thick := 0.35
	var center := start - basis.z * (along.length() * 0.5) - basis.y * (thick * 0.5)
	_ramp_i += 1
	var b := _walk_box(parent, center, Vector3(3.0, thick, along.length()), "Ramp%d" % _ramp_i, "gantry")
	b.basis = basis
	b.add_to_group(&"slag_ramp")
	b.set_meta(&"rise", RAMP_RISE)
	b.set_meta(&"run", run)
	return b


func _rail(room: Node3D, size: Vector2, index: int) -> void:
	var rail := Node3D.new()
	rail.name = "Rail"
	room.add_child(rail)
	var hx := size.x * 0.5 - 2.2
	var hz := size.y * 0.5 - 2.2
	var y := 0.35
	var pts: Array[Vector3] = [
		room.position + Vector3(-hx, y, -hz),
		room.position + Vector3(hx, y, -hz),
		room.position + Vector3(hx, y, hz),
		room.position + Vector3(-hx, y, hz),
	]
	rail.set_meta(&"loop", pts)
	var h := absi(hash([seed_value, index, "cart"]))
	rail.set_meta(&"period", clampf(6.0 + float(h % 8000) / 1000.0, 6.0, 14.0))
	_solid(rail, Vector3(0, y, 0), Vector3(maxf(hx * 2.0, 1.0), 0.15, 0.35), "GreyRail", "wall", false)


func _anvil(parent: Node3D, face: Vector3) -> Node3D:
	var a := Node3D.new()
	a.name = "FurnaceAnvil"
	a.add_to_group(&"furnace_anvil")
	var f := face if face.length() > 0.01 else Vector3(0, 0, -1)
	a.basis = Basis.looking_at(f.normalized(), Vector3.UP)
	parent.add_child(a)
	_solid(a, Vector3(0, 1.15, 0.15), Vector3(2.4, 2.2, 1.5), "Body", "elite", false)
	var mouth := Marker3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0, 1.25, -1.2)
	a.add_child(mouth)
	_volume(a, Vector3(0, 1.15, -2.1), Vector3(2.0, 1.8, 1.5), "shimmer")
	return a


func _place_pack(room: Node3D, kind: String) -> void:
	if kind == "normal":
		for k in 2:
			_spawn_marker("branded_troll", room.position + Vector3(-2.0 + k * 4.0, 0, 0), false, "")
	elif kind == "elite":
		_spawn_marker("forge_construct", room.position, false, String(room.name))


func _place_boss() -> void:
	if _state and _state.bosses.has(BOSS):
		return
	_spawn_marker(BOSS, Vector3(0, 0, 4), true, "")


func _spawn_marker(id: String, at: Vector3, boss: bool, elite: String) -> void:
	var root := get_node_or_null("EnemySpawns") as Node3D
	if root == null:
		return
	var m := Marker3D.new()
	m.name = "%s_%d" % [id, root.get_child_count()]
	m.position = at
	m.set_meta(&"enemy", id)
	if boss:
		m.set_meta(&"lab_boss", id)
	if elite != "":
		m.set_meta(&"lab_elite", elite)
	root.add_child(m)


func apply_phase(next: int) -> void:
	if next < phase:
		return
	phase = next
	for nm in ["GantryA", "GantryB", "GantryC"]:
		var seg := find_child(nm, true, false) as StaticBody3D
		if seg == null:
			continue
		var up := phase < 2 if nm == "GantryA" else phase < 3
		seg.visible = up
		seg.collision_layer = 1 if up else 0
	if phase >= 3:
		weak_open = true
		for n in find_children("*", "Area3D", true, false):
			if String(n.get_meta(&"kind", "")) != "lava" or not n.has_meta(&"wide_width"):
				continue
			var wide := float(n.get_meta(&"wide_width"))
			var cs := n.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if cs and cs.shape is BoxShape3D:
				var box := cs.shape as BoxShape3D
				box.size.z = wide
			var mesh := n.get_node_or_null("Greybox") as MeshInstance3D
			if mesh and mesh.mesh is BoxMesh:
				(mesh.mesh as BoxMesh).size.z = wide


func _pad(at: Vector3) -> void:
	_pad_at = at
	var a := Area3D.new()
	a.name = "Pad"
	a.position = at + Vector3(0, 1.2, 0)
	a.collision_layer = 0
	a.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	a.monitoring = true
	a.set_meta(&"waystone", waystone_id)
	a.set_meta(&"checkpoint", floor_no)
	a.set_meta(&"exempt_radius", EXEMPT)
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = EXEMPT
	cs.shape = sp
	a.add_child(cs)
	add_child(a)
	_marker(self, "PlayerStart", at)


func _shrine(at: Vector3) -> void:
	var s := RestShrine.new()
	s.name = "RestShrine"
	s.position = at
	s.set_meta(&"checkpoint", floor_no)
	add_child(s)
	var ws := get_node_or_null("WaveSpawns") as Node3D
	if ws == null:
		ws = Node3D.new()
		ws.name = "WaveSpawns"
		add_child(ws)
	_marker(ws, "station", at + Vector3(0, 0, 1.6))


func _stairs(nm: String, dir: int, at: Vector3) -> void:
	var s := LabyrinthStairs.new()
	s.name = nm
	s.dir = dir
	s.position = at
	add_child(s)


func _slag_prop(parent: Node3D, nm: String, role: String, at: Vector3) -> void:
	var a := SlagProp.new()
	a.name = nm
	a.role = role
	a.host = self
	a.position = at
	_solid(a, Vector3(0, 0, 0), Vector3(1.8, 2.4, 0.45), "Greybox", "boss", false)
	parent.add_child(a)


func prop_line(role: String) -> String:
	var dead := _state != null and _state.bosses.has(BOSS)
	if role == "lift":
		return "The lift is locked." if not dead else "The lift is open."
	if dead:
		return "The way down has opened and cannot be taken yet."
	return "The way down is still shut."


func use_lift() -> bool:
	if _state == null or not _state.bosses.has(BOSS):
		return false
	lift_home.emit()
	return true


func place_story(flags: StoryFlags) -> void:
	if floor_no == 11 and get_node_or_null("ScrapSpirit") == null:
		var spirit := Marker3D.new()
		spirit.name = "ScrapSpirit"
		spirit.position = _pad_at + Vector3(1.4, 0, 0.4)
		add_child(spirit)
	var seal_id := ""
	if floor_no == 9:
		seal_id = "railhead_rail"
	elif floor_no == 11:
		seal_id = "overlook_rail"
	elif floor_no == 13:
		seal_id = "crucible_rail"
	if seal_id == "" or flags == null or flags.has("seal:" + seal_id):
		return
	if get_node_or_null("Seal_" + seal_id):
		return
	var seal := SlagSeal.make_seal(seal_id, flags)
	add_child(seal)
	seal.position = _pad_at + Vector3(-1.6, 0.2, 0.2)


func note_boss_dead() -> void:
	var cast := find_child("SlagCast", true, false) as Node3D
	if cast:
		cast.visible = true
	var boss := get_node_or_null("EnemySpawns")
	if boss:
		for c in boss.get_children():
			if String(c.get_meta(&"lab_boss", "")) == BOSS:
				c.queue_free()


func _prop_area(parent: Node3D, nm: String, at: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = nm
	a.position = at
	a.collision_layer = 0
	a.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	a.monitoring = true
	a.set_meta(&"calls_travel", false)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.6, 2.2, 0.6)
	cs.shape = sh
	a.add_child(cs)
	_solid(a, Vector3(0, 0, 0), Vector3(1.8, 2.4, 0.45), "Greybox", "boss", false)
	parent.add_child(a)
	return a


func _slag_cast(parent: Node3D) -> void:
	var cast := Node3D.new()
	cast.name = "SlagCast"
	cast.position = Vector3(0, 0, 15)
	cast.visible = _state != null and _state.bosses.has(BOSS)
	parent.add_child(cast)
	_solid(cast, Vector3(0, 0.35, 0), Vector3(2.4, 0.7, 1.4), "Pool", "wall", false)
	var gap := MeshInstance3D.new()
	gap.name = "Negative"
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 1.5, 0.35)
	gap.mesh = bm
	gap.position = Vector3(0, 1.15, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.04, 0.04)
	gap.material_override = m
	cast.add_child(gap)


func _walk_box(parent: Node3D, centre: Vector3, size: Vector3, nm: String, kind: String) -> StaticBody3D:
	var b := _solid(parent, centre, size, nm, kind, true)
	b.add_to_group(&"slag_walk")
	return b


func _wall(parent: Node3D, centre: Vector3, size: Vector3, nm: String, kind: String) -> StaticBody3D:
	return _solid(parent, centre, size, nm, "wall" if kind == "wall" else kind, false)


func _solid(parent: Node3D, centre: Vector3, size: Vector3, nm: String, kind: String, collide: bool) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = nm
	b.position = centre
	if not collide:
		b.collision_layer = 0
		b.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.name = "Greybox"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(kind)
	b.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		cs.name = "CollisionShape3D"
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
	parent.add_child(b)
	return b


func _volume(parent: Node3D, centre: Vector3, size: Vector3, kind: String) -> Area3D:
	var a := Area3D.new()
	a.name = "Shimmer" if kind == "shimmer" else "Lava"
	a.position = centre
	a.collision_layer = 0
	a.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	a.monitoring = true
	a.add_to_group(&"slag_volume")
	a.set_meta(&"kind", kind)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	a.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.name = "Greybox"
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = (Color(1.0, 0.45, 0.15, 0.28) if kind == "shimmer" else Color(0.95, 0.28, 0.05, 0.72))
	mi.material_override = m
	a.add_child(mi)
	parent.add_child(a)
	return a


func _mat(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS.get(kind, Color(0.4, 0.4, 0.4))
		_mats[kind] = m
	return _mats[kind]


func _marker(parent: Node3D, nm: String, at: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	m.position = at
	parent.add_child(m)
	return m


func _chests() -> Node3D:
	var n := get_node_or_null("Chests") as Node3D
	if n == null:
		n = Node3D.new()
		n.name = "Chests"
		add_child(n)
	return n


func _kit_room(kit: Dictionary, id: String) -> Dictionary:
	for r: Dictionary in kit["room"]:
		if String(r["id"]) == id:
			return r
	return {}


func _has_tag(kit: Dictionary, id: String, tag: String) -> bool:
	var tags: Variant = _kit_room(kit, id).get("tags", [])
	return tags is Array and (tags as Array).has(tag)


func _side_dir(side: int) -> Vector3:
	match side:
		0:
			return Vector3(0, 0, -1)
		1:
			return Vector3(1, 0, 0)
		2:
			return Vector3(0, 0, 1)
		_:
			return Vector3(-1, 0, 0)


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


func _mesh_from_walk() -> NavigationMesh:
	# A single ribbon, vertices shared, the same way the Blightcoil joins its
	# pads. Separate quads do not link across a doorway. On a lava room the
	# ribbon follows the safe ring, not the molten hole.
	return _ribbon(_safe_points())


func _safe_points() -> Array[Vector3]:
	var pts: Array[Vector3] = [_pad_at + Vector3(0, 0.05, 0)]
	if layout.is_empty():
		pts.append(Vector3(0, 1.5, -14.5))
		pts.append(Vector3(0, 0.05, -16))
		return pts
	var rest := _room_index("rest")
	var ex := _room_index("exit")
	if rest < 0 or ex < 0:
		pts.append(exit_local())
		return pts
	var chain: Array = _chain(rest, ex)
	var arrived := -1
	for step in chain.size() - 1:
		var i := int(chain[step])
		var j := int(chain[step + 1])
		var depart := _side_between(i, j)
		if arrived >= 0 and arrived != depart:
			for p in _ring_points(rooms[i], arrived, depart):
				pts.append(p)
		else:
			pts.append(_door_point(rooms[i], depart))
		var arrive := (depart + 2) % 4
		pts.append(_door_point(rooms[j], arrive))
		arrived = arrive
	pts.append(exit_local() + Vector3(0, 0.05, 0))
	return pts


func _room_index(kind: String) -> int:
	for i in rooms.size():
		if String(rooms[i].get_meta(&"kind", "")) == kind:
			return i
	return -1


func _chain(a: int, b: int) -> Array:
	var prev := {a: -1}
	var q: Array = [a]
	while not q.is_empty() and not prev.has(b):
		var cur: int = q.pop_front()
		for e: Array in layout.get("edges", []):
			for k in 2:
				if int(e[k]) != cur:
					continue
				var nxt := int(e[1 - k])
				if prev.has(nxt):
					continue
				prev[nxt] = cur
				q.append(nxt)
	var chain: Array = []
	if not prev.has(b):
		return chain
	var c := b
	while c != -1:
		chain.push_front(c)
		c = int(prev[c])
	return chain


func _side_between(i: int, j: int) -> int:
	var rs: Array = layout["rooms"]
	var a: Vector2i = rs[i]["cell"]
	var b: Vector2i = rs[j]["cell"]
	var d := b - a
	if d.x > 0:
		return 1
	if d.x < 0:
		return 3
	if d.y > 0:
		return 2
	return 0


func _door_point(room: Node3D, side: int) -> Vector3:
	var sz: Vector2 = room.get_meta(&"size", Vector2(12, 12))
	var lava := bool(room.get_meta(&"lava", false))
	var horiz := side == 0 or side == 2
	var half := (sz.y if horiz else sz.x) * 0.5
	var inset := STRIP * 0.5 if lava else minf(2.2, half * 0.4)
	return room.position + _side_dir(side) * (half - inset) + Vector3(0, 0.05, 0)


func _ring_points(room: Node3D, from_side: int, to_side: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var side := from_side
	for _guard in 4:
		if side == to_side:
			break
		var nxt := (side + 1) % 4
		pts.append(_corner_point(room, side, nxt))
		side = nxt
	pts.append(_door_point(room, to_side))
	return pts


func _corner_point(room: Node3D, a: int, b: int) -> Vector3:
	var sz: Vector2 = room.get_meta(&"size", Vector2(12, 12))
	var lava := bool(room.get_meta(&"lava", false))
	var pair := [a, b]
	var ix := sz.x * 0.5 - (STRIP * 0.5 if lava else minf(2.2, sz.x * 0.2))
	var iz := sz.y * 0.5 - (STRIP * 0.5 if lava else minf(2.2, sz.y * 0.2))
	var x := ix if pair.has(1) else -ix
	var z := iz if pair.has(2) else -iz
	return room.position + Vector3(x, 0.05, z)


func _ribbon(pts: Array[Vector3]) -> NavigationMesh:
	var nm := _mesh_settings()
	var clean: Array[Vector3] = []
	for p in pts:
		if clean.is_empty() or clean[clean.size() - 1].distance_to(p) > 0.35:
			clean.append(p)
	if clean.size() < 2:
		return nm
	var verts := PackedVector3Array()
	var polys: Array[PackedInt32Array] = []
	var half := 1.05
	var first := clean[1] - clean[0]
	first.y = 0.0
	if first.length() < 0.05:
		first = Vector3(1, 0, 0)
	var s0 := Vector3(-first.z, 0, first.x).normalized() * half
	verts.append(clean[0] - s0)
	verts.append(clean[0] + s0)
	var i_l := 0
	var i_r := 1
	for i in clean.size() - 1:
		var step := clean[i + 1] - clean[i]
		step.y = 0.0
		if step.length() < 0.05:
			continue
		var side := Vector3(-step.z, 0, step.x).normalized() * half
		var base := verts.size()
		verts.append(clean[i + 1] + side)
		verts.append(clean[i + 1] - side)
		polys.append(PackedInt32Array([i_l, i_r, base, base + 1]))
		i_l = base + 1
		i_r = base
	nm.vertices = verts
	for poly in polys:
		nm.add_polygon(poly)
	return nm


func _path_in_lava(path: PackedVector3Array) -> bool:
	for p in path:
		for n in find_children("*", "Area3D", true, false):
			if not n.is_in_group(&"slag_volume"):
				continue
			if String(n.get_meta(&"kind", "")) != "lava":
				continue
			var area := n as Area3D
			var cs := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if cs == null or not (cs.shape is BoxShape3D):
				continue
			var h: Vector3 = (cs.shape as BoxShape3D).size * 0.5 - Vector3(0.15, 0.05, 0.15)
			if h.x <= 0.0 or h.y <= 0.0 or h.z <= 0.0:
				continue
			var lp: Vector3 = area.global_transform.affine_inverse() * p
			if absf(lp.x) < h.x and absf(lp.y) < h.y and absf(lp.z) < h.z:
				return true
	return false


func _cache_hash() -> String:
	var f := FileAccess.open(TOML, FileAccess.READ)
	var text := "" if f == null else f.get_as_text()
	return ("%s|%d|%d|%d" % [text, floor_no, seed_value, phase]).sha256_text()


func _read_cache(hashed: String) -> NavigationMesh:
	var man := cache_manifest_path()
	var mesh := cache_mesh_path()
	if not FileAccess.file_exists(man) or not ResourceLoader.exists(mesh):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(man))
	if not (parsed is Dictionary) or String(parsed.get("hash", "")) != hashed:
		return null
	return load(mesh) as NavigationMesh


func _write_cache(nm: NavigationMesh, hashed: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	var err := ResourceSaver.save(nm, cache_mesh_path())
	if err != OK:
		push_warning("Slagworks: nav cache save failed (%s)" % error_string(err))
		return
	var f := FileAccess.open(cache_manifest_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"hash": hashed, "polys": nm.get_polygon_count()}))


func _assign_nav(nm: NavigationMesh) -> void:
	_region.navigation_mesh = nm
	# The property alone does not upload polygons. The cavern does this too.
	NavigationServer3D.region_set_navigation_mesh(_region.get_rid(), nm)
	var map := _region.get_navigation_map()
	if map.is_valid():
		NavigationServer3D.map_set_edge_connection_margin(map, 3.0)
