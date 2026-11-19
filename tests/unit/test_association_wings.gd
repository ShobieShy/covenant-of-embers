extends TestCase
## 0.10.2: the Association is a close. The 90 m wings are gone. The library and
## the courtyard keep their anchors, and the side doors stay shut until the tutorial ends.


func test_close_keeps_the_hall_and_the_side_rooms() -> void:
	var lvl := (load("res://scenes/levels/mage_association.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(lvl)
	check(lvl.get_node_or_null(^"Terrain") != null, "the close has terrain")
	check(lvl.get_node_or_null(^"Boxes/east_wing_floor") == null, "the 90 m east wing is gone")
	check(lvl.get_node_or_null(^"Boxes/library_floor") != null, "the library is a room")
	check(lvl.get_node_or_null(^"Boxes/courtyard_floor") != null, "the courtyard is a room")
	check(lvl.find_child("mezzanine", true, false) == null, "no mezzanine over a long wing")
	var gates := lvl.get_node_or_null(^"Gates")
	check(gates != null and gates.get_child_count() == 2, "two side doors")
	for g in gates.get_children() if gates else []:
		check(String(g.requires_flag) == "tutorial_done", "%s opens after the tutorial" % g.name)
	var library := lvl.get_node(^"Anchors/library") as Node3D
	var court := lvl.get_node(^"Anchors/courtyard") as Node3D
	check(library.position.distance_to(Vector3(16, 0, 0)) < 0.1, "library anchor stayed")
	check(court.position.distance_to(Vector3(-16, 0, 0)) < 0.1, "courtyard anchor stayed")
	check(lvl.get_node_or_null(^"Chests").get_child_count() == 3, "library, archive, courtyard chests")
	check(lvl.get_node_or_null(^"PlayerStart") != null, "hall start kept for beats 1-4")
	lvl.queue_free()
