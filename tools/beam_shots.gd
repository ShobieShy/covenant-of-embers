extends SceneTree
## FX review (step 130): all six rarity loot beams side by side, plus a 1 m close-up.
## godot --display-driver wayland --path . -s tools/beam_shots.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl: Node3D = (load("res://scenes/levels/breach.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	for i in Rarity.IDS.size():
		var d := LootDrop.new()
		d.rarity_id = Rarity.IDS[i]
		var p := LootPickup.create(d, Vector3(-3.75 + i * 1.5, 0.02, -4.0))
		lvl.add_child(p)
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0, 2.0, 4.0), Vector3(0, 1.2, -4.0))
	await _shot(out + "/beams_all.png")
	cam.look_at_from_position(Vector3(3.75, 1.3, -3.0), Vector3(3.75, 1.0, -4.0))
	await _shot(out + "/beams_close.png")
	quit()


func _shot(path: String) -> void:
	for _f in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
