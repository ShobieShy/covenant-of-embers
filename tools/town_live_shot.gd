extends SceneTree
## Live town_square frames from the Main Gate and the square.
## DISPLAY=:1 godot --display-driver x11 --rendering-driver opengl3 --path . -s res://tools/town_live_shot.gd -- OUT


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/town-live"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	_go.call_deferred(out)


func _go(out: String) -> void:
	var town: Node3D = (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	root.add_child(town)
	for _i in 10:
		await process_frame
	OldOakLandmark.prepare(town)
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	root.add_child(cam)
	var env := town.get_node("WorldEnvironment") as WorldEnvironment
	cam.environment = env.environment
	var tz := town.get_node("Terrain") as TerrainZone
	var eye_y := tz.height_at(0.0, 148.0) + 1.7
	cam.global_position = Vector3(0.0, eye_y, 148.0)
	cam.look_at(Vector3(0.0, eye_y - 2.0, 40.0))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/gate.png")
	var fy := tz.height_at(-16.0, 24.0) + 2.4
	cam.global_position = Vector3(-16.0, fy, 24.0)
	cam.look_at(Vector3(-6.4, 3.2, 9.6))
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(out + "/square.png")
	var oak := town.get_node_or_null("Props/east_oak") as Node3D
	if oak:
		var door := oak.find_child("Door", true, false) as Node3D
		var aim := door.global_position if door else oak.global_position + Vector3(0, 6, 0)
		var fwd := oak.global_transform.basis * Vector3(0, 0, -1)
		cam.global_position = aim + fwd * 18.0 + Vector3(0, 2.0, 0)
		cam.look_at(aim + Vector3(0, 1.2, 0))
		await process_frame
		await process_frame
		root.get_texture().get_image().save_png(out + "/oak.png")
	quit(0)
