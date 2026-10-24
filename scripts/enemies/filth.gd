class_name Filth
extends Heap
## The Filth (BUILD_PLAN steps 56-57): the Landfill's three-phase slime boss (ai kind
## "filth"), replacing the Heap/wave ending (Q8). On the Heap brain (slam with a wind-up),
## plus:
##   * acid blobs: a lobbed projectile every blob_cooldown s while the target is within
##     BLOB_RANGE and in sight (lands as an attack, Earth, dodged in dash i-frames);
##   * phases by health: 1 above PHASE_2_AT, 2 above PHASE_3_AT, 3 below. Each phase is
##     ~1/3 of its health, so the 20-35 s per-phase target is a health budget
##     (balance: test_filth.gd);
##   * phase 2 "absorbs debris": with no hit for REGEN_DELAY s it regenerates REGEN_PER_S,
##     never above the phase-2 ceiling (so it can't climb back into phase 1);
##   * phase 3 exposes the core: no regen, faster blobs, the weak point grows x CORE_GROW
##     and glows (an easy crit target);
##   * death always drops Joe's Trash (QuestPickup) at its feet (step 57).
## Magewar reference (boss_the_filth, read-only): a landfill slime born from alchemical
## runoff + dungeon essence that spews acid and regenerates from debris. Magewar has no
## numbers for it; health/tempo are plan design. Bosses are immune to Dark corruption.

signal phase_changed(filth: Filth, phase: int)
signal trash_dropped(filth: Filth, pickup: QuestPickup)

const PHASE_2_AT := 0.66
const PHASE_3_AT := 0.33
const BLOB_RANGE := 14.0
const BLOB_SPEED := 9.0
const BLOB_HIT := 0.7
const BLOB_LIFE := 2.5
const BLOB_COOLDOWN := [3.0, 2.4, 1.6]  ## per phase
const REGEN_DELAY := 2.0
const REGEN_PER_S := 4.0
const CORE_GROW := 2.5
const CORE_GLOW := Color(0.6, 1.0, 0.2)
const DROP_ID := "joes_discards"  ## the_landfill quest's collect target
const DROP_NAME := "Joe's Trash"
const WAVE_ID := "the_filth"  ## midden_greybox.toml's boss wave


class Blob:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var age := 0.0
	var done := false


var phase := 1
var phase_ticks: Array[int] = [0, -1, -1]  ## tick each phase began
var blobs: Array[Blob] = []
var blobs_fired := 0
var blobs_landed := 0
var blob_timer := 1.0
var since_hit := 0.0
var regenerated := 0.0
var trash: QuestPickup


func is_boss() -> bool:
	return true


func reset(xform: Variant = null) -> void:
	super.reset(xform)
	blobs.clear()
	since_hit = 0.0
	blob_timer = 1.0
	if phase != 1:
		phase = 1
		phase_ticks = [0, -1, -1]
		rusher = def.rusher()
		if head_shape:
			(head_shape.shape as BoxShape3D).size = def.weak_point_size
			(_head_mesh.mesh as BoxMesh).size = def.weak_point_size


func apply_damage(amount: float, element: ElementTable.Element, announce := true) -> bool:
	if amount > 0.0:
		since_hit = 0.0
	var killed := super.apply_damage(amount, element, announce)
	if not dead:
		_update_phase()
	return killed


func _update_phase() -> void:
	var f := health / max_health() if max_health() > 0.0 else 0.0
	var want := 1 if f > PHASE_2_AT else (2 if f > PHASE_3_AT else 3)
	while phase < want:
		phase += 1
		phase_ticks[phase - 1] = ticks
		if phase == 3:
			_expose_core()
		phase_changed.emit(self, phase)


func _expose_core() -> void:
	rusher.attack_cooldown *= 0.75
	if head_shape:
		var s := def.weak_point_size * Vector3(CORE_GROW, CORE_GROW, 1.0)
		(head_shape.shape as BoxShape3D).size = s
		(_head_mesh.mesh as BoxMesh).size = s
	if _head_mat:
		_head_mat.emission = CORE_GLOW
		_head_mat.emission_energy_multiplier = 3.0


func core_exposed() -> bool:
	return phase >= 3


func think(dt: float) -> void:
	_tick_blobs(dt)
	if dead:
		super.think(dt)
		return
	since_hit += dt
	if phase == 2 and since_hit >= REGEN_DELAY:
		var cap := max_health() * PHASE_2_AT
		var add := minf(REGEN_PER_S * dt, cap - health)
		if add > 0.0:
			health += add
			regenerated += add
	super.think(dt)
	blob_timer -= dt
	if blob_timer <= 0.0 and _target_valid():
		var d := global_position.distance_to(target.global_position)
		if d <= BLOB_RANGE and d > rusher.attack_range and sees(_target_eye()):
			fire_blob()


func blob_cooldown() -> float:
	return BLOB_COOLDOWN[clampi(phase - 1, 0, 2)]


func fire_blob() -> void:
	blob_timer = blob_cooldown()
	var b := Blob.new()
	b.pos = eye_position()
	var aim := _target_eye() - Vector3(0.0, 0.4, 0.0)
	b.vel = (aim - b.pos).normalized() * BLOB_SPEED
	blobs.append(b)
	blobs_fired += 1


func _tick_blobs(dt: float) -> void:
	for b in blobs:
		if b.done:
			continue
		b.age += dt
		var nxt := b.pos + b.vel * dt
		if is_inside_tree():
			var q := PhysicsRayQueryParameters3D.create(b.pos, nxt, 1, [get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				b.done = true
				continue
		b.pos = nxt
		if _target_valid() and b.pos.distance_to(_target_eye() - Vector3(0.0, 0.4, 0.0)) <= BLOB_HIT:
			b.done = true
			blobs_landed += 1
			_land(global_position)
		elif b.age >= BLOB_LIFE:
			b.done = true
	blobs = blobs.filter(func(x: Blob) -> bool: return not x.done)


func _die(element: ElementTable.Element) -> void:
	super._die(element)
	blobs.clear()
	trash = QuestPickup.make(DROP_ID, DROP_NAME)
	var p := get_parent() as Node3D
	trash.position = position if p != null else global_position
	_place_trash.call_deferred(p, trash)
	trash_dropped.emit(self, trash)


## Deferred (death can land inside a physics callback); frees the pickup if the level is gone.
static func _place_trash(p: Variant, t: QuestPickup) -> void:
	if not is_instance_valid(t):
		return
	if is_instance_valid(p) and (p as Node).is_inside_tree():
		(p as Node).add_child(t)
	else:
		t.free()


## Step 57: the boss-door checkpoint. When The Filth's wave starts, the player's respawn
## point moves to the arena edge (the waves trigger), so a death mid-fight doesn't walk
## them back from PlayerStart. Returns true if it moved.
static func checkpoint(p: Player, wave_id: String, at: Vector3) -> bool:
	if wave_id != WAVE_ID or p == null:
		return false
	p.spawn_feet = at
	return true
