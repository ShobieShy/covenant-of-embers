extends TestCase
## Step 114 done check: the Association's staff-only back door stays shut until Bob opens
## the route, the Clerk waves you through, and stepping into the Landfill starts the combat.


func _game(level: String, beat: String, extra: Array = []) -> Node:
	GameFlow.dry_run = true
	GameFlow.level_id = level
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	IntroDirector.start(g.story_flags)
	IntroDirector.reach(g.story_flags, beat)
	for f in extra:
		g.story_flags.set_flag(f)
	runner_tree.root.add_child(g)
	return g


func _cleanup(g: Node) -> void:
	g.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"


func test_back_door_locked_before_bob() -> void:
	var g := _game("mage_association", "grant")
	var door: LevelGate = g.intro.gate_to("midden")
	check(door != null, "back door exists")
	check(door.locked() and not door.use(), "staff only")
	check(door.locked_text.contains("Staff only"), "Elders' order text")
	check(door.global_position.z < -12.0, "behind the dais")
	_cleanup(g)


func test_back_door_after_bob() -> void:
	var g := _game("mage_association", "back_door", ["permit_given", "bob_met", "landfill_route_open"])
	var it: IntroDirector = g.intro
	var door := it.gate_to("midden")
	check(not door.locked(), "Bob's word opens it")
	check(it.target_point() == door.global_position, "marker -> back door")
	var line: Dictionary = (g.dialogue as DialogueRunner).db.pick("Clerk", g.story_flags)
	check(String(line.get("id", "")) == "clerk_backdoor", "Clerk: Bob? ...Fine. Go.")
	_cleanup(g)


func test_landfill_starts_combat() -> void:
	var g := _game("midden", "back_door", ["permit_given", "bob_met", "landfill_route_open"])
	check(IntroDirector.beat(g.story_flags) == "combat", "Landfill -> combat beat")
	_cleanup(g)
