class_name Heap
extends Gnawer
## The Heap (BUILD_PLAN step 13, PLAN §7 "Tank: lumbering junk constructs; weak point is a
## glowing core seam"): ai kind "tank" (Enemy.BRAINS). The Gnawer's brain and tick shape
## (Idle/Detect/Chase/Attack/Knockback/Dead, navmesh steering, gravity, step-up), slower
## and heavier, with a telegraphed slam instead of an instant bite:
##   * in Attack with the cooldown ready and the target in reach, it plants itself
##     (no walk, no turn) and winds up for attack_windup (0.6 s); the cooldown starts then;
##   * the slam lands when the wind-up runs out: if the target is still within
##     attack_range + 0.3 m (and 1.2 m of height) it is attacked (Gnawer.attacked, a Bite
##     with the slam's damage, dodged during dash i-frames); out of reach it whiffs;
##   * a knockback (only hits over its high threshold, e.g. a Fire seam crit 30 > 25),
##     death or losing the target cancels the wind-up (`interrupted`); the cooldown stays
##     spent.
## The seam (weak point, x2) is a wide flat box across its back (+Z: yaw 0 faces -Z),
## drawn glowing, so the crit needs a flank.
##
## Magewar reference (enemy_garbage_golem.gd, read-only): Earth, contact_damage 8,
## attack_cooldown 2, detection 10, aggro 7, walk 1.2, sprint 2.5 are kept; the body is
## landfill_tutorial.tscn's Golem1 mesh (1.5 x 2.4 x 1.5). Magewar's knockback_strength 15
## (more than the rat's 10, so the "tanky" golem flies farther) is kept as the push speed
## but reinterpreted: a 25 threshold and 0.2 s make it hard to shove (1.5 m). Magewar has
## no slam, wind-up or seam (its golem never moves: no AI loop), and no golem health:
## 150 HP is plan design (ten 15-damage Fire bolts, five seam crits).

const SEAM_GLOW := Color(1.0, 0.45, 0.1)

var windup_left := 0.0
var slams := 0  ## wind-ups started
var landed := 0  ## slams that reached the target (dodged ones included)
var whiffs := 0  ## landed out of reach
var interrupted := 0
var windup_started_tick := -1


func setup(d: EnemyDef) -> void:
	super.setup(d)
	if _head_mat != null:  # the glowing core seam
		_head_mat.emission_enabled = true
		_head_mat.emission = SEAM_GLOW
		_head_mat.emission_energy_multiplier = 1.5


func reset(xform: Variant = null) -> void:
	super.reset(xform)
	windup_left = 0.0


func winding_up() -> bool:
	return windup_left > 0.0


func _start_attack(feet: Vector3) -> void:
	if rusher.attack_windup <= 0.0:
		_bite(feet)
		return
	attack_timer = rusher.attack_cooldown
	windup_left = rusher.attack_windup
	windup_started_tick = ticks
	slams += 1


func _attack_tick(dt: float, next: State, dist: float, feet: Vector3) -> void:
	if windup_left <= 0.0:
		return
	if next != State.ATTACK and next != State.CHASE:  # knocked back, dead, target lost
		windup_left = 0.0
		interrupted += 1
		return
	windup_left -= dt
	if windup_left > 1e-4:  # 0.6 - 36 x 1/60 is not exactly 0 in floats
		return
	windup_left = 0.0
	if _target_valid() and _in_reach(dist, feet):
		landed += 1
		_land(feet)
	else:
		whiffs += 1


func _rooted() -> bool:
	return windup_left > 0.0
