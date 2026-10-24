extends TestCase
## Step 116 done check: the Filth reveal, home to Bob, the crystal cinematic and the
## open world - the full chain to intro_done; fast travel (the map) only after.

const BEFORE := ["permit_given", "joe_met", "joe_expelled", "home_unlocked", "bob_arrived", "bob_met"]


func _game(level: String, beat: String, extra: Array = []) -> Node:
	GameFlow.dry_run = true
	GameFlow.level_id = level
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	IntroDirector.start(g.story_flags)
	IntroDirector.reach(g.story_flags, beat)
	for f in BEFORE + ["landfill_route_open", "crafted_once", "light_learned", "dark_learned"] + extra:
		g.story_flags.set_flag(f)
	runner_tree.root.add_child(g)
	return g


func _cleanup(g: Node) -> void:
	g.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"


func test_filth_reveal_and_return() -> void:
	var g := _game("midden", "filth")
	var it: IntroDirector = g.intro
	check(it.spawner().trigger_radius > 0.0, "mound armed")
	check(it.gate_to("town_square").locked(), "barrier gate barred")
	GameEvents.bus().wave_started.emit(0, Filth.WAVE_ID)
	check(it.cinematic != null and Cinematic.playing == it.cinematic, "Filth reveal plays")
	it.cinematic.skip()
	g.story_flags.set_flag("filth_defeated")
	check(it.current() == "return_to_bob", "back to Bob")
	check(not it.gate_to("town_square").locked(), "barrier gate opens")
	_cleanup(g)


func test_crystal_finale_opens_world() -> void:
	var g := _game("old_oak", "return_to_bob", ["filth_defeated"])
	var it: IntroDirector = g.intro
	check(it.current() == "crystal", "home -> crystal beat")
	check(IntroDirector.refuse(g, "map"), "no fast travel yet")
	check(g.talk_to("Bob"), "talk to Bob")
	var d: DialogueRunner = g.dialogue
	check(String(d.entry.get("id", "")) == "bob_after_filth", "Bob's after-Filth talk")
	for i in 20:
		if d.active:
			d.advance()
	check(it.cinematic != null, "crystal cinematic")
	it.cinematic.skip()
	var f: StoryFlags = g.story_flags
	check(f.has(IntroDirector.DONE) and not IntroDirector.active(f), "intro_done")
	check(f.has("tutorial_done") and f.has("fast_travel_crystal"), "crystal + tutorial flags")
	check(not IntroDirector.refuse(g, "map") and IntroDirector.lock_text("save") == "", "menus open")
	for gate in g.gates:
		check(not gate.locked(), "gate %s open" % gate.target)
	_cleanup(g)
