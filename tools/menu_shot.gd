extends SceneTree
## Art review: the main menu with the UI theme. godot --display-driver wayland --path . -s tools/menu_shot.gd -- <png>


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://menu.png"
	root.size = Vector2i(1600, 900)
	root.add_child((load("res://scenes/menu.tscn") as PackedScene).instantiate())
	for _f in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out)
	root.theme = null
	Input.set_custom_mouse_cursor(null)
	quit()
