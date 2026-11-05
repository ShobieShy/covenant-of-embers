extends TestCase
## U2: Crown door, crater choice, waystone pads. A trip home keeps the checkpoint.


func test_crater_choice_and_pads() -> void:
	var both := LabyrinthState.fresh(3)
	both.bosses.append("goblin_king")
	both.bosses.append("blightmaw_matriarch")
	check(LabGate.resolve(both, -1) == -1, "both bosses dead still waits for a choice")
	check(LabGate.resolve(both, 9) == 9, "the host can choose the Railhead")
	check(LabGate.choice_label(9) == "The Slagworks, Railhead", "Railhead label")
	check(LabGate.choices(both).has(9), "the picker offers the Railhead")
	check(LabGate.banner(9).begins_with("The Slagworks"), "the vote banner names the act")
	var resumed := LabyrinthState.fresh(3)
	resumed.current = 11
	check(LabGate.resolve(resumed, -1) == 11, "current 11 loads the Overlook and does not open the picker")
	var canopy := LabyrinthState.fresh(3)
	canopy.current = 7
	check(LabGate.resolve(canopy, -1) == 7, "current 7 still loads the Canopy")
	var flags := StoryFlags.new()
	flags.set_flag(FastTravel.CRYSTAL)
	flags.set_flag(FastTravel.TUTORIAL_DONE)
	var ft := FastTravel.new(flags)
	check(not ft.can_travel("slagworks_railhead"), "the Railhead is listed only after that pad is attuned")
	both.bosses.append("forgemaw")
	check(not ft.attuned("slagworks_crucible"), "Forgemaw's death does not attune the crucible")
	check(not ft.can_travel("slagworks_crucible"), "the crucible is refused until the pad is stepped on")
	ft.attune("slagworks_crucible")
	check(ft.can_travel("slagworks_crucible"), "stepping on the crucible pad attunes it")
	ft.attune("town_gate")
	both.current = 13
	check(ft.travel("town_gate"), "the hub travel is allowed")
	check(both.current == 13 and both.bosses.has("forgemaw"), "a trip home keeps current and bosses")
	check(int(FastTravel.info("warrens_hall")["floor"]) == 5, "warrens_hall still travels to floor 5")
	check(int(FastTravel.info("blightcoil_crown")["floor"]) == 8, "blightcoil_crown still travels to 8")
	check(not GameFlow.LEVELS.has("slagworks") and not GameFlow.LEVELS.has("sunken_ruins"), "no new level id")
	check(SaveGame.VERSION == 1 and LabyrinthState.V == 1, "save versions stay 1")


func test_crown_door_and_stairs_up() -> void:
	var level_before := GameFlow.level_id
	var shut := LabyrinthState.fresh(5)
	shut.current = 8
	var closed := Interiors.new()
	closed.labyrinth = shut
	runner_tree.root.add_child(closed)
	await closed.enter("labyrinth")
	closed.cavern.forge.interact()
	check(closed.floor_no == 8 and closed.slag == null, "a shut door does not descend")
	check(not closed.cavern.forge.calls_travel, "calls_travel stays false")
	closed.free()
	var open_state := LabyrinthState.fresh(5)
	open_state.current = 8
	open_state.bosses.append(LabGate.BOSS)
	var it := Interiors.new()
	it.labyrinth = open_state
	runner_tree.root.add_child(it)
	await it.enter("labyrinth")
	check(it.cavern.forge.opened, "the Matriarch's death opens the door")
	check(not it.cavern.forge.calls_travel, "the opened door still does not call travel")
	it.cavern.forge.interact()
	for _i in 180:
		if not it.busy:
			break
		await runner_tree.process_frame
	check(it.floor_no == 9 and it.slag != null and it.cavern == null, "the opened door loads the Railhead")
	check(it.labyrinth.current == 9, "current becomes 9")
	check(GameFlow.level_id == level_before, "the door adds no level id")
	it.free()
	var vote := Interiors.new()
	vote.labyrinth = LabyrinthState.fresh(5)
	vote.labyrinth.current = 8
	vote.labyrinth.bosses.append(LabGate.BOSS)
	runner_tree.root.add_child(vote)
	await vote.enter("labyrinth")
	vote.stair_gate = func() -> bool: return false
	vote.cavern.forge.interact()
	check(vote.floor_no == 8 and vote.pending_slag, "a joiner makes the Crown door wait on the stair vote")
	await vote.descend()
	for _i in 180:
		if not vote.busy:
			break
		await runner_tree.process_frame
	check(vote.floor_no == 9, "the vote then loads checkpoint 9")
	vote.free()
	var deep := Interiors.new()
	deep.labyrinth = LabyrinthState.fresh(8)
	deep.labyrinth.current = 12
	runner_tree.root.add_child(deep)
	await deep.enter("labyrinth")
	deep._on_stairs(LabyrinthStairs.UP)
	check(deep.labyrinth.current == 12, "stairs up on floor 12 restore current")
	check(deep.current == "", "the party is back in the crater")
	deep.free()
	var warren := Interiors.new()
	warren.labyrinth = LabyrinthState.fresh(8)
	warren.labyrinth.current = 2
	runner_tree.root.add_child(warren)
	await warren.enter("labyrinth")
	warren._on_stairs(LabyrinthStairs.UP)
	check(warren.labyrinth.current == 0, "Warrens stairs up still clear current")
	warren.free()


func test_joiner_pad_and_floor_change() -> void:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	var host := Interiors.new()
	host.labyrinth = LabyrinthState.fresh(4)
	host.labyrinth.current = 11
	runner_tree.root.add_child(host)
	await host.enter("labyrinth")
	var joiner := Interiors.new()
	var own := LabyrinthState.fresh(9)
	joiner.labyrinth = own
	joiner.labyrinth = host.labyrinth
	joiner.floor_no = 11
	runner_tree.root.add_child(joiner)
	await joiner.enter("labyrinth")
	var pad := joiner.slag.pad_global()
	check(
		Vector2(p.global_position.x - pad.x, p.global_position.z - pad.z).length() < 2.0,
		"a joiner in the crater stands on the Overlook pad"
	)
	check(own.bosses.is_empty(), "the joiner's own block does not gain the host's bosses")
	host.free()
	joiner.free()
	var moved := Interiors.new()
	moved.labyrinth = LabyrinthState.fresh(4)
	moved.labyrinth.current = 8
	runner_tree.root.add_child(moved)
	await moved.enter("labyrinth")
	check(moved.cavern != null, "checkpoint 8 is still the cavern")
	await moved.enter_floor(9)
	check(moved.floor_no == 9 and moved.slag != null and moved.cavern == null, "a push from 8 to 9 loads floor 9")
	moved.free()
	p.free()
	_wipe_nav()


func _wipe_nav() -> void:
	var dir := DirAccess.open("res://scenes/levels/nav/slagworks")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".res") or name.ends_with(".json") or name.ends_with(".remap"):
			dir.remove(name)
		name = dir.get_next()
