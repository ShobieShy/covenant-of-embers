extends TestCase
## L3 (Ember Art batch 08a/08b): the Warrens tile kit dresses Labyrinth floors, the throne
## hall is floor 5's arena, the gate stands at the crater, and the goblins have bodies.


func test_wall_fill_centres_the_door() -> void:
	check(WarrensKit.fill(10.0).map(func(a): return a[1]) == [4.0, 4.0, 2.0], "10 m = 4+4+2")
	var n := Node3D.new()
	check(WarrensKit.wall_line(n, Vector3.ZERO, 0.0, 24.0, true) == 7, "24 m side: 7 pieces")
	var xs := []
	var door := false
	for c: Node3D in n.get_children():
		xs.append(snappedf(c.position.x, 0.01))
		door = door or (String(c.name).begins_with("wall_door_4m") and is_zero_approx(c.position.x))
		if String(c.name).begins_with("wall_2m"):
			check(
				is_equal_approx(absf(c.position.x), 3.0),
				"2 m pieces beside the door (%s)" % c.position.x
			)
	xs.sort()
	check(xs == [-10.0, -6.0, -3.0, 0.0, 3.0, 6.0, 10.0], "handoff pivots (%s)" % [xs])
	check(door, "door centred")
	n.free()


func test_floor_is_dressed_and_still_collides() -> void:
	var kit := FloorGen.load_kit()
	var st := LabyrinthState.new()
	var f := LabyrinthFloor.build(kit, 1, st)
	check(f.dressed, "kit present -> dressed")
	var r: Node3D = f.rooms[0]
	check(r.has_node("Dress"), "room dressed")
	check(
		not r.has_node("Floor") or not (r.get_node("Floor").get_child(0) as MeshInstance3D).visible,
		"greybox hidden"
	)
	check(r.get_node("Floor") is StaticBody3D, "greybox collision kept")
	var rest := false
	for rr in f.rooms:
		if rr.get_meta(&"kind") == "rest":
			rest = (
				rr.find_child("cook_fire", true, false) != null
				and rr.find_child("bedroll", true, false) != null
			)
	check(rest, "rest room has the fungus-cellar set")
	check(f.find_child("craft_bench", true, false) != null, "craft bench at the station")
	f.free()


func test_boss_floor_throne_hall_lods() -> void:
	var f := LabyrinthFloor.build(FloorGen.load_kit(), 5, LabyrinthState.new())
	var h := f.find_child("throne_hall", true, false) as Node3D
	check(h != null, "throne hall is the arena")
	var lod1 := h.find_child("throne_hall_LOD1", true, false) as MeshInstance3D if h else null
	check(
		(
			lod1 != null
			and lod1.visibility_range_begin > 0.0
			and lod1.visibility_range_end > lod1.visibility_range_begin
		),
		"LOD1 range"
	)
	check(
		h != null and h.find_children("*", "StaticBody3D", true, false).size() == 1,
		"LOD0 collision only"
	)
	check(f.has_node("BossSpawn") and f.has_node("WaystoneSpot"), "markers kept")
	f.free()


func test_gate_slot_and_posts() -> void:
	var g := EmberArt.model("labyrinth_gate")
	check(g != null, "gate model")
	check(
		g != null and g.find_children("GatePost*", "StaticBody3D", true, false).size() == 2,
		"two posts, open portal"
	)
	if g:
		g.free()


func test_goblin_bodies_and_crown() -> void:
	var t := EnemyTable.load_default()
	for id in ["goblin_grunt", "goblin_archer", "goblin_shaman", "goblin_king"]:
		check(t.find(id) != null, "%s def" % id)
		check(ResourceLoader.exists(EnemyModels.path_for(id)), "%s model" % id)
	var k := Enemy.create(t.find("goblin_king"))
	runner_tree.root.add_child(k)
	var crown := k.model.find_child("Crown", true, false) as Node3D
	check(crown != null and crown.visible, "crown on")
	check(EnemyModels.throw_release(k.model) > 0.1, "throw release at 40% of the clip")
	k.apply_damage(99999.0, ElementTable.Element.FIRE)
	check(crown != null and not crown.visible, "crown hidden on death")
	k.free()


func test_hand_props_at_hand_height() -> void:
	var t := EnemyTable.load_default()
	for p in [["goblin_grunt", "Club"], ["goblin_archer", "Bow"], ["goblin_shaman", "Staff"]]:
		var e := Enemy.create(t.find(p[0]))
		runner_tree.root.add_child(e)
		await runner_tree.process_frame
		var prop := e.model.find_child(p[1], true, false) as Node3D
		check(prop != null, "%s has %s" % p)
		if prop:
			var y := _mesh_mid_y(prop) - e.global_position.y
			check(
				y > 0.25 * e.def.size.y and y < 1.0 * e.def.size.y,
				"%s %s at hand height (%.2f m)" % [p[0], p[1], y]
			)
		e.free()


func test_labyrinth_warmup_lists_the_kit() -> void:
	var paths := ShaderWarmup.labyrinth_mesh_paths()
	check(paths.size() >= 12, "warrens and goblin meshes (%d)" % paths.size())
	for p in paths:
		check(ResourceLoader.exists(p), p)
	check(paths.has(WarrensKit.DIR + "wall_4m.glb"), "walls")
	check(paths.has(WarrensKit.DIR + "throne_hall.glb"), "throne hall")
	check(paths.has("res://assets/original/ember_art/goblin_grunt.glb"), "skinned grunt")
	check(paths.has("res://assets/original/ember_art/goblin_king.glb"), "skinned king")
	var n: int = await ShaderWarmup.warm_labyrinth(runner_tree)
	check(n == 0, "headless dummy renderer does not draw (%d)" % n)


func _mesh_mid_y(n: Node3D) -> float:
	var ab := AABB()
	var first := true
	for mi in [n] + n.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D:
			var a: AABB = (
				(mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			)
			ab = a if first else ab.merge(a)
			first = false
	return ab.get_center().y if not first else n.global_position.y
