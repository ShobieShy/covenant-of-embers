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
]


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var i := 0
	for v: Array in VIEWS:
		var lvl: Node3D = (load("res://scenes/levels/%s.tscn" % v[0]) as PackedScene).instantiate()
		root.add_child(lvl)
		var cam := Camera3D.new()
		lvl.add_child(cam)
		cam.look_at_from_position(v[1], v[2])
		cam.current = true
		for _f in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%02d_%s.png" % [out, i, v[0]])
		lvl.queue_free()
		await process_frame
		i += 1
	quit()
