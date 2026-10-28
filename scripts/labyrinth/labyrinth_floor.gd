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
var rooms: Array[Node3D] = []
var dressed := false  ## L3: Ember Art kit pieces placed (greybox meshes hidden)
var _mats := {}


## Builds floor `n` for `state` from `kit` (FloorGen.load_kit()).
static func build(kit: Dictionary, n: int, state: LabyrinthState) -> LabyrinthFloor:
	var f := LabyrinthFloor.new()
	f.name = "LabyrinthFloor"
	f.floor_no = n
	f.kit_id = String(kit["kit"]["id"])
	f.set_meta(&"level_id", "labyrinth")
	f.dressed = WarrensKit.available()
	if n == int(kit["kit"]["boss_floor"]):
		f._build_boss(state)
	else:
		f.layout = FloorGen.generate(kit, state.floor_seed(n))
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
		WarrensKit.dress_room(r, size, open, slot)
		WarrensKit.props(r, kind, size)
	rooms.append(r)
	return r


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
		match kind:
			"start":
				_marker(self, "PlayerStart", c + Vector3(0, 0, 0))
				_stairs(
					"StairsUp", LabyrinthStairs.UP, c + Vector3(-sz.x / 2 + 2.0, 0, -sz.y / 2 + 2.0)
				)
			"exit":
				_stairs("StairsDown", LabyrinthStairs.DOWN, c)
			"rest":
				_shrine(c)


func _build_boss(state: LabyrinthState) -> void:
	# Handmade boss floor (plan section 6): an entry room, a corridor, the arena. L3 dresses
	# it and adds the Goblin King; the waystone stands once his kill is in the save.
	var entry := _room(
		"Room0_boss_entry", "start", Vector3.ZERO, Vector2(14, 14), [0] as Array[int], 24.0
	)
	_marker(self, "PlayerStart", entry.position)
	_stairs("StairsUp", LabyrinthStairs.UP, Vector3(-5, 0, 5))
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
	_marker(self, "BossSpawn", arena.position + Vector3(0, 0, -8))
	var w := _marker(self, "WaystoneSpot", arena.position + Vector3(6, 0, 10))
	w.set_meta(&"boss", boss_id())
	if state and state.bosses.has(boss_id()):
		w.set_meta(&"active", true)


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
