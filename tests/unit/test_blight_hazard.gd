extends TestCase
## U3: mire, fog height, vines, falls, shrine and pad saves.


func _player() -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	return p


func test_mire_fog_and_falls() -> void:
	var p := _player()
	var shield := p.health.shield
	var breath := p.breath.value
	var max_hp := p.health.max_value()
	p.hurt_health(max_hp * BlightHazard.MIRE_DPS)
	check_near(p.health.value, max_hp * (1.0 - BlightHazard.MIRE_DPS), 0.05, "one second of mire")
	check_near(p.health.shield, shield, 0.01, "mire leaves the shield")
	check_near(p.breath.value, breath, 0.01, "mire leaves Breath")
	check(not BlightHazard.in_fog_band(0.0, 12.0, false, false), "y 0 is not fog")
	check(BlightHazard.in_fog_band(12.0, 12.0, false, false), "y 12 outside the rest pad is fog")
	check(not BlightHazard.in_fog_band(12.0, 12.0, true, false), "the rest pad is exempt")
	p.poison_dps = BlightHazard.FOG_DPS
	p.poison_left = BlightHazard.FOG_LINGER
	var before := p.health.value
	p.tick_poison(3.0)
	check(p.health.value < before - max_hp * 0.05, "fog ticks for the linger")
	var held := p.health.value
	p.tick_poison(1.0)
	check_near(p.health.value, held, 0.01, "fog stops after 3 seconds")
	var shield2 := p.health.shield
	BlightHazard.apply_fall(p, 12.0)
	check_near(p.health.value, held * 0.0 + (held - max_hp * 0.64), 1.0, "12 m drop is 64 percent")
	check_near(p.health.value, held - max_hp * BlightHazard.fall_fraction(12.0), 0.2, "fall fraction")
	check_near(p.health.shield, shield2, 0.01, "a fall does not spend the shield")
	var after := p.health.value
	BlightHazard.apply_fall(p, 3.0)
	check_near(p.health.value, after, 0.01, "a 3 m drop is free")
	check(BlightHazard.fall_fraction(4.0) == 0.0, "4 m is not over the line")
	p.free()


func test_vine_downed_and_respawn() -> void:
	var p := _player()
	var hp := p.health.value
	p.apply_slow(BlightHazard.VINE_SLOW, BlightHazard.VINE_TIME)
	check_near(p.current_slow(), 0.5, 0.01, "a vine halves speed")
	check_near(p.health.value, hp, 0.01, "a vine does not hurt")
	p.slow_left = 0.0
	check_near(p.current_slow(), 1.0, 0.01, "leaving the vine ends the slow")
	p.poison_dps = 0.04
	p.poison_left = 5.0
	p.downed = true
	var held := p.health.value
	p.tick_poison(1.0)
	check_near(p.health.value, held, 0.01, "a downed player takes no more poison")
	p.downed = false
	p.health.dead = true
	p.tick_poison(1.0)
	check_near(p.health.value, held, 0.01, "a dead player is not poisoned")
	p.health.dead = false
	p.poison_left = 2.0
	p.slow_left = 1.0
	p.respawn()
	check(p.poison_left == 0.0 and p.slow_left == 0.0, "respawn clears poison and slow")
	p.free()


func test_shrine_and_pad_save_the_same_checkpoint() -> void:
	var state := LabyrinthState.fresh(2)
	var flags := StoryFlags.new()
	var travel := FastTravel.new(flags)
	var cav := BlightcoilCavern.make(6, state)
	cav.position = Vector3(0, -2000, 0)
	runner_tree.root.add_child(cav)
	var p := _player()
	p.global_position = cav.pad_global(6) + Vector3(0, 0.4, 0)
	cav.watch_pads([p])
	check(flags.has("waystone:blightcoil_sump") == false, "the signal has not saved yet")
	var got: Array = []
	cav.pad_reached.connect(func(n: int, id: String) -> void:
		state.current = n
		state.reach(n)
		travel.attune(id)
		got.append(n)
	)
	cav._stepped.clear()
	cav.watch_pads([p])
	check(got == [6] and state.current == 6 and travel.attuned("blightcoil_sump"), "a pad step attunes and sets current")
	p.poison_left = 4.0
	p.poison_dps = 0.02
	var shrine := cav.get_node("RestShrine") as RestShrine
	shrine.rest(p)
	check(p.poison_left == 0.0, "the shrine clears poison")
	check(int(shrine.get_meta("checkpoint")) == 7, "the shrine's checkpoint is the canopy")
	# A rest on the canopy writes the same current a pad step would.
	state.current = int(shrine.get_meta("checkpoint"))
	check(state.current == 7, "rest and the canopy pad share current")
	p.global_position = Vector3(0, cav.global_position.y - 10.0, 0)
	cav.hazard.last_pad = cav.pad_global(6)
	cav.hazard._falls(p, -10.0)
	check(
		p.global_position.distance_to(cav.pad_global(6) + Vector3(0, 0.5, 0)) < 0.2,
		"below y -8 returns to the last pad"
	)
	cav.free()
	p.free()
