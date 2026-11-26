extends SceneTree
## Act IV shots. Framing is a fraction of the floor bounds so a before strip and the
## rebuilt ruins share the same angles: top-down, from the entrance, from the side,
## and a three-quarter. Pass an output directory.
##
##   xvfb-run -a godot --display-driver x11 --rendering-driver opengl3 --path . \
##     -s res://tools/sunken_capture.gd -- /opt/cursor/artifacts/sunken/after


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/opt/cursor/artifacts/sunken"
	DirAccess.make_dir_recursive_absolute(out)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1152, 864)
	_run.call_deferred(out)


func _run(out: String) -> void:
	root.size = Vector2i(1152, 864)
	await _frames(1)
	var state := LabyrinthState.fresh(4)
	var hall := SunkenFloor.make(14, state)
	root.add_child(hall)
	await _frames(3)
	_tame(hall)
	var box := _bounds(hall)
	await _shot(out, "gallery_top", _ortho(box), false)
	await _shot(out, "gallery_entrance", _eye(box, Vector3(0, 0.08, 0.62), Vector3(0, 0.02, 0.05)), true)
	await _shot(out, "gallery_side", _eye(box, Vector3(-0.62, 0.1, 0.05), Vector3(0, 0.02, 0)), true)
	await _shot(out, "gallery_quarter", _eye(box, Vector3(0.48, 0.22, 0.48), Vector3(0, 0.04, 0)), true)
	# Player height, along the painted approach and across the spire.
	await _shot(out, "approach", _persp(Vector3(-8, 3.3, 62), Vector3(-16, 4.0, 0)), true)
	await _shot(out, "bells", _persp(Vector3(-62, 3.4, 12), Vector3(-18, 6.0, -4)), true)
	hall.free()
	var nave := SunkenFloor.make(18, state)
	root.add_child(nave)
	await _frames(3)
	_tame(nave)
	var nave_box := _bounds(nave)
	await _shot(out, "nave_entrance", _eye(nave_box, Vector3(0.15, 0.06, 0.42), Vector3(0.2, 0.03, -0.05)), true)
	await _shot(out, "nave_quarter", _eye(nave_box, Vector3(0.55, 0.2, 0.35), Vector3(0.15, 0.04, -0.1)), true)
	await _shot(out, "nave_pew", _persp(Vector3(46, 2.8, -38), Vector3(58, 2.2, -62)), true)
	nave.free()
	print("[sunken_capture] wrote ", out)
	quit(0)


func _tame(floor: Node) -> void:
	var sun := floor.get_node_or_null("DayGlow") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = false
	var world := floor.get_node_or_null("Atmosphere") as WorldEnvironment
	if world and world.environment:
		world.environment.fog_density = 0.0016


func _bounds(floor: Node3D) -> AABB:
	if floor.has_meta(&"painted_span"):
		var span: Vector2 = floor.get_meta(&"painted_span")
		return AABB(Vector3(-span.x * 0.5, 0, -span.y * 0.5), Vector3(span.x, 12, span.y))
	var box := AABB()
	var first := true
	for n in floor.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	for n in floor.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := n as MultiMeshInstance3D
		if mm.multimesh == null or mm.multimesh.mesh == null:
			continue
		var a := mm.global_transform * mm.multimesh.mesh.get_aabb()
		# Instance transforms sit in the multimesh; grow by a generous margin.
		var grow := maxf(a.size.x, a.size.z) * 12.0
		a = a.grow(grow)
		box = a if first else box.merge(a)
		first = false
	if first:
		box = AABB(Vector3(-8, 0, -20), Vector3(16, 4, 40))
	return box


func _ortho(box: AABB) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var centre := box.get_center()
	cam.size = box.size.z
	cam.position = Vector3(centre.x, centre.y + maxf(80.0, box.size.z), centre.z)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	return cam


func _eye(box: AABB, from_frac: Vector3, look_frac: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 48.0
	var centre := box.get_center()
	var half := box.size * 0.5
	var eye := centre + Vector3(from_frac.x * box.size.x, 1.7 + from_frac.y * box.size.y, from_frac.z * box.size.z)
	# Keep the eye outside the volume.
	eye.x = clampf(eye.x, box.position.x - half.x, box.end.x + half.x)
	eye.z = clampf(eye.z, box.position.z - half.z, box.end.z + half.z)
	var look := centre + Vector3(look_frac.x * half.x, look_frac.y * box.size.y, look_frac.z * half.z)
	look.y = box.position.y + 2.2
	cam.look_at_from_position(eye, look)
	return cam


func _env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.07, 0.09)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.62, 0.66)
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.05
	return e


func _persp(eye: Vector3, at: Vector3) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.look_at_from_position(eye, at)
	return cam


func _shot(out: String, label: String, cam: Camera3D, fill: bool) -> void:
	var sun: DirectionalLight3D = null
	if fill and root.get_node_or_null("DayGlow") == null and _needs_fill():
		sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-42, 28, 0)
		sun.light_energy = 1.1
		sun.light_color = Color(0.75, 0.86, 0.92)
		sun.shadow_enabled = false
		root.add_child(sun)
		cam.environment = _env()
	root.add_child(cam)
	cam.current = true
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, label])
	print("[sunken_capture] ", label, " ", img.get_width(), "x", img.get_height())
	cam.free()
	if sun:
		sun.free()


func _needs_fill() -> bool:
	return root.get_node_or_null("Atmosphere") == null and root.find_child("Atmosphere", true, false) == null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
