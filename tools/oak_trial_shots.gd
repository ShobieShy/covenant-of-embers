extends SceneTree
## 0.11.4 review captures of the Town east-lobe oak.
## DISPLAY=:99 godot --display-driver x11 --rendering-driver opengl3 --path . \
##   -s res://tools/oak_trial_shots.gd -- /opt/cursor/artifacts/v0.11.4-oak


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	if out == "":
		push_error("oak_trial_shots: pass an output directory")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run(out)


func _run(out: String) -> void:
	root.size = Vector2i(1280, 720)
	var town := (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate() as Node3D
	town.name = "Town"
	root.add_child(town)
	var oak := OldOakLandmark.prepare(town)
	var tz := town.get_node_or_null(^"Terrain") as TerrainZone
	if tz:
		tz.build_on_ready = true
	await process_frame
	await process_frame
	if tz:
		tz.snap_level()
	var door := oak.find_child("Door", true, false) as Node3D
	var aim := oak.global_position + Vector3(0, 14, 0)
	# Just inside the south Main Gate, looking north-east at the oak.
	await _shot(out, "gate_ne", Vector3(0, 4.2, 148), aim, false, false)
	var facing := Vector3(-0.7071, 0, 0.7071)
	var side := Vector3(0.7071, 0, 0.7071)
	var eye := oak.global_position + facing * 28.0 + side * 28.0 + Vector3(0, 8, 0)
	await _shot(out, "three_quarter_40m", eye, aim, false, false)
	# Beside the ramp, at a standing eye line, so the door and the root are both in frame.
	var close := door.global_position + facing * 8.0 + side * 7.0 + Vector3(0, -1.4, 0)
	await _shot(out, "door_ramp", close, door.global_position + Vector3(0, 0.4, 0), false, false)
	root.size = Vector2i(1280, 800)
	await _shot(out, "steam_deck_low", eye, aim, false, true)
	root.size = Vector2i(1280, 720)
	await _shot(out, "night", Vector3(0, 4.2, 148), aim, true, false)
	print("[oak_trial] wrote ", out)
	quit(0)


func _shot(out: String, label: String, eye: Vector3, at: Vector3, night: bool, low: bool) -> void:
	var town := root.get_node(^"Town") as Node3D
	if low:
		QualityPresets.level = QualityPresets.Level.LOW
		QualityPresets.apply_level(town)
		QualityPresets.apply_engine()
	else:
		QualityPresets.level = QualityPresets.Level.HIGH
		QualityPresets.apply_level(town)
	if night:
		NightPreset.apply(town, at)
	else:
		var sun := town.get_node_or_null(^"Sun") as DirectionalLight3D
		if sun and not low:
			sun.light_energy = 1.0
	var cam := town.get_node_or_null(^"ReviewCam") as Camera3D
	if cam == null:
		cam = Camera3D.new()
		cam.name = "ReviewCam"
		town.add_child(cam)
	cam.fov = 50.0
	cam.current = true
	cam.look_at_from_position(eye, at)
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, label])
	print("[oak_trial] ", label)
