extends TestCase
## 0.11.3: the painted town. A round hill about 320 m across, a small square,
## and the three exits still in the same directions.


func test_ring_matches_the_painting_layout() -> void:
	var level := (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(level)
	var terrain := level.get_node("Terrain") as TerrainZone
	check(terrain.size.x >= 320.0 and terrain.size.y >= 320.0, "the hill still covers a hub")
	check(terrain.mound_radius > 150.0 and terrain.mound_drop > 4.0, "the ground falls away outside the wall")
	var south := (level.get_node("Exits/to_landfill") as Node3D).position
	var north := (level.get_node("Exits/to_association") as Node3D).position
	var east := (level.get_node("Exits/to_old_oak") as Node3D).position
	check(south.z > 140.0 and absf(south.x) < 8.0, "the south gate is the main gate")
	check(north.z < -30.0 and north.z > -70.0, "the Association door is the cathedral, not the far wall")
	check(east.x > 100.0 and absf(east.z) < 30.0, "Bob's door is in the east lobe")
	var far_north := 0.0
	var wards := 0
	for b in level.get_node("Boxes").get_children():
		var p := (b as Node3D).position
		if String(b.name).begins_with("ring_"):
			far_north = minf(far_north, p.z)
		if String(b.name).begins_with("ward_"):
			wards += 1
	check(far_north < -145.0, "a round wall closes the north (%.0f)" % far_north)
	check(wards >= 6, "at least six ward crystals (%d)" % wards)
	check(level.get_node_or_null("Dome") != null, "a dome hangs over the hill")
	var plaza := level.get_node("Boxes/plaza") as Node3D
	var plaza_size := (plaza.get_node("Shape").shape as BoxShape3D).size
	check(plaza_size.x < 80.0 and plaza_size.z < 80.0, "the square is not a vast plaza")
	check(level.get_node_or_null("Boxes/cathedral") != null, "the cathedral is a building")
	check(level.get_node_or_null("Props/old_oak") != null, "the Old Oak stands in the east lobe")
	check(terrain.foliage > 0 and terrain.foliage <= 8000, "grass stays inside the instance cap")
	var kill := float(level.get_meta("kill_line_y"))
	check(kill < south.y - 7.0, "the kill line is under the streets")
	level.free()
