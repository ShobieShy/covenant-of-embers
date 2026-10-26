extends TestCase
## Step 159 done check: the 60x90 m Association keeps the grand hall and adds two wings
## behind tutorial_done gates, a 3-floor library (mezzanine 4 m, archive 8 m) and chests.


func test_wings_gated_and_three_floors() -> void:
	var lvl := (load("res://scenes/levels/mage_association.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(lvl)
	var gates := lvl.get_node_or_null(^"Gates")
	check(gates != null and gates.get_child_count() == 2, "two wing gates")
	for g in gates.get_children() if gates else []:
		check(String(g.requires_flag) == "tutorial_done", "%s opens after the tutorial" % g.name)
	var mez := lvl.find_child("mezzanine", true, false) as Node3D
	var arc := lvl.find_child("archive", true, false) as Node3D
	check(mez and absf(mez.global_position.y - 3.8) < 0.01, "floor 2 at 4 m")
	check(arc and absf(arc.global_position.y - 7.8) < 0.01, "floor 3 at 8 m")
	check(lvl.get_node_or_null(^"Chests").get_child_count() == 3, "library, archive, courtyard chests")
	check(lvl.get_node_or_null(^"PlayerStart") != null, "hall start kept for beats 1-4")
	lvl.queue_free()
