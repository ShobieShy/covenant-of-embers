extends TestCase
## Step 112 done check: intro gates open on their flags, the objective marker follows the
## beat (NPC here, else the next gate on the route), and menus stay locked until Bob.


func _game(level: String, beat: String) -> Node:
	GameFlow.dry_run = true
	GameFlow.level_id = level
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	IntroDirector.start(g.story_flags)
	IntroDirector.reach(g.story_flags, beat)
	runner_tree.root.add_child(g)
	return g


func _cleanup(g: Node) -> void:
	g.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"


func test_town_gates_and_marker() -> void:
	var g := _game("town_square", "welcome")
	var it: IntroDirector = g.intro
	check(it != null, "director in town")
	var landfill := it.gate_to("midden")
	check(landfill.locked() and not landfill.use(), "guard blocks the Landfill")
	check(not it.gate_to("old_oak").locked(), "Old Oak open")
	check(it.target_point() == it.gate_to("old_oak").global_position, "marker -> Old Oak gate")
	g.story_flags.set_flag("filth_defeated")
	check(not landfill.locked(), "guard steps aside after the Filth")
	IntroDirector.reach(g.story_flags, "back_door")
	check(it.target_point() == it.gate_to("mage_association").global_position, "marker -> Association")
	_cleanup(g)


func test_association_marker_and_locks() -> void:
	var g := _game("mage_association", "grant")
	var it: IntroDirector = g.intro
	check(it.target_point() == (it.cast["Clerk"] as Npc).global_position, "marker -> Clerk")
	check(it.gate_to("town_square").locked(), "front door locked")
	check(IntroDirector.lock_text("inventory") != "" and IntroDirector.lock_text("save") != "", "menus locked")
	check(IntroDirector.refuse(g, "map"), "waystone dormant")
	g.story_flags.set_flag("permit_given")
	check(not it.gate_to("town_square").locked(), "permit opens the front door")
	g.story_flags.set_flag("bob_met")
	check(IntroDirector.lock_text("inventory") == "" and IntroDirector.lock_text("skills") == "", "Bob unlocks menus")
	IntroDirector.finish(g.story_flags)
	check(IntroDirector.lock_text("map") == "", "nothing locked after the intro")
	_cleanup(g)
	check(IntroDirector.live == null, "lock state cleared with the director")
