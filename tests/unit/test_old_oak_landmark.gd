extends TestCase
## 0.11.4: the Town east-lobe oak is Ember Art v4. The ramp collision is the
## authored hull, the foliage cards are cut out, and the door sits on the threshold.


func test_the_east_lobe_oak_is_walkable() -> void:
	var town: Node3D = (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(town)
	var oak := OldOakLandmark.prepare(town)
	check(oak != null, "the east lobe has the oak")
	check(is_equal_approx(oak.rotation_degrees.y, 135.0), "yaw 135, door toward the south-west")
	var door := oak.find_child("Door", true, false) as Node3D
	check(door != null and absf(door.position.y - 6.2) < 0.05, "threshold at 6.2 m (%s)" % door.position)
	var lod0 := oak.find_child("LOD0", true, false) as Node3D
	var lod1 := oak.find_child("LOD1", true, false) as Node3D
	var card := lod0.find_child("FoliageCards", true, false) as MeshInstance3D
	check(card.visibility_range_end == 60.0 and card.visibility_range_begin == 0.0, "LOD0 holds through 60 m")
	var far := lod1.find_child("FoliageCards_LOD1", true, false) as MeshInstance3D
	check(far.visibility_range_begin == 60.0 and far.visibility_range_end == 0.0, "LOD1 takes over after 60 m")
	var mat := card.material_override as StandardMaterial3D
	check(
		(
			mat.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			and is_equal_approx(mat.alpha_scissor_threshold, 0.35)
		),
		"foliage alpha scissor 0.35"
	)
	check(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "foliage is double-sided")
	check(absi(_tris(lod0) - 30998) < 50, "LOD0 tris %d" % _tris(lod0))
	check(absi(_tris(lod1) - 9350) < 50, "LOD1 tris %d" % _tris(lod1))
	var hull := 0
	for n in oak.find_children("*", "StaticBody3D", true, false):
		var body := n as StaticBody3D
		check(body.collision_layer == 1, "the ramp collides with the world")
		for c in body.get_children():
			if c is CollisionShape3D and (c as CollisionShape3D).shape is ConcavePolygonShape3D:
				hull = (c as CollisionShape3D).shape.get_faces().size() / 3
	check(absi(hull - 194) < 8, "collision tris %d" % hull)
	await runner_tree.physics_frame
	var space: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var fwd := door.global_transform.basis * Vector3(0, 0, -1)
	var side := door.global_transform.basis * Vector3(1, 0, 0)
	var heights: Array[float] = []
	for dist: float in [2.0, 10.0, 20.0]:
		var from: Vector3 = door.global_position + fwd * dist + side * 2.0 + Vector3(0, 8, 0)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -20, 0)))
		check(not hit.is_empty() and (hit["normal"] as Vector3).y > 0.5, "walkable at %.0f m" % dist)
		if not hit.is_empty():
			heights.append((hit["position"] as Vector3).y)
	check(heights.size() == 3 and heights[2] < heights[0] - 1.5, "the ramp descends (%s)" % [heights])
	town.free()


func _tris(root: Node) -> int:
	var n := 0
	var meshes: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		meshes.append(root)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		meshes.append(c)
	for mi in meshes:
		var mesh := mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var idx: int = mesh.surface_get_array_index_len(s)
			n += idx / 3 if idx > 0 else int(mesh.surface_get_array_len(s) / 3)
	return n
