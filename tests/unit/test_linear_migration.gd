extends TestCase
## 0.4.0: a world save becomes a closed level. world_pos / region / fog stay (a 0.3.x
## build can still read the file), the Labyrinth floor stays, and the first write of a
## real slot keeps slotN.pre_linear.json.


func test_world_save_lands_on_a_level_or_the_hub() -> void:
	var oak := SaveMigration.entrance("old_oak")
	var d := {
		"version": SaveGame.VERSION,
		"progress":
		{
			"level_id": "old_oak",
			"world_v": SaveMigration.WORLD_V,
			"world_pos": [oak.x, oak.y, oak.z],
			"region": "eldoria",
			"fog": "kept",
			"flags": {"waystone:town_market": 1, "waystone:landfill_camp": 1},
			"labyrinth": {"current": 4, "deepest": 4, "save_seed": 9},
		},
	}
	check(SaveMigration.migrate_linear(d), "migrated")
	var pr: Dictionary = d["progress"]
	check(pr["level_id"] == "old_oak" and pr["flow"] == "linear" and int(pr["linear_v"]) == 3, "oak save stays")
	check(pr["world_pos"][0] == oak.x and pr["region"] == "eldoria" and pr["fog"] == "kept", "world keys kept")
	check(int(pr["labyrinth"]["current"]) == 4, "labyrinth floor kept")
	check(int(pr["flags"]["waystone:town_gate"]) == 1 and int(pr["flags"]["waystone:town_market"]) == 1, "market -> hub")
	check(int(pr["flags"]["waystone:landfill"]) == 1, "camp -> landfill")
	check(not SaveMigration.migrate_linear(d), "second pass is a no-op")


func test_locked_level_falls_back_to_the_hub() -> void:
	var breach := SaveMigration.entrance("breach")
	var d := {
		"progress":
		{
			"level_id": "breach",
			"world_v": 2,
			"world_pos": [breach.x, breach.y, breach.z],
			"region": "landfill",
			"flags": {},
		},
	}
	check(SaveMigration.migrate_linear(d), "migrated")
	check(d["progress"]["level_id"] == "town_square", "no story flags: hub, not the Breach")
	check(d["progress"]["world_pos"][0] == breach.x, "the world position is still there")


func test_level_save_keeps_its_level_id() -> void:
	var d := {"progress": {"level_id": "breach", "flags": {}}}
	check(SaveMigration.migrate_linear(d), "a classic level save migrates")
	check(d["progress"]["level_id"] == "breach" and int(d["progress"]["linear_v"]) == 3, "level_id kept")
	check(not d["progress"].has("world_pos"), "a level save does not grow a world position")


func test_character_file_and_slot_backup() -> void:
	var ch := {"version": 1, "player": {"level": 4}}
	check(not SaveMigration.migrate_linear(ch) and not ch.has("progress"), "character files skipped")
	var path := SaveGame.slot_path(2)
	var bak := SaveMigration.pre_linear_path(path)
	for f in [path, bak]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var body := {"version": SaveGame.VERSION, "progress": {"level_id": "midden"}}
	check(SaveGame.write(body, path) == OK, "slot written")
	var loaded: Dictionary = SaveGame.read(path)["data"]
	check(SaveMigration.store_linear(loaded, path), "first linear write")
	check(FileAccess.file_exists(bak), "slot2.pre_linear.json kept")
	var backup: Dictionary = SaveGame.read(bak)["data"]
	check(not backup["progress"].has("linear_v"), "the backup is the pre-linear file")
	check(int(loaded["progress"]["linear_v"]) == 3, "the slot is linear")
	check(not SaveMigration.store_linear(loaded, path), "already linear: no second write")
	for f in [path, bak, path + ".bak"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
