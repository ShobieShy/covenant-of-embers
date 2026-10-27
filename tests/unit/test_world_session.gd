extends TestCase
## OW10: open-world start spots (fresh intro, skipped intro, saves), and the progress keys.


func _fixture(lvl: String) -> Dictionary:
	var v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/saves_v1/%s.json" % lvl)
	)
	return v if v is Dictionary else {}


func test_fresh_runs() -> void:
	var play := WorldSession.start_spot({}, GameFlow.INTRO_PLAY)
	check(play["interior"] == "mage_association", "the intro opens in the Association")
	var skip := WorldSession.start_spot({}, GameFlow.INTRO_SKIP)
	check(
		skip["interior"] == "" and skip["pos"] == SaveMigration.entrance("old_oak"), "skip: Old Oak"
	)


func test_saves() -> void:
	var d := _fixture("midden")
	var s := WorldSession.start_spot(d, GameFlow.INTRO_PLAY)
	check(
		s["interior"] == "" and s["pos"] == SaveMigration.entrance("midden"), "old save: its level"
	)
	check(SaveMigration.is_migrated(d), "migrated on the way")
	var mid := {"progress": {"level_id": "mage_association", "flags": {"intro_beat": 2}}}
	check(
		WorldSession.start_spot(mid, "")["interior"] == "mage_association",
		"mid-intro in the Association resumes indoors"
	)
	check(WorldSession.nearest_level(SaveMigration.entrance("breach")) == "breach", "nearest level")


func test_capture_round_trip() -> void:
	var ow := OpenWorld.new()  # not in the tree: fog + interiors only
	ow.interiors = Interiors.new()
	var at := SaveMigration.entrance("old_oak") + Vector3(3, 0, 2)
	ow.fog.reveal(at.x, at.z)
	var pr := WorldSession.capture(ow, at)
	check(pr["region"] == "eldoria" and pr["interior"] == "", "outdoors in Eldoria")
	var wp: Array = pr["world_pos"]
	check(Vector3(wp[0], wp[1], wp[2]) == at, "world_pos")
	var ow2 := OpenWorld.new()
	WorldSession.restore(ow2, {"progress": pr})
	check(ow2.fog.is_revealed(at.x, at.z), "fog restored")
	var back := WorldSession.start_spot({"progress": pr}, "")
	check(back["pos"] == at, "resumes where it saved")
	ow.interiors.current = "mage_association"
	var inside := WorldSession.capture(ow, Vector3(0, -2000, 0))
	check(inside["interior"] == "mage_association", "indoors recorded")
	ow.interiors.free()
	ow.free()
	ow2.free()


## main.gd with GameFlow.open_world: an old save resumes at its level's world entrance and
## saves the world keys back.
func test_main_open_world() -> void:
	const FILE := "user://test_world_session_save.json"
	const STASH := "user://test_world_session_stash.json"
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	Stash.shared_path = STASH
	var fa := FileAccess.open(FILE, FileAccess.WRITE)
	fa.store_string(FileAccess.get_file_as_string("res://tests/fixtures/saves_v1/old_oak.json"))
	fa.close()
	GameFlow.level_id = "old_oak"
	GameFlow.load_save = true
	GameFlow.open_world = true
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	runner_tree.root.add_child(g)
	var p := g.get_node("Player") as Player
	var want := SaveMigration.entrance("old_oak")
	check(g.get_node_or_null("OpenWorld") is OpenWorld, "the open world is up")
	check(
		Vector2(p.spawn_feet.x, p.spawn_feet.z).distance_to(Vector2(want.x, want.z)) < 0.01,
		"at the Old Oak entrance"
	)
	var pr: Dictionary = g.progress()
	check(
		int(pr.get("world_v", 0)) == SaveMigration.WORLD_V and pr["region"] == "eldoria",
		"world keys %s" % [pr.keys()]
	)
	check(pr["level_id"] == "old_oak", "level_id still saved")
	g.queue_free()
	for i in 10:  # let its cell loads and deferred frees finish before the next test
		await runner_tree.process_frame
	GameFlow.open_world = false
	GameFlow.dry_run = false
	GameFlow.load_save = false
	GameFlow.level_id = "midden"
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	Stash.shared_path = Stash.PATH
	for f in [FILE, STASH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
