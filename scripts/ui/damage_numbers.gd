class_name DamageNumbers
extends Node3D
## Floating damage numbers (BUILD_PLAN step 11, port of the archived C++
## game/ui/damage_numbers.*, old step 22): one number per resolved bolt hit, at the impact
## point, coloured by the bolt's element (ElementTable colour). Each rises RISE m (ease-out)
## and fades after FADE_START of its LIFETIME; a weak-point crit draws CRIT_SCALE, a strong
## (x1.5) hit STRONG_SCALE, a weak (x0.5) one WEAK_SCALE. At most MAX live (oldest dropped).
## Drawn as billboard Label3Ds (no depth test, so they show through the dummy) with
## Godot's default font: no new assets. Logic (`numbers`, position/alpha/format) is pure so
## tests check it headless; `connect_bolts()` hooks a SpellBolts' bolt_hit.
##
## Effectiveness callouts: a strong hit's number carries Magewar's "Super Effective!" in
## its gold Color(1, 0.8, 0), a weak one "Not Very Effective..." in grey (0.5, 0.5, 0.5)
## (Damage.Result strong()/weak()), drawn just under the number and fading with it.
## Magewar shows no damage numbers and sends those texts as a player hint with the colour
## ignored (spell_projectile.gd -> send_hint); numbers + in-world callouts are a plan
## addition (the C++ build deferred the callouts to its HUD step).

const LIFETIME := 1.0  ## s
const RISE := 0.8  ## m over the lifetime
const FADE_START := 0.6  ## fraction of the lifetime before fading
const CRIT_SCALE := 1.5
const STRONG_SCALE := 1.2
const WEAK_SCALE := 0.85
const MAX := 64  ## oldest dropped beyond this
const DRIFT: PackedFloat64Array = [0.0, -0.12, 0.12]  ## m sideways, cycled per number
const FONT_SIZE := 48
const PIXEL_SIZE := 0.004  ## m per label pixel at scale 1
const SUPER_EFFECTIVE := "Super Effective!"
const NOT_VERY_EFFECTIVE := "Not Very Effective..."
const SUPER_COLOR := Color(1.0, 0.8, 0.0)  ## Magewar's callout colours
const NOT_VERY_COLOR := Color(0.5, 0.5, 0.5)
const CALLOUT_FONT_SIZE := 28
const HEAL_COLOR := Color(0.35, 1.0, 0.45)  ## step 50: heal numbers
## 0.3.1 P4 (L4): hits on one target within MERGE_S add into its newest number; later
## numbers on a target that still has live ones stack STACK_STEP m higher each.
const MERGE_S := 0.2
const STACK_STEP := 0.22  ## m
const STACK_MAX := 4  ## at most this many steps up
const POP_S := 0.15  ## s of the crit / merge pop
const CRIT_POP := 0.6  ## extra scale at the start of a crit pop
const MERGE_POP := 0.25  ## extra scale when a hit merges in


class Number:
	extends RefCounted
	var world := Vector3.ZERO  ## spawn point (impact)
	var amount := 0.0
	var color := Color.WHITE  ## element colour
	var age := 0.0
	var scale := 1.0
	var drift_x := 0.0
	var callout := ""  ## SUPER_EFFECTIVE / NOT_VERY_EFFECTIVE / ""
	var callout_color := Color.WHITE
	var label: Label3D  ## null when not drawn (tests)
	var callout_label: Label3D  ## child of label, null without a callout
	var target: Object  ## L4: what was hit (null: never merges)
	var hits := 1  ## L4: hits merged into this number
	var stack := 0  ## L4: steps up the per-target stack
	var pop_age := 0.0  ## L4: time since the last pop
	var pop := 0.0  ## L4: extra scale at pop_age 0


var elements: ElementTable  ## colours (default table when null)
var auto_tick := true  ## false: the owner (tests) calls tick()
var merge_s := MERGE_S  ## L4: 0 = never merge (a test driving hits with no clock)
var draw_labels := true  ## false: logic only
var numbers: Array[Number] = []
var spawned := 0


func connect_bolts(b: SpellBolts) -> void:
	if b and not b.bolt_hit.is_connected(_on_bolt_hit):
		b.bolt_hit.connect(_on_bolt_hit)
	var bus := GameEvents.bus()
	if not bus.player_healed.is_connected(_on_player_healed):
		bus.player_healed.connect(_on_player_healed)


func _on_player_healed(p: Player, amount: float) -> void:
	if is_instance_valid(p) and p.is_inside_tree():
		add_heal(p.global_position + Vector3(0.0, 1.9, 0.0), amount)


## Step 50: a green "+N" heal number (Light heals) at `world`.
func add_heal(world: Vector3, amount: float) -> Number:
	var r := Damage.Result.new()
	r.amount = amount
	var n := add(world, r, ElementTable.Element.LIGHT)
	n.color = HEAL_COLOR
	if n.label:
		n.label.text = "+" + format(amount)
		n.label.modulate = HEAL_COLOR
	return n


func _on_bolt_hit(h: SpellBolts.Hit) -> void:
	if h.result != null:
		add(h.point, h.result, h.element, h.collider)


## A number for a resolved hit at `world` (global position).
func add(world: Vector3, r: Damage.Result, element: ElementTable.Element, target: Object = null) -> Number:
	var m := merge_target(target)
	if m != null:
		m.amount += r.amount
		m.hits += 1
		# QA r12: a merge re-pops but keeps the age, so a number under constant fire still
		# rises and fades on its LIFETIME (merging stops at merge_s; the next hit starts a new one).
		m.pop_age = 0.0
		m.pop = CRIT_POP if r.crit > 1.0 else MERGE_POP
		if r.crit > 1.0:
			m.scale = maxf(m.scale, CRIT_SCALE)
		if m.label:
			m.label.text = format(m.amount)
			_place(m)
		return m
	var n := Number.new()
	n.target = target
	n.stack = stack_for(target)
	n.world = world
	n.amount = r.amount
	var t := elements if elements != null else ElementTable.load_default()
	n.color = t.color(element) if t else Color.WHITE
	n.scale = CRIT_SCALE if r.crit > 1.0 else STRONG_SCALE if r.strong() else WEAK_SCALE if r.weak() else 1.0
	n.drift_x = DRIFT[spawned % DRIFT.size()]
	n.pop = CRIT_POP if r.crit > 1.0 else 0.0
	if r.strong():
		n.callout = SUPER_EFFECTIVE
		n.callout_color = SUPER_COLOR
	elif r.weak():
		n.callout = NOT_VERY_EFFECTIVE
		n.callout_color = NOT_VERY_COLOR
	spawned += 1
	if numbers.size() >= MAX:
		_drop(0)
	numbers.append(n)
	if draw_labels:
		var l := Label3D.new()
		l.text = format(n.amount)
		l.modulate = n.color
		l.outline_modulate = Color(0, 0, 0, 1)
		l.font_size = FONT_SIZE
		l.outline_size = 8
		l.pixel_size = PIXEL_SIZE * n.scale
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.render_priority = 10
		l.shaded = false
		n.label = l
		add_child(l)
		if not n.callout.is_empty():
			var c := Label3D.new()
			c.text = n.callout
			c.modulate = n.callout_color
			c.outline_modulate = Color(0, 0, 0, 1)
			c.font_size = CALLOUT_FONT_SIZE
			c.outline_size = 6
			c.pixel_size = PIXEL_SIZE
			c.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			c.no_depth_test = true
			c.render_priority = 10
			c.shaded = false
			c.position = Vector3(0, -FONT_SIZE * PIXEL_SIZE * n.scale * 0.75, 0)
			n.callout_label = c
			l.add_child(c)
		_place(n)
	return n


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


func tick(dt: float) -> void:
	for i in range(numbers.size() - 1, -1, -1):
		var n := numbers[i]
		n.age += dt
		n.pop_age += dt
		if n.age >= LIFETIME:
			_drop(i)
		else:
			_place(n)


func clear() -> void:
	for i in range(numbers.size() - 1, -1, -1):
		_drop(i)


func _drop(i: int) -> void:
	var n := numbers[i]
	if n.label:
		n.label.queue_free()
		n.label = null
		n.callout_label = null
	numbers.remove_at(i)


func _place(n: Number) -> void:
	if n.label == null:
		return
	if is_inside_tree():
		n.label.global_position = position_of(n)
	else:
		n.label.position = position_of(n)
	n.label.pixel_size = PIXEL_SIZE * n.scale * pop_scale(n)
	var c := n.color
	c.a = alpha_of(n)
	n.label.modulate = c
	n.label.outline_modulate = Color(0, 0, 0, c.a)
	if n.callout_label:
		var cc := n.callout_color
		cc.a = c.a
		n.callout_label.modulate = cc
		n.callout_label.outline_modulate = Color(0, 0, 0, c.a)


## L4: the live number on `target` that a hit now merges into (null: start a new one).
func merge_target(target: Object) -> Number:
	if target == null:
		return null
	for i in range(numbers.size() - 1, -1, -1):
		var n := numbers[i]
		if n.target == target:
			return n if n.age < merge_s else null
	return null


## L4: the stack step for a new number on `target` (one above its highest live number).
func stack_for(target: Object) -> int:
	if target == null:
		return 0
	var top := -1
	for n in numbers:
		if n.target == target:
			top = maxi(top, n.stack)
	return mini(top + 1, STACK_MAX) if top >= 0 else 0


## L4: 1 + a pop that eases back to 1 over POP_S.
static func pop_scale(n: Number) -> float:
	if n.pop <= 0.0 or n.pop_age >= POP_S:
		return 1.0
	var k := 1.0 - n.pop_age / POP_S
	return 1.0 + n.pop * k * k


## Current world position (rising, drifting, stacked per target).
static func position_of(n: Number) -> Vector3:
	var t := clampf(n.age / LIFETIME, 0.0, 1.0)
	var rise := RISE * (1.0 - (1.0 - t) * (1.0 - t))
	return n.world + Vector3(n.drift_x * t, rise + STACK_STEP * n.stack, 0.0)


static func alpha_of(n: Number) -> float:
	var t := clampf(n.age / LIFETIME, 0.0, 1.0)
	if t <= FADE_START:
		return 1.0
	return clampf(1.0 - (t - FADE_START) / (1.0 - FADE_START), 0.0, 1.0)


## "15", "11.3", "7.5", "0": one decimal unless whole (rounded to 0.1); negatives show 0.
static func format(amount: float) -> String:
	var r := roundf(maxf(0.0, amount) * 10.0) / 10.0
	if absf(r - roundf(r)) < 1e-3:
		return "%d" % int(roundf(r))
	return "%.1f" % r
