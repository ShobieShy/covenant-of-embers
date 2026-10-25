extends SceneTree
## FX review (step 133): summoning circle, Bob's vortex, the crystal, and a letterboxed cinematic frame.
## godot --display-driver wayland --path . -s tools/ritual_shots.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl: Node3D = (load("res://scenes/levels/mage_association.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	await process_frame
	lvl.add_child(RitualFX.summoning_circle(Vector3(0, 0.3, -7.5)))
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 3.5, -1.0), Vector3(0, 0.5, -7.5))
	await _shot(out + "/summoning.png")
	var v := MentorArrival.vortex(Vector3(4, 0, -4))
	lvl.add_child(v)
	lvl.add_child(RitualFX.crystal(Vector3(-4, 1.4, -4)))
	cam.look_at_from_position(Vector3(4, 1.6, 0), Vector3(4, 1.2, -4))
	await _shot(out + "/vortex.png")
	cam.look_at_from_position(Vector3(-4, 1.6, -2.5), Vector3(-4, 1.4, -4))
	await _shot(out + "/crystal.png")
	var c := Cinematic.make(
		"shot",
		[
			{
				"from": Vector3(0, 3.5, -1),
				"look": Vector3(0, 0.5, -7.5),
				"s": 9.0,
				"text": "The circle cracks the marble."
			}
		],
		null
	)
	root.add_child(c)
	await _shot(out + "/letterbox.png")
	quit()


func _shot(path: String) -> void:
	for _f in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
