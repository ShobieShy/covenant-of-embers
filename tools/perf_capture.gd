extends SceneTree
## Perf capture (step 134): each quality preset x {midden, breach, town_square} at 1280x800
## (Steam Deck resolution), vsync off, with a stress load of FX (8 burning/frozen/dark enemies,
## a summoning circle, repeated spell bursts). Writes <out>/perf.json and prints a table.
## godot --display-driver wayland --path . -s tools/perf_capture.gd -- <out_dir>
## Step 153: `-- <out_dir> --flythrough` instead flies a camera (12 m/s, 8 m up) through
## every POI of each open-zone level (one with a Pois/ZoneStreamer), Low and High, so the
## streaming, visibility ranges and terrain LOD are measured while moving.
## OW11: `-- <out_dir> --world [--res 2560x1440]` walks a camera (at run speed, 1.7 m over the
## terrain) through the open world Town -> Landfill -> Breach at each preset, and reports the
## worst frame (streaming hitch), static RAM and video memory against OPEN_WORLD_PLAN section 10.

const FLY_SPEED := 12.0
const FLY_LEVELS := ["midden", "old_oak", "town_square", "breach", "mage_association"]

## Town square -> Landfill funnel -> Landfill pit -> Landfill/Breach strip -> Breach (world XZ).
const WORLD_ROUTE := [
	Vector2(0, 0),
	Vector2(300, -60),
	Vector2(576, -200),
	Vector2(576, 0),
	Vector2(840, 40),
	Vector2(1104, 0),
]
const WALK_SPEED := 7.0

const FRAMES := 300
const WARMUP := 60


func _initialize() -> void:
	var out: String = (
		OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://perf"
	)
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	var results := []
	var args := OS.get_cmdline_user_args()
	var ri := args.find("--res")
	if ri >= 0 and ri + 1 < args.size():
		var wh := args[ri + 1].split("x")
		DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
		root.size = Vector2i(int(wh[0]), int(wh[1]))
	if "--world" in args:
		for q in [QualityPresets.Level.LOW, QualityPresets.Level.MEDIUM, QualityPresets.Level.HIGH]:
			QualityPresets.level = q
			QualityPresets.apply_engine()
			Engine.max_fps = 0
			results.append(await _walk_world(q))
		_write(out, results)
		quit()
		return
	if "--flythrough" in OS.get_cmdline_user_args():
		for q in [QualityPresets.Level.LOW, QualityPresets.Level.HIGH]:
			QualityPresets.level = q
			QualityPresets.apply_engine()
			Engine.max_fps = 0
			for id in FLY_LEVELS:
				var r := await _fly(id, q)
				if not r.is_empty():
					results.append(r)
		_write(out, results)
		quit()
		return
	for q in [QualityPresets.Level.LOW, QualityPresets.Level.MEDIUM, QualityPresets.Level.HIGH]:
		QualityPresets.level = q
		QualityPresets.apply_engine()
		Engine.max_fps = 0  # measure headroom, not the 60 cap
		for id in ["midden", "breach", "town_square"]:
			results.append(await _run(id, q))
	_write(out, results)
	quit()


func _write(out: String, results: Array) -> void:
	var f := FileAccess.open(out + "/perf.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	print("[perf] gpu=%s" % RenderingServer.get_video_adapter_name())
	for r in results:
		print(
			(
				"[perf] %-6s %-12s avg %.2f ms (%.0f fps)  1%% low %.0f fps"
				% [r.preset, r.level, r.avg_ms, r.fps, r.low1_fps]
			)
		)


func _fly(id: String, q: int) -> Dictionary:
	var lvl: Node3D = (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
	var pois := lvl.get_node_or_null(^"Pois")
	if pois == null or pois.get_child_count() < 2:
		lvl.free()
		return {}
	var route: Array[Vector3] = []
	for p in pois.get_children():
		route.append((p.get_meta(&"center", Vector3.ZERO) as Vector3) + Vector3(0, 8, 0))
	var cam := Camera3D.new()
	cam.add_to_group(&"stream_viewers")
	lvl.add_child(cam)
	cam.position = route[0]
	root.add_child(lvl)
	cam.current = true
	QualityPresets.apply_level(lvl)
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in range(1, route.size()):
		while cam.position.distance_to(route[i]) > 1.0:
			var dir := cam.position.direction_to(route[i])
			cam.position += dir * FLY_SPEED / 60.0
			cam.look_at(cam.position + Vector3(dir.x, -0.2, dir.z + 0.001))
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
	lvl.queue_free()
	await process_frame
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= maxf(1.0, times.size())
	return {
		"preset": QualityPresets.NAMES[q].split(" ")[0],
		"level": id + " fly",
		"avg_ms": avg,
		"fps": 1000.0 / avg,
		"low1_fps": 1000.0 / sorted[int(sorted.size() * 0.99)],
	}


func _walk_world(q: int) -> Dictionary:
	var w := (load("res://scenes/world/open_world.tscn") as PackedScene).instantiate() as OpenWorld
	var cam := Camera3D.new()
	cam.far = 1500.0
	cam.add_to_group(&"stream_viewers")
	root.add_child(w)
	await process_frame  # OpenWorld builds its streamer a frame after entering the tree
	w.add_child(cam)
	cam.current = true
	QualityPresets.apply_level(w)
	var p := Vector3(WORLD_ROUTE[0].x, 0, WORLD_ROUTE[0].y)
	w.streamer.viewer_override = [p]
	w.streamer.flush()
	for _f in WARMUP:
		await process_frame
	w.streamer.viewer_override = []
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	var peak_ram := 0
	var peak_vram := 0
	for i in range(1, WORLD_ROUTE.size()):
		var to := Vector3(WORLD_ROUTE[i].x, 0, WORLD_ROUTE[i].y)
		while Vector2(p.x, p.z).distance_to(Vector2(to.x, to.z)) > 1.0:
			var dir := Vector3(to.x - p.x, 0, to.z - p.z).normalized()
			p += dir * WALK_SPEED / 60.0
			var h := w.height_at(p.x, p.z)
			cam.position = Vector3(p.x, (0.0 if is_nan(h) else h) + 1.7, p.z)
			cam.look_at(cam.position + dir + Vector3(0, -0.15, 0))
			await process_frame
			var now := Time.get_ticks_usec()
			times.append((now - last) / 1000.0)
			last = now
			peak_ram = maxi(peak_ram, OS.get_static_memory_usage())
			peak_vram = maxi(
				peak_vram, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
			)
	w.queue_free()
	await process_frame
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= maxf(1.0, times.size())
	return {
		"preset": QualityPresets.NAMES[q].split(" ")[0],
		"level": "world walk",
		"res": "%dx%d" % [root.size.x, root.size.y],
		"frames": times.size(),
		"avg_ms": avg,
		"fps": 1000.0 / avg,
		"low1_fps": 1000.0 / sorted[int(sorted.size() * 0.99)],
		"worst_ms": sorted[sorted.size() - 1],
		"over_33ms": sorted.size() - sorted.bsearch(33.3),
		"ram_mb": peak_ram / 1048576.0,
		"vram_mb": peak_vram / 1048576.0,
	}


func _run(id: String, q: int) -> Dictionary:
	var lvl: Node3D = (load("res://scenes/levels/%s.tscn" % id) as PackedScene).instantiate()
	root.add_child(lvl)
	await process_frame
	QualityPresets.apply_level(lvl)
	var spawn := lvl.get_node_or_null(^"PlayerStart") as Node3D
	var at := spawn.global_position if spawn else Vector3.ZERO
	var cam := Camera3D.new()
	lvl.add_child(cam)
	cam.current = true
	cam.look_at_from_position(at + Vector3(0, 1.6, 0), at + Vector3(0, 1.0, -10))
	lvl.add_child(RitualFX.summoning_circle(at + Vector3(0, 0.05, -8)))
	var table := EnemyTable.load_default()
	var enemies: Array[Enemy] = []
	for i in 8:
		var e := Enemy.new()
		e.setup(table.find("gnawer"))
		lvl.add_child(e)
		e.global_position = at + Vector3(-3.5 + i, 0, -6 - (i % 3))
		e.burn_left = 99.0 if i % 2 == 0 else 0.0
		e.slow_left = 99.0 if i % 2 == 1 else 0.0
		e.corrupted_left = 99.0 if i % 3 == 0 else 0.0
		enemies.append(e)
	var fx := SpellFX.new()
	lvl.add_child(fx)
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for fr in FRAMES + WARMUP:
		for e in enemies:
			e.tick(1.0 / 60.0)
		if fr % 6 == 0:
			fx.impact(
				at + Vector3(randf_range(-3, 3), 1.0, -7),
				Vector3.BACK,
				fr / 6 % 6 as ElementTable.Element
			)
		await process_frame
		var now := Time.get_ticks_usec()
		if fr >= WARMUP:
			times.append((now - last) / 1000.0)
		last = now
	lvl.queue_free()
	await process_frame
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	var p99: float = sorted[int(sorted.size() * 0.99)]
	return {
		"preset": QualityPresets.NAMES[q].split(" ")[0],
		"level": id,
		"avg_ms": avg,
		"fps": 1000.0 / avg,
		"low1_fps": 1000.0 / p99,
	}
