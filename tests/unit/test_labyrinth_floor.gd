extends TestCase
## Labyrinth L2 done check: floors build from FloorGen (rooms, walls with doorways where the
## layout opens, stairs, rest shrine), the crater gate enters floor 1, stairs descend and
## clear, leaving resets to a floor start, saves resume on the floor, the boss floor's
## waystone joins fast travel.


func _state() -> LabyrinthState:
	return LabyrinthState.fresh(12345)


func test_floor_builds_from_layout() -> void:
	var kit := FloorGen.load_kit()
	var s := _state()
	var f := LabyrinthFloor.build(kit, 1, s)
	var rs: Array = f.layout["rooms"]
	check(f.rooms.size() == rs.size(), "a room node per generated room (%d)" % rs.size())
	var gaps_ok := true
	for i in rs.size():
		var r := f.rooms[i]
		var open: Array[int] = FloorGen.doors(f.layout, i)
		for side in 4:
			var split := r.get_node_or_null("Wall%d_0" % side) != null
			var full := r.get_node_or_null("Wall%d" % side) != null
			if split != open.has(side) or full == open.has(side):
				gaps_ok = false
	check(gaps_ok, "doorways exactly on the layout's open sides")
	check(
		(
			f.get_node_or_null("PlayerStart") != null
			and f.get_node_or_null("StairsUp") is LabyrinthStairs
		),
		"start + stairs up"
	)
	check(f.get_node_or_null("StairsDown") is LabyrinthStairs, "stairs down in the exit room")
	check(
		(
			f.get_node_or_null("RestShrine") is RestShrine
			and f.get_node_or_null(AssemblyStation.MARKER) != null
		),
		"rest shrine + craft spot"
	)
	var f2 := LabyrinthFloor.build(kit, 1, s)
	check(FloorGen.signature(f2.layout) == FloorGen.signature(f.layout), "same save, same floor")
	var boss := LabyrinthFloor.build(kit, 5, s)
	check(
		(
			boss.layout.is_empty()
			and boss.get_node_or_null("WaystoneSpot") != null
			and boss.get_node_or_null("StairsDown") == null
		),
		"handmade boss floor"
	)
	for n in [f, f2, boss]:
		n.free()


func test_rest_heals_and_sets_respawn() -> void:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	var sh := RestShrine.new()
	runner_tree.root.add_child(sh)
	sh.global_position = Vector3(10, 0, 4)
	p.health.value = 10.0
	var got := []
	sh.rested.connect(func(at: Vector3) -> void: got.append(at))
	sh.rest(p)
	check(is_equal_approx(p.health.value, p.health.max_value()), "healed")
	check(p.spawn_feet.distance_to(Vector3(10, 0, 5.5)) < 0.01, "deaths respawn at the shrine")
	check(got.size() == 1, "rested asks for a save")
	p.free()
	sh.free()


func test_gate_stairs_leave_and_resume() -> void:
	var it := Interiors.new()
	runner_tree.root.add_child(it)
	var s := _state()
	it.labyrinth = s
	var dummy := Node3D.new()
	dummy.add_to_group(Player.GROUP)
	runner_tree.root.add_child(dummy)
	var land: Vector3 = await it.enter("labyrinth")
	check(
		it.current == "labyrinth" and it.floor_no == 1 and s.current == 1 and s.deepest == 1,
		"crater gate: floor 1"
	)
	check(
		land.distance_to(it.lab_floor.start_pos() + Vector3(0, 0.5, 0)) < 0.01,
		"party at the floor start"
	)
	await it.descend()
	check(
		it.floor_no == 2 and s.cleared == [1] and s.current == 2 and s.deepest == 2,
		"stairs: floor 2, floor 1 cleared"
	)
	var out := it.leave("breach")
	var gate := it.link_world(Interiors.LINKS["labyrinth"]["front"])
	check(it.current == "" and s.current == 0, "left the Labyrinth")
	check(
		Vector2(out.x, out.z).distance_to(Vector2(gate.x, gate.z)) < Interiors.INSET + 0.1,
		"back at the crater"
	)
	await it.enter("labyrinth")
	check(it.floor_no == 1, "the crater gate always leads to floor 1")
	it.leave("breach")
	s.current = 2  # a save made on floor 2
	await it.enter("labyrinth")
	check(it.floor_no == 2, "a save on floor 2 resumes at floor 2's start")
	it.leave("breach")
	await it.enter_floor(5)
	check(
		it.floor_no == 5 and it.lab_floor.get_node_or_null("WaystoneSpot") != null,
		"waystone travel to the boss floor"
	)
	it.leave("breach")
	it.free()
	dummy.free()


func test_deep_waystone_in_fast_travel() -> void:
	var ft := FastTravel.new()
	ft.flags.set_flag(FastTravel.CRYSTAL)
	ft.flags.set_flag(FastTravel.TUTORIAL_DONE)
	check(not ft.destinations().has("warrens_hall"), "not attuned before the boss")
	check(
		ft.attune("warrens_hall") and ft.destinations().has("warrens_hall"),
		"attunes like a world waystone"
	)
	check(FastTravel.info("warrens_hall")["floor"] == 5, "points at the boss floor")
	var t := WorldTravel.new()
	t.fast_travel = ft
	var went := []
	t.deep_travel = func(p: String) -> void: went.append(p)
	t.markers = {}
	check(t.can_travel("warrens_hall"), "the map can travel there")
	await t.travel_to("warrens_hall")
	check(went == ["warrens_hall"], "deep travel enters the floor")
	check(t.points().has("warrens_hall"), "shown on the map")
	t.free()


func test_save_inside_resumes_inside() -> void:
	var d := {
		"progress":
		{"interior": "labyrinth", "flags": {}, "labyrinth": {"v": 1, "save_seed": 5, "current": 3}}
	}
	var at := WorldSession.start_spot(d, GameFlow.INTRO_SKIP)
	check(String(at["interior"]) == "labyrinth", "a save on a floor starts in the Labyrinth")
	check(LabyrinthState.from_save(d).current == 3, "on the saved floor")


## L5 perf: only rooms within two doorways of the viewer's room are drawn.
func test_room_culling() -> void:
	var fl := LabyrinthFloor.build(FloorGen.load_kit(), 1, LabyrinthState.fresh(42))
	runner_tree.root.add_child(fl)
	var start := fl.get_node("PlayerStart") as Node3D
	var shown := fl.cull_to(start.global_position)
	check(shown < fl.rooms.size(), "some rooms hidden (%d / %d)" % [shown, fl.rooms.size()])
	var i := fl.room_at(start.global_position)
	check(fl.rooms[i].visible, "the viewer's room is drawn")
	for e: Array in fl.layout["edges"]:
		if int(e[0]) == i:
			check(fl.rooms[int(e[1])].visible, "a doorway neighbour is drawn")
	var far := fl.rooms[fl.rooms.size() - 1]
	fl.cull_to(far.global_position)
	check(far.visible, "moving shows the new room")
	check(fl.get_node("EnemySpawns") != null, "markers untouched")
	fl.free()


func test_route_walks_doorways() -> void:
	for n in [1, 3, 5]:
		var fl := LabyrinthFloor.build(FloorGen.load_kit(), n, LabyrinthState.fresh(42))
		runner_tree.root.add_child(fl)
		var a := (fl.get_node("PlayerStart") as Node3D).global_position
		var goal := fl.get_node_or_null(^"StairsDown") as Node3D
		if goal == null:
			goal = fl.get_node(^"BossSpawn") as Node3D
		var r := fl.route(a, goal.global_position)
		check(
			r.size() >= 1 and r[r.size() - 1].is_equal_approx(goal.global_position),
			"floor %d: route ends at the goal" % n
		)
		var prev := fl.room_at(a)
		for k in r.size() - 1:
			var cur := fl.room_at(r[k])
			var linked := fl.layout.is_empty()
			for e: Array in fl.layout.get("edges", []):
				if (
					int(e[2]) != 1
					and (
						(int(e[0]) == prev and int(e[1]) == cur)
						or (int(e[1]) == prev and int(e[0]) == cur)
					)
				):
					linked = true
			check(linked, "floor %d: hop %d->%d is a doorway" % [n, prev, cur])
			prev = cur
		check(fl.room_at(r[r.size() - 1]) == prev, "floor %d: last hop stays in the goal room" % n)
		fl.free()


## The 2 m strip inside each exit-room doorway never overlaps the 4 x 4 m stair hole.
func test_exit_doorways_clear_of_stair_well() -> void:
	var kit := FloorGen.load_kit()
	var rows := {}
	var bad := 0
	var n := 0
	for s in 16:
		for fno in [1, 2, 3, 4]:
			var f := LabyrinthFloor.build(kit, fno, LabyrinthState.fresh(1000 + s))
			for r: Node3D in f.rooms:
				if r.get_meta(&"kind") != "exit" or not r.has_node("StairLanding"):
					continue
				n += 1
				rows[f.stair_row] = true
				var hole := (r.get_node("StairLanding") as Node3D).position
				for side: int in r.get_meta(&"doors"):
					var horiz := side == 0 or side == 2
					var edge := (r.get_node("Wall%d_0" % side) as Node3D).position
					var e := edge.z if horiz else edge.x
					var inward := -signf(e)
					var c := Vector2(0, e + inward) if horiz else Vector2(e + inward, 0)
					var half := Vector2(2, 1) if horiz else Vector2(1, 2)
					var gap := Vector2(absf(c.x - hole.x), absf(c.y - hole.z)) - half - Vector2(2, 2)
					if gap.x < -0.01 and gap.y < -0.01:
						bad += 1
						fail("seed %d floor %d side %d opens onto the well" % [1000 + s, fno, side])
			f.free()
	check(n > 0 and bad == 0, "%d exit rooms, doorways clear (%d bad)" % [n, bad])
	check(rows.size() == 2 or n == 0, "both hole rows exercised (%s)" % [rows.keys()])


## stair_row 1 (south hole, yaw 0): trigger on the model's BottomExit, landing under it.
func test_south_stair_hole_foot() -> void:
	var kit := FloorGen.load_kit()
	var f: LabyrinthFloor
	for s in 64:
		f = LabyrinthFloor.build(kit, 1, LabyrinthState.fresh(2000 + s))
		if f.stair_row == 1:
			break
		f.free()
		f = null
	check(f != null, "a seed with the hole in the south row")
	if f == null or not f.dressed:
		if f:
			f.free()
		return
	runner_tree.root.add_child(f)
	f.position = Vector3(0, 900, 5000)
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	var s := f.get_node("StairsDown") as Node3D
	var be := f.find_child("BottomExit", true, false) as Node3D
	if be:
		check_near(be.global_position.distance_to(s.global_position), 0.4, 0.05, "trigger on BottomExit")
	var q := PhysicsRayQueryParameters3D.create(
		s.global_position + Vector3(0, 6, 0), s.global_position + Vector3(0, -3, 0)
	)
	var hit := f.get_world_3d().direct_space_state.intersect_ray(q)
	check(
		not hit.is_empty() and absf(hit["position"].y - s.global_position.y) < 0.6,
		"open shaft above the south foot, floor below (%s)" % [hit.get("position")]
	)
	f.free()
