extends SceneTree
## Act I review shots. Same cameras before and after the burrow dress.
## godot --display-driver x11 --rendering-driver opengl3 --path . -s tools/warrens_shots.gd -- <out_dir>

var out := "user://shots/warrens"
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _env(parent: Node) -> void:
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.04, 0.03, 0.025)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color(0.42, 0.32, 0.22)
	we.environment.ambient_light_energy = 0.22
	we.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment.tonemap_exposure = 1.05
	we.environment.fog_enabled = true
	we.environment.fog_light_color = Color(0.12, 0.07, 0.04)
	we.environment.fog_density = 0.012
	we.environment.ssao_enabled = true
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_color = Color(0.85, 0.62, 0.38)
	sun.light_energy = 0.18
	sun.shadow_enabled = true
	parent.add_child(sun)


func _shot(name: String, from: Vector3, at: Vector3, ortho := false, span := 40.0) -> void:
	if ortho:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = span
		cam.look_at_from_position(from, at)
		cam.rotation_degrees = Vector3(-90, 0, 0)
		cam.position = from
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = 50.0
		cam.look_at_from_position(from, at)
	for _f in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img == null:
		push_error("no image for %s" % name)
		return
	img.save_png("%s/%s.png" % [out, name])
	print("[warrens_shots] ", name, " ", img.get_width(), "x", img.get_height())


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var kit := FloorGen.load_kit()
	var ls := LabyrinthState.fresh(42)
	for n in [1, 2, 3, 4, 5]:
		var f := LabyrinthFloor.build(kit, n, ls)
		f.cull = false
		root.add_child(f)
		_env(f)
		cam = Camera3D.new()
		cam.current = true
		f.add_child(cam)
		for _i in 8:
			await process_frame
		_roofs(f, false)
		var box := _aabb(f)
		var centre := box.get_center()
		var span := maxf(box.size.x, box.size.z) * 1.08
		await _shot("floor%d_top" % n, Vector3(centre.x, centre.y + 80.0, centre.z), centre, true, span)
		_roofs(f, true)
		if n < 5:
			var start := f.get_node("PlayerStart") as Node3D
			var eye := start.global_position + Vector3(5.5, 1.65, 5.2)
			await _shot("floor%d_eye_start" % n, eye, start.global_position + Vector3(-2.0, 1.2, -3.0))
			var down := f.get_node("StairsDown") as Node3D
			await _shot(
				"floor%d_eye_exit" % n,
				down.global_position + Vector3(4.0, 6.2, 4.5),
				down.global_position + Vector3(0, 0.4, 0)
			)
		else:
			var arena := f.rooms[1]
			var c: Vector3 = arena.global_position
			await _shot("floor5_eye_door", c + Vector3(0.4, 2.0, 13.5), c + Vector3(0, 1.6, -6.0))
			await _shot("floor5_eye_side", c + Vector3(12.0, 3.2, 4.0), c + Vector3(0, 1.4, -4.0))
		f.queue_free()
		await process_frame
	quit()


func _roofs(root_n: Node, show: bool) -> void:
	for n in root_n.find_children("CaveRoof", "", true, false):
		n.visible = show


func _aabb(root_n: Node) -> AABB:
	var ab := AABB()
	var first := true
	for mi in root_n.find_children("*", "MeshInstance3D", true, false):
		if not (mi as GeometryInstance3D).visible:
			continue
		var a: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		ab = a if first else ab.merge(a)
		first = false
	return ab if not first else AABB(Vector3(-12, 0, -12), Vector3(24, 4, 24))
