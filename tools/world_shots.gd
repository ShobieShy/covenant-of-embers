extends SceneTree
## OW3 review: the open world from above the transition strips between zones.
## godot --display-driver wayland --path . -s tools/world_shots.gd -- <out_dir>

const VIEWS := [
	["town_to_midden", Vector3(300, 120, 260), Vector3(420, 0, -100)],
	["midden_to_breach", Vector3(1000, 90, 220), Vector3(980, 0, -60)],
	["oak_to_town", Vector3(-150, 70, 180), Vector3(-150, 0, 0)],
]


func _initialize() -> void:
	var out: String = (
		OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	)
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var cam := Camera3D.new()
	cam.far = 3000.0
	root.add_child(cam)
	cam.current = true
	var w := (load("res://scenes/world/open_world.tscn") as PackedScene).instantiate() as OpenWorld
	root.add_child(w)
	await process_frame
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_SKY
	env.environment.sky = Sky.new()
	env.environment.sky.sky_material = ProceduralSkyMaterial.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	root.add_child(env)
	for v in VIEWS:
		cam.look_at_from_position(v[1], v[2])
		w.streamer.viewer_override = [Vector3(v[2].x, 0, v[2].z)]
		w.streamer.flush()
		await _shot("%s/%s.png" % [out, v[0]])
	quit()


func _shot(path: String) -> void:
	for _f in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("[world_shots] ", path)
