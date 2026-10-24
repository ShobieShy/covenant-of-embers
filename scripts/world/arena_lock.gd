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


func drop() -> void:
	for c in get_children():
		c.queue_free()
		remove_child(c)
