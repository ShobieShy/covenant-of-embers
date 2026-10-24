class_name LightSummon
extends Node3D
## A Light summon (BUILD_PLAN step 51): a glowing wisp that floats at its caster's shoulder
## for LIFETIME s and every BOLT_COOLDOWN s smites the nearest living, hostile enemy within
## RANGE for DAMAGE Light damage (Enemy.apply_damage, so kills count). One per caster:
## LightSummon.of(player) finds his live one. CC0: a primitive sphere mesh, no assets.

const LIFETIME := 30.0
const RANGE := 14.0
const DAMAGE := 6.0
const BOLT_COOLDOWN := 1.2
const OFFSET := Vector3(0.6, 2.0, 0.0)
const GROUP := &"light_summons"

var owner_player: Player
var age := 0.0
var cooldown := 0.0
var smites := 0
var auto_tick := true


static func of(p: Object) -> LightSummon:
	if p == null or not (p is Node) or not (p as Node).is_inside_tree():
		return null
	for n in (p as Node).get_tree().get_nodes_in_group(GROUP):
		var s := n as LightSummon
		if s and s.owner_player == p and not s.is_queued_for_deletion() and s.age < LIFETIME:
			return s
	return null


func _ready() -> void:
	add_to_group(GROUP)
	var m := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	m.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.5)
	mat.emission_energy_multiplier = 3.0
	m.material_override = mat
	add_child(m)


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


func tick(dt: float) -> void:
	age += dt
	if age >= LIFETIME or owner_player == null or not is_instance_valid(owner_player):
		queue_free()
		return
	global_position = owner_player.global_position + OFFSET
	cooldown = maxf(0.0, cooldown - dt)
	if cooldown > 1e-6:
		return
	var t := nearest_target()
	if t != null:
		cooldown = BOLT_COOLDOWN
		smites += 1
		t.apply_damage(DAMAGE, ElementTable.Element.LIGHT)


func nearest_target() -> Enemy:
	var best: Enemy = null
	var best_d := RANGE
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or not e.alive() or MagicEffects.is_ally(e):
			continue
		var d := e.global_position.distance_to(global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best
