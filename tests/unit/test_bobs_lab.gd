extends TestCase
## 0.10.3: one room in the branches. The hollow, and Bob downstairs, stay put.


func test_the_stair_reaches_a_closed_room() -> void:
	var level: Node3D = (load("res://scenes/levels/old_oak.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(level)
	var floor := level.get_node("Boxes/lab_floor") as StaticBody3D
	check(floor.position.y > 3.0, "the room is up in the branches")
	var down := level.get_world_3d().direct_space_state
	var on_room := down.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			floor.global_position + Vector3(0, 3, 0), floor.global_position + Vector3(0, -1, 0)
		)
	)
	check(not on_room.is_empty() and (on_room["collider"] as Node).name == "lab_floor", "the room has a floor")
	var rail := down.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(-1.2, 4.5, -4.35), Vector3(2, 4.5, -4.35))
	)
	check(not rail.is_empty(), "the open edge has a rail")
	var steps := 0
	for z in [2.2, 1.0, 0.0, -1.0]:
		var hit := down.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-6.8, 6.0, z), Vector3(-6.8, -1.0, z)))
		if hit.is_empty():
			continue
		if (hit["collider"] as Node).name == "lab_stair" and (hit["normal"] as Vector3).y > 0.7:
			steps += 1
	check(steps >= 2, "the stair is walkable (%d samples)" % steps)
	var hollow := down.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 3, 6), Vector3(0, -2, 6)))
	check(
		not hollow.is_empty() and absf((hollow["position"] as Vector3).y) < 0.05,
		"the arrival floor is still the hollow"
	)
	check(level.get_node_or_null("Props/old_oak") != null, "the tree outside is unchanged")
	level.free()
