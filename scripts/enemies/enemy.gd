class_name Enemy
extends CharacterBody3D
## A live enemy (BUILD_PLAN step 11, port of the archived C++ game/enemies/enemy.*, old
## step 22): health, element affinity + per-element resistance, a weak-point hitbox and
## death. Training dummies are Enemies without a brain; step 12's Gnawer extends this and
## `create` picks it by the type's `ai.kind` (BRAINS).
##
## Body: a CharacterBody3D on physics layer "enemy" (3) with two CollisionShape3Ds, the
## body box (standing on the feet) and, if the type has one, the weak-point box ("Head").
## Bolts (SpellBolts) ray-hit either shape; SpellBolts asks `damage_target_for(hit)`, which
## sets `damage_target.weak_point` from the struck shape (Hit.shape), so the head takes x2.
## The resolved hit then arrives in take_hit(hit): health -= hit.result.amount, clamped at
## 0 (overkill isn't counted in damage_taken); reaching 0 kills the enemy: `died` fires
## once, its shapes stop colliding and later bolts fly through (`passes_bolts()`).
##
## Magewar reference (enemy_base.gd, read-only): MagewarEnemy is a CharacterBody3D in the
## "enemies" group with enemy_name, element, level, xp/gold rewards, a damage_received
## signal and a CogitoHealthAttribute whose death runs on_death. Reinterpreted, not copied:
## health lives here (Magewar's landfill enemies have no health attribute, so they never
## die), hits go through Damage.resolve_hit (resist cap 60 %, weak point x2; Magewar:
## effectiveness only), and the Magewar group "enemies" + signal name damage_received
## are kept so later systems read the same way. Knockback (> 10 damage) is the Gnawer's.

signal damage_received(amount: float, direction: Vector3, point: Vector3)  ## Magewar's name
signal damaged(enemy: Enemy, hit: SpellBolts.Hit)  ## after health changed (hit.result set)
signal died(enemy: Enemy, element: ElementTable.Element)

const ENEMY_LAYER := 3  ## physics layer "enemy" (bit 3)
const FLASH_TIME := 0.12  ## s of hit flash (C++ kFlashTime)
const WEAK_POINT_BRIGHTEN := 0.35  ## weak point tint = body colour lightened by this
const GROUP := &"enemies"  ## Magewar's group
## ai.kind -> the Enemy subclass that runs it (loaded by path: no class cycle).
const BRAINS := {
	"rusher": "res://scripts/enemies/gnawer.gd",
	"tank": "res://scripts/enemies/heap.gd",
	"boss": "res://scripts/enemies/warden.gd",
	"ranged": "res://scripts/enemies/scorchling.gd",
	"splitter": "res://scripts/enemies/ooze.gd",
}

var def: EnemyDef
var damage_target: Damage.Target
var health := 0.0
var dead := false
var hits := 0
var damage_taken := 0.0  ## health actually lost
var flash := 0.0
var last_hit: SpellBolts.Hit
var last_weak_point := false  ## the last resolved hit struck the weak point
var last_killing_element: ElementTable.Element = ElementTable.Element.ARCANE
var deaths := 0  ## deaths announced (a respawned dummy can die again)
var resets := 0
var _death_announced := false

var body_shape: CollisionShape3D
var head_shape: CollisionShape3D  ## null without a weak point
var _body_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _body_mat: StandardMaterial3D
var _head_mat: StandardMaterial3D


## A new enemy of type `d`, posed by `xform` (feet, yaw) in its future parent's space.
## Place it before add_child: Jolt ray queries see a body teleported after it entered the
## tree only after the next physics step (step 7 note).
## A type with an `ai` table gets its brain's subclass (rusher -> Gnawer).
static func create(d: EnemyDef, xform := Transform3D.IDENTITY) -> Enemy:
	var e: Enemy = null
	var kind := String(d.ai.get("kind", ""))
	if BRAINS.has(kind):
		e = (load(BRAINS[kind]) as GDScript).new() as Enemy
	if e == null:
		e = Enemy.new()
	e.setup(d)
	e.transform = xform
	return e


func setup(d: EnemyDef) -> void:
	def = d
	name = d.id
	health = d.max_health
	damage_target = d.make_target()
	collision_layer = 1 << (ENEMY_LAYER - 1)
	collision_mask = 1
	add_to_group(GROUP)
	set_meta(&"enemy", d.id)
	body_shape = _shape("Body", d.size, Vector3(0, d.size.y * 0.5, 0))
	_body_mat = _material(d.color)
	_body_mesh = _mesh("BodyMesh", d.size, body_shape.position, _body_mat)
	if d.has_weak_point:
		head_shape = _shape("Head", d.weak_point_size, d.weak_point_offset)
		_head_mat = _material(d.color.lerp(Color.WHITE, WEAK_POINT_BRIGHTEN))
		_head_mesh = _mesh("HeadMesh", d.weak_point_size, d.weak_point_offset, _head_mat)


func _shape(n: String, sz: Vector3, at: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = n
	var b := BoxShape3D.new()
	b.size = sz
	cs.shape = b
	cs.position = at
	add_child(cs)
	return cs


func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func _mesh(n: String, sz: Vector3, at: Vector3, m: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = m
	mi.position = at
	add_child(mi)
	return mi


## Magewar get_element(): the defender element.
func get_element() -> ElementTable.Element:
	return def.affinity if def else ElementTable.Element.ARCANE


func display_name() -> String:
	return def.display_name if def else "Enemy"


func max_health() -> float:
	return def.max_health if def else 0.0


func alive() -> bool:
	return not dead


## Dead enemies let bolts through (SpellBolts re-casts past them).
func passes_bolts() -> bool:
	return dead


## Which shape a ray result's shape index is (Hit.shape).
func is_weak_point_shape(shape_index: int) -> bool:
	if head_shape == null or shape_index < 0:
		return false
	var total := 0
	for o in get_shape_owners():
		total += shape_owner_get_shape_count(o)
	if shape_index >= total:
		return false
	var owner_id := shape_find_owner(shape_index)
	return shape_owner_get_owner(owner_id) == head_shape


## SpellBolts: the Damage.Target for this hit (weak_point from the struck shape).
func damage_target_for(h: SpellBolts.Hit) -> Damage.Target:
	damage_target.weak_point = is_weak_point_shape(h.shape)
	return damage_target


## A resolved bolt hit (SpellBolts calls this after damage_target_for + resolve_hit).
func take_hit(h: SpellBolts.Hit) -> void:
	if dead or h.result == null:
		return
	last_hit = h
	last_weak_point = h.result.crit > 1.0
	apply_damage(h.result.amount, h.element, false)
	damage_received.emit(h.result.amount, h.direction, h.point)
	damaged.emit(self, h)
	if dead:
		_announce_death()


## Lowers health by `amount` (>= 0), clamped at 0; true when this killed it. A kill is
## announced (`died` + EventBus.enemy_killed) at once unless `announce` is false
## (take_hit announces after `damaged`, so listeners see the hit before the death).
func apply_damage(amount: float, element: ElementTable.Element, announce := true) -> bool:
	if dead:
		return false
	var before := health
	health = maxf(0.0, health - maxf(0.0, amount))
	damage_taken += before - health
	hits += 1
	flash = FLASH_TIME
	if health <= 0.0:
		_die(element)
		if announce:
			_announce_death()
		return true
	return false


## Step 14: `died` and EventBus.enemy_killed, exactly once per death (reset() re-arms it).
func _announce_death() -> void:
	if _death_announced:
		return
	_death_announced = true
	deaths += 1
	died.emit(self, last_killing_element)
	GameEvents.bus().announce_kill(self, last_killing_element)


## Step 14 (respawning training dummies): back to full health at `xform` (in the parent's
## space), visible, colliding, in the "enemies" group again; the next death is announced
## again. Called from a physics tick, not from inside a physics query callback.
func reset(xform: Variant = null) -> void:
	dead = false
	_death_announced = false
	health = max_health()
	flash = 0.0
	last_hit = null
	last_weak_point = false
	damage_target = def.make_target()
	if xform is Transform3D:
		transform = xform
	velocity = Vector3.ZERO
	# Now and deferred: a death in the same frame queued deferred "collision off" calls,
	# which run after this; the deferred "on" calls queued here run after those.
	var layer := 1 << (ENEMY_LAYER - 1)
	collision_layer = layer
	set_deferred(&"collision_layer", layer)
	body_shape.disabled = false
	body_shape.set_deferred(&"disabled", false)
	if head_shape:
		head_shape.disabled = false
		head_shape.set_deferred(&"disabled", false)
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	visible = true
	if _body_mat:
		_body_mat.albedo_color = def.color
	if _head_mat:
		_head_mat.albedo_color = def.color.lerp(Color.WHITE, WEAK_POINT_BRIGHTEN)
	resets += 1


func _die(element: ElementTable.Element) -> void:
	dead = true
	health = 0.0
	last_killing_element = element
	remove_from_group(GROUP)
	# Deferred: this runs inside SpellBolts' physics tick; bolts already pass through via
	# passes_bolts(), the player stops colliding after the next physics step.
	set_deferred(&"collision_layer", 0)
	body_shape.set_deferred(&"disabled", true)
	if head_shape:
		head_shape.set_deferred(&"disabled", true)
	visible = false


func _physics_process(delta: float) -> void:
	tick(delta)


## Hit flash: the greybox tint goes towards white for FLASH_TIME after a hit.
func tick(dt: float) -> void:
	if flash <= 0.0:
		return
	flash = maxf(0.0, flash - dt)
	var k := flash / FLASH_TIME
	if _body_mat:
		_body_mat.albedo_color = def.color.lerp(Color.WHITE, 0.6 * k)
	if _head_mat:
		_head_mat.albedo_color = def.color.lerp(
			Color.WHITE, WEAK_POINT_BRIGHTEN + (1.0 - WEAK_POINT_BRIGHTEN) * 0.6 * k
		)


## Spawns one Enemy per EnemySpawns marker of `level` whose `enemy` meta is in `table`,
## under `parent` (posed before entering the tree). Unknown ids are skipped and returned
## in `skipped`. Types with a brain spawn as its subclass (the Gnawer, step 12).
static func spawn_at_markers(level: Node, parent: Node3D, table: EnemyTable, skipped: Array = []) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var spawns := level.get_node_or_null("EnemySpawns")
	if spawns == null:
		return out
	for m in spawns.get_children():
		var marker := m as Node3D
		if marker == null:
			continue
		var id := String(marker.get_meta(&"enemy", ""))
		var d := table.find(id)
		if d == null:
			skipped.append(id)
			continue
		var xf := (
			parent.global_transform.affine_inverse() * marker.global_transform
			if parent.is_inside_tree() and marker.is_inside_tree()
			else marker.transform
		)
		var e := Enemy.create(d, xf)
		e.name = marker.name
		parent.add_child(e)
		out.append(e)
	return out
