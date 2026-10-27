extends SceneTree
## Step 154 (W3): bakes every open-zone level's navmesh tiles offline into
## scenes/levels/nav/<level_id>/ (LevelNavigation.save_cache). Run after editing a level
## with [terrain]; tests/unit/test_nav_tiles.gd fails while a cache is stale.
## godot --headless --path . -s tools/bake_nav.gd

const LEVELS := ["mage_association", "town_square", "old_oak", "midden", "breach"]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame  # the root must be inside the tree before parsing geometry
	var bad := 0
	for id in LEVELS:
		var ps := load("res://scenes/levels/%s.tscn" % id) as PackedScene
		var lvl := ps.instantiate()
		if lvl.get_node_or_null(^"Terrain") == null:
			print("[bake_nav] %s: no [terrain], skipped" % id)
			lvl.free()
			continue
		root.add_child(lvl)
		await process_frame
		var nav := lvl.get_node(^"Navigation") as LevelNavigation
		if nav.from_cache:
			print("[bake_nav] %s: cache fresh (%d tiles)" % [id, nav.tiles.size()])
		else:
			var err := nav.save_cache()
			print(
				(
					"[bake_nav] %s: %d tiles, %d polygons: %s"
					% [id, nav.tiles.size(), nav.polygon_count(), error_string(err)]
				)
			)
			bad += int(err != OK)
		lvl.free()
	quit(1 if bad else 0)
