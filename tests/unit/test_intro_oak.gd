extends TestCase
## Step 113 done check: the Old Oak's first night - no weapon before Bob, the moss bed
## brings night + Bob's vortex once, and his kit (staff, dagger keepsake, route) after.


func _game(flags: StoryFlags) -> Node:
	GameFlow.dry_run = true
	GameFlow.level_id = "old_oak"
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.story_flags.from_dict(flags.to_dict())
	runner_tree.root.add_child(g)
	return g


func _finish_dialogue(g: Node) -> void:
	var d: DialogueRunner = g.dialogue
	for i in 40:
		if not d.active:
			return
		if not d.advance() and d.awaiting_choice():
			d.choose(0)


func test_first_night() -> void:
	var f := StoryFlags.new()
	IntroDirector.start(f)
	IntroDirector.reach(f, "welcome")
	var g := _game(f)
	var p := g.get_node("Player") as Player
	IntroDirector.strip_weapons(p)
	var it: IntroDirector = g.intro
	check(it.current() == "new_home" and it.bed != null, "arrival -> moss bed")
	check(not g.mentor_played and g.get_node_or_null("Npc_Bob") == null, "Bob waits for the night")
	check(it.target_point() == it.bed.global_position, "marker on the bed")
	check(p.loadout.wieldable(Loadout.Slot.STAFF) == null, "no weapon before Bob")
	check(it.rest(), "rest")
	check(not it.rest(), "rests once")
	check(it.cinematic != null and g.get_node_or_null("BobVortex") != null, "vortex cinematic")
	it.cinematic.skip()
	check(g.story_flags.has(MentorArrival.FLAG) and g.get_node_or_null("Npc_Bob") != null, "Bob arrives")
	check(g.dialogue.active and g.dialogue.speaker() == "Bob", "Bob talks")
	_finish_dialogue(g)
	check(p.loadout.wieldable(Loadout.Slot.STAFF) != null, "Bob hands over the staff")
	check(p.loadout.wieldable(Loadout.Slot.WAND) == null, "the wand comes later (Joe)")
	check(g.story_flags.has("rusty_dagger") and g.get_node_or_null("DaggerGlow") != null, "dagger keepsake glows")
	check(it.current() == "back_door" and g.story_flags.has("landfill_route_open"), "route to the Landfill")
	check(IntroDirector.lock_text("inventory") == "", "menus open after Bob")
	var after := StoryFlags.new()
	after.from_dict(g.story_flags.to_dict())
	g.free()
	var h := _game(after)
	check(not h.mentor_played and h.intro.bed == null, "mentor plays once")
	check(h.get_node_or_null("Npc_Bob") != null and h.get_node_or_null("DaggerGlow") != null, "Bob + glow persist")
	h.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"


func test_dagger_glow_range() -> void:
	var d := DaggerGlow.make(null)
	check(d.nearest() == INF, "nothing near without a player")
	d.free()


## Step 127: the night preset is moonlit and readable, not black.
func test_night_preset_is_readable() -> void:
	var level: Node3D = (load("res://scenes/levels/old_oak.tscn") as PackedScene).instantiate()
	NightPreset.apply(level, Vector3.ZERO)
	var env := (level.get_node("WorldEnvironment") as WorldEnvironment).environment
	var sun := level.get_node("Sun") as DirectionalLight3D
	check(sun.light_energy >= 0.3, "moonlight energy >= 0.3")
	check(sun.light_color.b > sun.light_color.r, "moonlight is blue")
	check(env.ambient_light_color.get_luminance() * env.ambient_light_energy > 0.15, "night ambient readable")
	check(env.tonemap_mode != Environment.TONE_MAPPER_LINEAR, "filmic tonemap")
	check(level.get_node_or_null("NightLantern") is OmniLight3D, "warm lantern fill")
	level.free()
