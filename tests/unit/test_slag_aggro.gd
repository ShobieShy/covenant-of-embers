extends TestCase
## U4: Act III is Fire, the floor offset replaces the boss offset, and the chase
## drops when the safe path is longer than 40 m.


func test_fire_band() -> void:
	check(ActLoot.act_of(9) == 3 and ActLoot.act_of(13) == 3, "checkpoints 9-13 are act 3")
	check(ActLoot.act_of(14) == 4 and ActLoot.item_level(14) == 36, "floor 14 is the Sunken gallery")
	check(LevelScale.labyrinth_offset(14) == 11 and LevelScale.labyrinth_offset(18) == 15, "Act IV offsets")
	check(ActLoot.act_of(5) == 1 and LevelScale.labyrinth_offset(5) == 2, "floor 5 stays act 1, offset +2")
	check(ActLoot.act_of(8) == 2 and LevelScale.labyrinth_offset(8) == 5, "floor 8 stays act 2")
	check(ActLoot.item_level(9) == 24 and LevelScale.labyrinth_offset(9) == 6, "Railhead 24 / +6")
	check(ActLoot.item_level(11) == 28 and LevelScale.labyrinth_offset(11) == 8, "Overlook 28 / +8")
	check(ActLoot.item_level(13) == 34 and LevelScale.labyrinth_offset(13) == 10, "Crucible 34 / +10")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var saw_fire := false
	var saw_other := false
	for _i in 40:
		var branded := ActLoot.brand_roll(rng, 11)
		if branded == ElementTable.Element.FIRE:
			saw_fire = true
		elif branded >= 0:
			saw_other = true
	check(saw_fire and not saw_other, "a branded Act III drop is Fire")
	rng.seed = 7
	var act2 := {}
	for _i in 80:
		var branded := ActLoot.brand_roll(rng, 7)
		if branded >= 0:
			act2[branded] = true
	check(act2.has(ElementTable.Element.EARTH) and act2.has(ElementTable.Element.DARK), "Act II is still Earth or Dark")
	var table := EnemyTable.load_default()
	check(String(table.find("branded_troll").ai["kind"]) == "rusher", "the troll is a rusher")
	check(String(table.find("forge_construct").ai["kind"]) == "tank", "the construct is a tank")
	check(String(table.find("forgemaw").ai["kind"]) == "forgemaw", "Forgemaw has his brain")
	var pools := DropRoller.default_pools()
	check(pools.validate().is_empty(), "pools still validate")
	check(pools.pool_for("branded_troll", 24).id == "act3_slag", "trolls have a pool")
	var elite := Enemy.create(table.find("forge_construct"))
	elite.def.set_meta(&"elite", "bulwark")
	ActLoot.tag(elite, 11)
	check(elite.level_offset == LevelScale.labyrinth_offset(11) + 1, "elite uses the floor offset plus 1")
	check(
		elite.level_offset != LevelScale.labyrinth_offset(11) + 1 + LevelScale.BOSS_OFFSET,
		"not the boss offset as well"
	)
	elite.def.remove_meta(&"elite")
	var boss := Enemy.create(table.find("forgemaw"))
	ActLoot.tag(boss, 13)
	check(boss.level_offset == LevelScale.labyrinth_offset(13), "Forgemaw uses the floor offset")
	check(boss.level_offset != LevelScale.labyrinth_offset(13) + LevelScale.BOSS_OFFSET, "the boss offset is not added")
	check(ActLoot.party_chance(0.2, 3) > ActLoot.party_chance(0.2, 1), "party size still raises drop chance")
	elite.free()
	boss.free()


func test_horizontal_chase_cap() -> void:
	var d := EnemyTable.load_default().find("branded_troll")
	var e := Enemy.create(d) as Gnawer
	e.auto_tick = false
	e.path_cap = 40.0
	e.position = Vector3.ZERO
	runner_tree.root.add_child(e)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	p.position = Vector3(8, 30, 0)
	runner_tree.root.add_child(p)
	e.target = p
	e.rusher.detect_range = 40.0
	e.rusher.aggro_range = 30.0
	e.path_length_override = 50.0
	e.think(1.0 / 60.0)
	check(e.state == Gnawer.State.IDLE, "a 50 m path does not chase")
	check(e.distance < 15.0, "Slagworks sense stays horizontal (%.1f)" % e.distance)
	e.path_length_override = 10.0
	e.state = Gnawer.State.IDLE
	e.think(1.0 / 60.0)
	check(e.state == Gnawer.State.DETECT or e.state == Gnawer.State.CHASE, "a 10 m path does chase")
	var grunt := Enemy.create(EnemyTable.load_default().find("goblin_grunt")) as Gnawer
	grunt.auto_tick = false
	grunt.position = Vector3.ZERO
	runner_tree.root.add_child(grunt)
	grunt.target = p
	grunt.think(1.0 / 60.0)
	check(grunt.distance < 15.0, "a Warrens grunt still uses horizontal distance")
	e.free()
	grunt.free()
	p.free()
