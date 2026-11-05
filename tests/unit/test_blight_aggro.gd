extends TestCase
## U4: Act II band, Earth and Dark brands, 3D leash.


func test_pad_band_and_brands() -> void:
	check(ActLoot.act_of(6) == 2 and ActLoot.act_of(8) == 2, "checkpoints 6-8 are act 2")
	check(ActLoot.act_of(5) == 1 and ActLoot.item_level(5) == 12, "floor 5 stays act 1")
	check(LevelScale.labyrinth_offset(5) == 2, "the King stays +2")
	check(ActLoot.item_level(6) == 14 and LevelScale.labyrinth_offset(6) == 3, "Sump 14 / +3")
	check(ActLoot.item_level(7) == 18 and LevelScale.labyrinth_offset(7) == 4, "Canopy 18 / +4")
	check(ActLoot.item_level(8) == 22 and LevelScale.labyrinth_offset(8) == 5, "Crown 22 / +5")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	for _i in 80:
		var branded := ActLoot.brand_roll(rng, 7)
		if branded >= 0:
			seen[branded] = true
	check(seen.has(ElementTable.Element.EARTH) and seen.has(ElementTable.Element.DARK), "Earth and Dark both brand")
	var table := EnemyTable.load_default()
	for id in ["spore_husk", "spore_beast"]:
		check(String(table.find(id).ai["kind"]) == "rusher", id + " is a rusher")
	check(String(table.find("mossbound_treant").ai["kind"]) == "tank", "the treant is a tank")
	check(String(table.find("blightmaw_matriarch").ai["kind"]) == "matriarch", "the Matriarch has her brain")
	var pools := DropRoller.default_pools()
	check(pools.validate().is_empty(), "pools still validate")
	check(pools.pool_for("spore_husk", 14).id == "act2_blight", "husks have a pool")
	check(pools.pool_for("goblin_grunt", 7).id == "act1_goblins", "Act I pools untouched")


func test_chase_limit_and_home() -> void:
	var d := EnemyTable.load_default().find("spore_husk")
	var e := Enemy.create(d) as Gnawer
	e.auto_tick = false
	e.cavern_sense = true
	e.position = Vector3(0, 20, 0)
	runner_tree.root.add_child(e)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	p.position = Vector3(0, 0, 0)
	runner_tree.root.add_child(p)
	e.target = p
	e.rusher.detect_range = 40.0
	e.rusher.aggro_range = 30.0
	e.path_length_override = 50.0
	e.think(1.0 / 60.0)
	check(e.state == Gnawer.State.IDLE, "a 50 m path does not chase")
	check(e.distance > 15.0, "cavern sense uses 3D distance (%.1f)" % e.distance)
	e.path_length_override = 10.0
	e.state = Gnawer.State.IDLE
	e.think(1.0 / 60.0)
	check(e.state == Gnawer.State.DETECT or e.state == Gnawer.State.CHASE, "a 10 m path does chase")
	var grunt := Enemy.create(EnemyTable.load_default().find("goblin_grunt")) as Gnawer
	grunt.auto_tick = false
	grunt.position = Vector3(0, 0, 0)
	runner_tree.root.add_child(grunt)
	grunt.target = p
	p.position = Vector3(0, 20, 0)
	grunt.think(1.0 / 60.0)
	check(grunt.distance < 1.0, "a Warrens grunt still uses horizontal distance")
	e.has_home = true
	e.home_pad = Vector3(3, 12, 4)
	e.global_position = Vector3(3, 3, 4)
	e.think(1.0 / 60.0)
	check(e.global_position.distance_to(e.home_pad) < 0.1, "8 m below the pad returns home")
	e.free()
	grunt.free()
	p.free()
