extends TestCase
## Step 161 done check: the Landfill carries 10 POIs, 8 camps, 23 chests (2 hidden, 1
## lever vault), the Overlook waystone and 2 Breach portal anchors; a camp wakes only with a
## player near, respawns after a clear; 3 levers open the vault.


func test_landfill_layout() -> void:
	var lvl := (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate()
	check(lvl.get_node("Camps").get_child_count() == 8, "8 camps")
	var chests := lvl.get_node("Chests").get_children()
	check(chests.size() == 24, "24 chests (camp + 20 + 2 hidden + vault): %d" % chests.size())
	var tiers := chests.map(func(c: Node) -> String: return String(c.get_meta(&"tier")))
	check(tiers.count("hidden") == 2 and tiers.count("vault") == 1, "2 hidden, 1 vault")
	check(lvl.get_node_or_null("Waystones/landfill_overlook") != null, "Overlook waystone")
	for a in ["breach_portal_1", "breach_portal_2", "lever_joes_stash_3"]:
		check(lvl.get_node_or_null("Anchors/" + a) != null, a)
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
	check(got[0].has_meta(CampLeash.HOME), "camp members are leashed home")
	sp.queue_free()
