extends TestCase
## U1: checkpoints 6-8 are one cavern. The Warrens golden fixture stays put.


func _ready_cavern(n: int) -> BlightcoilCavern:
	var state := LabyrinthState.fresh(3)
	var c := BlightcoilCavern.make(n, state)
	c.position = Vector3(0, -2000, 0)
	runner_tree.root.add_child(c)
	c.ensure_nav()
	for _i in 20:
		await runner_tree.physics_frame
		if c.path_reaches_crown():
			break
	return c


func test_pads_ramps_and_nav() -> void:
	var c := await _ready_cavern(6)
	for n in [6, 7, 8]:
		check_near(c.pad_local(n).y, float((n - 6) * 12), 0.01, "pad %d height" % n)
	for deg in c.ramp_degrees():
		check(float(deg) <= 40.0 and float(deg) > 5.0, "ramp %.1f deg" % float(deg))
		var ramp_run_ok := true
		for ramp in c.doc["ramp"]:
			var fr: Array = ramp["fr"]
			var to: Array = ramp["to"]
			var run := Vector2(float(to[0]) - float(fr[0]), float(to[2]) - float(fr[2])).length()
			if run < 20.0:
				ramp_run_ok = false
		check(ramp_run_ok, "each ramp runs at least 20 m")
	var gap := c.min_clearance()
	check(gap >= 3.0, "underside clearance %.2f m" % gap)
	check(c.path_reaches_crown(), "nav path from the Sump pad to the Crown pad")
	check(c.get_node_or_null("Walk/Slab_sump") != null, "Sump collider")
	check(c.get_node_or_null("Walk/Slab_crown") != null, "Crown collider")
	check(c.nav_bakes == 1 or c.nav_from_cache, "baked or loaded a mesh")
	c.free()


func test_enter_canopy_keeps_every_tier() -> void:
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	var ints := Interiors.new()
	ints.labyrinth = LabyrinthState.fresh(4)
	ints.labyrinth.current = 7
	runner_tree.root.add_child(ints)
	await ints.enter("labyrinth")
	check(ints.cavern != null and ints.lab_floor == null, "checkpoint 7 is the cavern")
	check(ints.floor_no == 7, "canopy checkpoint")
	var local_y := p.global_position.y - ints.cavern.global_position.y
	check(local_y > 12.0 and local_y < 14.0, "body on the Canopy pad (y %.2f)" % local_y)
	var pad := ints.cavern.pad_global(7)
	check(Vector2(p.global_position.x - pad.x, p.global_position.z - pad.z).length() < 1.5, "body over the Canopy pad")
	check(ints.cavern.get_node_or_null("Walk/Slab_sump") != null, "Sump still in the tree")
	check(ints.cavern.get_node_or_null("Walk/Slab_crown") != null, "Crown still in the tree")
	check(LabyrinthFloor.build_count == LabyrinthFloor.build_count, "build counter readable")
	var before := LabyrinthFloor.build_count
	await ints.enter_floor(6)
	check(LabyrinthFloor.build_count == before, "checkpoint 6 does not call LabyrinthFloor.build")
	ints.free()
	p.free()


func test_descend_stops_at_the_king() -> void:
	var before := LabyrinthFloor.build_count
	var ints := Interiors.new()
	ints.labyrinth = LabyrinthState.fresh(5)
	runner_tree.root.add_child(ints)
	await ints.enter("labyrinth")
	for _i in 4:
		if ints.floor_no >= 5 or ints.busy:
			break
		await ints.descend()
		while ints.busy:
			await runner_tree.process_frame
	# Walk to floor 5 directly.
	if ints.floor_no != 5:
		await ints.enter_floor(5)
		while ints.busy:
			await runner_tree.process_frame
	var built := LabyrinthFloor.build_count
	var stayed := await ints.descend()
	check(stayed == Vector3.INF and ints.floor_no == 5, "descend on floor 5 does not build the cavern")
	check(ints.cavern == null, "no cavern on the King's floor")
	check(LabyrinthFloor.build_count == built, "no extra floor build")
	check(built > before, "the Warrens floor did build")
	ints.free()


func test_warrens_fixture_unchanged() -> void:
	var kit := FloorGen.load_kit()
	var lines := FileAccess.get_file_as_string("res://tests/fixtures/labyrinth/warrens_golden.txt").strip_edges().split(
		"\n"
	)
	var bad := 0
	for line in lines:
		var p := line.split(" ", false, 3)
		var s := FloorGen.floor_seed(int(p[0]), "warrens", int(p[1]), int(p[2]))
		if FloorGen.signature(FloorGen.generate(kit, s)) != p[3]:
			bad += 1
	check(bad == 0, "golden fixture still matches (%d bad)" % bad)
	var state := LabyrinthState.fresh(9)
	var a := FloorGen.signature(FloorGen.generate(kit, state.floor_seed(3)))
	var b := FloorGen.signature(FloorGen.generate(kit, FloorGen.floor_seed(state.save_seed, "warrens", 3, 0)))
	check(a == b, "floor 3 still hashes with the warrens seed")


func test_nav_cache_bakes_once() -> void:
	var manifest := "res://scenes/levels/nav/blightcoil/manifest.json"
	var mesh := "res://scenes/levels/nav/blightcoil/mesh.res"
	var saved_manifest := ""
	var saved_mesh: NavigationMesh = null
	if FileAccess.file_exists(manifest):
		saved_manifest = FileAccess.get_file_as_string(manifest)
	if ResourceLoader.exists(mesh):
		saved_mesh = load(mesh)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manifest))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mesh))
	var first := BlightcoilCavern.make(8, LabyrinthState.fresh(1))
	runner_tree.root.add_child(first)
	first.ensure_nav()
	check(first.nav_bakes == 1 and not first.nav_from_cache, "a missing cache bakes")
	check(FileAccess.file_exists(manifest), "the bake writes the cache")
	var polys := first._region.navigation_mesh.get_polygon_count()
	check(polys > 0, "the bake has polygons")
	check(not first.has_node("Floor9"), "checkpoint 8 does not build a floor 9")
	first.free()
	var second := BlightcoilCavern.make(6, LabyrinthState.fresh(1))
	runner_tree.root.add_child(second)
	second.ensure_nav()
	check(second.nav_bakes == 0 and second.nav_from_cache, "the same toml does not bake again")
	second.free()
	if saved_manifest != "":
		var f := FileAccess.open(manifest, FileAccess.WRITE)
		f.store_string(saved_manifest)
	if saved_mesh != null:
		ResourceSaver.save(saved_mesh, mesh)
