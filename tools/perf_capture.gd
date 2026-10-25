extends SceneTree
## Perf capture (step 134): each quality preset x {midden, breach, town_square} at 1280x800
## (Steam Deck resolution), vsync off, with a stress load of FX (8 burning/frozen/dark enemies,
## a summoning circle, repeated spell bursts). Writes <out>/perf.json and prints a table.
## godot --display-driver wayland --path . -s tools/perf_capture.gd -- <out_dir>

const FRAMES := 300
const WARMUP := 60


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://perf"
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	var results := []
	for q in [QualityPresets.Level.LOW, QualityPresets.Level.MEDIUM, QualityPresets.Level.HIGH]:
		QualityPresets.level = q
		QualityPresets.apply_engine()
		Engine.max_fps = 0  # measure headroom, not the 60 cap
		for id in ["midden", "breach", "town_square"]:
			results.append(await _run(id, q))
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
	quit()


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
			fx.impact(at + Vector3(randf_range(-3, 3), 1.0, -7), Vector3.BACK, fr / 6 % 6 as ElementTable.Element)
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
