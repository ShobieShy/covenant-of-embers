extends TestCase
## The Landfill is a closed arena with its own name, a waystone, and roads to town
## and the Breach. A camp still wakes only with a player near.


func test_landfill_layout() -> void:
	var lvl := (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate()
	check(lvl.get_node_or_null("Terrain") == null, "the Landfill is a closed level")
	check(String(lvl.get_meta("level_name", "")) == "The Landfill", "its own name")
	check(lvl.get_node_or_null("Waystones/landfill") != null, "Landfill waystone")
	check(lvl.get_node_or_null("Exits/to_town") != null, "road back to town")
	check(lvl.get_node_or_null("Exits/to_breach") != null, "road on to the Breach")
	check(lvl.get_node_or_null("Anchors/breach_portal_1") == null, "no Breach mark in the dump")
	var camps := lvl.get_node_or_null("Camps")
	check(camps == null or camps.get_child_count() == 0, "no open-zone camps")
	lvl.free()


func test_levers_open_vault() -> void:
	var holder := Node3D.new()
	runner_tree.root.add_child(holder)
	var lvl := Node3D.new()
	holder.add_child(lvl)
	var an := Node3D.new()
	an.name = "Anchors"
	lvl.add_child(an)
	for i in 2:
		var m := Marker3D.new()
		m.name = "lever_box_%d" % (i + 1)
		an.add_child(m)
	var f := StoryFlags.new()
	var sws := ZoneChests.setup_levers(holder, lvl, "midden", null, f)
	check(sws.size() == 2 and ZoneChests.lever_group("lever_joes_stash_2") == "joes_stash", "levers grouped")
	sws[0].press()
	check(not f.has("levers_box"), "one lever is not enough")
	sws[1].press()
	check(f.has("levers_box") and f.has("lever:midden:lever_box_1"), "both levers set the group flag")
	holder.queue_free()


func test_camp_wakes_and_respawns() -> void:
	var sp := EnemySpawner.new()
	sp.table = EnemyTable.load_default()
	runner_tree.root.add_child(sp)
	var c := {
		"name": "t",
		"center": Vector3(0, 0, 0),
		"radius": 4.0,
		"respawn_s": 5.0,
		"enemies": [{"enemy": "gnawer", "count": 3}],
		"alive": [] as Array[Enemy],
		"wait": 0.0,
		"spawned": 0
	}
	var got := sp.spawn_camp(c)
	check(got.size() == 3 and sp.camp_spawns == 1, "camp spawns its pack")
	sp.queue_free()
