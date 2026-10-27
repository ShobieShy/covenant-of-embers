extends SceneTree
## Loading screen screenshot (dry run: no scene change), one per backdrop region.
## godot --display-driver wayland --path . -s tools/loading_shot.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1600, 900)
	LoadingScreen.dry_run = true
	for v in [["midden", LoadingScreen.Stage.TERRAIN, 0.5], ["old_oak", LoadingScreen.Stage.LEVEL, 0.6]]:
		var s := LoadingScreen.new()
		s.level_id = v[0]
		root.add_child(s)
		await process_frame
		s.advance(v[1], v[2])
		for _f in 20:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/loading_%s.png" % [out, v[0]])
		s.queue_free()
		await process_frame
	quit()
