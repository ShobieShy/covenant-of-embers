extends TestCase
## OW10d: the outdoor levels' markers sit at their world offsets, art stripped, and each
## zone's EnemySpawner spawns at world positions.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func test_zones_and_spawners() -> void:
	var root := Node3D.new()
	runner_tree.root.add_child(root)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	root.add_child(p)
	var wz := WorldZones.new()
	root.add_child(wz)
	wz.build(p)
	for id in WorldZones.ZONES:
		var z := wz.zones.get(id) as Node3D
		check(z != null, "%s: zone built" % id)
		if z == null:
			continue
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate() as Node3D
		var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
		var start := (lvl.get_node("PlayerStart") as Node3D).position
		lvl.free()
		check(z.position == Vector3(wo.x, 0, wo.y), "%s at its world offset" % id)
		for s in WorldZones.STRIP:
			check(z.get_node_or_null(NodePath(s)) == null, "%s: %s stripped" % [id, s])
		var st := z.get_node("PlayerStart") as Node3D
		check(
			st.global_position.distance_to(SaveMigration.entrance(id)) < 0.01,
			"%s: PlayerStart = the migration entrance" % id
		)
		check(st.position == start, "%s: local layout kept" % id)
		check(wz.zone_at(st.global_position) == id, "%s: zone_at" % id)
		var sp := wz.spawners.get(id) as EnemySpawner
		check(sp != null, "%s: spawner" % id)
		for c in sp.get_children() if sp else []:
			if c is Enemy:
				var d := Vector2(
					(c as Enemy).global_position.x - wo.x, (c as Enemy).global_position.z - wo.y
				)
				check(d.length() < 600.0, "%s: %s spawned in its zone" % [id, c.name])
				break
	var total := 0
	for id in wz.spawners:
		total += (wz.spawners[id] as EnemySpawner).spawned
	print("    zones: %d enemies spawned across %d zones" % [total, wz.spawners.size()])
	check(total > 0, "zone spawners spawned enemies")
	root.free()


func test_merged_level() -> void:
	var lv := WorldZones.merged("old_oak")
	check(String(lv.get_meta(&"level_id", "")) != "", "level_id from the start zone")
	check(lv.get_node_or_null("Exits") == null, "no Exits (seamless zones)")
	check(lv.get_node_or_null("Boxes") != null, "an empty Boxes for main's log")
	var st := lv.get_node("PlayerStart") as Node3D
	check(st.position.distance_to(SaveMigration.entrance("old_oak")) < 0.01, "old_oak's start")
	for g in WorldZones.MERGE:
		var want := 0
		var probe := ""
		var probe_at := Vector3.INF
		for id in WorldZones.ZONES:
			var z := WorldZones.zone_of(id)
			var src := z.get_node_or_null(NodePath(g))
			if src:
				want += src.get_child_count()
				var c := src.get_child(0) if src.get_child_count() > 0 else null
				if c is Node3D and probe == "":
					probe = id
					probe_at = z.transform * (src as Node3D).transform * (c as Node3D).position
			z.free()
		var got := lv.get_node_or_null(NodePath(g))
		check((got.get_child_count() if got else 0) == want, "%s: %d markers merged" % [g, want])
		if probe != "" and got:
			var hit := false
			for c in got.get_children():
				if c is Node3D and (c as Node3D).position.distance_to(probe_at) < 0.01:
					hit = true
			check(hit, "%s: %s's first marker at its world position" % [g, probe])
	lv.free()
