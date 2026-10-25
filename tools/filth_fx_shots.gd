extends SceneTree
## FX review (step 131): The Filth with acid blobs + a pool, a phase shockwave, then the
## exposed core. godot --display-driver wayland --path . -s tools/filth_fx_shots.gd -- <out_dir>


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl: Node3D = (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate()
	root.add_child(lvl)
	await process_frame
	var f := Enemy.create(EnemyTable.load_default().find("the_filth")) as Filth
	f.set_physics_process(false)
	lvl.add_child(f)
	f.global_position = Vector3(0, 0, -6)
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(-1.5, 4.0, -0.5), Vector3(0, 1.0, -6.0))
	for i in 3:
		var b := Filth.Blob.new()
		b.pos = Vector3(0.6 * i, 1.6 + 0.2 * i, -4.5 + 1.3 * i)
		f.blobs.append(b)
	f.fx.acid_pool(Vector3(1.2, 0, -2.5))
	await _shot(out + "/filth_acid.png", 20)
	f.blobs.clear()
	f.apply_damage(f.max_health() * 0.4, ElementTable.Element.FIRE)
	await _shot(out + "/filth_shockwave.png", 14)
	f.apply_damage(f.max_health() * 0.3, ElementTable.Element.FIRE)
	await _shot(out + "/filth_core.png", 60)
	quit()


func _shot(path: String, frames: int) -> void:
	for _f in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
