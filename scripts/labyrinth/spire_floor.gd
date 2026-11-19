class_name SpireFloor
extends Node3D
## Act V, the Inverted Spire. Checkpoints 19-22 are platforms over a kill void.
## Checkpoint 23 is the Storm Warden: the platforms fail, and the fall between
## them is the arena, not the kill line. The throat is a lit path, not a shell.

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

var floor_no := FIRST
var waystone_id := ""
var lit_path: Node3D
var _state: LabyrinthState
var _failing: Array[StaticBody3D] = []
var _age := 0.0


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
	return global_position + Vector3(0, 8.4, -8)


## A fall beside the lowest platform crosses the kill line. A fall between the
## Warden's platforms stays above it: that drop is the arena.
func fall_kind(y: float) -> String:
	var line := float(get_meta(&"kill_line_y", -10000.0))
	return "kill" if y < line else "arena"


func fail_platforms() -> void:
	for b in _failing:
		var shape := b.get_node_or_null("Shape") as CollisionShape3D
		if shape:
			shape.disabled = true


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
	_platform(Vector3(0, 8, -8), Vector3(6, 0.4, 6), "High")
	_platform(Vector3(0, 4, 0), Vector3(6, 0.4, 6), "Mid")
	_platform(Vector3(0, 0, 8), Vector3(8, 0.4, 8), "Low")
	if floor_no == 21:
		var wind := Area3D.new()
		wind.name = "Wind"
		wind.position = Vector3(0, 4.6, 0)
		wind.collision_layer = 0
		wind.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
		wind.body_entered.connect(_on_wind)
		var ws := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(10, 2, 6)
		ws.shape = wb
		wind.add_child(ws)
		add_child(wind)
	var pad := Area3D.new()
	pad.name = "Pad"
	pad.position = Vector3(2, 0.6, 8)
	pad.collision_layer = 0
	pad.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	pad.body_entered.connect(_on_pad)
	var ps := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(2, 2, 2)
	ps.shape = pb
	pad.add_child(ps)
	add_child(pad)
	var spawns := Node3D.new()
	spawns.name = "EnemySpawns"
	add_child(spawns)
	if floor_no < LAST:
		var foe := "harpy" if floor_no % 2 == 1 else "storm_elemental"
		_marker(spawns, foe, Vector3(0, 4.4, 0), false)
		var stairs := LabyrinthStairs.new()
		stairs.name = "StairsDown"
		stairs.dir = LabyrinthStairs.DOWN
		stairs.position = Vector3(0, 0.4, 11)
		add_child(stairs)
	else:
		_marker(spawns, BOSS, Vector3(0, 8.4, -8), true)
		lit_path = Node3D.new()
		lit_path.name = "LitPath"
		lit_path.position = Vector3(0, -2, 12)
		lit_path.visible = _state != null and _state.bosses.has(BOSS)
		add_child(lit_path)
		var spot := Marker3D.new()
		spot.name = "WaystoneSpot"
		spot.position = Vector3(2, 0.4, 8)
		spot.set_meta(&"boss", BOSS)
		add_child(spot)


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


func _marker(parent: Node3D, id: String, at: Vector3, boss: bool) -> void:
	var m := Marker3D.new()
	m.name = id
	m.position = at
	m.set_meta(&"enemy", id)
	m.set_meta(&"pad", floor_no)
	if boss:
		m.set_meta(&"lab_boss", id)
	parent.add_child(m)


func _on_wind(body: Node) -> void:
	if body is Player:
		apply_wind(body as Player)


func _on_pad(body: Node) -> void:
	if body is Player:
		pad_reached.emit(floor_no, waystone_id)
		if floor_no == LAST and _state != null and _state.bosses.has(BOSS):
			home_requested.emit()
