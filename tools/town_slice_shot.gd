extends SceneTree
## Gate and fountain frames of the 0.12.0 slice. Not a score submission.
##
##   DISPLAY=:99 godot --display-driver x11 --rendering-driver opengl3 --path . \
##     -s res://tools/town_slice_shot.gd -- /opt/cursor/artifacts/v0.12.0-town


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/town-slice"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	_go.call_deferred(out)


func _go(out: String) -> void:
	var slice: Node3D = (load("res://scenes/levels/town_golden_slice.tscn") as PackedScene).instantiate()
	root.add_child(slice)
	for _i in 12:
		await process_frame
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	root.add_child(cam)
	var env := (slice.get_node("WorldEnvironment") as WorldEnvironment).environment
	cam.environment = env
	cam.global_position = Vector3(-6.4, 4.2, 104.0)
	cam.look_at(Vector3(-6.4, 3.0, 9.6))
	await process_frame
	await process_frame
	_save(out + "/gate.png")
	cam.global_position = Vector3(-6.4, 3.4, 28.0)
	cam.look_at(Vector3(-6.4, 2.4, 9.6))
	await process_frame
	await process_frame
	_save(out + "/fountain.png")
	quit(0)


func _save(path: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png(path)
