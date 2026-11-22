extends TestCase
## 0.11.3: the lab is its own interior. The oak keeps the hollow and the tree,
## and the crown no longer has a floor running through it.


func test_the_room_is_its_own_scene() -> void:
	var oak: Node3D = (load("res://scenes/levels/old_oak.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(oak)
	check(oak.get_node_or_null("Boxes/lab_floor") == null, "the oak has no upstairs floor")
	check(oak.get_node_or_null("Boxes/lab_stair") == null, "the oak has no stair through the crown")
	check(oak.get_node_or_null("Props/old_oak") != null, "the tree stays in the grove")
	var down := oak.get_world_3d().direct_space_state
	var crown := down.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 8, -10), Vector3(0, 2, -10)))
	check(crown.is_empty() or (crown["collider"] as Node).name != "lab_floor", "nothing to walk on inside the crown")
	var hollow := down.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 3, 6), Vector3(0, -2, 6)))
	check(not hollow.is_empty() and (hollow["collider"] as Node).name == "floor", "the hollow floor stays")
	oak.free()
	var lab: Node3D = (load("res://scenes/levels/bobs_lab.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(lab)
	check(lab.get_node_or_null("Props/old_oak") == null, "the tree is not inside the room")
	var floor := lab.get_node("Boxes/lab_floor") as StaticBody3D
	var space := lab.get_world_3d().direct_space_state
	var on_room := space.intersect_ray(
		PhysicsRayQueryParameters3D.create(
			floor.global_position + Vector3(0, 3, 0), floor.global_position + Vector3(0, -1, 0)
		)
	)
	check(not on_room.is_empty() and (on_room["collider"] as Node).name == "lab_floor", "the room has a floor")
	var rail := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0, 0.8, 0), Vector3(4, 0.8, 0)))
	check(not rail.is_empty(), "the open edge has a rail")
	check(lab.get_node_or_null("Exits/to_town") != null, "the door leads back to the town")
	lab.free()
