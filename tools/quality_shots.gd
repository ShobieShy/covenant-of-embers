extends SceneTree
## FX review (step 134): the Landfill at Low (Steam Deck) / Medium / High, 1280x800.
## godot --display-driver wayland --path . -s tools/quality_shots.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 800)
	for q in [QualityPresets.Level.LOW, QualityPresets.Level.MEDIUM, QualityPresets.Level.HIGH]:
		QualityPresets.level = q
		var lvl: Node3D = (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate()
		root.add_child(lvl)
		await process_frame
		QualityPresets.apply_level(lvl)
		var cam := Camera3D.new()
		lvl.add_child(cam)
		cam.current = true
		cam.look_at_from_position(Vector3(0, 1.6, 12.5), Vector3(0, 1.0, 2.5))
		for _f in 30:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/q%d.png" % [out, q])
		lvl.queue_free()
		await process_frame
	quit()
