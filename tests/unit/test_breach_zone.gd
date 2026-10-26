extends TestCase
## Step 162 (W11) done check: the Breach is a 220x320 m zone. A crater approach from the
## breach waystone, 6 rooms on 2 levels (the annex's bell loft and reliquary at 4 m), 3
## levers, and the optional side wing (camp + hidden chest) behind a tutorial_done gate.
## Every new spot is reachable on the navmesh from the start.

const SCENE := "res://scenes/levels/breach.tscn"


func test_breach_zone_layout() -> void:
	var lvl := (load(SCENE) as PackedScene).instantiate()
	check(lvl.get_node_or_null("Terrain") != null or lvl.find_child("*Terrain*", false) != null, "has terrain")
	check(lvl.get_node_or_null("Waystones/breach") != null, "entrance waystone")
	check(lvl.get_node("Camps").get_child_count() == 1, "side wing camp")
	var tiers := lvl.get_node("Chests").get_children().map(func(c: Node) -> String: return String(c.get_meta(&"tier")))
	check(tiers.count("hidden") == 1 and tiers.size() == 4, "4 zone chests, 1 hidden: %s" % [tiers])
	check(lvl.get_node_or_null("Switches/lever_loft") != null, "3rd lever in the reliquary")
	var ups := 0
	for e in lvl.get_node("Encounters").get_children():
		if Vector3(e.get_meta("trigger_center", Vector3.ZERO)).y > 3.0:
			ups += 1
	check(ups == 2, "2 rooms on the upper level: %d" % ups)
	for a in ["crater_entrance", "ossuary", "reliquary"]:
		check(lvl.get_node_or_null("Anchors/" + a) != null, a)
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
		"lever_loft": (lvl.get_node("Switches/lever_loft") as Node3D).global_position,
		"crater_entrance": (lvl.get_node("Anchors/crater_entrance") as Node3D).global_position,
		"side_hidden": lvl.to_global(Vector3(32, 0, 60)),
	}
	for g in goals:
		var to: Vector3 = goals[g]
		var path := NavigationServer3D.map_get_path(map, start, to, true)
		check(path.size() > 1 and path[path.size() - 1].distance_to(to) < 1.5, "%s reachable" % g)
	holder.queue_free()
