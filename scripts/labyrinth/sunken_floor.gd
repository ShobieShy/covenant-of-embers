class_name SunkenFloor
extends Node3D
## Act IV, The Sunken Ruins. Checkpoints 14-17 walk the painted galleries.
## Checkpoint 18 is the nave: the Drowned Choir, then a waystone and the coral
## sarcophagus. Breath drains while a body stands in the flood. The plan comes
## from data/labyrinth/sunken.toml. Floors 1-13 are not built here.

signal pad_reached(checkpoint: int, waystone_id: String)
signal home_requested
signal spire_descend

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
var routes: Array[PackedVector3Array] = []
var spawn_local := Vector3(0, 1.7, -16)
var pad_local := Vector3(0, 1.7, 16)
var exit_local := Vector3(0, 1.7, 18)
var enemy_local := Vector3(0, 1.7, 4)
var boss_local := Vector3(0, 1.7, 6)
var sarcophagus_local := Vector3(0, 1.7, 12)
var waystone_local := Vector3(2.2, 1.7, 16)
var door_local := Vector3(-2.2, 1.7, 14)
var bell_at := Vector3(-84, 1.7, 0)
var bell_north := Vector3(-84, 1.7, -36)
var _state: LabyrinthState
var water: Area3D
var sarcophagus: Node3D
var _region: LevelNavigation
var _wet: Array[Player] = []


static func is_floor(n: int) -> bool:
	return n >= FIRST and n <= LAST


static func make(checkpoint: int, state: LabyrinthState) -> SunkenFloor:
	var f := SunkenFloor.new()
	f.floor_no = checkpoint
	f._state = state
	f.waystone_id = String(WAYSTONES.get(checkpoint, ""))
	f._build()
	return f


func _ready() -> void:
	KillPlane.stamp(self)
	_hide_stair_block()
	if _region and is_inside_tree():
		var map := _region.get_navigation_map()
		if map.is_valid():
			NavigationServer3D.map_set_edge_connection_margin(map, 5.0)


func _physics_process(delta: float) -> void:
	if _wet.is_empty():
		return
	for p in _wet:
		if is_instance_valid(p):
			drown(p, delta)


func start_pos() -> Vector3:
	return to_global(spawn_local)


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


func ensure_nav() -> void:
	if _region != null and _region.navigation_mesh != null and _region.navigation_mesh.get_polygon_count() > 0:
		return
	_region = LevelNavigation.new()
	_region.name = "Navigation"
	_region.bake_on_ready = false
	_region.navigation_mesh = _authored_nav()
	add_child(_region)


func path_reaches(to_local: Vector3) -> bool:
	if _region == null or _region.navigation_mesh == null:
		return false
	var map := _region.get_navigation_map()
	if not map.is_valid():
		return false
	NavigationServer3D.map_set_edge_connection_margin(map, 5.0)
	NavigationServer3D.map_force_update(map)
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	var lift := Vector3(0, 0.45, 0)
	var path := NavigationServer3D.map_get_path(map, to_global(pad_local) + lift, to_global(to_local) + lift, true)
	if path.size() < 2:
		return false
	return path[path.size() - 1].distance_to(to_global(to_local) + lift) < 3.0


func _build() -> void:
	SunkenLayout.dress(self)
	_flood()
	_bell(bell_at, "AirBell")
	if bell_north != Vector3.ZERO:
		_bell(bell_north, "AirBellNorth")
	var pad := Area3D.new()
	pad.name = "Pad"
	pad.position = pad_local
	pad.collision_layer = 0
	pad.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	pad.body_entered.connect(_on_pad)
	var ps := CollisionShape3D.new()
	var pb := BoxShape3D.new()
	pb.size = Vector3(3.0, 2.4, 3.0)
	ps.shape = pb
	ps.position.y = 1.0
	pad.add_child(ps)
	add_child(pad)
	var spawns := Node3D.new()
	spawns.name = "EnemySpawns"
	add_child(spawns)
	if floor_no < LAST:
		_marker(spawns, "drowned_cultist", enemy_local, false)
		var stairs := LabyrinthStairs.new()
		stairs.name = "StairsDown"
		stairs.dir = LabyrinthStairs.DOWN
		stairs.position = exit_local
		add_child(stairs)
	else:
		_marker(spawns, BOSS, boss_local, true)
		sarcophagus = Node3D.new()
		sarcophagus.name = "CoralSarcophagus"
		sarcophagus.position = sarcophagus_local
		sarcophagus.visible = _state != null and _state.bosses.has(BOSS)
		var beam := MeshInstance3D.new()
		beam.mesh = SunkenMeshes.doorway_glow()
		var glow := StandardMaterial3D.new()
		glow.albedo_color = Color(0.65, 0.3, 1.0)
		glow.emission_enabled = true
		glow.emission = Color(0.6, 0.25, 0.95)
		glow.emission_energy_multiplier = 3.0
		beam.material_override = glow
		beam.position = Vector3(0, 0.2, 0)
		beam.scale = Vector3(0.6, 2.4, 0.6)
		sarcophagus.add_child(beam)
		add_child(sarcophagus)
		var spot := Marker3D.new()
		spot.name = "WaystoneSpot"
		spot.position = waystone_local
		spot.set_meta(&"boss", BOSS)
		add_child(spot)
		var door := SlagProp.new()
		door.name = "SpireDoor"
		door.role = "spire"
		door.host = self
		door.position = door_local
		var ds := CollisionShape3D.new()
		var db := BoxShape3D.new()
		db.size = Vector3(1.6, 2.6, 0.6)
		ds.shape = db
		ds.position.y = 1.2
		door.add_child(ds)
		add_child(door)
	ensure_nav()


func _flood() -> void:
	var span := Vector2(200, 150)
	if has_meta(&"painted_span"):
		span = get_meta(&"painted_span")
	water = Area3D.new()
	water.name = "Flood"
	water.monitoring = true
	water.collision_layer = 0
	water.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(span.x * 0.8, 1.15, span.y * 0.78)
	ws.shape = wb
	ws.position = Vector3(0, 0.7, 0)
	water.add_child(ws)
	water.body_entered.connect(_on_water)
	water.body_exited.connect(_off_water)
	add_child(water)


func _marker(parent: Node3D, id: String, at: Vector3, boss: bool) -> void:
	var m := Marker3D.new()
	m.name = id
	m.position = at
	m.set_meta(&"enemy", id)
	m.set_meta(&"pad", floor_no)
	if boss:
		m.set_meta(&"lab_boss", id)
	parent.add_child(m)


func _bell(at: Vector3, nm: String) -> void:
	var bell := Area3D.new()
	bell.name = nm
	bell.position = at + Vector3(0, 1.1, 0)
	bell.collision_layer = 0
	bell.collision_mask = 1 << (Player.CHARACTER_LAYER - 1)
	bell.body_entered.connect(_on_bell)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 2.4
	cs.shape = sh
	bell.add_child(cs)
	add_child(bell)


func _on_water(body: Node) -> void:
	if body is Player and not _wet.has(body):
		_wet.append(body)


func _off_water(body: Node) -> void:
	if body is Player:
		_wet.erase(body)


func _on_bell(body: Node) -> void:
	if body is Player and (body as Player).breath != null:
		(body as Player).breath.refill()


func use_spire() -> bool:
	if _state == null or not _state.bosses.has(BOSS):
		return false
	spire_descend.emit()
	return true


func prop_line(role: String) -> String:
	if role != "spire":
		return ""
	if _state != null and _state.bosses.has(BOSS):
		return "The shaft becomes sky."
	return "The wind locks hold."


func _on_pad(body: Node) -> void:
	if body is Player:
		pad_reached.emit(floor_no, waystone_id)
		if floor_no == LAST and _state != null and _state.bosses.has(BOSS):
			home_requested.emit()


func _hide_stair_block() -> void:
	var stairs := get_node_or_null("StairsDown")
	if stairs == null:
		return
	for c in stairs.get_children():
		if c is CSGShape3D:
			(c as CSGShape3D).visible = false


func _authored_nav() -> NavigationMesh:
	var verts: Array[Vector3] = []
	var polys: Array[PackedInt32Array] = []
	for route in routes:
		_add_ribbon(verts, polys, route, 2.15)
	var packed := PackedVector3Array()
	packed.resize(verts.size())
	for i in verts.size():
		packed[i] = verts[i]
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 45.0
	nm.vertices = packed
	for poly in polys:
		nm.add_polygon(poly)
	return nm


func _add_ribbon(verts: Array[Vector3], polys: Array[PackedInt32Array], pts: PackedVector3Array, half: float) -> void:
	var clean: Array[Vector3] = []
	for p in pts:
		var q := Vector3(p.x, p.y + 0.08, p.z)
		if clean.is_empty() or clean[clean.size() - 1].distance_to(q) > 0.4:
			clean.append(q)
	if clean.size() < 2:
		return
	var first := clean[1] - clean[0]
	first.y = 0.0
	if first.length() < 0.05:
		first = Vector3(1, 0, 0)
	var side0 := Vector3(-first.z, 0, first.x).normalized() * half
	var i_l := verts.size()
	verts.append(clean[0] - side0)
	var i_r := verts.size()
	verts.append(clean[0] + side0)
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
