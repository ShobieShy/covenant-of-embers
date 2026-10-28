class_name GoblinKing
extends Warden
## The Goblin King (LABYRINTH_PLAN section 6, step L3): ai kind "king" (Enemy.BRAINS), the
## floor-5 boss of the Goblin Warrens. The Warden's two phases on the Heap's brain:
##   * Slam: the Heap's telegraphed club slam (attack_windup, attack_range);
##   * Throw: when the target is THROW_MIN..THROW_MAX m away, in sight, and the throw is
##     ready, he plants and plays Throw; the rock leaves his hand at 40 % of the clip
##     (EnemyModels.throw_release, batch 08b has no release marker) and flies straight at
##     the target's chest. A rock that comes within ROCK_HIT m lands as a Bite
##     (THROW_DAMAGE, Earth; dodged during i-frames); walls stop it;
##   * Roar: once, at the phase-2 enrage: planted for ROAR_S and `roared` fires with the
##     two grunts he calls (spawned next to him into his parent, adopted by an
##     EnemySpawner parent).
## On death the Crown mesh on his head hides (EnemyModels.DEATH_HIDE) and a loose CrownDrop
## prop is left at his feet; LootDropper rolls his level-12 loot as for any enemy.

signal roared(king: GoblinKing, minions: Array)
signal threw(king: GoblinKing, rock: Rock)

const THROW_MIN := 6.0
const THROW_MAX := 18.0
const THROW_COOLDOWN := 5.0
const THROW_DAMAGE := 14.0
const THROW_FALLBACK := 0.5  ## s to release with no Throw clip (greybox)
const ROCK_SPEED := 16.0
const ROCK_HIT := 0.7
const ROCK_LIFE := 2.0
const ROAR_S := 2.0  ## Roar is ~2 s (frames 0-50 at 24 fps)
const MINIONS := ["goblin_grunt", "goblin_grunt"]


class Rock:
	extends RefCounted
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var age := 0.0
	var done := false
	var hit := false


var rocks: Array[Rock] = []
var throw_timer := 0.0
var throw_left := 0.0  ## s until the rock leaves the hand (0 = not throwing)
var throws := 0
var rocks_hit := 0
var roar_left := 0.0
var roars := 0
var crown_drop: Node3D


func reset(xform: Variant = null) -> void:
	super.reset(xform)
	rocks.clear()
	throw_timer = 0.0
	throw_left = 0.0
	roar_left = 0.0


func think(dt: float) -> void:
	super.think(dt)
	if dead:
		throw_left = 0.0
		return
	throw_timer = maxf(0.0, throw_timer - dt)
	roar_left = maxf(0.0, roar_left - dt)
	if throw_left > 0.0:
		throw_left -= dt
		if throw_left <= 1e-4:
			throw_left = 0.0
			_release()
	elif (
		throw_timer <= 1e-4
		and roar_left <= 0.0
		and not winding_up()
		and not staggered()
		and _target_valid()
		and state in [State.CHASE, State.ATTACK]
		and distance >= THROW_MIN
		and distance <= THROW_MAX
		and sees(_target_eye())
	):
		_begin_throw()
	_tick_rocks(dt)


func _rooted() -> bool:
	return super._rooted() or throw_left > 0.0 or roar_left > 0.0


func _begin_throw() -> void:
	throw_timer = THROW_COOLDOWN
	var r := EnemyModels.throw_release(model) if model else 0.0
	throw_left = r if r > 0.0 else THROW_FALLBACK
	throws += 1
	_clip(&"Throw")


## The rock leaves the hand (right side, shoulder height) toward the target's chest now.
func _release() -> void:
	if not _target_valid():
		return
	var k := Rock.new()
	k.pos = global_transform * Vector3(0.5, def.size.y * 0.75, -0.4)
	var aim := _target_eye() - Vector3(0.0, 0.4, 0.0)
	k.vel = (aim - k.pos).normalized() * ROCK_SPEED
	rocks.append(k)
	threw.emit(self, k)


func _tick_rocks(dt: float) -> void:
	for k in rocks:
		k.age += dt
		var nxt := k.pos + k.vel * dt
		if is_inside_tree():
			var q := PhysicsRayQueryParameters3D.create(k.pos, nxt, 1, [get_rid()])
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				k.done = true
				continue
		k.pos = nxt
		if (
			_target_valid()
			and k.pos.distance_to(_target_eye() - Vector3(0.0, 0.4, 0.0)) <= ROCK_HIT
		):
			k.done = true
			k.hit = true
			rocks_hit += 1
			var dmg := rusher.attack_damage
			rusher.attack_damage = THROW_DAMAGE
			_land(global_position)
			rusher.attack_damage = dmg
		elif k.age >= ROCK_LIFE:
			k.done = true
	rocks = rocks.filter(func(x: Rock) -> bool: return not x.done)


func _enrage() -> void:
	super._enrage()
	roar_left = ROAR_S
	throw_left = 0.0
	roars += 1
	windup_left = 0.0
	_clip(&"Roar")
	var got: Array = []
	var t := EnemyTable.load_default()
	var p := get_parent() as Node3D
	for i in MINIONS.size():
		var d := t.find(MINIONS[i])
		if d == null or p == null:
			continue
		var side := -1.0 if i == 0 else 1.0
		var at := transform * Transform3D(Basis.IDENTITY, Vector3(side * 2.5, 0.0, 1.0))
		var g := Enemy.create(d, Transform3D(Basis.IDENTITY, at.origin))
		g.name = "KingGrunt%d" % (roars * 10 + i)
		p.add_child.call_deferred(g)
		if p.has_method(&"adopt"):
			p.call_deferred(&"adopt", g)
		got.append(g)
	roared.emit(self, got)


func _die(element: ElementTable.Element) -> void:
	super._die(element)
	throw_left = 0.0
	rocks.clear()
	var p := get_parent() as Node3D
	if p == null:
		return
	crown_drop = EnemyModels.crown_drop(model) if model else null
	if crown_drop:
		crown_drop.name = "CrownDrop"
		crown_drop.transform = transform * Transform3D(Basis.IDENTITY, Vector3(0.8, 0.0, 0.6))
		p.add_child.call_deferred(crown_drop)


func _clip(n: StringName) -> void:
	var ap := model.anim if model else null
	if ap and ap.has_animation(n):
		ap.get_animation(n).loop_mode = Animation.LOOP_NONE
		ap.play(n, 0.15)
