extends TestCase
## 0.11.3: Eldoria follows the town painting. North to south stays a short sprint.


func test_ring_scale_and_ground() -> void:
	var level := (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	runner_tree.root.add_child(level)
	var terrain := level.get_node("Terrain") as TerrainZone
	check(terrain.size.x >= 320.0 and terrain.size.y >= 320.0, "the zone covers the ring")
	var north := (level.get_node("Exits/to_association") as Node3D).position
	var south := (level.get_node("Exits/to_landfill") as Node3D).position
	var east := (level.get_node("Exits/to_old_oak") as Node3D).position
	var across := north.distance_to(south)
	check(across > 240.0 and across < 340.0, "north to south stays a town crossing (%.0f m)" % across)
	check(east.x > 140.0 and absf(east.z) < 80.0, "the east gate stays on the east road")
	check(level.get_node_or_null("Exits/to_west") == null, "the west arc has no gate")
	check(terrain.foliage > 0 and terrain.foliage <= 8000, "grass stays inside the instance cap")
	check(level.get_node_or_null("Terrain/Foliage") != null, "grass is one instanced mesh")
	var kill := float(level.get_meta("kill_line_y"))
	check(kill < north.y - 7.0, "the kill line sits under the streets (%.1f)" % kill)
	var pad := terrain.height_at(0.0, 28.0)
	var dropped := terrain.height_at(-230.0, 10.0)
	check(dropped < pad - 4.0, "the ground drops outside the west wall (%.1f vs %.1f)" % [dropped, pad])
	check(level.get_node_or_null("Props/old_oak") == null, "the grove keeps the Old Oak name")
	check(level.get_node_or_null("Props/oak_landmark") != null, "the east lobe holds the oak")
	check(level.get_node_or_null("Underlay") != null, "the painting is the underlay")
	check(level.get_node_or_null("Boxes/cliff_w") == null, "the west boundary is not a wall box")
	level.free()
