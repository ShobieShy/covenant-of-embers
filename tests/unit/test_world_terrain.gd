extends TestCase
## OW1/OW2: every terrain level carries a world_offset on the 16 m grid, and the saved world
## Terrain3DData (res://world/terrain/, tools/build_world.sh) matches each zone's own
## heightfield inside its footprint (stale region files fail here).

const LEVELS := ["town_square", "old_oak", "midden", "breach"]


func test_world_offsets() -> void:
	for id in LEVELS + ["mage_association"]:
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate()
		check(lvl.has_meta(&"world_offset"), "%s has world_offset" % id)
		var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2(1, 1))
		check(
			fmod(wo.x, 16.0) == 0.0 and fmod(wo.y, 16.0) == 0.0, "%s offset on the 16 m grid" % id
		)
		lvl.free()


func test_world_terrain_matches_zones() -> void:
	if not TerrainZone.available():
		return
	check(FileAccess.file_exists("res://world/terrain/world_terrain.json"), "world terrain saved")
	var t: Node3D = ClassDB.instantiate(&"Terrain3D")
	var cam := Camera3D.new()
	runner_tree.root.add_child(cam)
	t.call(&"set_camera", cam)
	t.set(&"data_directory", "res://world/terrain/")
	runner_tree.root.add_child(t)
	var data: Object = t.get(&"data")
	for id in LEVELS:
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate()
		var tz := lvl.get_node(^"Terrain") as TerrainZone
		var wo: Vector2 = lvl.get_meta(&"world_offset")
		var worst := 0.0
		for p in [Vector2(0.17, -0.21), Vector2(-0.3, 0.3), Vector2(0.31, 0.12)]:
			var l: Vector2 = tz.center + tz.size * p
			var wh: float = data.call(&"get_height", Vector3(l.x + wo.x, 0, l.y + wo.y))
			check(not is_nan(wh), "%s world height defined at %s" % [id, l])
			worst = maxf(worst, absf(wh - tz.height_at(l.x, l.y)))
		print("[world_terrain] %s max height error %.3f m" % [id, worst])
		check(worst < 0.25, "%s world height matches the zone (off by %.2f m)" % [id, worst])
		lvl.free()
	t.free()
	cam.free()


func test_open_world_scene() -> void:
	var w := (load("res://scenes/world/open_world.tscn") as PackedScene).instantiate() as OpenWorld
	runner_tree.root.add_child(w)
	check(w.streamer != null, "open world has a cell streamer")
	check(not w.info.is_empty(), "world_terrain.json read")
	if TerrainZone.available():
		check(w.terrain != null, "world terrain built from saved regions")
		var tz := (
			(load(GameFlow.level_scene("midden")) as PackedScene).instantiate().get_node(^"Terrain")
			as TerrainZone
		)
		var wo := Vector2(576, -240)
		var p := tz.center + Vector2(37, -51)
		check(
			absf(w.height_at(p.x + wo.x, p.y + wo.y) - tz.height_at(p.x, p.y)) < 0.25,
			"open world height matches the Midden"
		)
		tz.get_parent().free()
	w.streamer.viewer_override = [Vector3(10, 0, 10)]
	w.streamer.flush()
	check(w.streamer.loaded.has(Vector2i(0, 0)), "town cell streamed in")
	w.free()
