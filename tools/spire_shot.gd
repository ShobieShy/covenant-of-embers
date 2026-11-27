extends SceneTree
## Before/after shots of Act V. Cameras are fixed in world space so the two
## passes line up. Pass the output directory as the first user arg.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/spire-shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	_run.call_deferred(out)


func _run(out: String) -> void:
	var state := LabyrinthState.fresh(3)
	for n in [19, 23]:
		var floor := SpireFloor.make(n, state)
		floor.name = "Spire"
		root.add_child(floor)
		await process_frame
		await process_frame
		var hidden: Array[Node] = []
		for id in ["FalseSky", "VoidWall", "SkyRing"]:
			var node := floor.get_node_or_null(id)
			if node:
				hidden.append(node)
		await _shot(out, "f%d_side" % n, _side(floor))
		for node in hidden:
			node.visible = false
		await _shot(out, "f%d_top" % n, _top(floor))
		for node in hidden:
			node.visible = true
		await _shot(out, "f%d_eye" % n, _eye(floor))
		await _shot(out, "f%d_close" % n, _close(floor))
		floor.free()
	print("[spire_shot] wrote ", out)
	quit(0)


func _side(floor: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 72.0
	cam.environment = _env(floor)
	cam.look_at_from_position(Vector3(0, 24, 96), Vector3(0, 24, 0))
	return cam


func _top(floor: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 100.0
	var env := _env(floor)
	if env:
		env = env.duplicate() as Environment
		env.fog_enabled = false
	cam.environment = env
	cam.look_at_from_position(Vector3(0, 140, 0.01), Vector3(0, 0, 0), Vector3(0, 0, -1))
	return cam


func _eye(floor: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.environment = _env(floor)
	cam.look_at_from_position(Vector3(-6, 30.4, -26), Vector3(0, 20, -8))
	return cam


func _close(floor: Node) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.environment = _env(floor)
	cam.look_at_from_position(Vector3(7, 10.5, -12), Vector3(0, 4, 2))
	return cam


func _env(floor: Node) -> Environment:
	var world := floor.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world and world.environment:
		return world.environment
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.04, 0.08)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.32, 0.45)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.05
	return e


func _shot(out: String, label: String, cam: Camera3D) -> void:
	root.add_child(cam)
	cam.current = true
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, label])
	print("[spire_shot] ", label, " ", img.get_width(), "x", img.get_height())
	cam.free()
