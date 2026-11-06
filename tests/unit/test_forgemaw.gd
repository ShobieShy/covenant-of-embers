extends TestCase
## U6: Forgemaw's phases, the lift, the slag cast, and the Sunken door.


func _boss() -> Forgemaw:
	var e := Enemy.create(EnemyTable.load_default().find("forgemaw")) as Forgemaw
	e.auto_tick = false
	runner_tree.root.add_child(e)
	e.health = e.max_health()
	e.sync_phase()
	return e


func test_phases_only_advance() -> void:
	var b := _boss()
	check(b.phase == 1 and not b.arena_locked and b.regenerated == 0.0, "full health is phase 1")
	b.health = b.max_health() * 0.5
	b.sync_phase()
	check(b.phase == 2, "50 percent is phase 2")
	b.health = b.max_health() * 0.9
	b.sync_phase()
	check(b.phase == 2, "raising the fraction does not rewind")
	b.health = b.max_health() * 0.2
	b.sync_phase()
	check(b.phase == 3 and b.weak_open, "20 percent opens the weak point")
	b.drives_brain = false
	b.think(1.0)
	check(b.phase == 3, "a client does not run the attack brain")
	var floor := SlagworksFloor.make(13, LabyrinthState.fresh(4))
	floor.position = Vector3(0, -2000, 0)
	runner_tree.root.add_child(floor)
	floor.apply_phase(2)
	check(not (floor.find_child("GantryA", true, false) as Node3D).visible, "phase 2 drops segment A")
	check((floor.find_child("GantryB", true, false) as Node3D).visible, "segment B is still up")
	floor.apply_phase(1)
	check(not (floor.find_child("GantryA", true, false) as Node3D).visible, "phase does not rewind")
	var before := (_lava(floor).get_node("CollisionShape3D").shape as BoxShape3D).size.z
	floor.apply_phase(3)
	check(not (floor.find_child("GantryC", true, false) as Node3D).visible, "phase 3 drops the ring")
	var after := (_lava(floor).get_node("CollisionShape3D").shape as BoxShape3D).size.z
	check(after > before, "phase 3 lava is wider")
	check(floor.weak_open, "the weak point is open")
	b.free()
	floor.free()


func test_ending_props() -> void:
	var state := LabyrinthState.fresh(4)
	var floor := SlagworksFloor.make(13, state)
	runner_tree.root.add_child(floor)
	var lift := floor.find_child("MainLift", true, false) as SlagProp
	var door := floor.find_child("SunkenDoor", true, false) as SlagProp
	check(not lift.calls_travel and not door.calls_travel, "neither prop calls travel")
	check(lift.line().contains("locked"), "the lift is locked")
	check(not floor.use_lift(), "the locked lift does not move the party")
	check(door.line().contains("still shut"), "the Sunken door is shut")
	state.defeat_boss("forgemaw")
	state.defeat_boss("forgemaw")
	check(state.bosses.size() == 1, "a second death does not append the id")
	floor.note_boss_dead()
	check((floor.find_child("SlagCast", true, false) as Node3D).visible, "the slag cast is shown")
	check(door.line().contains("way down has opened"), "the way down has opened")
	check(not door.line().contains("travel"), "the line does not offer travel")
	var went: Array = []
	floor.lift_home.connect(func() -> void: went.append(9))
	check(floor.use_lift() and went == [9], "the open lift sends the party toward the Railhead")
	check(floor.get_node_or_null("WaystoneSpot") == null, "death does not create a second waystone")
	check(not GameFlow.LEVELS.has("sunken_ruins"), "the Sunken door adds no level")
	floor.free()


func _lava(floor: SlagworksFloor) -> Node3D:
	for n in floor.find_children("*", "Area3D", true, false):
		if n.has_meta(&"wide_width"):
			return n
	return null
