extends TestCase
## OW10: the 0.1.4 save fixtures migrate to world positions + region + seeded fog.

const LEVELS: PackedStringArray = ["midden", "town_square", "old_oak", "breach"]


func _fixture(lvl: String) -> Dictionary:
	var v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/saves_v1/%s.json" % lvl)
	)
	return v if v is Dictionary else {}


func test_fixtures_migrate() -> void:
	for lvl in LEVELS:
		var d := _fixture(lvl)
		check(not d.is_empty() and not SaveMigration.is_migrated(d), "%s: an old save" % lvl)
		check(SaveMigration.migrate(d), "%s: migrated" % lvl)
		var pr: Dictionary = d["progress"]
		var wp: Array = pr["world_pos"]
		var want := SaveMigration.entrance(lvl)
		check(
			Vector3(wp[0], wp[1], wp[2]).distance_to(want) < 0.01 and want != Vector3.ZERO,
			"%s: lands at its entrance %s" % [lvl, want]
		)
		check(pr["region"] == WorldMap.LEVEL_REGION[lvl], "%s: region %s" % [lvl, pr["region"]])
		check(pr["level_id"] == lvl, "%s: level_id kept for level builds" % lvl)
		var fog := WorldFog.new()
		fog.from_save(String(pr["fog"]))
		check(fog.is_revealed(want.x, want.z), "%s: fog seeded around the entrance" % lvl)
		check(not SaveMigration.migrate(d), "%s: a second migration is a no-op" % lvl)
		var a := SaveGame.capture(_dummy(), {})
		check(a["version"] == SaveGame.VERSION, "save version unchanged")


func _dummy() -> Player:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.free.call_deferred()
	return p


func test_local_and_unknown() -> void:
	var d := {"progress": {"level_id": "midden", "local_pos": [10.0, 2.0, -4.0]}}
	SaveMigration.migrate(d)
	var e := SaveMigration.entrance("midden")
	var wp: Array = d["progress"]["world_pos"]
	var mid := (load(GameFlow.level_scene("midden")) as PackedScene).instantiate() as Node3D
	var wo: Vector2 = mid.get_meta(&"world_offset")
	mid.free()
	check(
		Vector3(wp[0], wp[1], wp[2]).is_equal_approx(Vector3(10 + wo.x, 2, -4 + wo.y)), "local kept"
	)
	check(e != Vector3(wp[0], wp[1], wp[2]), "not the entrance")
	var u := {"progress": {"level_id": "no_such_place"}}
	SaveMigration.migrate(u)
	var up: Array = u["progress"]["world_pos"]
	check(
		Vector3(up[0], up[1], up[2]).is_equal_approx(SaveMigration.entrance("town_square")),
		"unknown level lands at the town gate"
	)
	var ch := {"version": 1, "player": {"level": 4}}  # a co-op character file
	check(not SaveMigration.migrate(ch) and not ch.has("progress"), "character files untouched")
