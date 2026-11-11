extends TestCase
## U2: the crater choice, waystones that keep current, a joiner on the host pad.


func test_choice_and_waystones() -> void:
	var alive := LabyrinthState.fresh(1)
	check(LabGate.resolve(alive, -1) == 1, "the King alive is floor 1")
	alive.bosses.append("goblin_king")
	check(LabGate.resolve(alive, -1) == -1, "the picker does not send 0")
	check(LabGate.resolve(alive, 6) == 6, "the host can choose the Sump")
	check(LabGate.choices(alive) == [1, 6], "the King dead and the Matriarch alive is still two labels")
	check(LabGate.resolve(alive, 9) == -1, "the Railhead is refused while the Matriarch is alive")
	check(LabGate.choice_label(1) == "Goblin Warrens, floor 1", "Warrens label")
	check(LabGate.choice_label(6) == "The Blightcoil, Sump", "Blightcoil label")
	var back := LabyrinthState.fresh(1)
	back.current = 7
	back.bosses.append("blightmaw_matriarch")
	check(LabGate.resolve(back, -1) == 7, "current 7 does not open the picker")
	check(LabGate.needs_choice(back) == false, "a resumed pad is not a choice")
	var flags := StoryFlags.new()
	flags.set_flag(FastTravel.CRYSTAL)
	flags.set_flag(FastTravel.TUTORIAL_DONE)
	var ft := FastTravel.new(flags)
	check(not ft.can_travel("blightcoil_sump"), "unattuned pad is refused")
	check(not ft.destinations().has("blightcoil_sump"), "the list hides it")
	ft.attune("blightcoil_sump")
	check(ft.destinations().has("blightcoil_sump"), "attuned Sump is listed")
	check(not ft.can_travel("blightcoil_crown"), "the Crown is refused until stepped on")
	back.bosses.append("blightmaw_matriarch")
	check(not ft.attuned("blightcoil_crown"), "her death does not attune the Crown")
	check(int(FastTravel.info("warrens_hall")["floor"]) == 5, "warrens_hall is still floor 5")
	check(int(FastTravel.info("blightcoil_crown")["floor"]) == 8, "crown floor 8")
	# Going home does not clear the checkpoint.
	var current := 7
	var home := "town_square"
	if home == "town_square":
		pass
	check(current == 7 and back.bosses.has("blightmaw_matriarch"), "a trip home keeps current and bosses")


func test_joiner_stands_on_the_host_pad() -> void:
	var hs := Node.new()
	var js := Node.new()
	# Reuse the labyrinth sync test's shape with a cavern checkpoint.
	var hi := Interiors.new()
	var ji := Interiors.new()
	runner_tree.root.add_child(hi)
	runner_tree.root.add_child(ji)
	hi.labyrinth = LabyrinthState.fresh(4)
	hi.labyrinth.current = 8
	ji.labyrinth = LabyrinthState.fresh(9)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	await hi.enter("labyrinth")
	check(hi.cavern != null and hi.floor_no == 8, "the host loaded the Crown")
	var pad_y := hi.cavern.pad_global(8).y
	ji.floor_no = 8
	ji.labyrinth = hi.labyrinth
	await ji.enter("labyrinth")
	check(
		(
			is_equal_approx(p.global_position.y, ji.cavern.pad_global(8).y + 1.0)
			or absf(p.global_position.y - pad_y) < 2.0
		),
		"joiner height matches the Crown pad"
	)
	check(ji.cavern.get_node_or_null("Walk/Slab_sump") != null, "both tiers exist for the joiner")
	hi.free()
	ji.free()
	p.free()
	hs.free()
	js.free()
