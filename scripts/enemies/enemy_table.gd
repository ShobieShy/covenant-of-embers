class_name EnemyTable
extends Resource
## Enemy types by id (BUILD_PLAN step 11). The shipped table is
## resources/enemies/training_dummies.tres + gnawer.tres (step 12) + heap.tres (step 13); `from_toml_files`
## builds one from data/enemies/*.toml for the tests' .tres-vs-TOML comparison.

const DEFAULT_PATHS: PackedStringArray = [
	"res://resources/enemies/training_dummies.tres",
	"res://resources/enemies/gnawer.tres",
	"res://resources/enemies/heap.tres",
	"res://resources/enemies/breach_warden.tres",
	"res://resources/enemies/scorchling.tres",
	"res://resources/enemies/ooze.tres",
]  ## step 34: the Breach mini-boss

@export var defs: Array[EnemyDef] = []

static var _default: EnemyTable


## The shipped enemy types (every DEFAULT_PATHS table merged, validated once).
static func load_default() -> EnemyTable:
	if _default == null:
		_default = EnemyTable.new()
		for p in DEFAULT_PATHS:
			var t := load(p) as EnemyTable
			if t == null:
				push_error("%s: not an EnemyTable" % p)
				continue
			_default.defs.append_array(t.defs)
		var errs := _default.validate()
		if not errs.is_empty():
			push_error("enemy tables: %s" % "; ".join(errs))
	return _default


func find(id: String) -> EnemyDef:
	for d in defs:
		if d != null and d.id == id:
			return d
	return null


func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if defs.is_empty():
		errs.append("no enemy types")
	var seen := {}
	for d in defs:
		if d == null:
			errs.append("null enemy def")
			continue
		if seen.has(d.id):
			errs.append("duplicate enemy id '%s'" % d.id)
		seen[d.id] = true
		errs.append_array(d.validate())
	return errs


## {"table": EnemyTable} or {"error": "path: ..."} from data/enemies/*.toml files.
static func from_toml_files(paths: PackedStringArray) -> Dictionary:
	var t := EnemyTable.new()
	for p in paths:
		var r := from_toml(LevelToml.load_file(p), p)
		if r.has("error"):
			return r
		for d in (r["table"] as EnemyTable).defs:
			if t.find(d.id) != null:
				return {"error": "%s: duplicate enemy id '%s'" % [p, d.id]}
			t.defs.append(d)
	return {"table": t}


static func from_toml(doc: Dictionary, source := "toml") -> Dictionary:
	if doc.has("error"):
		return {"error": doc["error"]}
	var rows: Variant = doc.get("enemy")
	if not (rows is Array) or (rows as Array).is_empty():
		return {"error": "%s: no [[enemy]] tables" % source}
	var t := EnemyTable.new()
	for i in (rows as Array).size():
		var r := EnemyDef.from_toml(rows[i])
		if r.has("error"):
			return {"error": "%s: enemy #%d: %s" % [source, i + 1, r["error"]]}
		var d: EnemyDef = r["def"]
		if t.find(d.id) != null:
			return {"error": "%s: duplicate enemy id '%s'" % [source, d.id]}
		t.defs.append(d)
	return {"table": t}
