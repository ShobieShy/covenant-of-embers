extends SceneTree
## L5: Labyrinth floor perf census, headless (no GPU: Ember QA may be on the display).
## For floors 1-5 (Act I, dressed with the Warrens kit when present): build time, node /
## mesh / light / shadow-light / collision counts, goblins, then 300 fixed frames with the
## floor's goblins awake and reports the mean and worst process + physics frame time.
## godot --headless --path . -s tools/lab_perf.gd -- [out.json]

const FRAMES := 300


func _initialize() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	Engine.max_fps = 0
	var kit := FloorGen.load_kit()
	var st := LabyrinthState.fresh(1234)
	var rows := []
	for n in range(1, 6):
		var t0 := Time.get_ticks_usec()
		var fl := LabyrinthFloor.build(kit, n, st)
		var holder := Node3D.new()
		holder.position = Vector3(0, 900, -4200)
		root.add_child(holder)
		holder.add_child(fl)
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var sp := EnemySpawner.new()
		holder.add_child(sp)
		var es := sp.setup(fl, null)
		await process_frame
		var start := fl.get_node_or_null(^"PlayerStart") as Node3D
		if start and not fl.layout.is_empty():
			fl.cull_to(start.global_position)
		var c := _census(fl)
		var times := PackedFloat64Array()
		var last := Time.get_ticks_usec()
		for i in FRAMES:
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
		var avg := 0.0
		var worst := 0.0
		for t in times:
			avg += t
			worst = maxf(worst, t)
		avg /= times.size()
		c.merge(
			{
				"floor": n,
				"build_ms": snappedf(build_ms, 0.1),
				"goblins": es.size(),
				"frame_ms": snappedf(avg, 0.01),
				"worst_ms": snappedf(worst, 0.01)
			}
		)
		rows.append(c)
		print("[labperf] ", JSON.stringify(c))
		holder.queue_free()
		await process_frame
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(rows, "  "))
	quit()


func _census(fl: Node) -> Dictionary:
	var c := {"nodes": 0, "meshes": 0, "lights": 0, "shadow_lights": 0, "shapes": 0, "rooms": 0}
	var stack: Array[Node] = [fl]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		c.nodes += 1
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			c.meshes += 1
		if n is Light3D and (n as Light3D).is_visible_in_tree():
			c.lights += 1
			if (n as Light3D).shadow_enabled:
				c.shadow_lights += 1
		if n is CollisionShape3D:
			c.shapes += 1
		stack.append_array(n.get_children())
	c.rooms = (fl as LabyrinthFloor).rooms.size()
	return c
