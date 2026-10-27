extends SceneTree
## OW1: writes every terrain level's heightfield (TerrainZone.height_image, float32) to
## build/world/<id>.f32, its control map (<id>.ctl, u32) plus <id>.json (origin, grid, spacing, world_offset, footprint)
## for tools/build_world.py. Headless; nothing is added to the tree, nothing is built.

const LEVELS := ["town_square", "old_oak", "midden", "breach", "mage_association"]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/world"))
	for id in LEVELS:
		var lvl := (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
		var wo: Vector2 = lvl.get_meta(&"world_offset", Vector2.ZERO)
		var tz := lvl.get_node_or_null(^"Terrain") as TerrainZone
		var info := {"id": id, "world_offset": [wo.x, wo.y], "terrain": tz != null}
		if tz:
			var img := tz.height_image()
			var f := FileAccess.open("res://build/world/%s.f32" % id, FileAccess.WRITE)
			f.store_buffer(img.get_data())
			f.close()
			var c := FileAccess.open("res://build/world/%s.ctl" % id, FileAccess.WRITE)
			c.store_buffer(tz.control_image().get_data())  # OW2: u32 control words
			c.close()
			var o := tz.origin()
			(
				info
				. merge(
					{
						"origin": [o.x, o.y],
						"grid": [img.get_width(), img.get_height()],
						"spacing": tz.spacing,
						"center": [tz.center.x, tz.center.y],
						"size": [tz.size.x, tz.size.y],
						"rim": tz.rim,
						"layers": Array(tz.layers),
					}
				)
			)
		var j := FileAccess.open("res://build/world/%s.json" % id, FileAccess.WRITE)
		j.store_string(JSON.stringify(info, "  "))
		j.close()
		print("[export_heights] %s: %s" % [id, "terrain" if tz else "no terrain (interior)"])
		lvl.free()
	quit()
