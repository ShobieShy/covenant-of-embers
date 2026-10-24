class_name RusherDef
extends RefCounted
## The "rusher" brain's tuning (BUILD_PLAN step 12, port of the archived C++ RusherDef +
## its loader checks in game/enemies/enemy.cpp, old step 23). Read from EnemyDef.ai (the
## raw `ai` inline table of data/enemies/*.toml, kept as a Dictionary in the .tres).
##
## Defaults are Magewar's enemy_base.gd exports (read-only): detection_range 15,
## aggro_range 10, walk_speed 2, sprint_speed 4, contact_damage 5, attack_cooldown 1.5,
## knockback_strength 10, knockback_duration 0.5, knockback over 10 damage. The Gnawer
## (Magewar's Mutant Rat: 8 / 6 / 3 / 5.5 / 3 dmg / 0.8 s) overrides them in its TOML.

const KINDS: PackedStringArray = ["rusher", "tank", "boss"]   ## tank (step 13): the Heap; boss (step 34): the Warden (Enemy.BRAINS)
const KEYS: PackedStringArray = ["kind", "detect_range", "aggro_range", "walk_speed", "sprint_speed",
	"attack_range", "attack_damage", "attack_cooldown", "knockback_strength", "knockback_time",
	"knockback_threshold", "turn_rate_deg", "attack_windup"]
const PLAYER_RADIUS := 0.3     ## the bite must reach past half the body + this

## key -> [default, min, max] (C++ readFloatIn ranges).
const RANGES := {
	"detect_range": [15.0, 0.5, 200.0],
	"aggro_range": [10.0, 0.5, 200.0],
	"walk_speed": [2.0, 0.1, 30.0],
	"sprint_speed": [4.0, 0.1, 30.0],
	"attack_range": [1.0, 0.2, 10.0],
	"attack_damage": [5.0, 0.0, 100000.0],
	"attack_cooldown": [1.5, 0.05, 60.0],
	"knockback_strength": [10.0, 0.0, 50.0],
	"knockback_time": [0.5, 0.0, 5.0],
	"knockback_threshold": [10.0, 0.0, 100000.0],
	"turn_rate_deg": [540.0, 1.0, 3600.0],
	"attack_windup": [0.0, 0.0, 10.0],   ## step 13: s rooted before the hit lands (0 = at once, the bite)
}

var kind := "rusher"
var detect_range := 15.0
var aggro_range := 10.0
var walk_speed := 2.0
var sprint_speed := 4.0
var attack_range := 1.0
var attack_damage := 5.0
var attack_cooldown := 1.5
var knockback_strength := 10.0
var knockback_time := 0.5
var knockback_threshold := 10.0
var turn_rate_deg := 540.0
var attack_windup := 0.0

## {"def": RusherDef} or {"error": "..."} (the C++ loader's messages). `body` is the enemy's
## size (the attack-range check needs it). "tank" (the Heap, step 13) takes the same keys;
## its attack_windup roots it before the slam lands (Gnawer/rusher: 0, the bite is instant).
static func parse(ai: Variant, body: Vector3) -> Dictionary:
	if not (ai is Dictionary):
		return {"error": "ai must be a table { kind = \"rusher\", ... }"}
	var t: Dictionary = ai
	for k in t:
		if not KEYS.has(String(k)):
			return {"error": "ai: unknown key '%s'" % k}
	if not t.has("kind"):
		return {"error": "ai: missing key 'kind'"}
	if not (t["kind"] is String):
		return {"error": "ai kind must be a string"}
	if not KINDS.has(String(t["kind"])):
		return {"error": "unknown ai kind '%s' (expected rusher or tank)" % t["kind"]}
	var r := RusherDef.new()
	r.kind = t["kind"]
	for k: String in RANGES:
		var spec: Array = RANGES[k]
		var v: Variant = t.get(k, spec[0])
		if not (v is float or v is int):
			return {"error": "ai.%s must be a number" % k}
		var f := float(v)
		if f < float(spec[1]) or f > float(spec[2]):
			return {"error": "ai.%s must be in [%s, %s]" % [k, spec[1], spec[2]]}
		r.set(k, f)
	if r.aggro_range > r.detect_range:
		return {"error": "ai aggro_range must not exceed detect_range"}
	if r.attack_windup >= r.attack_cooldown:
		return {"error": "ai attack_windup must be shorter than attack_cooldown"}
	var contact := 0.5 * maxf(body.x, body.z) + PLAYER_RADIUS
	if r.attack_range <= contact:
		return {"error": "ai attack_range must exceed half the body + the 0.3 m player radius (%.2f m)" % contact}
	return {"def": r}
