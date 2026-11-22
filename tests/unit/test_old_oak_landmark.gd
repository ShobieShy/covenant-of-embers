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
	for _i in 4:
		await runner_tree.physics_frame
	var space: PhysicsDirectSpaceState3D = town.get_world_3d().direct_space_state
	var fwd := door.global_transform.basis * Vector3(0, 0, -1)
	var ramp := _ramp_meets_the_ground(space, door, fwd)
	check(ramp == "", ramp)
	var tz := town.get_node(^"Terrain") as TerrainZone
	var eye := Vector3(0.0, tz.height_at(0.0, 148.0) + 1.7, 148.0)
	var trunk := Vector3(oak.global_position.x, oak.global_position.y + 4.0, oak.global_position.z)
	var clear := true
	for i in 7:
		var p: Vector3 = eye.lerp(trunk, float(i + 1) / 8.0)
		if tz.height_at(p.x, p.z) > p.y - 0.8:
			clear = false
	check(clear, "the trunk is visible from the Main Gate")
	check(town.get_node_or_null(^"Props/grove_tree_1") == null, "no placeholder oaks")
	town.free()


## The authored ramp is a 37 deg root. The player climbs 0.35 m, so the ground may
## sit a little above the ramp foot but not a full step below it. A root under the
## doorway is not the deck, and a graze on the door frame is not a wall.
func _ramp_meets_the_ground(space: PhysicsDirectSpaceState3D, door: Node3D, fwd: Vector3) -> String:
	var peak := -1.0e8
	var hits: Array[Dictionary] = []
	for i in 18:
		var dist := float(i) * 0.6
		var from: Vector3 = door.global_position + fwd * dist + Vector3(0, 16, 0)
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -40, 0)))
		if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
			continue
		var at := hit["position"] as Vector3
		var oak_hit := String((hit["collider"] as Node).name) == "old_oak"
		if oak_hit:
			peak = maxf(peak, at.y)
		hits.append({"y": at.y, "oak": oak_hit, "dist": dist})
	var started := false
	var foot := 0.0
	var prev_y := 0.0
	var prev_dist := 0.0
	var ground := -1.0
	for h in hits:
		var y: float = h["y"]
		var dist: float = h["dist"]
		if h["oak"]:
			if not started:
				if y < peak - 0.2:
					continue
				started = true
			else:
				var run := maxf(dist - prev_dist, 0.05)
				if y > prev_y + 0.05:
					return "the ramp rises on the way down from the door"
				if (prev_y - y) / run > 1.0:
					return "the ramp is steeper than the player can walk"
			prev_y = y
			prev_dist = dist
			foot = y
		elif started:
			if y < foot - 0.3:
				return "a %.2f m step where the ramp meets the ground" % (foot - y)
			if ground >= 0.0:
				var run := maxf(dist - prev_dist, 0.05)
				if (ground - y) / run > 1.0:
					return "the ground in front of the ramp is steeper than the player can walk"
			ground = y
			prev_dist = dist
	if not started:
		return "the ramp does not leave the doorway"
	if ground < 0.0:
		return "the ramp does not reach the ground"
	return ""


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
