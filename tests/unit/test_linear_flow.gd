extends TestCase
## 0.4.0: Old Oak -> Town (hub) -> Landfill -> Breach -> the crater portal.
## Forward gates need the story flag; the road back to town does not.


const FILE := "user://test_linear_flow_save.json"


func _reset() -> void:
	GameFlow.dry_run = true
	GameFlow.open_world = false
	GameFlow.save_path = FILE
	GameFlow.path_override = FILE
	GameFlow.intro_mode = ""
	GameFlow.load_save = false
	GameFlow.last_request = ""
	for f in [FILE, FILE + ".bak", FILE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _restore() -> void:
	GameFlow.dry_run = false
	GameFlow.open_world = false
	GameFlow.path_override = ""
	GameFlow.select_slot(1)
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	for f in [FILE, FILE + ".bak", FILE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _game(level: String, flags: Array) -> Node:
	GameFlow.level_id = level
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	for id in flags:
		g.story_flags.set_flag(id)
	g.position = Vector3(7000, 0, 0)
	runner_tree.root.add_child(g)
	return g


func _gate(g: Node, target: String) -> LevelGate:
	for gate in g.gates:
		if gate.target == target:
			return gate
	return null


func test_closed_levels_are_the_default() -> void:
	check(not GameFlow.open_world and not GameFlow.open_world_on(), "closed levels, no dev flag")
	GameFlow.open_world = true
	check(GameFlow.open_world_on(), "a test can still opt into the world")
	GameFlow.open_world = false


func test_forward_gates_follow_the_story() -> void:
	_reset()
	var oak := _game("old_oak", ["intro_done"])
	var to_town := _gate(oak, "town_square")
	check(to_town != null and to_town.locked() and not to_town.use(), "the grove road waits for the finale")
	oak.story_flags.set_flag("home_unlocked")
	oak.apply_linear_gates()
	check(not to_town.locked() and to_town.use(), "Old Oak finale opens the road to town")
	check(GameFlow.level_id == "town_square" and GameFlow.load_save, "travel loads the hub")
	oak.free()
	var town := _game("town_square", ["intro_done"])
	check(town.stash != null and town.can_respec(), "the hub keeps the stash and respec")
	var map_ev := InputEventAction.new()
	map_ev.action = &"map"
	map_ev.pressed = true
	town._unhandled_input(map_ev)
	check(
		town.level_map != null and town.level_map.visible and town.level_map.linear_level == "town_square",
		"M shows this closed level"
	)
	town.level_map.close()
	var to_fill := _gate(town, "midden")
	check(to_fill.locked(), "the Landfill waits for Bob's lead")
	town.story_flags.set_flag("landfill_route_open")
	town.apply_linear_gates()
	check(not to_fill.locked() and to_fill.use(), "Bob's lead opens the Landfill")
	check(GameFlow.level_id == "midden", "Landfill loaded")
	town.free()
	var fill := _game("midden", ["intro_done", "landfill_route_open"])
	var to_breach := _gate(fill, "breach")
	check(to_breach.locked(), "the Breach waits until the Landfill is done")
	fill.story_flags.set_flag("filth_defeated")
	fill.apply_linear_gates()
	check(not to_breach.locked() and to_breach.use(), "Landfill done opens the Breach")
	check(GameFlow.level_id == "breach", "Breach loaded")
	var back := _gate(fill, "town_square")
	check(back != null and not back.locked(), "the road back to the hub stays open")
	fill.free()
	var breach := _game("breach", ["intro_done", "filth_defeated"])
	var portal := _gate(breach, "labyrinth")
	check(portal != null and not portal.locked(), "the crater portal is the Labyrinth gate")
	check(breach.get_node_or_null("Level/Props/old_oak") == null, "no east-gate oak on this level")
	portal.use()
	var ints := breach.get_node_or_null("LinearInteriors") as Interiors
	var n := 0
	while (ints == null or ints.busy or ints.current != "labyrinth") and n < 120:
		await runner_tree.process_frame
		ints = breach.get_node_or_null("LinearInteriors") as Interiors
		n += 1
	check(ints != null and ints.current == "labyrinth" and ints.floor_no == 1, "entered floor 1 (%d frames)" % n)
	check(ints.level_local, "the floor is in the closed level, not the world offset")
	var town_scene: Node3D = (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	check(town_scene.get_node_or_null("Props/old_oak") == null, "Eldoria does not keep a second Old Oak")
	town_scene.free()
	var grove: Node3D = (load("res://scenes/levels/old_oak.tscn") as PackedScene).instantiate()
	check(grove.get_node_or_null("Props/old_oak") != null, "the oak stands in its own level")
	grove.free()
	breach.free()
	_restore()
