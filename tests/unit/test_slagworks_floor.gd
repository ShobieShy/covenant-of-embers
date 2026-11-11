extends TestCase
## U1: checkpoints 9-13 are Slagworks floors. The Warrens kit and the Blightcoil
## cavern stay on the builders they already have.


func _live(n: int, seed := 4) -> SlagworksFloor:
	var f := SlagworksFloor.make(n, LabyrinthState.fresh(seed))
	f.position = Vector3(0, -2000, 0)
	runner_tree.root.add_child(f)
	f.ensure_nav()
	for _i in 30:
		await runner_tree.physics_frame
		if f._region and f._region.navigation_mesh and f._region.navigation_mesh.get_polygon_count() > 0:
			if n >= SlagworksFloor.LAST or f.path_reaches(f.exit_local()):
				break
	return f


func _wipe_nav() -> void:
	var dir := DirAccess.open("res://scenes/levels/nav/slagworks")
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".res") or name.ends_with(".json") or name.ends_with(".remap"):
			dir.remove(name)
		name = dir.get_next()


func _drop(f: SlagworksFloor) -> void:
	if is_instance_valid(f):
		f.free()


func test_kit_floors_connect_and_crucible_is_handmade() -> void:
	_wipe_nav()
	for n in [9, 10, 11, 12]:
		var f := await _live(n, 11)
		check(f.floor_no == n, "checkpoint %d" % n)
		check(f.get_node_or_null("StairsDown") is LabyrinthStairs, "floor %d has an exit" % n)
		check(f.get_node_or_null("Pad") != null, "floor %d has a pad" % n)
		check(f.anvils().size() == 1, "floor %d has one furnace-anvil" % n)
		var anvil := f.anvils()[0] as Node3D
		check(String(anvil.get_parent().get_meta(&"kind", "")) == "elite", "anvil is in the elite room")
		var face := f.entry_direction(int(anvil.get_parent().get_meta(&"index")))
		var fwd := -anvil.global_transform.basis.z
		fwd.y = 0.0
		check(fwd.normalized().dot(face) > 0.75, "floor %d anvil faces the entry" % n)
		var ramps: Array = f.ramp_degrees()
		check(ramps.size() > 0, "floor %d has a gantry ramp" % n)
		for deg in ramps:
			check(float(deg) <= 40.0, "ramp %.1f deg" % float(deg))
		var run_ok := true
		for node in f.find_children("*", "StaticBody3D", true, false):
			if node.is_in_group(&"slag_ramp") and float(node.get_meta(&"run", 0)) + 0.01 < 6.0:
				run_ok = false
		check(run_ok, "gantry ramps run at least 6 m")
		var deck_ok := false
		for node in f.find_children("*", "StaticBody3D", true, false):
			if float(node.get_meta(&"deck_top", 0)) > 0.0:
				deck_ok = absf(float(node.get_meta(&"deck_top")) - 3.0) < 0.05
		check(deck_ok, "gantry deck top is 3 m")
		var polys := 0
		if f._region and f._region.navigation_mesh:
			polys = f._region.navigation_mesh.get_polygon_count()
		check(polys > 0, "floor %d nav has polygons (%d)" % [n, polys])
		check(f.path_reaches(f.exit_local()), "floor %d pad reaches the exit off the lava (%s)" % [n, f.path_note])
		_drop(f)
	var crucible := await _live(13, 11)
	check(crucible.anvils().size() == 1, "crucible anvil")
	check(crucible.find_child("GantryA", true, false) != null, "segment A")
	check(crucible.find_child("GantryB", true, false) != null, "segment B")
	check(crucible.find_child("GantryC", true, false) != null, "segment C")
	check(crucible.get_node_or_null("Pad") != null, "crucible pad")
	check(crucible.get_node_or_null("StairsDown") == null, "no floor 14 stair")
	check(crucible.find_child("RailProp", true, false) != null, "crucible rail prop, no cart")
	check(crucible.find_children("Rail", "", true, false).is_empty(), "crucible has no cart rail")
	var mouth := -(crucible.anvils()[0] as Node3D).global_transform.basis.z
	mouth.y = 0.0
	var to_pad := crucible.pad_local() - (crucible.anvils()[0] as Node3D).position
	to_pad.y = 0.0
	check(mouth.normalized().dot(to_pad.normalized()) > 0.75, "crucible anvil faces the way in")
	for deg in crucible.ramp_degrees():
		check(float(deg) <= 40.0, "crucible ramp %.1f deg" % float(deg))
	_drop(crucible)
	_wipe_nav()


func test_branches_keep_warrens_and_cavern() -> void:
	var before := LabyrinthFloor.build_count
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	var king := Interiors.new()
	king.labyrinth = LabyrinthState.fresh(6)
	king.labyrinth.current = 5
	runner_tree.root.add_child(king)
	await king.enter("labyrinth")
	var stayed := await king.descend()
	check(stayed == Vector3.INF, "descend on floor 5 does not build a floor")
	check(king.floor_no == 5 and king.slag == null and king.lab_floor != null, "still the Warrens boss floor")
	king.free()
	var cav := Interiors.new()
	cav.labyrinth = LabyrinthState.fresh(6)
	cav.labyrinth.current = 8
	runner_tree.root.add_child(cav)
	await cav.enter("labyrinth")
	check(cav.cavern != null and cav.slag == null and cav.lab_floor == null, "checkpoint 8 is the cavern")
	check_near(cav.cavern.pad_local(6).y, 0.0, 0.01, "sump height")
	check_near(cav.cavern.pad_local(7).y, 12.0, 0.01, "canopy height")
	check_near(cav.cavern.pad_local(8).y, 24.0, 0.01, "crown height")
	cav.free()
	var built := LabyrinthFloor.build_count
	var overlook := Interiors.new()
	overlook.labyrinth = LabyrinthState.fresh(6)
	overlook.labyrinth.current = 11
	runner_tree.root.add_child(overlook)
	await overlook.enter("labyrinth")
	check(LabyrinthFloor.build_count == built, "checkpoint 11 does not call LabyrinthFloor.build")
	check(overlook.slag != null and overlook.floor_no == 11, "Overlook floor")
	check(overlook.lab_floor == null and overlook.cavern == null, "not a Warrens floor or the cavern")
	var pad := overlook.slag.pad_global()
	check(
		Vector2(p.global_position.x - pad.x, p.global_position.z - pad.z).length() < 2.0,
		"the body stands on the Overlook pad"
	)
	check(
		runner_tree.root.find_children("*", "SlagworksFloor", true, false).size() == 1,
		"floors 9 and 13 are not in the same tree"
	)
	var manifest := "res://scenes/levels/nav/blightcoil/manifest.json"
	var before_manifest := FileAccess.get_file_as_string(manifest)
	overlook.free()
	check(FileAccess.get_file_as_string(manifest) == before_manifest, "the Blightcoil cache is not rewritten")
	check(LabyrinthFloor.build_count >= before, "warrens build counter still moves for floor 5")
	var end := Interiors.new()
	end.labyrinth = LabyrinthState.fresh(6)
	end.labyrinth.current = 13
	runner_tree.root.add_child(end)
	await end.enter("labyrinth")
	var stopped := await end.descend()
	check(stopped == Vector3.INF, "checkpoint 13 does not build a floor 14")
	check(end.floor_no == 13, "still on the crucible")
	end.free()
	p.free()
	_wipe_nav()


func test_nav_cache_bakes_once() -> void:
	_wipe_nav()
	var manifest := "res://scenes/levels/nav/blightcoil/manifest.json"
	var before_manifest := FileAccess.get_file_as_string(manifest)
	var first := SlagworksFloor.make(9, LabyrinthState.fresh(21))
	runner_tree.root.add_child(first)
	first.ensure_nav()
	check(first.nav_bakes == 1 and not first.nav_from_cache, "a missing cache bakes")
	check(FileAccess.file_exists(first.cache_manifest_path()), "the bake writes the cache")
	check(first._region.navigation_mesh.get_polygon_count() > 0, "the bake has polygons")
	var stem := first.cache_mesh_path()
	first.free()
	var second := SlagworksFloor.make(9, LabyrinthState.fresh(21))
	runner_tree.root.add_child(second)
	second.ensure_nav()
	check(second.nav_bakes == 0 and second.nav_from_cache, "the same toml and seed do not bake again")
	check(second.cache_mesh_path() == stem, "same cache file")
	second.free()
	check(
		FileAccess.get_file_as_string(manifest) == before_manifest,
		"baking a Slagworks floor does not rewrite the Blightcoil cache"
	)
	_wipe_nav()
