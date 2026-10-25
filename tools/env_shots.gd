extends SceneTree
## FX review (step 132): Landfill / Breach haze + grade, and the town at day / dusk / night.
## godot --display-driver wayland --path . -s tools/env_shots.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	await _level(out, "midden", Vector3(0, 1.6, 12.5), [-1])
	await _level(out, "breach", Vector3(0, 1.6, 74.0), [-1])
	await _level(out, "town_square", Vector3(0, 1.6, 14.0), [0, 1, 2])
	quit()


func _level(out: String, id: String, eye: Vector3, presets: Array) -> void:
	var lvl: Node3D = (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
	root.add_child(lvl)
	await process_frame
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	cam.look_at_from_position(eye, eye + Vector3(0, -0.1, -10))
	for p in presets:
		if p >= 0:
			TimeOfDay.apply(lvl, p)
		await _shot("%s/%s%s.png" % [out, id, "" if p < 0 else "_" + str(TimeOfDay.Preset.keys()[p]).to_lower()])
	lvl.queue_free()
	await process_frame


func _shot(path: String) -> void:
	for _f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
