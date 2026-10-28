extends TestCase
## L3: the Goblin King (ai kind "king") and the Labyrinth's goblin spawns.
##  - Throw: at 6-18 m he plants and the rock leaves at 40 % of the Throw clip, flies at the
##    target and lands as a 14-damage Earth bite; Slam is the Heap's;
##  - Roar: the phase-2 enrage roots him ~2 s and calls two grunts into his parent;
##  - death: the Crown hides and a CrownDrop prop is left;
##  - floors: normal/elite rooms get seeded goblin markers, floor 5 the King until he is
##    in the save; a dead elite pack stays dead; the exit room has a stair hole.

const DT := 1.0 / 60.0
const E := ElementTable.Element


func _world() -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(0, 700, -3100)
	runner_tree.root.add_child(w)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	b.add_child(cs)
	b.position.y = -0.5
	w.add_child(b)
	return w


func _king(w: Node3D) -> GoblinKing:
	var k := Enemy.create(EnemyTable.load_default().find("goblin_king")) as GoblinKing
	k.auto_tick = false
	w.add_child(k)
	return k


func _target(w: Node3D, at: Vector3) -> Node3D:
	var t := Node3D.new()
	w.add_child(t)
	t.position = at
	return t


func test_king_kind_and_boss() -> void:
	var w := _world()
	var k := _king(w)
	check(k != null, "king kind spawns a GoblinKing")
	check(k != null and k.is_boss() and k is Warden, "a boss on the Warden's phases")
	w.free()


func test_throw_releases_at_40_percent() -> void:
	var w := _world()
	var k := _king(w)
	var t := _target(w, Vector3(0, 0, -10))
	k.target = t
	var bites: Array = []
	k.attacked.connect(func(_g, b): bites.append(b))
	var rel := EnemyModels.throw_release(k.model)
	check(rel > 0.1, "Throw clip present (release %.2f s)" % rel)
	var start := -1
	var thrown := [-1]
	k.threw.connect(func(_k, _r): thrown[0] = k.ticks)
	for i in 240:
		k.think(DT)
		if start < 0 and k.throws > 0:
			start = k.ticks
		if not bites.is_empty():
			break
	check(start > 0, "he throws at 10 m")
	check(
		thrown[0] > 0 and absf((thrown[0] - start) * DT - rel) <= 2.0 * DT,
		"release at 40 %% (%d -> %d ticks)" % [start, thrown[0]]
	)
	check(
		bites.size() == 1 and is_equal_approx(bites[0].damage, GoblinKing.THROW_DAMAGE),
		"rock lands for 14"
	)
	check(k.rocks_hit == 1 and k.slams == 0, "a rock, not a slam")
	w.free()


func test_no_throw_up_close_slams_instead() -> void:
	var w := _world()
	var k := _king(w)
	k.target = _target(w, Vector3(0, 0, -2.4))
	for i in 120:
		k.think(DT)
	check(
		k.throws == 0 and k.slams >= 1, "slam at 2.4 m (%d throws, %d slams)" % [k.throws, k.slams]
	)
	w.free()


func test_roar_calls_two_grunts() -> void:
	var w := _world()
	var k := _king(w)
	var got: Array = []
	k.roared.connect(func(_k, m): got.append_array(m))
	k.apply_damage(k.max_health() * 0.55, E.FIRE)
	check(k.phase == 2 and k.roars == 1 and k.roar_left > 1.5, "roar at the enrage")
	await runner_tree.process_frame
	check(
		(
			got.size() == 2
			and got.all(func(g): return g.is_inside_tree() and g.def.id == "goblin_grunt")
		),
		"two grunts"
	)
	k.apply_damage(1.0, E.FIRE)
	check(k.roars == 1, "once")
	w.free()


func test_death_drops_the_crown() -> void:
	var w := _world()
	var k := _king(w)
	k.apply_damage(99999.0, E.FIRE)
	await runner_tree.process_frame
	var c := w.get_node_or_null("CrownDrop") as Node3D
	check(
		c != null and c.find_children("*", "MeshInstance3D", true, false).size() == 1,
		"CrownDrop left"
	)
	check(not (k.model.find_child("Crown", true, false) as Node3D).visible, "crown off his head")
	w.free()


func _floor(n: int, st: LabyrinthState) -> LabyrinthFloor:
	return LabyrinthFloor.build(FloorGen.load_kit(), n, st)


func test_floor_goblins_seeded() -> void:
	var st := LabyrinthState.fresh(42)
	var a := _floor(1, st)
	var b := _floor(1, st)
	var ids := func(f: Node) -> Array:
		return f.get_node("EnemySpawns").get_children().map(
			func(m): return [m.name, m.get_meta(&"enemy"), m.position]
		)
	var la: Array = ids.call(a)
	check(la.size() >= 4, "goblins on floor 1 (%d)" % la.size())
	check(la == ids.call(b), "same seed, same goblins")
	check(la.all(func(x): return String(x[1]) in LabyrinthFloor.GOBLINS), "goblin ids")
	var t := EnemyTable.load_default()
	check(la.all(func(x): return t.find(String(x[1])) != null), "all in the table")
	var elite := ""
	for r in a.rooms:
		if r.get_meta(&"kind") == "elite":
			elite = String(r.name)
	if elite != "":
		st.kill_elite(1, elite)
		var c := _floor(1, st)
		check(
			(ids.call(c) as Array).all(func(x): return not String(x[0]).begins_with(elite)),
			"dead elites stay dead"
		)
		c.free()
	a.free()
	b.free()


func test_boss_floor_spawns_king_until_defeated() -> void:
	var st := LabyrinthState.fresh(7)
	var f := _floor(5, st)
	var m := f.get_node_or_null("EnemySpawns/GoblinKing") as Node3D
	check(m != null and m.get_meta(&"enemy") == "goblin_king", "the King at BossSpawn")
	check(
		m != null and m.position.is_equal_approx(f.get_node("BossSpawn").position), "on the marker"
	)
	f.free()
	st.defeat_boss("goblin_king")
	f = _floor(5, st)
	check(f.get_node_or_null("EnemySpawns/GoblinKing") == null, "not after his kill")
	f.free()


func test_exit_room_stair_hole() -> void:
	var f := _floor(1, LabyrinthState.fresh(42))
	var ex: Node3D
	for r in f.rooms:
		if r.get_meta(&"kind") == "exit":
			ex = r
	check(ex != null, "exit room")
	if ex == null or not f.dressed:
		f.free()
		return
	check(ex.find_child("stair_down", true, false) != null, "stair_down placed")
	check(
		ex.has_node("FloorW") and ex.has_node("FloorE") and ex.has_node("StairLanding"),
		"slab cut round the hole"
	)
	var s := f.get_node("StairsDown") as Node3D
	check(s.position.y < -3.4, "trigger at the stair foot (y %.1f)" % s.position.y)
	runner_tree.root.add_child(f)
	f.position = Vector3(0, 900, 4000)
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	var h := ex.global_position + WarrensKit.stair_hole(Vector2.ZERO)
	var q := PhysicsRayQueryParameters3D.create(
		s.global_position + Vector3(0, 6, 0), s.global_position + Vector3(0, -3, 0)
	)
	var hit := f.get_world_3d().direct_space_state.intersect_ray(q)
	check(
		not hit.is_empty() and absf(hit["position"].y - s.global_position.y) < 0.6,
		(
			"open shaft above the foot, floor below (%s, foot %.2f)"
			% [hit.get("position"), s.global_position.y]
		)
	)
	f.free()
