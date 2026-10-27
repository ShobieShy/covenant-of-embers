extends TestCase
## OW3: the 128 m world cells (tools/build_cells.gd) are fresh, and WorldStreamer loads the
## 5 x 5 ring around a viewer on threads, one cell per frame, with a one-ring unload hysteresis.


func test_cells_fresh() -> void:
	var info: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://world/cells/cells.json")
	)
	check(info is Dictionary, "cells.json present (tools/build_world.sh)")
	if not info is Dictionary:
		return
	var total := 0
	for k in info["cells"]:
		total += int(info["cells"][k]["nodes"])
	var expect := 0
	for id in ["town_square", "old_oak", "midden", "breach"]:
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate()
		for g in ["Boxes", "Props", "Pois"]:
			var n := lvl.get_node_or_null(NodePath(g))
			expect += n.get_child_count() if n else 0
		lvl.free()
	check(
		total == expect,
		"cells hold every static node (%d vs %d): rerun tools/build_cells.gd" % [total, expect]
	)


func test_ring_and_hysteresis() -> void:
	var s := WorldStreamer.new()
	runner_tree.root.add_child(s)
	s.viewer_override = [Vector3(10, 0, 10)]  # town square, cell (0, 0)
	s.flush()
	check(s.loaded.has(Vector2i(0, 0)), "viewer's own cell loaded")
	check(s.loaded.size() <= 25, "at most the 5 x 5 ring (%d)" % s.loaded.size())
	for k in s.loaded:
		check(maxi(absi(k.x), absi(k.y)) <= WorldStreamer.RING, "cell %s inside the ring" % k)
	var n0 := s.loaded.size()
	s.viewer_override = [Vector3(10 + WorldStreamer.CELL, 0, 10)]  # one cell east
	s.flush()
	var west := Vector2i(-WorldStreamer.RING, 0)
	if s.wanted([Vector3(10, 0, 10)], WorldStreamer.RING).has(west):
		check(s.loaded.has(west), "west ring cell kept by the hysteresis ring")
	s.viewer_override = [Vector3(5000, 0, 5000)]  # nothing out there
	s.flush()
	runner_tree.process_frame.emit()
	check(s.loaded.is_empty(), "everything unloads far away (had %d)" % n0)
	s.free()


func test_cell_of() -> void:
	check(WorldStreamer.cell_of(Vector2(0, 0)) == Vector2i(0, 0), "origin")
	check(WorldStreamer.cell_of(Vector2(-0.5, 127.9)) == Vector2i(-1, 0), "floor on negatives")
	check(WorldStreamer.cell_of(Vector2(256, -129)) == Vector2i(2, -2), "multiples")
