extends TestCase
## Act V: five platform floors, a kill void, the Storm Warden's failing platforms,
## a lit path instead of a fourth shell, and the door after the Choir.


func test_five_floors_kill_void_and_warden() -> void:
	for n in [19, 20, 21, 22]:
		var hall := SpireFloor.make(n, LabyrinthState.fresh(3))
		runner_tree.root.add_child(hall)
		check(hall.get_node_or_null("StairsDown") != null, "floor %d has stairs" % n)
		check(hall.get_node_or_null("LitPath") == null, "floor %d is not the throat" % n)
		check(hall.fall_kind(-30.0) == "kill", "floor %d void is a kill" % n)
		check(hall.fall_kind(2.0) == "arena", "floor %d drop between platforms is not a kill" % n)
		hall.free()
	var wind := SpireFloor.make(21, LabyrinthState.fresh(3))
	runner_tree.root.add_child(wind)
	check(wind.get_node_or_null("Wind") != null, "the wind floor has a corridor")
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(wind.global_position, 0.0)
	var before := p.velocity.x
	wind.apply_wind(p)
	check(p.velocity.x != before, "the host shoves")
	p.free()
	wind.free()
	var top := SpireFloor.make(23, LabyrinthState.fresh(3))
	runner_tree.root.add_child(top)
	check(top.get_node_or_null("StairsDown") == null, "the Warden floor has no next stair")
	check(top.lit_path != null and not top.lit_path.visible, "the lit path waits")
	check(top.get_node_or_null("CoralSarcophagus") == null, "no fourth shell")
	top.fail_platforms()
	var gone := true
	for b in top._failing:
		var shape := b.get_node("Shape") as CollisionShape3D
		gone = gone and shape.disabled
	check(gone, "the Warden's platforms fail")
	check(top.fall_kind(2.0) == "arena", "the failing drop stays above the kill line")
	check(top.fall_kind(-30.0) == "kill", "past the lowest platform is a kill")
	var warden := Enemy.create(EnemyTable.load_default().find("storm_warden"))
	check(warden != null and warden.is_boss(), "the Warden is the boss")
	top._state.defeat_boss(SpireFloor.BOSS)
	top.note_boss_dead()
	check(top.lit_path.visible, "the throat is a lit path")
	var homes: Array = []
	top.home_requested.connect(func() -> void: homes.append(1))
	var home_body := Player.new()
	top._on_pad(home_body)
	home_body.free()
	warden.free()
	top.free()


func test_choir_door_opens_the_spire() -> void:
	var state := LabyrinthState.fresh(4)
	var nave := SunkenFloor.make(18, state)
	runner_tree.root.add_child(nave)
	var door := nave.get_node("SpireDoor") as SlagProp
	check(not nave.use_spire(), "the door stays shut")
	check(door.line() == "The wind locks hold.", "the locks are shut")
	state.defeat_boss("drowned_choir")
	check(door.line() == "The shaft becomes sky.", "the shaft opens")
	var went: Array = []
	nave.spire_descend.connect(func() -> void: went.append(SpireFloor.FIRST))
	check(nave.use_spire() and went == [19], "the open door asks for checkpoint 19")
	check(not GameFlow.LEVELS.has("inverted_spire"), "the spire is labyrinth floors, not a new level id")
	nave.free()


func test_quest_starts_when_the_choir_is_known() -> void:
	var q := QuestLog.create()
	q.known_bosses = ["drowned_choir"]
	q.check_auto_start()
	check(q.state("the_inverted_spire") == "active", "the Warden quest starts")
	check(q.recommended("the_inverted_spire") == 50, "the Warden's level")
	var done := QuestLog.create()
	done.known_bosses = ["drowned_choir", "storm_warden"]
	done.check_auto_start()
	check(done.state("the_inverted_spire") == "done", "already dead, already done")
