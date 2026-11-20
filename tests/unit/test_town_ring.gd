extends TestCase
## 0.11.1: Eldoria is a hub you cross in about a minute of sprint, not a 72 m pad.


func test_ring_scale_and_ground() -> void:
	var level := (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(level)
	var terrain := level.get_node("Terrain") as TerrainZone
	check(terrain.size.x >= 320.0 and terrain.size.y >= 320.0, "the zone covers the ring")
	var north := (level.get_node("Exits/to_association") as Node3D).position
	var south := (level.get_node("Exits/to_landfill") as Node3D).position
	var east := (level.get_node("Exits/to_old_oak") as Node3D).position
	var across := north.distance_to(south)
	check(across > 300.0 and across < 360.0, "north to south is a hub crossing (%.0f m)" % across)
	check(east.x > 140.0 and absf(east.z) < 80.0, "the east gate stays on the east road")
	check(level.get_node_or_null("Exits/to_west") == null, "the west arc has no gate")
	check(terrain.foliage > 0 and terrain.foliage <= 8000, "grass stays inside the instance cap")
	check(level.get_node_or_null("Terrain/Foliage") != null, "grass is one instanced mesh")
	var kill := float(level.get_meta("kill_line_y"))
	check(kill < north.y - 7.0, "the kill line sits under the streets (%.1f)" % kill)
	var pad := terrain.height_at(0.0, 0.0)
	var mound := terrain.height_at(-100.0, 40.0)
	check(mound > pad + 2.0, "a hill stands west of the square")
	var moat := terrain.height_at(-139.1, 50.6)
	check(moat < pad - 0.5, "a ravine sits off the roads")
	check(level.get_node_or_null("Boxes/cliff_w") == null, "the west boundary is not a wall box")
	level.free()
