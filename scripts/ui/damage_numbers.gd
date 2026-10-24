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


var elements: ElementTable  ## colours (default table when null)
var auto_tick := true  ## false: the owner (tests) calls tick()
var draw_labels := true  ## false: logic only
var numbers: Array[Number] = []
var spawned := 0


func connect_bolts(b: SpellBolts) -> void:
	if b and not b.bolt_hit.is_connected(_on_bolt_hit):
		b.bolt_hit.connect(_on_bolt_hit)


func _on_bolt_hit(h: SpellBolts.Hit) -> void:
	if h.result != null:
		add(h.point, h.result, h.element)


## A number for a resolved hit at `world` (global position).
func add(world: Vector3, r: Damage.Result, element: ElementTable.Element) -> Number:
	var n := Number.new()
	n.world = world
	n.amount = r.amount
	var t := elements if elements != null else ElementTable.load_default()
	n.color = t.color(element) if t else Color.WHITE
	n.scale = CRIT_SCALE if r.crit > 1.0 else STRONG_SCALE if r.strong() else WEAK_SCALE if r.weak() else 1.0
	n.drift_x = DRIFT[spawned % DRIFT.size()]
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
	var c := n.color
	c.a = alpha_of(n)
	n.label.modulate = c
	n.label.outline_modulate = Color(0, 0, 0, c.a)
	if n.callout_label:
		var cc := n.callout_color
		cc.a = c.a
		n.callout_label.modulate = cc
		n.callout_label.outline_modulate = Color(0, 0, 0, c.a)


## Current world position (rising, drifting).
static func position_of(n: Number) -> Vector3:
	var t := clampf(n.age / LIFETIME, 0.0, 1.0)
	var rise := RISE * (1.0 - (1.0 - t) * (1.0 - t))
	return n.world + Vector3(n.drift_x * t, rise, 0.0)


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
