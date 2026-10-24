extends TestCase
## Step 115 done check: the Landfill lessons - each soft wall drops on its flag, the first
## part is guaranteed, Joe hands over the wand, and the forced Dark convert happens once only.


func _game(beat: String, extra: Array = []) -> Node:
	GameFlow.dry_run = true
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	IntroDirector.start(g.story_flags)
	IntroDirector.reach(g.story_flags, beat)
	for f in ["permit_given", "bob_met", "landfill_route_open", "joe_met", "joe_expelled"] + extra:
		g.story_flags.set_flag(f)
	runner_tree.root.add_child(g)
	return g


func _cleanup(g: Node) -> void:
	g.free()
	MagicEffects.force_convert = false
	MagicEffects.dark_roll = Callable()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"


func test_walls_drop_on_their_flags() -> void:
	var g := _game("back_door")
	var it: IntroDirector = g.intro
	check(it.current() == "combat", "Landfill -> combat")
	check(it.wall_up("YardWall") and it.wall_up("JunkWall") and it.wall_up("ArenaWall"), "three walls up")
	check(it.spawner().trigger_radius == 0.0, "the Filth's mound stays quiet")
	check(it.yard.size() == 3, "three yard Gnawers")
	check(it.station().global_position.distance_to(IntroDirector.CAMP) < 0.1, "bench at Joe's camp")
	for e in it.yard.duplicate():
		e.apply_damage(99999.0, ElementTable.Element.FIRE)
	check(g.story_flags.has("gnawers_cleared") and not it.wall_up("YardWall"), "yard wall drops")
	check(it.wall_up("JunkWall"), "junk wall still up")
	check(it.part_pickup != null and it.part_pickup.drop.kind == LootDrop.Kind.PART, "guaranteed part")
	check(it.current() == "crafting" and it.target_point() == it.station().global_position, "marker -> bench")
	GameEvents.bus().crafting_completed.emit(g.get_node("Player"), null)
	check(g.story_flags.has("crafted_once") and not it.wall_up("JunkWall"), "junk wall drops")
	check(it.current() == "light_dark" and it.shrines.size() == 2, "shrines")
	it.touch_shrine("Light shrine")
	check(g.story_flags.has("light_learned") and it.wall_up("ArenaWall"), "Light learned, arena still shut")
	it.touch_shrine("Dark shrine")
	check(it.dark_gnawer != null and it.dark_gnawer.is_ally(), "forced convert")
	check(not it.wall_up("ArenaWall") and it.current() == "filth", "arena opens -> Filth")
	check(it.spawner().trigger_radius > 0.0, "mound trigger back")
	_cleanup(g)


func test_forced_convert_once() -> void:
	MagicEffects.dark_roll = func() -> float: return 0.99
	var g := _game("light_dark", ["gnawers_cleared", "crafted_once", "tutorial_force_convert"])
	var it: IntroDirector = g.intro
	it.touch_shrine("Dark shrine")
	check(not it.dark_gnawer.is_ally(), "no second forced convert")
	check(not MagicEffects.force_convert, "force consumed")
	MagicEffects.force_convert = true
	var d := it.spawner().table.find("gnawer")
	var a := Enemy.create(d, Transform3D(Basis(), Vector3(3, 0, 3)))
	var b := Enemy.create(d, Transform3D(Basis(), Vector3(-3, 0, 3)))
	it.spawner().add_child(a)
	it.spawner().add_child(b)
	check(MagicEffects.try_corrupt(a, 0.0), "forced roll turns")
	check(not MagicEffects.try_corrupt(b, 0.0), "then back to the normal chance")
	_cleanup(g)


func test_joe_gives_wand() -> void:
	var g := _game("combat")
	var p := g.get_node("Player") as Player
	IntroDirector.strip_weapons(p)
	var d: DialogueRunner = g.dialogue
	check(g.talk_to("Crazy Joe") and String(d.entry.get("id", "")) == "joe_landfill", "Joe at his camp")
	for i in 20:
		if d.active:
			d.advance()
	check(p.loadout.wieldable(Loadout.Slot.WAND) != null and g.story_flags.has("joe_wand_given"), "wind wand")
	check((g.get_node("Level") as Node).get_meta("level_name", "").begins_with("The Landfill"), "renamed")
	_cleanup(g)
