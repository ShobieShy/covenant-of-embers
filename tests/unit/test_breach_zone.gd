extends TestCase
## The Breach is a closed dungeon: the room slice, its waystone, and the road back
## to the Landfill. The open crater zone is not part of the level.

const SCENE := "res://scenes/levels/breach.tscn"


func test_breach_zone_layout() -> void:
	var lvl := (load(SCENE) as PackedScene).instantiate()
	check(lvl.get_node_or_null("Terrain") == null, "no open crater")
	check(String(lvl.get_meta("level_name", "")) == "The Breach", "the Breach keeps its name")
	check(lvl.get_node_or_null("Waystones/breach") != null, "entrance waystone")
	check(lvl.get_node_or_null("Exits/to_midden") != null, "road back to the Landfill")
	check(lvl.get_node_or_null("Anchors/crater_entrance") == null, "the crater approach is gone")
	var camps := lvl.get_node_or_null("Camps")
	check(camps == null or camps.get_child_count() == 0, "no side-wing camp")
	lvl.free()


func test_breach_zone_reachable() -> void:
	var holder := Node3D.new()
	holder.position = Vector3(5000, 0, 5000)
	runner_tree.root.add_child(holder)
	var lvl: Node3D = (load(SCENE) as PackedScene).instantiate()
	holder.add_child(lvl)
	var nav := lvl.get_node("Navigation") as LevelNavigation
	var t0 := Time.get_ticks_msec()
	while not nav.map_ready() and Time.get_ticks_msec() - t0 < 20000:
		await runner_tree.physics_frame
	check(nav.map_ready(), "Breach navmesh synced")
	var start := (lvl.get_node("PlayerStart") as Node3D).global_position
	var map := nav.get_navigation_map()
	var goals := {
		"lever_west": (lvl.get_node("Switches/lever_west") as Node3D).global_position,
		"to_midden": (lvl.get_node("Exits/to_midden") as Node3D).global_position,
	}
	for g in goals:
		var to: Vector3 = goals[g]
		var path := NavigationServer3D.map_get_path(map, start, to, true)
		check(path.size() > 1 and path[path.size() - 1].distance_to(to) < 1.5, "%s reachable" % g)
	holder.queue_free()
