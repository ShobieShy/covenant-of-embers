class_name SpireFloor
extends Node3D
## Act V, the Inverted Spire. Checkpoints 19-22 are shelves over a kill void.
## Checkpoint 23 is the Storm Warden: the shelves fail, and the fall between
## them is the arena, not the kill line. The throat is a lit path, not a shell.
## Layout comes from data/labyrinth/spire.toml. The tower does not collide.

signal pad_reached(checkpoint: int, waystone_id: String)
signal home_requested

const FIRST := 19
const LAST := 23
const BOSS := "storm_warden"
const NAMES := {
	19: "Platforms",
	20: "Falls",
	21: "Wind",
	22: "Facets",
	23: "Warden",
}
const WAYSTONES := {
	19: "spire_platforms",
	20: "spire_falls",
	21: "spire_wind",
	22: "spire_facets",
	23: "spire_warden",
}
const ARENA := "res://scenes/labyrinth/spire_arena.tscn"

var floor_no := FIRST
var waystone_id := ""
var lit_path: Node3D
var _state: LabyrinthState
var _failing: Array[StaticBody3D] = []
var _age := 0.0
var _doc: Dictionary = {}


static func is_floor(n: int) -> bool:
	return n >= FIRST and n <= LAST


static func make(checkpoint: int, state: LabyrinthState) -> SpireFloor:
	var f := SpireFloor.new()
	f.floor_no = checkpoint
	f._state = state
	f.waystone_id = String(WAYSTONES.get(checkpoint, ""))
	f._build()
	return f


func _ready() -> void:
	KillPlane.stamp(self)
	_nav()
	call_deferred("_dress_stairs")


func _process(delta: float) -> void:
	_age += delta
	if floor_no == LAST and _age >= 8.0:
		fail_platforms()
	var wind := get_node_or_null("Wind") as Area3D
	if wind:
		for body in wind.get_overlapping_bodies():
			if body is Player:
				apply_wind(body as Player)


func start_pos() -> Vector3:
	var high := get_node_or_null("High") as StaticBody3D
	if high == null:
		return global_position + Vector3(0, 8.4, -8)
	return high.global_position + Vector3(0, _top_y(high) + 0.25, 0)


## A fall beside the lowest shelf crosses the kill line. A fall between the
## Warden's shelves stays above it: that drop is the arena.
func fall_kind(y: float) -> String:
	var line := float(get_meta(&"kill_line_y", -10000.0))
	return "kill" if y < line else "arena"


func fail_platforms() -> void:
	for b in _failing:
		var shape := b.get_node_or_null("Shape") as CollisionShape3D
		if shape:
			shape.disabled = true
		var shelf := b.get_node_or_null("Shelf")
		if shelf:
			shelf.visible = false


func note_boss_dead() -> void:
	if lit_path:
		lit_path.visible = true
	var marks := get_node_or_null("EnemySpawns")
	if marks:
		for c in marks.get_children():
			if String(c.get_meta(&"lab_boss", "")) == BOSS:
				c.queue_free()


func apply_wind(p: Player) -> void:
	# The host applies the shove. A client does not add it again.
	if Coop.is_client() or p == null:
		return
	p.velocity.x = wind_sign() * 6.0


func wind_sign() -> int:
	return -1 if int(Time.get_ticks_msec() / 3000.0) % 2 == 1 else 1


func _build() -> void:
	_doc = SpireKit.layout()
	for pad in _doc.get("pad", []):
		_platform(LevelToml.vec3(pad["at"]), LevelToml.vec3(pad["size"]), String(pad["name"]))
	for br in _doc.get("bridge", []):
		_bridge(br)
	if floor_no == 21:
		_wind_volume()
	_pad_trigger()
	var spawns := Node3D.new()
	spawns.name = "EnemySpawns"
	add_child(spawns)
	var low := _pad("Low")
	var low_top := _surface(low)
	if floor_no < LAST:
		var foe := "harpy" if floor_no % 2 == 1 else "storm_elemental"
		var stand := _surface(_pad("Nest")) if foe == "harpy" else _surface(_pad("Mid"))
		_marker(spawns, foe, stand + Vector3(0, 0.2, 0), false)
		var stairs := LabyrinthStairs.new()
		stairs.name = "StairsDown"
		stairs.dir = LabyrinthStairs.DOWN
		stairs.position = Vector3(low_top.x, low_top.y + 0.15, low_top.z + _half_z(low) - 1.4)
		add_child(stairs)
	else:
		_marker(spawns, BOSS, low_top + Vector3(0, 0.4, 0), true)
		lit_path = Node3D.new()
		lit_path.name = "LitPath"
		lit_path.position = Vector3(low_top.x, low_top.y, low_top.z + _half_z(low))
		lit_path.visible = _state != null and _state.bosses.has(BOSS)
		add_child(lit_path)
		var spot := Marker3D.new()
		spot.name = "WaystoneSpot"
		spot.position = low_top + Vector3(3.2, 0.1, 1.5)
		spot.set_meta(&"boss", BOSS)
		add_child(spot)
		if ResourceLoader.exists(ARENA):
			var arena := (load(ARENA) as PackedScene).instantiate()
			arena.name = "Arena"
			add_child(arena)
	SpireKit.dress(self, floor_no)


func _platform(at: Vector3, size: Vector3, nm: String) -> void:
	var body := StaticBody3D.new()
	body.name = nm
	body.position = at
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	if floor_no == LAST:
		_failing.append(body)


func _bridge(br: Dictionary) -> void:
	var a := _pad(String(br["a"]))
	var b := _pad(String(br["b"]))
	if a.is_empty() or b.is_empty():
		return
	var fr: Vector3 = SpireKit._lip(a, LevelToml.vec3(b["at"]))
	var to: Vector3 = SpireKit._lip(b, LevelToml.vec3(a["at"]))
	var delta := to - fr
	var length := delta.length()
	if length < 0.4:
		return
	var fwd := delta / length
	var side := Vector3.UP.cross(fwd)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := fwd.cross(side).normalized()
	var thick := 0.4
	var body := StaticBody3D.new()
	body.name = "Bridge"
	body.basis = Basis(side, up, -fwd)
	body.position = (fr + to) * 0.5 - up * (thick * 0.5)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(float(br["width"]), thick, length)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	if floor_no == LAST:
		_failing.append(body)


func _wind_volume() -> void:
	var mid := _surface(_pad("Mid"))
	var wind := Area3D.new()
	wind.name = "Wind"
	wind.position = mid + Vector3(0, 1.2, 0)
	wind.collision_layer = 0
	wind.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	wind.body_entered.connect(_on_wind)
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(40, 5, 24)
	ws.shape = wb
	wind.add_child(ws)
	add_child(wind)


func _pad_trigger() -> void:
	var low := _surface(_pad("Low"))
	var pad := Area3D.new()
	pad.name = "Pad"
	pad.position = low + Vector3(2, 0.6, 0)
	pad.collision_layer = 0
	pad.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	pad.body_entered.connect(_on_pad)
	var ps := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(2, 2, 2)
	ps.shape = pb
	pad.add_child(ps)
	add_child(pad)


func _marker(parent: Node3D, id: String, at: Vector3, boss: bool) -> void:
	var m := Marker3D.new()
	m.name = id
	m.position = at
	m.set_meta(&"enemy", id)
	m.set_meta(&"pad", floor_no)
	if boss:
		m.set_meta(&"lab_boss", id)
	parent.add_child(m)


func _pad(name: String) -> Dictionary:
	for pad in _doc.get("pad", []):
		if String(pad.get("name", "")) == name:
			return pad
	return {}


func _surface(pad: Dictionary) -> Vector3:
	if pad.is_empty():
		return Vector3.ZERO
	var at := LevelToml.vec3(pad["at"])
	var size := LevelToml.vec3(pad["size"])
	return at + Vector3(0, size.y * 0.5, 0)


func _half_z(pad: Dictionary) -> float:
	if pad.is_empty():
		return 4.0
	return LevelToml.vec3(pad["size"]).z * 0.5


func _top_y(body: StaticBody3D) -> float:
	var shape := body.get_node_or_null("Shape") as CollisionShape3D
	if shape and shape.shape is BoxShape3D:
		return (shape.shape as BoxShape3D).size.y * 0.5
	return 0.4


func _dress_stairs() -> void:
	var stairs := get_node_or_null("StairsDown")
	if stairs:
		SpireKit.hide_stair_box(stairs)


func _nav() -> void:
	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.cell_size = 0.4
	nm.agent_radius = 0.35
	nm.agent_height = 1.7
	var verts := PackedVector3Array()
	var polys: Array[PackedInt32Array] = []
	for pad in _doc.get("pad", []):
		_nav_pad(verts, polys, pad)
	for br in _doc.get("bridge", []):
		_nav_bridge(verts, polys, br)
	nm.vertices = verts
	for poly in polys:
		nm.add_polygon(poly)
	region.navigation_mesh = nm
	add_child(region)


func _nav_pad(verts: PackedVector3Array, polys: Array[PackedInt32Array], pad: Dictionary) -> void:
	var c := _surface(pad)
	var size := LevelToml.vec3(pad["size"])
	var hx := size.x * 0.5 - 0.45
	var hz := size.z * 0.5 - 0.45
	if hx < 0.4 or hz < 0.4:
		return
	var y := c.y + 0.08
	var b := verts.size()
	verts.append(Vector3(c.x - hx, y, c.z - hz))
	verts.append(Vector3(c.x + hx, y, c.z - hz))
	verts.append(Vector3(c.x + hx, y, c.z + hz))
	verts.append(Vector3(c.x - hx, y, c.z + hz))
	polys.append(PackedInt32Array([b, b + 1, b + 2, b + 3]))


func _nav_bridge(verts: PackedVector3Array, polys: Array[PackedInt32Array], br: Dictionary) -> void:
	var a := _pad(String(br["a"]))
	var b := _pad(String(br["b"]))
	if a.is_empty() or b.is_empty():
		return
	var fr: Vector3 = SpireKit._lip(a, LevelToml.vec3(b["at"])) + Vector3(0, 0.08, 0)
	var to: Vector3 = SpireKit._lip(b, LevelToml.vec3(a["at"])) + Vector3(0, 0.08, 0)
	var flat := Vector3(to.x - fr.x, 0, to.z - fr.z)
	if flat.length() < 0.2:
		return
	var side := Vector3(-flat.z, 0, flat.x).normalized() * 0.8
	var i0 := verts.size()
	verts.append(fr - side)
	verts.append(fr + side)
	verts.append(to + side)
	verts.append(to - side)
	polys.append(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 3]))


func _on_wind(body: Node) -> void:
	if body is Player:
		apply_wind(body as Player)


func _on_pad(body: Node) -> void:
	if body is Player:
		pad_reached.emit(floor_no, waystone_id)
		if floor_no == LAST and _state != null and _state.bosses.has(BOSS):
			home_requested.emit()
