extends TestCase
## OW6: waystones live in the open world (world/markers.json) and fast travel moves the
## party within it, streaming the destination cells first; level exits are roads.


func _ft() -> FastTravel:
	var ft := FastTravel.new()
	ft.flags.set_flag(FastTravel.CRYSTAL)
	ft.flags.set_flag(FastTravel.TUTORIAL_DONE)
	return ft


func test_markers_cover_points() -> void:
	var m := WorldTravel.load_markers()
	check(not m.is_empty(), "markers.json present (tools/bake_world_markers.gd)")
	for p in FastTravel.POINTS:
		check(m["waystones"].has(p), "waystone %s placed in the world" % p)
	var fresh := (
		(load("res://tools/bake_world_markers.gd") as GDScript).call("collect") as Dictionary
	)
	check(JSON.stringify(fresh) == JSON.stringify(m), "markers.json fresh: rerun the bake")
	var roads := 0
	for e in m["exits"]:
		roads += 1 if e["kind"] == "road" else 0
	check(roads >= 4, "level exits become roads (%d)" % roads)


func test_travel_moves_party() -> void:
	LoadingScreen.dry_run = true
	var s := WorldStreamer.new()
	s.cells_dir = "res://world/__none__/"
	runner_tree.root.add_child(s)
	var t := WorldTravel.new()
	t.fast_travel = _ft()
	t.streamer = s
	var a := Node3D.new()
	var b := Node3D.new()
	runner_tree.root.add_child(a)
	runner_tree.root.add_child(b)
	b.global_position = Vector3(2, 0, 0)
	t.party = func() -> Array: return [a, b]
	var fighting := [true]
	t.in_combat = func() -> bool: return fighting[0]
	runner_tree.root.add_child(t)
	check(t.waystones.size() == FastTravel.POINTS.size(), "a waystone per point")
	check(not t.can_travel("landfill"), "not attuned")
	t.fast_travel.attune("landfill")
	check(not t.can_travel("landfill") and t.last_error.contains("fight"), "refused in combat")
	fighting[0] = false
	var ok: bool = await t.travel_to("landfill")
	check(ok, "travelled")
	var d := t.point_world("landfill") + WorldTravel.LAND
	check(
		Vector2(a.global_position.x, a.global_position.z).distance_to(Vector2(d.x, d.z)) < 0.1,
		"leader at the waystone"
	)
	check(is_equal_approx(b.global_position.x - a.global_position.x, 2.0), "party spread kept")
	check(not s.nav_pending([a.global_position] as Array[Vector3]), "destination nav streamed")
	check(s.viewer_override.is_empty(), "viewer override restored")
	LoadingScreen.dry_run = false
	for n in [t, a, b, s]:
		n.free()
