class_name LabyrinthFloor
extends Node3D
## Labyrinth step L2 (LABYRINTH_PLAN sections 6-7): one floor built as greybox from the
## FloorGen layout. Each room sits at its slot (cell x kit slot metres, north = -z) with
## its kit size (swapped on odd rotations), walls on every side and a 4 m doorway plus a
## corridor to the slot edge on each side FloorGen.doors opens. Marker nodes for the
## runtime (Interiors): PlayerStart, StairsUp (back to the Breach crater), StairsDown (exit
## room), RestShrine (rest room; WaveSpawns/station is its craft station spot) and, on the
## handmade boss floor, WaystoneSpot. L3: WarrensKit dresses the greybox with Ember Art's
## Act I tile kit (batch 08a) when it is present; the throne hall is the floor 5 arena.
## L3: EnemySpawns holds the goblins (normal and elite rooms, seeded by the floor seed) and,
## on floor 5 until he is in the save, the Goblin King at BossSpawn (EnemySpawner reads it).

const H := 4.0
const WALL := 0.5
const DOOR := 4.0
const BOSS_ARENA := Vector2(36, 36)
const HALL := 32.0  ## L3: throne_hall.glb is 32 x 32 m
const COLORS := {
	"start": Color(0.45, 0.42, 0.36),
	"normal": Color(0.38, 0.33, 0.27),
	"elite": Color(0.5, 0.28, 0.22),
	"rest": Color(0.3, 0.42, 0.3),
	"secret": Color(0.35, 0.3, 0.45),
	"exit": Color(0.3, 0.35, 0.5),
	"boss": Color(0.45, 0.2, 0.18),
}

var floor_no := 1
var kit_id := ""
var layout := {}  ## FloorGen.generate output (normal floors), {} on the boss floor
var stair_row := 0  ## FloorGen stair_row: the exit's stair hole row (0 north, 1 south)
var rooms: Array[Node3D] = []
var dressed := false  ## L3: Ember Art kit pieces placed (greybox meshes hidden)
var _mats := {}
var _spawns: Node3D
var _state: LabyrinthState
## L5 perf: only rooms within CULL_DEPTH doorways of the viewer's room are drawn (meshes and
## their lights; collision stays). A doorway line of sight runs at most two rooms deep.
const CULL_DEPTH := 2
var cull := true
var viewer: Node3D  ## null: the first Player, else the viewport camera
var shown_from := -1  ## the room the visible set was last built around
## L3: the Act I goblin pool and how many a room kind gets (min, max).
const GOBLINS := ["goblin_grunt", "goblin_grunt", "goblin_archer", "goblin_shaman"]
const PACK := {"normal": [2, 3], "elite": [4, 5]}


## Builds floor `n` for `state` from `kit` (FloorGen.load_kit()).
static func build(kit: Dictionary, n: int, state: LabyrinthState) -> LabyrinthFloor:
	var f := LabyrinthFloor.new()
	f.name = "LabyrinthFloor"
	f.floor_no = n
	f.kit_id = String(kit["kit"]["id"])
	f.set_meta(&"level_id", "labyrinth")
	f.dressed = WarrensKit.available()
	f._state = state
	f._spawns = Node3D.new()
	f._spawns.name = "EnemySpawns"
	f.add_child(f._spawns)
	if n == int(kit["kit"]["boss_floor"]):
		f._build_boss(state)
	else:
		f.layout = FloorGen.generate(kit, state.floor_seed(n))
		f.stair_row = int(f.layout.get("stair_row", 0))
		f._build_rooms(kit)
	return f


static func is_boss_floor(kit: Dictionary, n: int) -> bool:
	return n == int(kit["kit"]["boss_floor"])


func _mat(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		var m := StandardMaterial3D.new()
		m.albedo_color = COLORS.get(kind, Color.GRAY)
		_mats[kind] = m
	return _mats[kind]


func _box(parent: Node3D, centre: Vector3, size: Vector3, kind: String, nm: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = nm
	b.position = centre
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(kind)
	b.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	parent.add_child(b)
	return b


func _marker(parent: Node3D, nm: String, at: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = nm
	m.position = at
	parent.add_child(m)
	return m


func _kit_room(kit: Dictionary, id: String) -> Dictionary:
	for r: Dictionary in kit["room"]:
		if String(r["id"]) == id:
			return r
	return {}


## One room: floor slab, walls with doorways on `open` sides, corridors to the slot edge.
func _room(
	nm: String, kind: String, centre: Vector3, size: Vector2, open: Array[int], slot: float
) -> Node3D:
	var r := Node3D.new()
	r.name = nm
	r.position = centre
	add_child(r)
	if kind == "exit" and dressed:
		_holed_slab(r, size, kind)
	else:
		_box(r, Vector3(0, -0.25, 0), Vector3(size.x, 0.5, size.y), kind, "Floor")
	for side in 4:
		var horiz := side == 0 or side == 2  # north/south walls run along x
		var length := size.x if horiz else size.y
		var sgn := -1.0 if side == 0 or side == 3 else 1.0
		var edge := (
			Vector3(0, H / 2, sgn * size.y / 2) if horiz else Vector3(sgn * size.x / 2, H / 2, 0)
		)
		if not open.has(side):
			var full := (
				Vector3(length + WALL, H, WALL) if horiz else Vector3(WALL, H, length + WALL)
			)
			_box(r, edge, full, kind, "Wall%d" % side)
			continue
		var seg := (length - DOOR) / 2.0
		for k in 2:
			var off := (DOOR / 2 + seg / 2) * (-1.0 if k == 0 else 1.0)
			var at := edge + (Vector3(off, 0, 0) if horiz else Vector3(0, 0, off))
			var sz := Vector3(seg + WALL, H, WALL) if horiz else Vector3(WALL, H, seg + WALL)
			_box(r, at, sz, kind, "Wall%d_%d" % [side, k])
		var run := slot / 2.0 - (size.y if horiz else size.x) / 2.0
		if run <= 0.01:
			continue
		var mid := (size.y if horiz else size.x) / 2.0 + run / 2.0
		var dir := Vector3(0, 0, sgn) if horiz else Vector3(sgn, 0, 0)
		var c := Node3D.new()
		c.name = "Corridor%d" % side
		r.add_child(c)
		var fl := Vector3(DOOR, 0.5, run) if horiz else Vector3(run, 0.5, DOOR)
		_box(c, dir * mid + Vector3(0, -0.25, 0), fl, kind, "Floor")
		for k in 2:
			var s := (DOOR / 2 + WALL / 2) * (-1.0 if k == 0 else 1.0)
			var at := (
				dir * mid + Vector3(0, H / 2, 0) + (Vector3(s, 0, 0) if horiz else Vector3(0, 0, s))
			)
			var sz := Vector3(WALL, H, run) if horiz else Vector3(run, H, WALL)
			_box(c, at, sz, kind, "Wall%d" % k)
	r.set_meta(&"kind", kind)
	r.set_meta(&"doors", open)
	if dressed:
		WarrensKit.dress_room(r, size, open, slot, kind == "exit", stair_row)
		WarrensKit.props(r, kind, size)
	rooms.append(r)
	return r


## L3: the exit room's slab with the 4 x 4 m stair hole cut out (Floor = the strip on the
## far side of the hole's row from the stair top, FloorS / FloorN the strip on the other side
## when there is one; FloorW / FloorE flank the hole) and a landing at the stair foot.
func _holed_slab(r: Node3D, size: Vector2, kind: String) -> void:
	var m := WarrensKit.MODULE
	var h := WarrensKit.stair_hole(size, stair_row)
	var z0 := -size.y / 2
	var n_len := h.z - m / 2 - z0  # slab north of the hole
	var s_len := size.y / 2 - (h.z + m / 2)  # slab south of the hole
	var big := "Floor"
	for part: Array in [[n_len, z0 + n_len / 2, "FloorN"], [s_len, size.y / 2 - s_len / 2, "FloorS"]]:
		if float(part[0]) <= 0.01:
			continue
		var nm := String(part[2])
		if (stair_row == 0 and nm == "FloorS") or (stair_row != 0 and nm == "FloorN"):
			nm = big
		_box(r, Vector3(0, -0.25, float(part[1])), Vector3(size.x, 0.5, float(part[0])), kind, nm)
	var w := h.x - m / 2 + size.x / 2
	_box(r, Vector3(-size.x / 2 + w / 2, -0.25, h.z), Vector3(w, 0.5, m), kind, "FloorW")
	var e := size.x / 2 - (h.x + m / 2)
	_box(r, Vector3(size.x / 2 - e / 2, -0.25, h.z), Vector3(e, 0.5, m), kind, "FloorE")
	var d := WarrensKit.STAIR_DEPTH
	_box(r, h + Vector3(0, -d - 0.25, 0), Vector3(m, 0.5, m), kind, "StairLanding")


func _build_rooms(kit: Dictionary) -> void:
	var slot := float(kit["kit"]["slot"])
	var rs: Array = layout["rooms"]
	for i in rs.size():
		var rd: Dictionary = rs[i]
		var kr := _kit_room(kit, String(rd["room"]))
		var sz := Vector2(float(kr["size"][0]), float(kr["size"][1]))
		if int(rd["rot"]) % 2 == 1:
			sz = Vector2(sz.y, sz.x)
		var cell: Vector2i = rd["cell"]
		var kind := String(rd["kind"])
		var r := _room(
			"Room%d_%s" % [i, rd["room"]],
			kind,
			Vector3(cell.x * slot, 0, cell.y * slot),
			sz,
			FloorGen.doors(layout, i),
			slot
		)
		r.set_meta(&"room", String(rd["room"]))
		r.set_meta(&"cell", cell)
		var c := r.position
		_goblins(r, kind, sz, i)
		if kind == "secret":  # L4: a chest a tier above the floor (main._lab_chests)
			var ch := _marker(_chests(), "secret%d" % i, c + Vector3(0, 0, -sz.y / 2 + 1.5))
			ch.set_meta(&"secret", true)
		match kind:
			"start":
				_marker(self, "PlayerStart", c + Vector3(0, 0, 0))
				_stairs(
					"StairsUp", LabyrinthStairs.UP, c + Vector3(-sz.x / 2 + 2.0, 0, -sz.y / 2 + 2.0)
				)
			"exit":
				# L3: dressed, the trigger sits at the stair's BottomExit (SW corner of the well)
				var h := WarrensKit.stair_hole(sz, stair_row)
				var foot := c + h + WarrensKit.stair_exit(stair_row) + Vector3(0, 0.4, 0)
				_stairs("StairsDown", LabyrinthStairs.DOWN, foot if dressed else c)
			"rest":
				_shrine(c)


func _process(_dt: float) -> void:
	if not cull or layout.is_empty() or not is_inside_tree():
		return
	var v := viewer
	if v == null:
		v = get_tree().get_first_node_in_group(Player.GROUP) as Node3D
	if v == null:
		v = get_viewport().get_camera_3d()
	if v != null:
		cull_to(v.global_position)


## The room nearest `world_pos` (by centre, in floor space).
func room_at(world_pos: Vector3) -> int:
	var p := to_local(world_pos)
	var best := -1
	var bd := INF
	for i in rooms.size():
		var d := Vector2(rooms[i].position.x - p.x, rooms[i].position.z - p.z).length_squared()
		if d < bd:
			bd = d
			best = i
	return best


## Rooms within CULL_DEPTH doorways of room `i` (FloorGen edges, secret ones too).
func near_rooms(i: int) -> Dictionary:
	var seen := {i: true}
	var ring := [i]
	for _d in CULL_DEPTH:
		var nxt := []
		for e: Array in layout.get("edges", []):
			for k in 2:
				var a := int(e[k])
				var b := int(e[1 - k])
				if a in ring and not seen.has(b):
					seen[b] = true
					nxt.append(b)
		ring = nxt
	return seen


## L5 (playtest bot): a walk from `from` to `to` (world) through the doorways: the room
## centres along the shortest room-graph path (doorways and corridors sit on the line
## between adjacent centres; secret edges are left out), then `to`. The handmade boss floor
## is a straight entry -> arena run.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var a := room_at(from)
	var b := room_at(to)
	if a < 0 or b < 0:
		return out
	var chain: Array = []
	if layout.is_empty():
		for i in range(a, b + (1 if b >= a else -1), 1 if b >= a else -1):
			chain.append(i)
	else:
		var prev := {a: -1}
		var q := [a]
		while not q.is_empty() and not prev.has(b):
			var cur: int = q.pop_front()
			for e: Array in layout.get("edges", []):
				if int(e[2]) == 1:
					continue
				for k in 2:
					if int(e[k]) == cur and not prev.has(int(e[1 - k])):
						prev[int(e[1 - k])] = cur
						q.append(int(e[1 - k]))
		if not prev.has(b):
			return out
		var c := b
		while c != -1:
			chain.push_front(c)
			c = int(prev[c])
	var start := 1
	if chain.size() > 1:  # off the centre line (a fight in a corner): back to the centre first
		var c0 := rooms[int(chain[0])].global_position
		var c1 := rooms[int(chain[1])].global_position
		var d := Vector2(c1.x - c0.x, c1.z - c0.z).normalized()
		var r := Vector2(from.x - c0.x, from.z - c0.z)
		if absf(r.cross(d)) > 1.5:
			start = 0
	for i in chain.slice(start):
		var p := rooms[int(i)].global_position
		out.append(Vector3(p.x, from.y, p.z))
	out.append(to)
	return out


## Shows the rooms near the viewer's room, hides the rest; returns how many are shown.
func cull_to(world_pos: Vector3) -> int:
	var i := room_at(world_pos)
	if i < 0:
		return rooms.size()
	var near := near_rooms(i)
	if i != shown_from:
		shown_from = i
		for j in rooms.size():
			rooms[j].visible = near.has(j)
	return near.size()


## L4: the Chests marker group (created on first use).
func _chests() -> Node3D:
	var n := get_node_or_null(^"Chests") as Node3D
	if n == null:
		n = Node3D.new()
		n.name = "Chests"
		add_child(n)
	return n


func _build_boss(state: LabyrinthState) -> void:
	# Handmade boss floor (plan section 6): an entry room, a corridor, the arena. L3 dresses
	# it and adds the Goblin King; the waystone stands once his kill is in the save.
	var entry := _room(
		"Room0_boss_entry", "start", Vector3.ZERO, Vector2(14, 14), [0] as Array[int], 24.0
	)
	_marker(self, "PlayerStart", entry.position)
	_stairs("StairsUp", LabyrinthStairs.UP, Vector3(-5, 0, 5))
	_shrine(entry.position + Vector3(-2, 0, -3))  # QA-5: the rest room before the arena (plan 7)
	var hall := WarrensKit.throne_hall() if dressed else null
	var arena: Node3D
	if hall:
		# The 32 m throne hall (its own walls, dais and collision); its south door meets the
		# entry corridor at z = -12.
		arena = Node3D.new()
		arena.name = "Room1_boss_arena"
		arena.position = Vector3(0, 0, -12 - HALL / 2)
		add_child(arena)
		arena.add_child(hall)
		arena.set_meta(&"kind", "boss")
		rooms.append(arena)
	else:
		arena = _room(
			"Room1_boss_arena", "boss", Vector3(0, 0, -30), BOSS_ARENA, [2] as Array[int], 24.0
		)
	var bs := _marker(self, "BossSpawn", arena.position + Vector3(0, 0, -8))
	if not (state and state.bosses.has(boss_id())):
		var k := _marker(_spawns, "GoblinKing", bs.position)
		k.set_meta(&"enemy", boss_id())
		k.set_meta(&"lab_boss", boss_id())
		k.rotation.y = PI  # faces the south door (+z): yaw 0 faces -z
	var w := _marker(self, "WaystoneSpot", arena.position + Vector3(6, 0, 10))
	w.set_meta(&"boss", boss_id())
	if state and state.bosses.has(boss_id()):
		w.set_meta(&"active", true)


## L3: a room's goblin pack at seeded spots inside it (one metre clear of the walls); an
## elite room's pack stays dead once its elites are in the save (marker meta lab_elite).
func _goblins(r: Node3D, kind: String, sz: Vector2, i: int) -> void:
	if not PACK.has(kind):
		return
	var id := String(r.name)
	if kind == "elite" and _state and _state.elite_dead(floor_no, id):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([_state.floor_seed(floor_no) if _state else floor_no, i, "goblins"])
	var n := rng.randi_range(int(PACK[kind][0]), int(PACK[kind][1]))
	for k in n:
		var at := Vector3(
			rng.randf_range(-sz.x / 2 + 2.0, sz.x / 2 - 2.0),
			0,
			rng.randf_range(-sz.y / 2 + 2.0, sz.y / 2 - 2.0)
		)
		var m := _marker(_spawns, "%s_g%d" % [id, k], r.position + at)
		m.set_meta(&"enemy", GOBLINS[rng.randi() % GOBLINS.size()])
		m.rotation.y = rng.randf() * TAU
		if kind == "elite":
			m.set_meta(&"lab_elite", id)


func boss_id() -> String:
	return "goblin_king"


func _stairs(nm: String, dir: int, at: Vector3) -> void:
	var s := LabyrinthStairs.new()
	s.name = nm
	s.dir = dir
	s.position = at
	add_child(s)


func _shrine(at: Vector3) -> void:
	var s := RestShrine.new()
	s.name = "RestShrine"
	s.position = at
	add_child(s)
	var ws := Node3D.new()
	ws.name = "WaveSpawns"
	add_child(ws)
	var st := _marker(ws, "station", at + Vector3(3, 0, 0))
	if dressed:
		WarrensKit.bench(st, Vector3(0, 0, 1.2))


func start_pos() -> Vector3:
	var m := get_node_or_null("PlayerStart") as Node3D
	return m.global_position if m else global_position
