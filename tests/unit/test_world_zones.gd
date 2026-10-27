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
