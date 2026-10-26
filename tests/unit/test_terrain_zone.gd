extends TestCase
## Step 152 (Phase W1): TerrainZone heights are deterministic, flat on pads, rise at the
## edge; the Terrain3D extension loads, collides, and joins the level navmesh.

const C := Vector2(6000, 6000)


func _zone(build := false) -> TerrainZone:
	var z := TerrainZone.new()
	z.size = Vector2(160, 160)
	z.center = C
	z.height = 12.0
	z.noise_seed = 7
	z.spacing = 2.0
	z.pads = [Rect2(C.x - 10, C.y - 10, 20, 20)]
	z.build_on_ready = build
	return z


func test_heights_deterministic_flat_pads_and_rim() -> void:
	var a := _zone()
	var b := _zone()
	check(a.content_hash() == b.content_hash(), "same settings, same bytes")
	b.noise_seed = 8
	b._hash = 0
	b._noise = null
	check(a.content_hash() != b.content_hash(), "seed changes the terrain")
	check_near(a.height_at(C.x, C.y), a.pad_y, 0.001, "pad centre flat")
	check_near(a.height_at(C.x + 9, C.y - 9), a.pad_y, 0.001, "pad corner flat")
	check(a.height_at(C.x + 79, C.y) > a.rim * 0.8, "edge rises to the rim")
	var hilly := 0
	for i in 20:
		if a.height_at(C.x - 40 + i * 3, C.y + 40) > 1.0:
			hilly += 1
	check(hilly > 0, "hills away from pads")
	check(a.grid_size() == Vector2i(225, 225), "grid from region-snapped origin %s" % a.grid_size())
	a.free()
	b.free()


func test_terrain3d_builds_and_collides() -> void:
	check(TerrainZone.available(), "Terrain3D extension registered (addons/terrain_3d)")
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var boxes := Node3D.new()
	boxes.name = "Boxes"
	w.add_child(boxes)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.2, 20)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = Vector3(C.x, -0.1, C.y)
	boxes.add_child(sb)
	var z := _zone(true)
	z.name = "Terrain"
	w.add_child(z)
	check(z.terrain != null, "Terrain3D node built")
	var nav := LevelNavigation.new()
	nav.name = "Navigation"
	w.add_child(nav)
	for i in 3:
		await runner_tree.physics_frame
	var x := C.x - 30.0
	var zz := C.y + 30.0
	var want := z.height_at(x, zz)
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 200, zz), Vector3(x, -50, zz))
	var hit := w.get_world_3d().direct_space_state.intersect_ray(q)
	check(not hit.is_empty(), "ray hits terrain collision")
	if not hit.is_empty():
		check(absf(hit.position.y - want) < 0.6, "collision at %.2f ~ height %.2f" % [hit.position.y, want])
	check(not nav.tiles.is_empty(), "step 154: terrain levels bake in tiles")
	var bounds := PackedVector3Array()
	for t in nav.tiles:
		bounds.append_array(t.navigation_mesh.get_vertices())
	var far := 0
	for v in bounds:
		if absf(v.x - C.x) > 11.0 or absf(v.z - C.y) > 11.0:
			far += 1
	check(far > 0, "navmesh reaches terrain beyond the pad (%d verts)" % far)
	w.queue_free()
	await runner_tree.physics_frame
