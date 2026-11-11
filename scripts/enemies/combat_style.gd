class_name CombatStyle
extends RefCounted
## Per-type combat (0.8.3, issue #24). data/enemies/combat_styles.toml names at least
## two attack patterns and the movement mix (strafe, retreat, dodge, a second strike).
## The Gnawer brain still owns detect / chase / bite cadence. This only adds what that
## brain does once it is in the pocket, so the opening rush stays the authored speeds.
## Each enemy gets its own copy: tests can arm a special early without changing the
## shared row the next spawn reads.

const PATH := "res://data/enemies/combat_styles.toml"

var id := ""
var patterns: PackedStringArray = PackedStringArray()
var special := ""  ## lunge, cleave, fan, feint
var strafe_speed := 0.0
var strafe_period := 1.2
var retreat_speed := 0.0
var retreat_s := 0.0
var dodge_speed := 0.0
var dodge_s := 0.16
var arm_s := 8.0  ## seconds in the fight before the second strike can start
var windup := 0.3
var lunge_speed := 0.0
var damage_mul := 1.0
var cooldown := 3.0
var recover := 0.2

static var _by_id := {}
static var _loaded := false


static func for_id(id: String) -> CombatStyle:
	_ensure()
	var src: CombatStyle = _by_id.get(id) as CombatStyle
	if src == null:
		return null
	return src.cloned()


static func ids() -> PackedStringArray:
	_ensure()
	var out := PackedStringArray()
	for k in _by_id:
		out.append(String(k))
	return out


static func reload() -> void:
	_loaded = false
	_by_id = {}
	_ensure()


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed := LevelToml.load_file(PATH)
	if parsed.has("error"):
		push_error(String(parsed["error"]))
		return
	for row in parsed.get("style", []):
		if not (row is Dictionary):
			continue
		var s := from_row(row)
		if not s.id.is_empty():
			_by_id[s.id] = s


static func from_row(row: Dictionary) -> CombatStyle:
	var s := CombatStyle.new()
	s.id = String(row.get("id", ""))
	s.special = String(row.get("special", "feint"))
	var pats: Variant = row.get("patterns", [])
	if pats is Array:
		for p in pats:
			s.patterns.append(String(p))
	s.strafe_speed = float(row.get("strafe_speed", 0.0))
	s.strafe_period = maxf(0.2, float(row.get("strafe_period", 1.2)))
	s.retreat_speed = float(row.get("retreat_speed", 0.0))
	s.retreat_s = float(row.get("retreat_s", 0.0))
	s.dodge_speed = float(row.get("dodge_speed", 0.0))
	s.dodge_s = float(row.get("dodge_s", 0.16))
	s.arm_s = float(row.get("arm_s", 8.0))
	s.windup = float(row.get("windup", 0.3))
	s.lunge_speed = float(row.get("lunge_speed", 0.0))
	s.damage_mul = float(row.get("damage_mul", 1.0))
	s.cooldown = float(row.get("cooldown", 3.0))
	s.recover = float(row.get("recover", 0.2))
	return s


func cloned() -> CombatStyle:
	var s := CombatStyle.new()
	s.id = id
	s.patterns = patterns.duplicate()
	s.special = special
	s.strafe_speed = strafe_speed
	s.strafe_period = strafe_period
	s.retreat_speed = retreat_speed
	s.retreat_s = retreat_s
	s.dodge_speed = dodge_speed
	s.dodge_s = dodge_s
	s.arm_s = arm_s
	s.windup = windup
	s.lunge_speed = lunge_speed
	s.damage_mul = damage_mul
	s.cooldown = cooldown
	s.recover = recover
	return s


## Keep a slide inside the bite pocket: `toward` is a unit vector to the target,
## `dist` is the current horizontal gap. Moving past `pocket` (or inside `min_dist`)
## is shaved off so a strafe cannot walk the enemy out of its attack state.
static func clamp_pocket(delta: Vector3, toward: Vector3, dist: float, pocket: float, min_dist: float) -> Vector3:
	if toward.length_squared() < 1e-8:
		return delta
	var dir := toward.normalized()
	var away := -delta.dot(dir)
	var room := pocket - dist - 0.02
	if away > room:
		delta += dir * (away - maxf(room, 0.0))
	var toward_m := delta.dot(dir)
	var close_room := dist - min_dist
	if toward_m > close_room:
		delta -= dir * (toward_m - maxf(close_room, 0.0))
	return delta
