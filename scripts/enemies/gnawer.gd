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

const ATTACK_SLACK := 0.3  ## m past attack_range before Attack drops back to Chase
const HUNT_TIME := 5.0  ## s it keeps chasing out of detect range after a hit
const BITE_HEIGHT := 1.2  ## max |target feet y - its feet y| for a bite
const ALLY_SEEK := 20.0  ## m: step 52 corrupted ally hunts enemies this close
const PLAYER_RADIUS := 0.3  ## target capsule radius (Player)
const GRAVITY := 9.8
const STEP_UP := 0.25  ## m it can step up (C++ kStepUp)
const NAV_SNAP := 1.0  ## a path starting farther than this from it is someone else's
const CAVERN_CHASE_M := 40.0  ## Act II: drop the chase when the nav path is longer
const CAVERN_HOME_DROP := 8.0  ## Act II: fall this far below the home pad and return
const SEPARATION_GAP := 0.35  ## step 14: m of clearance kept from other enemies' bodies
const LOD_IDLE_M := 10.0  ## past detect_range + this, an idle enemy thinks every 4th tick
const CROWD_CELL := 2.0
static var _crowd_frame := -1
static var _crowd_max_r := 0.0
static var _crowd: Dictionary = {}
const SEPARATION_WEIGHT := 1.5  ## how hard a neighbour bends its path
const SEPARATION_AHEAD := 0.3  ## cos: a neighbour within ~73 deg of its heading is "ahead"
const SEPARATION_FORWARD := 0.25  ## blocked: share of the heading kept while going around
const SLIDE_OFF_SPEED := 4.0  ## m/s off another enemy's back


## What it senses this tick (C++ GnawerSenses).
class Senses:
	extends RefCounted
	var target_valid := false
	var distance := 0.0  ## horizontal, feet to feet
	var line_of_sight := false
	var provoked := false
	var hunting := false
	var knockback_left := 0.0
	var dead := false
	var leashed := false


## One bite (C++ EnemyAttack).
class Bite:
	extends RefCounted
	var damage := 0.0
	var element: ElementTable.Element = ElementTable.Element.EARTH
	var from := Vector3.ZERO  ## its feet
	var dodged := false
	var tick := 0
	var dl := 0  ## 0.3.2: level delta the defender applies to this base damage


class Transition:
	extends RefCounted
	var from: State
	var to: State
	var distance := 0.0
	var tick := 0


var rusher: RusherDef
var state: State = State.IDLE
var target: Node3D  ## the Player (feet = global_position); null = none
var ally_target_was: Node3D  ## step 52: the player target set aside while corrupted
var ally_bites := 0  ## step 52: bites landed on enemies while corrupted
var auto_tick := true  ## false in tests: tick() is called by hand
var ticks := 0
var _senses := Senses.new()
var _lod_n := 0
var attack_timer := 0.0
var hunt_left := 0.0
var knockback_left := 0.0
var knockback_dir := Vector3.ZERO
var provoked := false
var distance := 0.0
var travelled := 0.0  ## horizontal metres moved
var bites := 0
var dodged := 0
var knockbacks := 0
var steps_climbed := 0
var nav_ticks := 0  ## ticks steered by a navmesh path
var separations := 0  ## step 14: ticks a neighbour bent its path
var separation := true  ## step 14: crowd separation on (tests can switch it off)
var rode := 0  ## step 14: ticks it found itself on an enemy's back
var transitions: Array[Transition] = []
var attacks: Array[Bite] = []
var nav: NavigationAgent3D
var _vy := 0.0
var cavern_sense := false  ## Act II: 3D distance, not the flat Warrens check
var path_cap := -1.0  ## Act III: horizontal sense, drop the chase past this path length
var path_length_override := -1.0  ## tests: the nav path length, in metres
var home_pad := Vector3.ZERO
var has_home := false
## 0.8.3: pocket movement and a second strike. Null when this id has no style row
## (training dummies never get here). `engaged` counts time spent chasing or attacking.
var style: CombatStyle
var engaged := 0.0
var attack_flash := 0.0
var recover_left := 0.0
var pattern_windup_left := 0.0
var pattern_cd := 0.0
var pattern_burst := Vector3.ZERO
var dodge_left := 0.0
var dodge_dir := Vector3.RIGHT
var specials := 0
var style_lock := 0.0  ## seconds after a knockback before strafing again
var _strafe_t := 0.0
var _strafe_sign := 1.0


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
	style = CombatStyle.for_id(d.id)
	if style != null and hash(d.id) % 2 != 0:
		_strafe_sign = -1.0


static func state_name(s: State) -> String:
	return STATE_NAMES[s]


## C++ nextGnawerState: the state after `s` given senses `i` (one step).
static func next_state(s: State, r: RusherDef, i: Senses) -> State:
	if s == State.DEAD or i.dead:
		return State.DEAD
	if i.knockback_left > 0.0:
		return State.KNOCKBACK
	if i.leashed:
		return State.IDLE
	if not i.target_valid:
		return State.IDLE
	var dist := i.distance
	match s:
		State.KNOCKBACK:  # a hit always leaves it aggressive
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
		State.CHASE:  # a rusher keeps coming without sight; it gives up out of detect range
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
	if is_ally():
		_ally_retarget()
	elif ally_target_was != null:
		target = ally_target_was
		ally_target_was = null
	if _lod_hold():
		return
	think(dt)


## Step 52: a corrupted Gnawer hunts the nearest hostile enemy within ALLY_SEEK instead.
func _ally_retarget() -> void:
	if ally_target_was == null and not (target is Enemy):
		ally_target_was = target
	var best: Enemy = null
	var best_d := ALLY_SEEK
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or e == self or not e.alive() or e.is_ally():
			continue
		var d := e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	target = best
	if best != null:
		provoked = true


func think(dt: float) -> void:
	if state == State.DEAD:
		return  # dead enemies stop thinking
	ticks += 1
	var before := state
	if dead or rusher == null:
		_set_state(State.DEAD, distance)
		velocity = Vector3.ZERO
		_update_pose(dt, State.DEAD)
		return
	attack_timer = maxf(0.0, attack_timer - dt)
	hunt_left = maxf(0.0, hunt_left - dt)

	# Sense. One object, rewritten each think.
	var s := _senses
	s.dead = false
	s.target_valid = _target_valid()
	var feet := global_position
	if has_home and global_position.y < home_pad.y - CAVERN_HOME_DROP:
		global_position = home_pad
		velocity = Vector3.ZERO
		feet = global_position
	var delta := target.global_position - feet if s.target_valid else Vector3.ZERO
	var to := _flat(delta)
	s.distance = delta.length() if cavern_sense else to.length()
	distance = s.distance
	var cap := -1.0
	if cavern_sense:
		cap = CAVERN_CHASE_M
	elif path_cap >= 0.0:
		cap = path_cap
	s.leashed = cap >= 0.0 and _chase_path() > cap
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
			if knockback_left < 1e-6:  # 0.5 - 30 x (1/60) leaves ~1e-16 in doubles: 30 ticks, as in C++
				knockback_left = 0.0
				style_lock = 0.35

	walk *= move_scale()  # step 53: Water slow / Earth stagger
	if next == State.CHASE or next == State.ATTACK:
		engaged += dt
	elif next == State.IDLE:
		engaged = 0.0
	_tick_pattern(dt, next, dir)
	_attack_tick(dt, next, s.distance, feet)  # Heap: a winding-up slam lands / is cancelled
	# (1e-4 s slack: 0.8 - 48 x 1/60 is not exactly 0 in floats.)
	if (
		next == State.ATTACK
		and attack_timer <= 1e-4
		and not staggered()
		and _in_reach(s.distance, feet)
		and pattern_windup_left <= 0.0
	):
		_start_attack(feet)
	if _rooted():  # Heap winding up, or a pattern telegraph: planted, no walk, no turn
		walk = 0.0

	var move := Vector3.ZERO
	var face := dir
	if walk > 1e-6 and s.distance > 1e-4:
		face = _steer(dir)
		if separation:
			face = _separate(face)
		move = face * walk
	if next in [State.DETECT, State.CHASE, State.ATTACK] and face.length() > 1e-4 and not _rooted():
		_turn_toward(face, rusher.turn_rate_deg * dt)
	if not _rooted() and not staggered() and next != State.KNOCKBACK:
		move += _style_slide(dt, next, dir, s.distance)
	_move(move + push, dt)
	travelled += _flat(global_position - feet).length()
	_update_pose(dt, next)


func _chase_path() -> float:
	if path_length_override >= 0.0:
		return path_length_override
	if nav == null or not is_inside_tree():
		return 0.0
	var path := nav.get_current_navigation_path()
	if path.size() < 2:
		return 0.0
	var length := 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	return length


func _in_reach(dist: float, feet: Vector3) -> bool:
	return dist <= rusher.attack_range + ATTACK_SLACK and absf(target.global_position.y - feet.y) <= BITE_HEIGHT


## Overridden by the Heap (a wind-up); the Gnawer bites at once.
func _start_attack(feet: Vector3) -> void:
	_play_clip("Attack")
	_bite(feet)


## Per tick before the attack check (Heap: the wind-up). Gnawer: nothing.
func _attack_tick(_dt: float, _next: State, _dist: float, _feet: Vector3) -> void:
	pass


func _rooted() -> bool:
	return pattern_windup_left > 0.0


## The bite (cooldown starts now) + the attack.
func _bite(feet: Vector3) -> void:
	attack_timer = rusher.attack_cooldown
	_land(feet)


## Emits one attack (dodged if the target is invulnerable now) without touching the cooldown.
func _land(feet: Vector3) -> void:
	if is_ally():
		if target is Enemy:
			(target as Enemy).apply_damage(rusher.attack_damage, def.affinity)
			ally_bites += 1
		return
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
	attacks.append(b)
	attacked.emit(self, b)
	attack_flash = maxf(attack_flash, 0.18)
	recover_left = maxf(recover_left, 0.16)


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


## A dead player (step 13: Player.alive() false) is no target until he respawns.
func _target_valid() -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	return not target.has_method(&"alive") or bool(target.call(&"alive"))


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


## Idle, unprovoked, and far from every player (including a co-op partner): think every 4th tick.
## Off in tests (auto_tick false, or GameFlow.dry_run). Status and flash still tick.
func _lod_hold() -> bool:
	if not auto_tick or GameFlow.dry_run:
		return false
	if state != State.IDLE or provoked or hunt_left > 0.0 or dead or rusher == null:
		return false
	_lod_n += 1
	if _lod_n % 4 == 0:
		return false
	return _far_from_players(rusher.detect_range + LOD_IDLE_M)


func _far_from_players(limit: float) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for grp in [Player.GROUP, RemotePlayer.GROUP]:
		for n in tree.get_nodes_in_group(grp):
			var body := n as Node3D
			if body != null and global_position.distance_to(body.global_position) <= limit:
				return false
	return true


static func _crowd_key(at: Vector3) -> Vector2i:
	return Vector2i(int(floor(at.x / CROWD_CELL)), int(floor(at.z / CROWD_CELL)))


static func _crowd_reach(tree: SceneTree) -> float:
	if _crowd_frame != Engine.get_physics_frames():
		_crowd_fill(tree)
	return _crowd_max_r


static func _crowd_fill(tree: SceneTree) -> void:
	_crowd_frame = Engine.get_physics_frames()
	_crowd.clear()
	_crowd_max_r = 0.0
	for n in tree.get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or e.dead or e.def == null:
			continue
		var r := 0.5 * maxf(e.def.size.x, e.def.size.z)
		_crowd_max_r = maxf(_crowd_max_r, r)
		var key := _crowd_key(e.global_position)
		if not _crowd.has(key):
			_crowd[key] = []
		(_crowd[key] as Array).append(e)


static func _crowd_near(tree: SceneTree, at: Vector3, radius: float) -> Array:
	_crowd_reach(tree)
	var reach := int(ceil(radius / CROWD_CELL))
	var key := _crowd_key(at)
	var out: Array = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell: Variant = _crowd.get(Vector2i(key.x + dx, key.y + dz), [])
			out.append_array(cell)
	return out


## Step 14 crowd separation: Gnawers are kinematic and mask the enemy layer, so they block
## each other; a pack in a corridor used to queue up behind the first one, out of bite
## range. Every other live enemy whose body (+ SEPARATION_GAP) overlaps its own pushes it
## away, scaled by the overlap; a neighbour ahead on its path also pushes it sideways (to
## the side it already is on; dead ahead: a fixed side from its name) so it goes around.
## The result never points back from `want` (it doesn't flee its target). Deterministic,
## no NavigationAgent3D avoidance callback (that one answers a physics frame late).
func _separate(want: Vector3) -> Vector3:
	if not is_inside_tree():
		return want
	var push := Vector3.ZERO
	var around := Vector3.ZERO
	var me := global_position
	var my_r := 0.5 * maxf(def.size.x, def.size.z)
	var side := Vector3(-want.z, 0.0, want.x)  # its left
	var query := my_r + _crowd_reach(get_tree()) + SEPARATION_GAP
	for n in _crowd_near(get_tree(), me, query):
		var o := n as Enemy
		if o == null or o == self or o.dead or o.def == null:
			continue
		var off := _flat(me - o.global_position)
		var r := my_r + 0.5 * maxf(o.def.size.x, o.def.size.z) + SEPARATION_GAP
		var d := off.length()
		if d >= r:
			continue
		var away := off / d if d > 1e-4 else side
		push += away * (1.0 - d / r)
		if -away.dot(want) > SEPARATION_AHEAD:  # the neighbour is ahead: go around it
			var s := side.dot(away)
			var sgn := signf(s) if absf(s) > 1e-3 else (1.0 if (hash(String(name)) & 1) == 0 else -1.0)
			around += side * sgn
	if push.length() < 1e-5 and around.length() < 1e-5:
		return want
	separations += 1
	var out := want + push * SEPARATION_WEIGHT
	if around.length() > 1e-5:
		out = want * SEPARATION_FORWARD + around.normalized() + push * SEPARATION_WEIGHT
	var back := out.dot(want)
	if back < 0.0:
		out -= want * back  # sideways only, never away from the target
	return out.normalized() if out.length() > 1e-4 else want


## Step 14 (spawner respawns): Enemy.reset + a fresh brain (idle, no timers, no knockback).
func reset(xform: Variant = null) -> void:
	super.reset(xform)
	state = State.IDLE
	attack_timer = 0.0
	hunt_left = 0.0
	knockback_left = 0.0
	provoked = false
	distance = 0.0
	_vy = 0.0
	engaged = 0.0
	attack_flash = 0.0
	recover_left = 0.0
	pattern_windup_left = 0.0
	pattern_cd = 0.0
	pattern_burst = Vector3.ZERO
	dodge_left = 0.0
	specials = 0
	style_lock = 0.0
	pose = "idle"


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
	_slide_off_enemies()
	var want := delta.length()
	if want > 1e-5 and _flat(global_position - start).length() < 0.5 * want and is_on_wall() and not _walled_by_enemy():
		_try_step_up(_flat(delta))


## Step 14 fix (step 12 bug): a Gnawer pressed into another one climbed onto its back
## (feet at 0.45 m) and rode it. Landing on an enemy now slides it off sideways (away
## from the one below) at SLIDE_OFF_SPEED, and enemies are never stepped up onto.
func _slide_off_enemies() -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var o := c.get_collider() as Enemy
		if o == null or c.get_normal().y < 0.5:
			continue
		var off := _flat(global_position - o.global_position)
		if off.length() < 1e-3:
			off = _flat(global_transform.basis.x)
		rode += 1
		move_and_collide(off.normalized() * SLIDE_OFF_SPEED * get_physics_process_delta_time())
		return


func _walled_by_enemy() -> bool:
	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() is Enemy:
			return true
	return false


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
	if h.result == null or h.result.amount <= stagger_threshold(rusher.knockback_threshold):
		_try_dodge()
		return
	dodge_left = 0.0
	if rusher.knockback_time <= 0.0 or rusher.knockback_strength <= 0.0:
		return
	var d := _flat(h.direction)
	if d.length() < 1e-4:
		d = _flat(global_position - h.point)
	if d.length() < 1e-4:
		d = Vector3(0.0, 0.0, 1.0)
	knockback_dir = d.normalized()
	knockback_left = rusher.knockback_time  # a new hit restarts it
	knockbacks += 1


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## A light hit in a fight: step sideways instead of eating the next swing. A hit
## heavy enough to knock back clears this (the push already moves the body).
func _try_dodge() -> void:
	if style == null or style.dodge_speed <= 0.0 or _rooted() or staggered():
		return
	if state != State.CHASE and state != State.ATTACK:
		return
	var side := Vector3(-dodge_dir.z, 0.0, dodge_dir.x)
	if side.length_squared() < 1e-6:
		side = Vector3(1.0, 0.0, 0.0)
	dodge_dir = side.normalized()
	dodge_left = style.dodge_s


## Wind up the second strike (lunge / cleave). Fans and feints do not use this:
## a fan is extra projectiles, a feint is the strafe itself. Boss phase attacks
## stay in their own brains.
func _tick_pattern(dt: float, next: State, dir: Vector3) -> void:
	if pattern_windup_left > 0.0:
		pattern_windup_left = maxf(0.0, pattern_windup_left - dt)
		if pattern_windup_left <= 1e-4:
			pattern_windup_left = 0.0
			_release_special(dir)
		return
	pattern_cd = maxf(0.0, pattern_cd - dt)
	if style == null or style.special == "feint" or style.special == "fan" or style.special == "":
		return
	if next != State.ATTACK or not _target_valid() or staggered():
		return
	if engaged < style.arm_s or pattern_cd > 0.0:
		return
	if has_method(&"winding_up") and bool(call(&"winding_up")):
		return
	# Leave the basic cooldown alone so a slam or bite still lands on its timer.
	if attack_timer <= style.windup + 0.05:
		return
	pattern_windup_left = style.windup
	pattern_cd = style.cooldown


func _release_special(dir: Vector3) -> void:
	if style == null or rusher == null or not _target_valid():
		return
	specials += 1
	if style.special == "lunge" and dir.length_squared() > 1e-6:
		pattern_burst = dir.normalized() * style.lunge_speed * 0.1
	var saved := rusher.attack_damage
	rusher.attack_damage = saved * style.damage_mul
	_land(global_position)
	rusher.attack_damage = saved


## Metres to add this tick: a dodge, or (in the pocket) a strafe with a short retreat.
## Clamped so the gap stays inside attack_range and the state machine does not drop
## back to chase just because the enemy sidestepped.
func _style_slide(dt: float, next: State, dir: Vector3, dist: float) -> Vector3:
	if style_lock > 0.0:
		style_lock = maxf(0.0, style_lock - dt)
		return Vector3.ZERO
	if style == null or rusher == null:
		return Vector3.ZERO
	var delta := Vector3.ZERO
	if dodge_left > 0.0:
		dodge_left = maxf(0.0, dodge_left - dt)
		delta = dodge_dir * style.dodge_speed * dt
	elif (
		next == State.ATTACK and dir.length_squared() > 1e-6 and (style.strafe_speed > 0.0 or style.retreat_speed > 0.0)
	):
		var side := dir.cross(Vector3.UP)
		if side.length_squared() < 1e-8:
			side = Vector3.RIGHT
		side = side.normalized() * _strafe_sign
		_strafe_t += dt
		if _strafe_t >= style.strafe_period:
			_strafe_t = 0.0
			_strafe_sign *= -1.0
		delta = side * style.strafe_speed * dt
		if style.retreat_s > 0.0 and _strafe_t < style.retreat_s:
			delta -= dir * style.retreat_speed * dt
	if pattern_burst.length_squared() > 1e-8:
		delta += pattern_burst
		pattern_burst = Vector3.ZERO
	if delta.length_squared() < 1e-10:
		return Vector3.ZERO
	delta *= move_scale()
	var pocket := rusher.attack_range
	var min_dist := maxf(0.2, rusher.attack_range * 0.7)
	return CombatStyle.clamp_pocket(delta, dir, dist, pocket, min_dist)


func _update_pose(dt: float, next: State) -> void:
	attack_flash = maxf(0.0, attack_flash - dt)
	if attack_flash <= 0.0:
		recover_left = maxf(0.0, recover_left - dt)
	var want := "idle"
	if dead or next == State.DEAD:
		want = "death"
	elif flinch_left > 0.0 or next == State.KNOCKBACK:
		want = "hurt"
	elif _rooted():
		want = "windup"
	elif attack_flash > 0.0:
		want = "attack"
	elif recover_left > 0.0:
		want = "recover"
	elif next == State.CHASE or next == State.DETECT or next == State.ATTACK:
		want = "chase"
	pose = want
	if model:
		model.set_combat_pose(want)
