class_name Gnawer
extends Enemy
## The Gnawer (BUILD_PLAN step 12, port of the archived C++ game/ai/gnawer.*, old step
## 23): a rat-sized "rusher" that notices the player, closes in and bites.
##
## State machine (next_state, a pure port of C++ nextGnawerState; one transition a tick):
##   Idle -> Detect      target within detect_range (8 m) and in line of sight;
##   Detect -> Chase     within aggro_range (6 m), or provoked (hit); walks (3 m/s) closer;
##   Detect -> Idle      out of detect range or sight;
##   Chase -> Attack     within attack_range (1 m); sprints (5.5 m/s), no sight needed;
##   Chase -> Idle       beyond detect_range, unless hunting (5 s after its last hit);
##   Attack -> Chase     beyond attack_range + 0.3 m;
##   any -> Knockback    while a > knockback_threshold (10) hit's push runs, then Attack/Chase;
##   any -> Dead         dead enemies stop thinking (terminal).
## In Attack it bites (attack_damage 3 Earth) at once and then every attack_cooldown (0.8 s =
## 48 ticks) while the target is within attack_range + 0.3 m and 1.2 m of height; a bite
## on an invulnerable (dashing) target is dodged but still spends the cooldown. Bites are
## emitted (`attacked`); step 13 applies them to the player's health.
##
## Movement: a CharacterBody3D (layer enemy, mask world + enemy: it never pushes or rides
## the player) moved by move_and_slide with gravity and a 0.25 m step-up, closing to 90 %
## of the bite range (0.9 m) and never into the 0.3 m player capsule. It follows a
## NavigationAgent3D path over the level's baked NavigationMesh (LevelNavigation), so it
## runs around walls; without a synced navmesh nearby it steers straight (sliding along
## walls). It turns toward where it goes at turn_rate_deg (540°/s; yaw 0 faces -Z).
## Knockback: a hit over knockback_threshold pushes it along the bolt's flattened
## direction, decaying linearly from knockback_strength over knockback_time (sampled
## mid-tick: 10 x 0.5 / 2 = 2.5 m), and provokes it (hunting for 5 s).
##
## Magewar reference (enemy_base.gd / enemy_mutant_rat.gd, read-only): the rat's numbers
## (Earth, contact 3, cooldown 0.8, detection 8, aggro 6, walk 3, sprint 5.5) and the base
## knockback (> 10 damage, strength 10, 0.5 s) are kept. Magewar's enemies have no AI loop
## at all (no state machine, the take_elemental_damage knockback is never called, the
## landfill navmesh is never baked): the brain is ours, reinterpreted from the C++ port.

signal attacked(gnawer: Gnawer, bite: Bite)
signal state_changed(gnawer: Gnawer, from: State, to: State)

enum State { IDLE, DETECT, CHASE, ATTACK, KNOCKBACK, DEAD }
const STATE_NAMES: PackedStringArray = ["idle", "detect", "chase", "attack", "knockback", "dead"]

const ATTACK_SLACK := 0.3        ## m past attack_range before Attack drops back to Chase
const HUNT_TIME := 5.0           ## s it keeps chasing out of detect range after a hit
const BITE_HEIGHT := 1.2         ## max |target feet y - its feet y| for a bite
const PLAYER_RADIUS := 0.3       ## target capsule radius (Player)
const GRAVITY := 9.8
const STEP_UP := 0.25            ## m it can step up (C++ kStepUp)
const NAV_SNAP := 1.0            ## a path starting farther than this from it is someone else's

## What it senses this tick (C++ GnawerSenses).
class Senses:
	extends RefCounted
	var target_valid := false
	var distance := 0.0          ## horizontal, feet to feet
	var line_of_sight := false
	var provoked := false
	var hunting := false
	var knockback_left := 0.0
	var dead := false

## One bite (C++ EnemyAttack).
class Bite:
	extends RefCounted
	var damage := 0.0
	var element: ElementTable.Element = ElementTable.Element.EARTH
	var from := Vector3.ZERO     ## its feet
	var dodged := false
	var tick := 0

class Transition:
	extends RefCounted
	var from: State
	var to: State
	var distance := 0.0
	var tick := 0

var rusher: RusherDef
var state: State = State.IDLE
var target: Node3D               ## the Player (feet = global_position); null = none
var auto_tick := true            ## false in tests: tick() is called by hand
var ticks := 0
var attack_timer := 0.0
var hunt_left := 0.0
var knockback_left := 0.0
var knockback_dir := Vector3.ZERO
var provoked := false
var distance := 0.0
var travelled := 0.0             ## horizontal metres moved
var bites := 0
var dodged := 0
var knockbacks := 0
var steps_climbed := 0
var nav_ticks := 0               ## ticks steered by a navmesh path
var transitions: Array[Transition] = []
var attacks: Array[Bite] = []
var nav: NavigationAgent3D
var _vy := 0.0

func setup(d: EnemyDef) -> void:
	super.setup(d)
	rusher = d.rusher()
	collision_mask = 1 | (1 << (ENEMY_LAYER - 1))
	floor_snap_length = STEP_UP + 0.05
	nav = NavigationAgent3D.new()
	nav.name = "Nav"
	nav.path_desired_distance = 0.3
	nav.target_desired_distance = 0.3
	nav.path_max_distance = 2.0
	nav.avoidance_enabled = false
	add_child(nav)
	damaged.connect(_on_damaged)

static func state_name(s: State) -> String:
	return STATE_NAMES[s]

## C++ nextGnawerState: the state after `s` given senses `i` (one step).
static func next_state(s: State, r: RusherDef, i: Senses) -> State:
	if s == State.DEAD or i.dead:
		return State.DEAD
	if i.knockback_left > 0.0:
		return State.KNOCKBACK
	if not i.target_valid:
		return State.IDLE
	var dist := i.distance
	match s:
		State.KNOCKBACK:   # a hit always leaves it aggressive
			return State.ATTACK if dist <= r.attack_range else State.CHASE
		State.IDLE:
			if i.provoked:
				return State.CHASE
			return State.DETECT if dist <= r.detect_range and i.line_of_sight else State.IDLE
		State.DETECT:
			if i.provoked:
				return State.CHASE
			if dist > r.detect_range or not i.line_of_sight:
				return State.IDLE
			return State.CHASE if dist <= r.aggro_range else State.DETECT
		State.CHASE:   # a rusher keeps coming without sight; it gives up out of detect range
			if dist > r.detect_range and not i.hunting:
				return State.IDLE
			return State.ATTACK if dist <= r.attack_range else State.CHASE
		State.ATTACK:
			return State.CHASE if dist > r.attack_range + ATTACK_SLACK else State.ATTACK
	return State.DEAD

func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)

## Hit flash (Enemy) + one brain tick.
func tick(dt: float) -> void:
	super.tick(dt)
	think(dt)

func think(dt: float) -> void:
	if state == State.DEAD:
		return   # dead enemies stop thinking
	ticks += 1
	var before := state
	if dead or rusher == null:
		_set_state(State.DEAD, distance)
		velocity = Vector3.ZERO
		return
	attack_timer = maxf(0.0, attack_timer - dt)
	hunt_left = maxf(0.0, hunt_left - dt)

	# Sense.
	var s := Senses.new()
	s.target_valid = _target_valid()
	var feet := global_position
	var to := _flat(target.global_position - feet) if s.target_valid else Vector3.ZERO
	s.distance = to.length()
	distance = s.distance
	s.line_of_sight = s.target_valid and s.distance <= rusher.detect_range and sees(_target_eye())
	s.provoked = provoked
	s.hunting = hunt_left > 0.0
	s.knockback_left = knockback_left
	provoked = false

	# Decide.
	var next := next_state(before, rusher, s)
	_set_state(next, s.distance)

	# Act.
	var half_body := 0.5 * maxf(def.size.x, def.size.z)
	var stop_at := maxf(rusher.attack_range * 0.9, half_body + PLAYER_RADIUS + 0.05)
	var dir := to / s.distance if s.distance > 1e-4 else Vector3.ZERO
	var walk := 0.0
	var push := Vector3.ZERO
	match next:
		State.DETECT, State.CHASE, State.ATTACK:
			var speed := rusher.walk_speed if next == State.DETECT else rusher.sprint_speed
			walk = minf(speed * dt, maxf(0.0, s.distance - stop_at))
		State.KNOCKBACK:
			var mid := maxf(0.0, knockback_left - 0.5 * dt)
			var k := mid / rusher.knockback_time if rusher.knockback_time > 0.0 else 0.0
			push = knockback_dir * (rusher.knockback_strength * k * dt)
			knockback_left = maxf(0.0, knockback_left - dt)
			if knockback_left < 1e-6:   # 0.5 - 30 x (1/60) leaves ~1e-16 in doubles: 30 ticks, as in C++
				knockback_left = 0.0

	# (1e-4 s slack: 0.8 - 48 x 1/60 is not exactly 0 in floats.)
	if next == State.ATTACK and attack_timer <= 1e-4 and s.distance <= rusher.attack_range + ATTACK_SLACK \
			and absf(target.global_position.y - feet.y) <= BITE_HEIGHT:
		_bite(feet)

	var move := Vector3.ZERO
	var face := dir
	if walk > 1e-6 and s.distance > 1e-4:
		face = _steer(dir)
		move = face * walk
	if next in [State.DETECT, State.CHASE, State.ATTACK] and face.length() > 1e-4:
		_turn_toward(face, rusher.turn_rate_deg * dt)
	_move(move + push, dt)
	travelled += _flat(global_position - feet).length()

func _bite(feet: Vector3) -> void:
	var b := Bite.new()
	b.damage = rusher.attack_damage
	b.element = def.affinity
	b.from = feet
	b.dodged = target.has_method(&"invulnerable") and bool(target.call(&"invulnerable"))
	b.tick = ticks
	if b.dodged:
		dodged += 1
	else:
		bites += 1
	attack_timer = rusher.attack_cooldown
	attacks.append(b)
	attacked.emit(self, b)

func _set_state(next: State, dist: float) -> void:
	if next == state:
		return
	var t := Transition.new()
	t.from = state
	t.to = next
	t.distance = dist
	t.tick = ticks
	transitions.append(t)
	var was := state
	state = next
	state_changed.emit(self, was, next)

func _target_valid() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree()

func _target_eye() -> Vector3:
	if target.has_method(&"eye_position"):
		return target.call(&"eye_position")
	return target.global_position + Vector3(0.0, 1.5, 0.0)

func eye_position() -> Vector3:
	return global_position + Vector3(0.0, def.size.y * 0.8, 0.0)

## Line of sight from its eye to `to`, blocked by world geometry only (layer 1).
func sees(to: Vector3) -> bool:
	var from := eye_position()
	if from.distance_to(to) < 1e-4:
		return true
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Where to go: the next corner of the navmesh path to the target, else straight at it.
func _steer(straight: Vector3) -> Vector3:
	if nav == null or not nav.is_inside_tree():
		return straight
	nav.target_position = target.global_position
	var next := nav.get_next_path_position()
	var path := nav.get_current_navigation_path()
	if path.size() < 2 or _flat(path[0] - global_position).length() > NAV_SNAP:
		return straight
	var d := _flat(next - global_position)
	if d.length() < 0.05:
		return straight
	nav_ticks += 1
	return d.normalized()

func _turn_toward(d: Vector3, max_deg: float) -> void:
	var want := rad_to_deg(atan2(-d.x, -d.z))
	var cur := rad_to_deg(rotation.y)
	var diff := clampf(fposmod(want - cur + 540.0, 360.0) - 180.0, -max_deg, max_deg)
	rotation.y = deg_to_rad(wrapf(cur + diff, -180.0, 180.0))

## Horizontal `delta` metres this tick (+ gravity), sliding on walls, stepping up ledges.
func _move(delta: Vector3, dt: float) -> void:
	_vy = 0.0 if is_on_floor() else _vy - GRAVITY * dt
	var start := global_position
	velocity = delta / dt + Vector3(0.0, _vy, 0.0) if dt > 0.0 else Vector3.ZERO
	move_and_slide()
	var want := delta.length()
	if want > 1e-5 and _flat(global_position - start).length() < 0.5 * want and is_on_wall():
		_try_step_up(_flat(delta))

func _try_step_up(motion: Vector3) -> bool:
	var up := Vector3(0.0, STEP_UP, 0.0)
	if test_move(global_transform, up):
		return false
	var raised := global_transform.translated(up)
	if test_move(raised, motion):
		return false
	global_position += up + motion
	move_and_collide(Vector3(0.0, -STEP_UP - 0.05, 0.0))
	steps_climbed += 1
	return true

## The push (C++ GnawerAI::onHit): provoked + hunting; over the threshold, knocked back.
func _on_damaged(_e: Enemy, h: SpellBolts.Hit) -> void:
	if dead or state == State.DEAD or rusher == null:
		return
	provoked = true
	hunt_left = HUNT_TIME
	if h.result == null or h.result.amount <= rusher.knockback_threshold:
		return
	if rusher.knockback_time <= 0.0 or rusher.knockback_strength <= 0.0:
		return
	var d := _flat(h.direction)
	if d.length() < 1e-4:
		d = _flat(global_position - h.point)
	if d.length() < 1e-4:
		d = Vector3(0.0, 0.0, 1.0)
	knockback_dir = d.normalized()
	knockback_left = rusher.knockback_time   # a new hit restarts it
	knockbacks += 1

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
