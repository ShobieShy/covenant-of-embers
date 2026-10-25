extends SceneTree
## Art review: each enemy model rendered alone in the Town Square, one PNG per enemy.
## godot --display-driver wayland --path . -s tools/enemy_shots.gd -- <out_dir>

const IDS := ["gnawer", "ooze", "heap", "breach_warden", "the_filth", "scorchling"]
const HEIGHTS := [0.6, 1.0, 2.2, 2.6, 3.5, 0.8]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1280, 720)
	var lvl := Node3D.new()  # neutral stage: sky-ish env, sun, grey floor
	root.add_child(lvl)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.45, 0.55, 0.7)
	we.environment.ambient_light_color = Color(0.6, 0.65, 0.75)
	we.environment.ambient_light_energy = 0.6
	we.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	lvl.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	lvl.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mi.mesh = pm
	lvl.add_child(floor_mi)
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	for i in IDS.size():
		var id: String = IDS[i]
		var m := EnemyModels.make(id, HEIGHTS[i])
		if m == null:
			push_error("no model " + id)
			continue
		lvl.add_child(m)
		m.position = Vector3(-8, 0, 6)
		for _f in 20:
			await process_frame
		var bb := AABB()
		var first := true
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			var a := mi.global_transform * mi.get_aabb()
			bb = a if first else bb.merge(a)
			first = false
		print("[enemy_shots] ", id, " size=", bb.size, " anim=", m.anim.current_animation if m.anim else "none")
		var h: float = HEIGHTS[i]
		cam.look_at_from_position(m.position + Vector3(h * 0.9, h * 0.8, h * 2.2), m.position + Vector3(0, h * 0.5, 0))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/enemy_%s.png" % [out, id])
		m.queue_free()
	quit()
