class_name Scorchling
extends Gnawer
## Ember Scorchling (BUILD_PLAN step 54, PLAN Cinderkin role): ai kind "ranged". The
## Gnawer brain and movement, but it stops at ~90 % of its attack_range (7 m) and lobs
## embers instead of biting:
##   * in Attack with the cooldown ready and the target in range and sight, it fires an
##     Ember (a simulated projectile, projectile_speed m/s at the target's chest);
##   * an ember that comes within EMBER_HIT m of the target lands as a Bite (attack_damage,
##     Fire; dodged during dash i-frames), or burns out after EMBER_LIFE s / on a wall;
##   * inside min_range it backs away from the target while still shooting;
##   * under flee_below of its max health it flees (sprint away, no shots) until it is
##     beyond detect_range.
## Magewar reference (enemy_ember_scorchling.gd, read-only): Fire, level 2, xp 8,
## contact 4.5, cooldown 0.65, detection 9, aggro 7, walk 2.8, sprint 6. Magewar's
## Scorchling is a melee pest with no AI loop; the ranged lob + flee is plan design
## (PLAN Cinderkin), so the cooldown is stretched to 1.6 s for a dodgeable volley.

const EMBER_HIT := 0.6  ## m from the target's chest
const EMBER_LIFE := 2.0  ## s


class Ember:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var age := 0.0
	var done := false


var embers: Array[Ember] = []
var shots := 0
var fleeing := false
var flee_ticks := 0


func reset(xform: Variant = null) -> void:
	super.reset(xform)
	embers.clear()
	fleeing = false


func health_fraction() -> float:
	return health / def.max_health if def and def.max_health > 0.0 else 0.0


func think(dt: float) -> void:
	_tick_embers(dt)
	if state == State.DEAD or dead:
		super.think(dt)
		return
	fleeing = rusher.flee_below > 0.0 and health_fraction() < rusher.flee_below and _target_valid()
	var away := Vector3.ZERO
	if _target_valid():
		away = _flat(global_position - target.global_position)
	if fleeing and away.length() < rusher.detect_range:
		ticks += 1
		flee_ticks += 1
		var d := away.normalized() if away.length() > 1e-4 else Vector3(0, 0, 1)
		_turn_toward(d, rusher.turn_rate_deg * dt)
		_move(d * rusher.sprint_speed * dt, dt)
		return
	super.think(dt)
	if state == State.ATTACK and rusher.min_range > 0.0 and away.length() < rusher.min_range:
		var d := away.normalized() if away.length() > 1e-4 else Vector3(0, 0, 1)
		_move(d * rusher.walk_speed * dt, dt)


func _in_reach(dist: float, feet: Vector3) -> bool:
	return dist <= rusher.attack_range + ATTACK_SLACK and absf(target.global_position.y - feet.y) <= 4.0


func _start_attack(_feet: Vector3) -> void:
	if not sees(_target_eye()):
		return
	attack_timer = rusher.attack_cooldown
	var e := Ember.new()
	e.pos = eye_position()
	var aim := _target_eye() - Vector3(0.0, 0.4, 0.0)
	e.vel = (aim - e.pos).normalized() * rusher.projectile_speed
	embers.append(e)
	shots += 1


func _tick_embers(dt: float) -> void:
	for e in embers:
		if e.done:
			continue
		e.age += dt
		var nxt := e.pos + e.vel * dt
		if is_inside_tree():
			var q := PhysicsRayQueryParameters3D.create(e.pos, nxt, 1, [get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				e.done = true
				continue
		e.pos = nxt
		if _target_valid() and e.pos.distance_to(_target_eye() - Vector3(0.0, 0.4, 0.0)) <= EMBER_HIT:
			e.done = true
			_land(global_position)
		elif e.age >= EMBER_LIFE:
			e.done = true
	embers = embers.filter(func(x: Ember) -> bool: return not x.done)
