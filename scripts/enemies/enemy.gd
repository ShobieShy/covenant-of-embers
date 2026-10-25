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
	"filth": "res://scripts/enemies/filth.gd",  # step 56
}

const BURN_TICK := 0.5  ## s between burn damage ticks (step 53)
const ALLY_COLOR := Color(0.55, 0.2, 0.85)  ## step 52: corrupted tint

var health_scale := 1.0  ## step 80: co-op enemy health multiplier
## Step 94: a co-op client puppet only shows predicted damage; it never dies from it (it
## stays at >= 1 HP, so later hits still go to the host). Only the host's kill ends it.
var hold_death := false
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
## Step 52 (Magewar Dark): > 0 while corrupted into the players' ally (s left). When it runs
## out the husk crumbles (dies, announced as a Dark kill).
var corrupted_left := 0.0
## Step 53 status effects (MagicEffects applies them): burn (Fire DoT), slow (Water),
## stagger (Earth: no moving or attacking). Seconds left; burn_dps = damage per second.
var burn_left := 0.0
var burn_dps := 0.0
var burn_damage := 0.0  ## total burn damage dealt
var slow_left := 0.0
var slow_factor := 1.0
var stagger_left := 0.0
var _burn_acc := 0.0
var corruptions := 0

var body_shape: CollisionShape3D
var head_shape: CollisionShape3D  ## null without a weak point
var _body_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _body_mat: StandardMaterial3D
var model: CharacterModel  ## step 121: rigged body (EnemyModels), or null = greybox box
var _overlay: StandardMaterial3D
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
	_attach_model()


## Step 121: swap the greybox mesh for the batch_04 model; tints go to an overlay.
func _attach_model() -> void:
	model = EnemyModels.make(def.id, def.size.y)
	if model == null:
		return
	add_child(model)
	_body_mesh.visible = false
	if _head_mesh:
		_head_mesh.visible = false
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.albedo_color = Color(1, 1, 1, 0)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = _overlay


func _sync_overlay() -> void:
	if _overlay == null:
		return
	var c := _body_mat.albedo_color
	_overlay.albedo_color = Color(c.r, c.g, c.b, 0.0 if c.is_equal_approx(def.color) else 0.55)


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
	return def.max_health * health_scale if def else 0.0


## Step 80: co-op scaling (x1.6 with 2 players, ...); keeps the current health fraction.
func scale_health(k: float) -> void:
	var frac := health / max_health() if max_health() > 0.0 else 1.0
	health_scale = maxf(0.01, k)
	if not dead:
		health = max_health() * frac


## Bosses (the Warden, The Filth) are immune to Dark corruption (step 52).
func is_boss() -> bool:
	return def != null and String(def.ai.get("kind", "")) in ["boss", "filth"]


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
	if hold_death and health - maxf(0.0, amount) <= 0.0:
		health = minf(health, 1.0)
		damage_taken += before - health
		hits += 1
		flash = FLASH_TIME
		return false
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


## Step 94: the host confirmed this puppet's death (kill message or a dead snapshot).
func confirm_kill(element: ElementTable.Element) -> void:
	hold_death = false
	if not dead:
		apply_damage(health + 1.0, element)


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
	corrupted_left = 0.0
	clear_statuses()
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
	_status_tick(dt)
	_sync_overlay()
	if corrupted_left > 0.0 and not dead:
		corrupted_left = maxf(0.0, corrupted_left - dt)
		if corrupted_left <= 0.0:
			_uncorrupt()
			return
		if flash <= 0.0 and _body_mat:
			_body_mat.albedo_color = def.color.lerp(ALLY_COLOR, 0.65)
	if flash <= 0.0:
		return
	flash = maxf(0.0, flash - dt)
	var k := flash / FLASH_TIME
	if _body_mat:
		var base := def.color.lerp(ALLY_COLOR, 0.65) if corrupted_left > 0.0 else def.color
		_body_mat.albedo_color = base.lerp(Color.WHITE, 0.6 * k)
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


## Step 52: true while corrupted into an ally.
func is_ally() -> bool:
	return corrupted_left > 0.0 and not dead


## Step 52: turn on the players' side for `seconds` (bosses refuse). True when it took.
func corrupt(seconds: float) -> bool:
	if dead or is_boss() or seconds <= 0.0:
		return false
	corrupted_left = seconds
	corruptions += 1
	return true


## The corruption ran out: the husk crumbles.
func _uncorrupt() -> void:
	if _body_mat:
		_body_mat.albedo_color = def.color
	apply_damage(health + 1.0, ElementTable.Element.DARK)


## Step 53: walk speed multiplier from statuses (0 while staggered).
func move_scale() -> float:
	if stagger_left > 0.0:
		return 0.0
	return slow_factor if slow_left > 0.0 else 1.0


func staggered() -> bool:
	return stagger_left > 0.0


func clear_statuses() -> void:
	burn_left = 0.0
	burn_dps = 0.0
	slow_left = 0.0
	slow_factor = 1.0
	stagger_left = 0.0
	_burn_acc = 0.0


## Burn ticks every BURN_TICK s (Fire kills count as Fire kills).
func _status_tick(dt: float) -> void:
	slow_left = maxf(0.0, slow_left - dt)
	stagger_left = maxf(0.0, stagger_left - dt)
	if burn_left <= 0.0 or dead:
		return
	var step := minf(dt, burn_left)
	burn_left -= step
	_burn_acc += step
	if _burn_acc >= BURN_TICK - 1e-6 or burn_left <= 1e-6:
		var amount := burn_dps * _burn_acc
		_burn_acc = 0.0
		burn_damage += minf(amount, health)
		apply_damage(amount, ElementTable.Element.FIRE)
