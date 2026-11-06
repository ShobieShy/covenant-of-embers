class_name ArenaLock
extends Node3D
## The Filth's arena lock (BUILD_PLAN step 57 follow-up): when the boss wave starts, a
## ring of slag walls rises around the wave trigger so neither side can leave; they drop
## when the waves are done. Plain boxes on the world layer (1), no assets needed.

const SEGMENTS := 16
const HEIGHT := 4.0
const THICK := 0.6
const MARGIN := 1.5  ## beyond the trigger radius
const COLOR := Color(0.45, 0.22, 0.1)

var center := Vector3.ZERO
var radius := 10.0
var wave_id := ""


static func attach(spawner: EnemySpawner, id: String) -> ArenaLock:
	var a := ArenaLock.new()
	a.name = "ArenaLock"
	a.wave_id = id
	a.center = spawner.trigger_center
	a.radius = spawner.trigger_radius + MARGIN
	spawner.add_child(a)
	spawner.wave_started.connect(a._on_wave_started)
	spawner.waves_completed.connect(a.drop)
	return a


func raised() -> bool:
	return get_child_count() > 0


func _on_wave_started(_i: int, id: String) -> void:
	if id == wave_id:
		raise()


func raise() -> void:
	if raised():
		return
	_fit_radius()
	var seg_len := TAU * radius / SEGMENTS + 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = COLOR * 0.4
	for i in SEGMENTS:
		var ang := TAU * i / SEGMENTS
		var b := StaticBody3D.new()
		b.collision_layer = 1
		b.collision_mask = 0
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(seg_len, HEIGHT, THICK)
		cs.shape = box
		b.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = box.size
		bm.material = mat
		mi.mesh = bm
		b.add_child(mi)
		add_child(b)
		b.global_position = center + Vector3(sin(ang) * radius, HEIGHT * 0.5, cos(ang) * radius)
		b.global_rotation = Vector3(0, ang, 0)
	print("[arena] walls up (r %.1f)" % radius)
	_watch_boss()


## The walls also drop when the wave's boss dies: a wave gnawer turned ally and back again
## must not keep the ring up after the Filth is dead.
func _watch_boss() -> void:
	var sp := get_parent()
	if sp == null:
		return
	for c in sp.get_children():
		_watch(c)
	if not sp.child_entered_tree.is_connected(_watch):
		sp.child_entered_tree.connect(_watch)  # the boss spawns after the wave's delay


func _watch(c: Node) -> void:
	if c is Enemy and (c as Enemy).is_boss() and not (c as Enemy).died.is_connected(_on_boss_died):
		(c as Enemy).died.connect(_on_boss_died)


func _on_boss_died(_a: Variant = null, _b: Variant = null) -> void:
	if raised():
		print("[arena] walls down (boss dead)")
	drop.call_deferred()


## The ring encloses the player and the live wave (the Filth on its ledge, a gnawer still
## in that wave). Marker packs earlier in the valley stay outside, or the ring would
## stretch back over the whole trench and cover the north road.
func _fit_radius() -> void:
	if not is_inside_tree():
		return
	var fit := radius
	var sp := get_parent() as EnemySpawner
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		var p3 := n as Node3D
		if p3 == null:
			continue
		var poff := p3.global_position - center
		fit = maxf(fit, Vector2(poff.x, poff.z).length() + MARGIN)
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or not e.alive() or sp == null or not sp.is_ancestor_of(e):
			continue
		if not sp.wave_alive.has(e):
			continue
		var off := e.global_position - center
		fit = maxf(fit, Vector2(off.x, off.z).length() + MARGIN)
	radius = fit


func drop() -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
