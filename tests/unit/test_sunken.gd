extends TestCase
## Act IV: five flooded floors, Breath in the water, the Drowned Choir, the door
## after Forgemaw, and the coral sarcophagus.


func test_five_floors_breath_and_choir() -> void:
	for n in [14, 15, 16, 17]:
		var hall := SunkenFloor.make(n, LabyrinthState.fresh(3))
		runner_tree.root.add_child(hall)
		check(hall.get_node_or_null("StairsDown") != null, "floor %d has stairs" % n)
		check(hall.get_node_or_null("AirBell") != null, "floor %d has an air bell" % n)
		check(hall.get_node_or_null("Flood") != null, "floor %d is flooded" % n)
		hall.free()
	var nave := SunkenFloor.make(18, LabyrinthState.fresh(3))
	runner_tree.root.add_child(nave)
	check(nave.get_node_or_null("StairsDown") == null, "the nave has no next stair")
	check(nave.sarcophagus != null and not nave.sarcophagus.visible, "the sarcophagus waits")
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(nave.global_position, 0.0)
	var before := p.breath.value
	nave.drown(p, 1.0)
	check(p.breath.value < before, "water spends Breath")
	p.breath.value = 0.0
	var hp := p.health.value
	nave.drown(p, 0.5)
	check(p.health.value < hp, "empty Breath costs health")
	var choir := Enemy.create(EnemyTable.load_default().find("drowned_choir"))
	check(choir is DrownedChoir and choir.is_boss(), "the Choir is the boss")
	choir.health = choir.max_health() * 0.4
	(choir as DrownedChoir).sync_phase()
	check((choir as DrownedChoir).phase == 2 and (choir as DrownedChoir).submerged, "it submerges at half")
	nave._state.defeat_boss(SunkenFloor.BOSS)
	nave.note_boss_dead()
	check(nave.sarcophagus.visible, "the coral sarcophagus is open")
	var homes: Array = []
	nave.home_requested.connect(func() -> void: homes.append(1))
	nave._on_pad(p)
	check(homes == [1], "the nave pad sends the party home")
	choir.free()
	p.free()
	nave.free()


func test_forgemaw_door_opens_the_ruins() -> void:
	var state := LabyrinthState.fresh(4)
	var floor := SlagworksFloor.make(13, state)
	runner_tree.root.add_child(floor)
	var door := floor.find_child("SunkenDoor", true, false) as SlagProp
	check(not floor.use_sunken(), "the door stays shut")
	state.defeat_boss("forgemaw")
	check(door.line().contains("flooded halls"), "the door names the flooded halls")
	check(not door.line().contains("travel"), "the line does not offer travel")
	var went: Array = []
	floor.sunken_descend.connect(func() -> void: went.append(SunkenFloor.FIRST))
	check(floor.use_sunken() and went == [14], "the open door asks for checkpoint 14")
	check(not GameFlow.LEVELS.has("sunken_ruins"), "the ruins are labyrinth floors, not a new level id")
	floor.free()
