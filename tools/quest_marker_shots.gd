extends SceneTree
## Offscreen shots of the live quest marker in three acts.
## godot --display-driver x11 --path . -s tools/quest_marker_shots.gd -- <out_dir>


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/opt/cursor/artifacts"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	await _shot(out, "act0_town_gate", "town_square", _beat("welcome", ["permit_given"]), {})
	await _shot(
		out,
		"act0_landfill",
		"midden",
		_filth(),
		{
			"active": {"the_landfill": {"step": 1, "have": 0, "opt": {}}},
			"done": ["a_new_home"],
			"tracked": "the_landfill"
		},
	)
	await _shot(
		out,
		"act0_breach_warden",
		"breach",
		_breach(),
		{
			"active": {"the_breach": {"step": 1, "have": 0, "opt": {}}},
			"done": ["a_new_home", "the_landfill", "report_to_bob"],
			"tracked": "the_breach",
		},
	)
	quit()


func _beat(id: String, extra: Array) -> Dictionary:
	var f := StoryFlags.new()
	IntroDirector.start(f)
	if id != "summoning":
		IntroDirector.reach(f, id)
	for e in extra:
		f.set_flag(String(e))
	return f.to_dict()


func _filth() -> Dictionary:
	var d := _beat("filth", ["permit_given", "starter_gear_given", "landfill_route_open", "bob_met"])
	return d


func _breach() -> Dictionary:
	var f := StoryFlags.new()
	IntroDirector.start(f)
	IntroDirector.finish(f)
	f.set_flag("filth_defeated")
	f.set_flag("starter_gear_given")
	f.set_flag("permit_given")
	return f.to_dict()


func _shot(out: String, name: String, level: String, flags: Dictionary, quests: Dictionary) -> void:
	GameFlow.dry_run = true
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	GameFlow.level_id = level
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.story_flags.from_dict(flags)
	if not quests.is_empty():
		g._loaded_quests = quests
	root.add_child(g)
	for _i in 8:
		await process_frame
	var at: Variant = _spot(g)
	if at is Vector3:
		var pos := at as Vector3
		var cam := Camera3D.new()
		g.add_child(cam)
		var eye := pos + Vector3(8, 4, 10)
		cam.look_at_from_position(eye, pos + Vector3(0, 1.2, 0))
		cam.current = true
		var ball := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.45
		mesh.height = 0.9
		ball.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1, 0.85, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ball.material_override = mat
		g.add_child(ball)
		ball.global_position = pos + Vector3(0, 0.6, 0)
	for _i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("[marker-shot] %s at %s" % [name, at])
	g.free()
	await process_frame


func _spot(g: Node) -> Variant:
	var intro: IntroDirector = g.get("intro")
	if intro and intro.target_point() != null:
		return intro.target_point()
	var marker := g.get_node_or_null("QuestMarker")
	if marker and marker.has_method("_process"):
		marker._process(0.0)
	if marker and marker.has_method("_cached"):
		return marker.call("_cached")
	return null
