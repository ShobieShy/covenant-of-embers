extends TestCase
## Step 109 done check: the intro's beat state (forward only, saved as a flag), New Game
## starting it in the Association empty-handed, --skip-intro landing at the Old Oak with the
## end state, and plain test loads (no intro mode) staying untouched.

const FILE := "user://test_intro_save.json"


func _game(level: String, mode: String) -> Node:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.level_id = level
	GameFlow.load_save = false
	GameFlow.intro_mode = mode
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(0, 0, -9000)
	runner_tree.root.add_child(g)
	return g


func _cleanup(g: Node) -> void:
	if g:
		g.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.intro_mode = ""
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


func test_beats_forward_only() -> void:
	var f := StoryFlags.new()
	check(IntroDirector.beat(f) == "" and not IntroDirector.active(f), "no intro by default")
	IntroDirector.start(f)
	check(IntroDirector.beat(f) == "summoning", "starts at the summoning")
	check(IntroDirector.reach(f, "grant") and IntroDirector.beat(f) == "grant", "moves forward")
	check(not IntroDirector.reach(f, "appraisal") and IntroDirector.beat(f) == "grant", "never back")
	check(not IntroDirector.reach(f, "nope"), "unknown beat refused")
	var g := StoryFlags.new()
	g.from_dict(f.to_dict())
	check(IntroDirector.beat(g) == "grant", "beat survives a save")
	IntroDirector.finish(f)
	check(not IntroDirector.active(f) and f.has("tutorial_done") and f.has("filth_defeated"), "finish opens the world")
	check(IntroDirector.BEATS.size() == 13 and IntroDirector.LEVEL.size() == 13, "13 beats, each with a level")
	for b in IntroDirector.BEATS:
		check(GameFlow.LEVELS.has(IntroDirector.LEVEL[b]) and IntroDirector.OBJECTIVES.has(b), "%s placed" % b)


func test_new_game_runs_intro() -> void:
	GameFlow.dry_run = true
	GameFlow.new_run(null)
	check(
		GameFlow.level_id == "mage_association" and GameFlow.intro_mode == GameFlow.INTRO_PLAY,
		"new game -> Association"
	)
	var g := _game("mage_association", GameFlow.INTRO_PLAY)
	var p := g.get_node("Player") as Player
	check(g.intro != null and g.intro.current() == "summoning", "director runs the summoning")
	check(p.loadout.wieldable(Loadout.Slot.STAFF) == null, "empty-handed until Bob")
	check(GameFlow.intro_mode == "", "intro mode consumed")
	g.save_game()
	g.free()
	g = null
	GameFlow.level_id = "mage_association"
	GameFlow.load_save = true
	var h: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	runner_tree.root.add_child(h)
	var hp := h.get_node("Player") as Player
	check(
		h.intro != null and hp.loadout.wieldable(Loadout.Slot.STAFF) == null,
		"reload keeps the intro and the empty hand"
	)
	_cleanup(h)


func test_skip_intro() -> void:
	check(GameFlow.intro_mode_from_args(PackedStringArray(["--skip-intro"])) == GameFlow.INTRO_SKIP, "--skip-intro")
	GameFlow.dry_run = true
	GameFlow.new_run(null, GameFlow.INTRO_SKIP)
	check(GameFlow.level_id == "old_oak", "skip -> Old Oak")
	var g := _game("old_oak", GameFlow.INTRO_SKIP)
	var p := g.get_node("Player") as Player
	check(g.intro == null and g.story_flags.has(IntroDirector.DONE), "skipped intro is done")
	check(g.story_flags.has("tutorial_done") and g.story_flags.has("fast_travel_crystal"), "world open")
	check(p.loadout.wieldable(Loadout.Slot.STAFF) != null and p.loadout.wieldable(Loadout.Slot.WAND) != null, "armed")
	_cleanup(g)


func test_plain_load_untouched() -> void:
	var g := _game("midden", "")
	check(g.intro == null and not g.story_flags.has(IntroDirector.FLAG), "no intro without a mode")
	check((g.get_node("Player") as Player).loadout.wieldable(Loadout.Slot.STAFF) != null, "default staff")
	_cleanup(g)
