class_name EnemyDef
extends Resource
## One enemy type (BUILD_PLAN step 11, port of the archived C++ EnemyDef, old step 22).
## Data: resources/enemies/*.tres, cross-checked against data/enemies/*.toml (the C++
## engine's source, read with LevelToml) by tests/unit/test_enemy.gd.
##
## Magewar reference (scripts/enemies/enemy_base.gd, read-only): an enemy has a name and an
## element affinity (MagicElement) used for get_effectiveness; health is a
## CogitoHealthAttribute child. Reinterpreted: health on the def, plus per-element
## resistance and a weak-point hitbox (x2), our additions to Magewar's formula (PLAN §30.1).

@export var id := ""                                           ## lower_snake_case, unique
@export var display_name := ""
@export var affinity: ElementTable.Element = ElementTable.Element.ARCANE  ## defender element
@export var max_health := 100.0                                ## 1..100000
@export var size := Vector3(0.7, 1.6, 0.7)                     ## body box full extents; stands on its feet
@export var color := Color(0.6, 0.6, 0.6)                      ## greybox tint (the weak point draws brighter)
@export var resist: Dictionary = {}                            ## element id -> 0..1 (applied capped at 60 %)
@export var has_weak_point := false
@export var weak_point_offset := Vector3.ZERO                  ## box centre from the feet (yaw-rotated)
@export var weak_point_size := Vector3(0.3, 0.3, 0.3)          ## full extents
@export var ai: Dictionary = {}                                ## step 12: raw `ai` table (empty = a dummy; see RusherDef)

const MAX_HEALTH_LIMIT := 100000.0

## A fresh Damage.Target for this type: its affinity and (uncapped) resistances.
func make_target() -> Damage.Target:
	var t := Damage.Target.new(affinity)
	for k in resist:
		var e := ElementTable.parse(String(k))
		if e >= 0:
			t.set_resist(e as ElementTable.Element, float(resist[k]))
	return t

## Resist for one element (0 when unset).
func resist_of(e: ElementTable.Element) -> float:
	return float(resist.get(ElementTable.id_of(e), 0.0))

func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	if re.search(id) == null:
		errs.append("id '%s' must be lower_snake_case" % id)
	if display_name.strip_edges().is_empty():
		errs.append("'%s': name is empty" % id)
	if affinity < 0 or affinity >= ElementTable.COUNT:
		errs.append("'%s': bad affinity" % id)
	if not (max_health >= 1.0 and max_health <= MAX_HEALTH_LIMIT):
		errs.append("'%s': max_health must be in 1..100000" % id)
	if not (size.x > 0.0 and size.y > 0.0 and size.z > 0.0):
		errs.append("'%s': size must be > 0" % id)
	for c in [color.r, color.g, color.b]:
		if c < 0.0 or c > 1.0:
			errs.append("'%s': color must be in 0..1" % id)
			break
	for k in resist:
		if ElementTable.parse(String(k)) < 0:
			errs.append("'%s': unknown resist element '%s'" % [id, k])
		elif not (float(resist[k]) >= 0.0 and float(resist[k]) <= 1.0):
			errs.append("'%s': resist.%s must be in 0..1" % [id, k])
	if has_weak_point and not (weak_point_size.x > 0.0 and weak_point_size.y > 0.0 and weak_point_size.z > 0.0):
		errs.append("'%s': weak_point size must be > 0" % id)
	if not ai.is_empty():
		var r := RusherDef.parse(ai, size)
		if r.has("error"):
			errs.append("'%s': %s" % [id, r["error"]])
	return errs

## The brain's tuning (null for a brainless dummy or a bad `ai` table).
func rusher() -> RusherDef:
	if ai.is_empty():
		return null
	return RusherDef.parse(ai, size).get("def") as RusherDef

const KEYS: PackedStringArray = ["id", "name", "affinity", "max_health", "size", "color", "resist", "weak_point", "ai"]
const REQUIRED: PackedStringArray = ["id", "name", "affinity", "max_health", "size", "color"]

## From one data/enemies/*.toml [[enemy]] row (LevelToml). Returns {"def": EnemyDef} or
## {"error": "..."} with the C++ loader's checks (required keys, unknown keys, ranges).
## `ai` (step 12's brain) is kept raw in `ai` and checked by RusherDef.parse.
static func from_toml(row: Dictionary) -> Dictionary:
	for k in row:
		if not KEYS.has(String(k)):
			return {"error": "unknown key '%s'" % k}
	for k in REQUIRED:
		if not row.has(k):
			return {"error": "missing key '%s'" % k}
	var d := EnemyDef.new()
	if not (row["id"] is String and row["name"] is String and row["affinity"] is String):
		return {"error": "id, name and affinity must be strings"}
	d.id = row["id"]
	d.display_name = row["name"]
	var e := ElementTable.parse(row["affinity"])
	if e < 0:
		return {"error": "'%s': unknown affinity '%s'" % [d.id, row["affinity"]]}
	d.affinity = e as ElementTable.Element
	if not (row["max_health"] is float):
		return {"error": "'%s': max_health must be a number" % d.id}
	d.max_health = row["max_health"]
	var sz: Variant = _vec3_or_null(row["size"])
	var col: Variant = _vec3_or_null(row["color"])
	if sz == null or col == null:
		return {"error": "'%s': size and color must be [x, y, z] numbers" % d.id}
	d.size = sz
	d.color = Color((col as Vector3).x, (col as Vector3).y, (col as Vector3).z)
	if row.has("resist"):
		if not (row["resist"] is Dictionary):
			return {"error": "'%s': resist must be an inline table" % d.id}
		for k in row["resist"]:
			if not (row["resist"][k] is float):
				return {"error": "'%s': resist.%s must be a number" % [d.id, k]}
			d.resist[String(k)] = float(row["resist"][k])
	if row.has("weak_point"):
		var wp: Variant = row["weak_point"]
		if not (wp is Dictionary):
			return {"error": "'%s': weak_point must be an inline table" % d.id}
		var off: Variant = _vec3_or_null((wp as Dictionary).get("offset"))
		if off == null:
			return {"error": "'%s': weak_point offset must be [x, y, z]" % d.id}
		var ws: Variant = _vec3_or_null((wp as Dictionary).get("size"))
		if ws == null:
			return {"error": "'%s': weak_point size must be [x, y, z]" % d.id}
		d.has_weak_point = true
		d.weak_point_offset = off
		d.weak_point_size = ws
	if row.has("ai"):
		if not (row["ai"] is Dictionary):
			return {"error": "'%s': ai must be a table { kind = \"rusher\", ... }" % d.id}
		if (row["ai"] as Dictionary).is_empty():
			return {"error": "'%s': ai: missing key 'kind'" % d.id}
		d.ai = row["ai"]
	var errs := d.validate()
	if not errs.is_empty():
		return {"error": "; ".join(errs)}
	return {"def": d}

static func _vec3_or_null(v: Variant) -> Variant:
	if not (v is Array) or (v as Array).size() != 3:
		return null
	for x in v:
		if not (x is float):
			return null
	return LevelToml.vec3(v)
