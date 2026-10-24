class_name Ooze
extends Gnawer
## Mire Ooze (BUILD_PLAN step 55): ai kind "splitter", a slow Water slime on the Gnawer
## brain (chases and slaps). Plan design (Magewar has no slime enemy below The Filth):
##   * death splits a full-size ooze (generation 0) into SPLIT_COUNT halves: half max
##     health, 0.6 x size, no further splits, standing beside where it died;
##   * a Fire hit that leaves it under half health boils it apart at once (it dies and
##     splits): Fire is how you speed it up;
##   * every ooze death leaves a Puddle (radius PUDDLE_RADIUS, PUDDLE_TIME s) that slows a
##     target standing in it to PUDDLE_SLOW speed (Player.apply_slow).
## `split` hands the halves (not yet in the tree) and `puddle` to whoever owns it (the
## EnemySpawner adds them, and adds the halves to the wave it was in); with nobody
## listening the ooze adds them to its own parent.

signal split(ooze: Ooze, halves: Array)

const SPLIT_COUNT := 2
const SPLIT_SCALE := 0.6
const PUDDLE_RADIUS := 1.5
const PUDDLE_TIME := 6.0
const PUDDLE_SLOW := 0.6

var generation := 0
var halves: Array[Ooze] = []
var puddle: Puddle


class Puddle:
	extends Node3D
	var target: Node3D
	var radius := PUDDLE_RADIUS
	var left := PUDDLE_TIME
	var slowed_ticks := 0
	var auto_tick := true

	func _ready() -> void:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = radius
		c.bottom_radius = radius
		c.height = 0.03
		mi.mesh = c
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.4, 0.2, 0.7)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m
		mi.position.y = 0.02
		add_child(mi)

	func _physics_process(dt: float) -> void:
		if auto_tick:
			tick(dt)

	func tick(dt: float) -> void:
		left -= dt
		if left <= 0.0:
			queue_free()
			return
		if target == null or not is_instance_valid(target) or not target.is_inside_tree():
			return
		var off := target.global_position - global_position
		if Vector2(off.x, off.z).length() <= radius and absf(off.y) < 1.0 and target.has_method(&"apply_slow"):
			target.call(&"apply_slow", PUDDLE_SLOW, 0.2)
			slowed_ticks += 1


func setup(d: EnemyDef) -> void:
	super.setup(d)
	died.connect(_on_self_died)


func _on_damaged(e: Enemy, h: SpellBolts.Hit) -> void:
	super._on_damaged(e, h)
	if dead or generation > 0 or h.element != ElementTable.Element.FIRE:
		return
	if health < 0.5 * max_health():
		last_killing_element = ElementTable.Element.FIRE
		apply_damage.call_deferred(health + 1.0, ElementTable.Element.FIRE)


func _on_self_died(_e: Enemy, _el: ElementTable.Element) -> void:
	var at := global_position
	puddle = Puddle.new()
	puddle.target = ally_target_was if ally_target_was != null else target
	puddle.position = at if get_parent() == null else (get_parent() as Node3D).to_local(at)
	halves.clear()
	if generation == 0:
		var hd := def.duplicate(true) as EnemyDef
		hd.max_health = def.max_health * 0.5
		hd.size = def.size * SPLIT_SCALE
		hd.has_weak_point = false
		hd.display_name = "%s (small)" % def.display_name
		hd.xp_reward = maxi(1, def.xp_reward / 2)
		for i in SPLIT_COUNT:
			var side := Vector3(1.0 if i == 0 else -1.0, 0.0, 0.0) * (0.5 * def.size.x + 0.3)
			var o := Enemy.create(hd, Transform3D(Basis.IDENTITY, puddle.position + side)) as Ooze
			o.generation = 1
			o.target = ally_target_was if ally_target_was != null else target
			o.auto_tick = auto_tick
			halves.append(o)
	if split.get_connections().is_empty():
		var p := get_parent()
		if p:
			for o in halves:
				p.add_child.call_deferred(o)
			p.add_child.call_deferred(puddle)
	else:
		split.emit(self, halves)
