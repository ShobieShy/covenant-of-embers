extends TestCase
## 0.3.2: every enemy stat has a LevelScale.TABLE row, and nothing stale remains.

const SUBTYPES := [
	"res://scripts/enemies/elites.gd",
	"res://scripts/enemies/goblin_king.gd",
	"res://scripts/enemies/filth.gd",
	"res://scripts/enemies/warden.gd",
	"res://scripts/enemies/ooze.gd",
	"res://scripts/enemies/scorchling.gd",
	"res://scripts/enemies/gnawer.gd",
	"res://scripts/enemies/heap.gd",
	"res://scripts/enemies/enemy.gd",
]


func test_table_covers_every_stat() -> void:
	var have := {}
	var e := EnemyDef.new()
	for p in e.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			have[String(p["name"])] = "EnemyDef"
	for k in RusherDef.RANGES:
		have[String(k)] = "RusherDef"
	have["kind"] = "RusherDef"
	for path in SUBTYPES:
		var s: Script = load(path)
		var cmap: Dictionary = s.get_script_constant_map()
		for k in cmap:
			var v: Variant = cmap[k]
			var t := typeof(v)
			if t == TYPE_INT or t == TYPE_FLOAT:
				have[String(k)] = path.get_file()
	for stat in have:
		check(LevelScale.TABLE.has(stat), "no TABLE row for %s (%s)" % [stat, have[stat]])
		if not LevelScale.TABLE.has(stat):
			continue
		var row: Dictionary = LevelScale.TABLE[stat]
		if row.has("scale"):
			check(LevelScale.CURVES.has(String(row["scale"])), "%s uses unknown curve %s" % [stat, row["scale"]])
		else:
			check(row.has("fixed") and String(row["fixed"]) != "", "%s needs a fixed reason" % stat)
	for stat in LevelScale.TABLE:
		check(have.has(stat), "stale TABLE row %s" % stat)
