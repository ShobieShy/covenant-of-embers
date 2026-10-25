extends SceneTree
## Art review (step 122): line up StaffKit builds (bare, basic, mixed, high rarity, wand) and render a PNG.
## godot --display-driver wayland --path . -s tools/staff_shots.gd -- <out_dir>

const BUILDS := [
	["apprentice_fire_staff", []],
	["apprentice_fire_staff", ["basic_handle", "basic_exterior", "basic_interior", "basic_fire_head"]],
	[
		"apprentice_fire_staff",
		["rare_air_handle", "uncommon_air_exterior", "basic_earth_interior", "rare_water_head", "rare_light_charm"]
	],
	[
		"apprentice_fire_staff",
		[
			"uncommon_dark_handle",
			"mythic_water_exterior",
			"basic_fire_interior",
			"primordial_fire_head",
			"unique_void_charm"
		]
	],
	["swift_wind_wand", ["uncommon_fire_head", "uncommon_earth_charm"]],
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.12, 0.1, 0.09)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.environment.glow_enabled = true
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	stage.add_child(sun)
	var x := -0.8
	for b: Array in BUILDS:
		var w := WieldableInstance.load_base(String(b[0]))
		for id: String in b[1]:
			w.parts.append(load("res://resources/parts/%s.tres" % id) as WieldablePart)
		w.assembled = not (b[1] as Array).is_empty()
		var vm := Viewmodel.new()
		stage.add_child(vm)
		vm.show_wieldable(w)
		for mi in vm.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).layers = 1
		vm.position = Vector3(x, 0, 0)
		vm.rotation_degrees = Vector3(90, 0, 15)
		print("[staff_shots] ", w.display_name(), " tris=", StaffKit.tris(vm))
		x += 0.4
	var cam := Camera3D.new()
	stage.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.1, 1.3), Vector3(0, 0, 0))
	cam.current = true
	for _f in 10:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/staffs.png" % out)
	quit()
