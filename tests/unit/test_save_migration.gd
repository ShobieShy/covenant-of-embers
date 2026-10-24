extends TestCase
## Step 118 done check: saves from before the intro. Clearly-past saves are marked done with
## no question; unclear ones are asked once (both answers stick); "Skip prologue" keys off
## any finished slot; --skip-intro still skips.

const FILE := "user://test_migration_save.json"


func _old_save(level_id: String, lvl: int, flags: Dictionary) -> Dictionary:
	return {
		"version": SaveGame.VERSION,
		"player": {"level": lvl},
		"items": {},
		"progress": {"level_id": level_id, "flags": flags}
	}


func _cleanup() -> void:
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


func test_status() -> void:
	check(SaveGame.intro_status(_old_save("midden", 1, {"tutorial_done": 1})) == SaveGame.INTRO_PAST, "tutorial done")
	check(SaveGame.intro_status(_old_save("midden", 1, {"filth_defeated": 1})) == SaveGame.INTRO_PAST, "filth dead")
	check(SaveGame.intro_status(_old_save("midden", 3, {})) == SaveGame.INTRO_PAST, "level 3")
	check(SaveGame.intro_status(_old_save("breach", 1, {})) == SaveGame.INTRO_PAST, "non-intro level")
	check(SaveGame.intro_status(_old_save("midden", 2, {"bob_met": 1})) == SaveGame.INTRO_ASK, "unclear: ask")
	check(SaveGame.intro_status(_old_save("old_oak", 1, {"intro_beat": 6})) == SaveGame.INTRO_ACTIVE, "mid-intro")
	check(SaveGame.intro_status(_old_save("midden", 1, {"intro_done": 1})) == SaveGame.INTRO_DONE, "done")


func test_past_marked_done_on_disk() -> void:
	SaveGame.write(_old_save("breach", 4, {"bob_met": 1}), FILE)
	check(SaveGame.migrate_intro(FILE) == SaveGame.INTRO_PAST, "reported past")
	var d: Dictionary = SaveGame.read(FILE)["data"]
	check(SaveGame.intro_status(d) == SaveGame.INTRO_DONE, "now done")
	check(int(d["progress"]["flags"].get("fast_travel_crystal", 0)) == 1, "end flags set")
	check(String(d["progress"]["level_id"]) == "breach", "stays where it was")
	check(int(d["progress"]["flags"].get("bob_met", 0)) == 1, "old flags kept")
	_cleanup()


func test_ask_once() -> void:
	SaveGame.write(_old_save("midden", 1, {}), FILE)
	check(SaveGame.migrate_intro(FILE) == SaveGame.INTRO_ASK, "asks")
	check(SaveGame.intro_status(SaveGame.read(FILE)["data"]) == SaveGame.INTRO_ASK, "nothing written before the answer")
	check(SaveGame.answer_intro(FILE, true) == OK, "answer saved")
	var d: Dictionary = SaveGame.read(FILE)["data"]
	check(SaveGame.intro_status(d) == SaveGame.INTRO_ACTIVE, "yes: the intro runs")
	check(IntroDirector.beat(_flags(d)) == "summoning", "from the summoning")
	check(String(d["progress"]["level_id"]) == "mage_association", "in the Association")
	check(SaveGame.migrate_intro(FILE) == SaveGame.INTRO_ACTIVE, "not asked again")
	SaveGame.write(_old_save("midden", 1, {}), FILE)
	SaveGame.answer_intro(FILE, false)
	check(SaveGame.intro_status(SaveGame.read(FILE)["data"]) == SaveGame.INTRO_DONE, "no: marked done")
	_cleanup()


func test_scripted_continue_never_asks() -> void:
	SaveGame.write(_old_save("midden", 1, {}), FILE)
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.continue_run(null)
	check(SaveGame.intro_status(SaveGame.read(FILE)["data"]) == SaveGame.INTRO_DONE, "unasked continue keeps playing")
	GameFlow.dry_run = false
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	_cleanup()


func test_skip_flag() -> void:
	check(GameFlow.intro_mode_from_args(PackedStringArray(["--skip-intro"])) == GameFlow.INTRO_SKIP, "--skip-intro")
	check(GameFlow.intro_mode_from_args(PackedStringArray(["--autoplay"])) == GameFlow.INTRO_PLAY, "bot plays it")


func _flags(d: Dictionary) -> StoryFlags:
	var f := StoryFlags.new()
	f.from_dict(d["progress"]["flags"])
	return f
