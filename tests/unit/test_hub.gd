extends TestCase
## Step 66 done check: the Old Oak hub - its stash is shared across save slots, the Assembly
## Station is there, and Bob's arrival plays once (then never again, even after a reload).

const FILE := "user://test_hub_save.json"
const STASH := "user://test_hub_stash.json"


func _game(load_save: bool) -> Node:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	Stash.shared_path = STASH
	GameFlow.level_id = "old_oak"
	GameFlow.load_save = load_save
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(0, 0, 9000)
	runner_tree.root.add_child(g)
	return g


func _cleanup() -> void:
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	Stash.shared_path = Stash.PATH
	for f in [FILE, STASH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func test_stash_shared() -> void:
	var p := Player.new()
	p.input_enabled = false
	var item := (
		WieldablePart.load_part(WieldablePart.list_ids()[0]) if not WieldablePart.list_ids().is_empty() else null
	)
	check(item != null, "a part to stash")
	p.inventory.add(item)
	var a := Stash.load_shared(STASH)
	check(a.store(p, item) and not p.inventory.has(item), "backpack -> stash")
	check(not a.store(p, item), "can't stash what isn't carried")
	a.save()
	var b := Stash.load_shared(STASH)  # another slot / character opens the same stash
	check(b.items.size() == 1, "same stash from another load")
	var other := Player.new()
	other.input_enabled = false
	check(
		b.take(other, b.items[0]) and other.inventory.size() == 1 and b.items.is_empty(), "taken by another character"
	)
	p.free()
	other.free()
	_cleanup()


func test_station_and_mentor_once() -> void:
	var g := _game(false)
	check(GameFlow.id_of(g.get_node("Level")) == "old_oak", "Old Oak loaded")
	check(g.get_node_or_null("AssemblyStation") is AssemblyStation, "Assembly Station present")
	check(g.stash != null, "stash present")
	check(g.gate.target == "town_square", "exit to town")
	check(not g.mentor_played, "no Bob before the home is unlocked")
	g.story_flags.set_flag("home_unlocked")
	var p := g.get_node("Player") as Player
	check(MentorArrival.play(g.story_flags, p, g.dialogue, g, Vector3.ZERO), "Bob arrives")
	check(g.dialogue.active and g.dialogue.speaker() == "Bob", "Bob appraises the Summoned")
	check(g.get_node_or_null("BobVortex") != null, "teleport vortex")
	check(p.equipment.potion_count >= 1 and g.story_flags.has("starter_gear_given"), "starter gear")
	check(not MentorArrival.play(g.story_flags, p, g.dialogue), "only once")
	g.dialogue.end()
	g.save_game()
	g.free()
	var h := _game(true)
	check(h.story_flags.has(MentorArrival.FLAG) and not h.mentor_played, "not again after a reload")
	h.free()
	_cleanup()
