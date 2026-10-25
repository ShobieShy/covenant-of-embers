extends SceneTree
## Art review: render fixed camera views of the dressed levels to PNGs.
## godot --display-driver wayland --path . -s tools/level_shots.gd -- <out_dir>

const VIEWS := [
	["town_square", Vector3(0, 1.7, 15), Vector3(0, 2, -10)],
	["town_square", Vector3(12, 9, 14), Vector3(-6, 0, -6)],
	["town_square", Vector3(-4, 1.7, 2), Vector3(-14, 2, 8)],
	["town_square", Vector3(10, 1.7, 8), Vector3(26, 6, 14)],
	["town_square", Vector3(0, 1.7, -12), Vector3(0, 3, -20)],
	["mage_association", Vector3(0, 1.7, 12), Vector3(0, 1.5, -10)],
	["mage_association", Vector3(7, 4, -12), Vector3(-6, 1, 6)],
	["old_oak", Vector3(0, 1.7, 6), Vector3(0, 2, -6)],
	["old_oak", Vector3(-5, 2.5, 5), Vector3(4, 4, -4)],
	["old_oak", Vector3(0, 1.7, 6), Vector3(0, 2, -6), "night"],
	["town_square", Vector3(0, 1.7, 15), Vector3(0, 2, -10), "night"],
	["midden", Vector3(0, 1.7, 12.5), Vector3(0, 1, -6)],
	["midden", Vector3(-10, 5, 10), Vector3(6, 0, -6)],
	["mage_association", Vector3(-3, 1.7, 8), Vector3(-8, 0.8, 2)],
	["breach", Vector3(0, 1.7, 0), Vector3(0, 6, -20)],
	["breach", Vector3(-8, 4, 10), Vector3(4, 0, -6)],
	["breach", Vector3(0, 1.7, 72), Vector3(0, 1, 50)],
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var i := 0
	for v: Array in VIEWS:
		var lvl: Node3D = (load("res://scenes/levels/%s.tscn" % v[0]) as PackedScene).instantiate()
		root.add_child(lvl)
		if v.size() > 3 and v[3] == "night":
			NightPreset.apply(lvl, v[1] - Vector3(0, 1.4, 2))
		var cam := Camera3D.new()
		lvl.add_child(cam)
		cam.look_at_from_position(v[1], v[2])
		cam.current = true
		for _f in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%02d_%s%s.png" % [out, i, v[0], "_night" if v.size() > 3 else ""])
		lvl.queue_free()
		await process_frame
		i += 1
	quit()
