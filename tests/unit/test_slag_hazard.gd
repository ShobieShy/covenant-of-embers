extends TestCase
## U3: lava, shimmer, carts and falls spend health only. Blightcoil rates stay put.


func _player() -> Player:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	return p


func _floor(n := 9) -> SlagworksFloor:
	var f := SlagworksFloor.make(n, LabyrinthState.fresh(11))
	f.position = Vector3(0, -2000, 0)
	runner_tree.root.add_child(f)
	return f


func _lava(f: SlagworksFloor) -> Node3D:
	for n in f.find_children("*", "Area3D", true, false):
		if String(n.get_meta(&"kind", "")) == "lava":
			return n
	return null


func test_heat_carts_and_falls() -> void:
	check_near(BlightHazard.MIRE_DPS, 0.04, 0.0001, "mire rate is unchanged")
	var f := _floor(9)
	var p := _player()
	var shield := p.health.shield
	var breath := p.breath.value
	var max_hp := p.health.max_value()
	var lava := _lava(f)
	check(lava != null and not lava.is_in_group(&"blight_volume"), "a slag volume is not blight")
	p.global_position = lava.global_position + Vector3(0, 0.2, 0)
	f.hazard.tick(1.0)
	check_near(p.health.value, max_hp * (1.0 - SlagHazard.LAVA_DPS), 0.2, "one second in lava is 8 percent")
	check_near(p.health.shield, shield, 0.01, "lava leaves the shield")
	check_near(p.breath.value, breath, 0.01, "lava leaves Breath")
	var deck := f.find_child("GantryDeck", true, false) as Node3D
	var held := p.health.value
	p.global_position = deck.global_position + Vector3(0, 1.0, 0)
	f.hazard.tick(1.0)
	check_near(p.health.value, held, 0.05, "the gantry deck is outside the shimmer")
	var mouth := f.find_child("Shimmer", true, false) as Node3D
	p.global_position = mouth.global_position
	f.hazard.tick(0.25)
	check(p.health.value < held, "the anvil mouth shimmers")
	p.global_position = f.pad_global() + Vector3(0, 0.4, 0)
	var mid := p.health.value
	f.hazard.tick(2.0)
	check(p.health.value < mid - max_hp * 0.03, "shimmer lingers for 2 seconds")
	var after := p.health.value
	f.hazard.tick(1.0)
	check_near(p.health.value, after, 0.05, "shimmer stops after the linger")
	f.hazard._move_carts()
	var cart := f.find_child("Cart", true, false) as Node3D
	check(cart != null, "a floor with a rail has a cart")
	if cart == null:
		p.free()
		f.free()
		return
	check(cart != null and not cart.is_in_group(&"enemies"), "a cart is not an enemy")
	p.global_position = cart.global_position
	var before_cart := p.health.value
	f.hazard.tick(0.05)
	check_near(p.health.value, before_cart - max_hp * SlagHazard.CART_HIT, 0.4, "a cart hit is 12 percent")
	check_near(p.breath.value, breath, 0.01, "a cart hit leaves Breath")
	var once := p.health.value
	p.global_position = cart.global_position
	f.hazard.tick(0.05)
	check_near(p.health.value, once, 0.05, "a second overlap inside 1 second does not hit")
	var shield2 := p.health.shield
	BlightHazard.apply_fall(p, 12.0)
	check_near(p.health.value, once - max_hp * 0.64, 0.4, "a 12 m drop is 64 percent")
	check_near(p.health.shield, shield2, 0.01, "a fall does not spend the shield")
	var landed := p.health.value
	BlightHazard.apply_fall(p, 3.0)
	check_near(p.health.value, landed, 0.01, "a 3 m drop removes none")
	p.downed = true
	var downed := p.health.value
	p.global_position = lava.global_position
	f.hazard.tick(1.0)
	check_near(p.health.value, downed, 0.01, "a downed player in lava takes no further heat")
	p.downed = false
	p.health.dead = true
	f.hazard.tick(1.0)
	check_near(p.health.value, downed, 0.01, "a dead player is not heated")
	p.health.dead = false
	f.hazard._shimmer[p.get_instance_id()] = 2.0
	p.respawn()
	check(float(f.hazard._shimmer.get(p.get_instance_id(), 0.0)) == 0.0, "respawn clears heat")
	p.free()
	f.free()


func test_shrine_pad_and_clock() -> void:
	check(SlagHazard.clock_from({}) == 0.0, "a missing cart_t starts at 0")
	check_near(SlagHazard.clock_from({"cart_t": 4.25}), 4.25, 0.001, "cart_t sets the loop time")
	check(NetSession.PROTOCOL == 5, "the protocol stays 5")
	var f := _floor(11)
	var p := _player()
	f.hazard._shimmer[p.get_instance_id()] = 3.0
	var got: Array = []
	var shrine := f.get_node("RestShrine") as RestShrine
	shrine.rested.connect(func(at: Vector3) -> void: got.append(at))
	shrine.rest(p)
	check(got.size() == 1, "the shrine signal reaches the save")
	check(float(f.hazard._shimmer.get(p.get_instance_id(), 0.0)) == 0.0, "the shrine clears heat")
	check(int(shrine.get_meta(&"checkpoint")) == 11, "the shrine writes this floor, not the canopy")
	var state := LabyrinthState.fresh(11)
	var flags := StoryFlags.new()
	var travel := FastTravel.new(flags)
	flags.set_flag(FastTravel.CRYSTAL)
	flags.set_flag(FastTravel.TUTORIAL_DONE)
	f.pad_reached.connect(
		func(n: int, id: String) -> void:
			state.current = n
			travel.attune(id)
	)
	f._on_pad_body(p)
	check(state.current == 11 and travel.attuned("slagworks_overlook"), "a pad step attunes and sets current")
	p.global_position = f.pad_global() + Vector3(0, 0.4, 0)
	var safe := p.health.value
	f.hazard.tick(1.0)
	check_near(p.health.value, safe, 0.05, "landing on the rest pad does not start a tick")
	var other := _player()
	var other_hp := other.health.value
	p.global_position = _lava(f).global_position
	f.hazard.tick(1.0)
	check(p.health.value < safe, "the body in the lava is heated")
	check_near(other.health.value, other_hp, 0.01, "the other body is not")
	p.global_position = Vector3(0, f.global_position.y - 10.0, 0)
	f.hazard.last_pad = f.pad_global()
	f.hazard._falls(p)
	check(
		p.global_position.distance_to(f.pad_global() + Vector3(0, 0.5, 0)) < 0.3, "below y -8 returns to the last pad"
	)
	p.free()
	other.free()
	f.free()
