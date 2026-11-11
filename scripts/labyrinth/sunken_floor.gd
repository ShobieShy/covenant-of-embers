class_name SunkenFloor
extends Node3D
## Act IV, The Sunken Ruins. Checkpoints 14-17 are a flooded hall with a raised
## air path. Checkpoint 18 is the nave: the Drowned Choir, then a waystone and
## the coral sarcophagus. Breath drains in the water. Floors 1-13 are not built here.

signal pad_reached(checkpoint: int, waystone_id: String)
signal home_requested

const FIRST := 14
const LAST := 18
const BOSS := "drowned_choir"
const NAMES := {
	14: "Gallery",
	15: "Pocket",
	16: "Murals",
	17: "Spire",
	18: "Nave",
}
const WAYSTONES := {
	14: "sunken_gallery",
	15: "sunken_pocket",
	16: "sunken_murals",
	17: "sunken_spire",
	18: "sunken_nave",
}

var floor_no := FIRST
var waystone_id := ""
var _state: LabyrinthState
var water: Area3D
var sarcophagus: Node3D


static func is_floor(n: int) -> bool:
	return n >= FIRST and n <= LAST


static func make(checkpoint: int, state: LabyrinthState) -> SunkenFloor:
	var f := SunkenFloor.new()
	f.floor_no = checkpoint
	f._state = state
	f.waystone_id = String(WAYSTONES.get(checkpoint, ""))
	f._build()
	return f


func start_pos() -> Vector3:
	return global_position + Vector3(0, 1.7, -16)


func pad_global() -> Vector3:
	var pad := get_node_or_null("Pad") as Node3D
	return pad.global_position if pad else start_pos()


## One second in the water. Breath is the leash. Empty Breath costs health.
func drown(p: Player, dt: float) -> void:
	if p == null or p.breath == null:
		return
	p.breath.tick(true, dt)
	if p.breath.value <= 0.0:
		p.hurt_health(8.0 * dt)


func note_boss_dead() -> void:
	if sarcophagus:
		sarcophagus.visible = true
	var marks := get_node_or_null("EnemySpawns")
	if marks:
		for c in marks.get_children():
			if String(c.get_meta(&"lab_boss", "")) == BOSS:
				c.queue_free()


func _build() -> void:
	var deck := StaticBody3D.new()
	deck.name = "AirPath"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.4, 36.0)
	shape.shape = box
	shape.position = Vector3(0, 1.5, 0)
	deck.add_child(shape)
	add_child(deck)
	water = Area3D.new()
	water.name = "Flood"
	water.monitoring = true
	water.collision_layer = 0
	water.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(14.0, 1.4, 40.0)
	ws.shape = wb
	ws.position = Vector3(0, 0.7, 0)
	water.add_child(ws)
	water.body_entered.connect(_on_water)
	add_child(water)
	_bell(Vector3(-1.2, 1.7, -8))
	var pad := Area3D.new()
	pad.name = "Pad"
	pad.position = Vector3(0, 1.7, 16)
	pad.collision_layer = 0
	pad.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	pad.body_entered.connect(_on_pad)
	var ps := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(2.0, 2.0, 2.0)
	ps.shape = pb
	pad.add_child(ps)
	add_child(pad)
	var spawns := Node3D.new()
	spawns.name = "EnemySpawns"
	add_child(spawns)
	if floor_no < LAST:
		_marker(spawns, "drowned_cultist", Vector3(0, 1.7, 4), false)
		var stairs := LabyrinthStairs.new()
		stairs.name = "StairsDown"
		stairs.dir = LabyrinthStairs.DOWN
		stairs.position = Vector3(0, 1.7, 18)
		add_child(stairs)
	else:
		_marker(spawns, BOSS, Vector3(0, 1.7, 6), true)
		sarcophagus = Node3D.new()
		sarcophagus.name = "CoralSarcophagus"
		sarcophagus.position = Vector3(0, 1.7, 12)
		sarcophagus.visible = _state != null and _state.bosses.has(BOSS)
		add_child(sarcophagus)
		var spot := Marker3D.new()
		spot.name = "WaystoneSpot"
		spot.position = Vector3(2.2, 1.7, 16)
		spot.set_meta(&"boss", BOSS)
		add_child(spot)


func _marker(parent: Node3D, id: String, at: Vector3, boss: bool) -> void:
	var m := Marker3D.new()
	m.name = id
	m.position = at
	m.set_meta(&"enemy", id)
	m.set_meta(&"pad", floor_no)
	if boss:
		m.set_meta(&"lab_boss", id)
	parent.add_child(m)


func _bell(at: Vector3) -> void:
	var bell := Area3D.new()
	bell.name = "AirBell"
	bell.position = at
	bell.collision_layer = 0
	bell.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	bell.body_entered.connect(_on_bell)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.4
	cs.shape = sh
	bell.add_child(cs)
	add_child(bell)


func _on_water(body: Node) -> void:
	if body is Player:
		drown(body as Player, 1.0 / 60.0)


func _on_bell(body: Node) -> void:
	if body is Player and (body as Player).breath != null:
		(body as Player).breath.refill()


func _on_pad(body: Node) -> void:
	if body is Player:
		pad_reached.emit(floor_no, waystone_id)
		if floor_no == LAST and _state != null and _state.bosses.has(BOSS):
			home_requested.emit()
