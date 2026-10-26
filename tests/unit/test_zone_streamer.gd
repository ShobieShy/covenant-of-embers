extends TestCase
## Step 153 (Phase W2): POI content streams in within the quality load radius, out only
## past the +50 m hysteresis, comes back intact; prop meshes get per-preset visibility ranges.


func _level() -> Node3D:
	var lvl := Node3D.new()
	var s := ZoneStreamer.new()
	s.name = "Pois"
	for spec in [["near", Vector3.ZERO], ["far", Vector3(400, 0, 0)]]:
		var p := Node3D.new()
		p.name = spec[0]
		p.set_meta(&"center", spec[1])
		p.set_meta(&"radius", 20.0)
		var m := MeshInstance3D.new()
		m.name = "Mesh"
		p.add_child(m)
		s.add_child(p)
	lvl.add_child(s)
	return lvl


func test_load_unload_with_hysteresis() -> void:
	var saved := QualityPresets.level
	QualityPresets.level = QualityPresets.Level.LOW
	var lvl := _level()
	var s := lvl.get_node("Pois") as ZoneStreamer
	s.update_now([Vector3.ZERO])
	check(s.loaded["near"] and not s.loaded["far"], "far POI out at 380 m")
	check(lvl.get_node("Pois/far").get_child_count() == 0, "far content detached")
	s.update_now([Vector3(220, 0, 0)])  # far edge at 160 m: still beyond Low's 150
	check(not s.loaded["far"], "160 m > 150 m stays out")
	s.update_now([Vector3(240, 0, 0)])  # far edge at 140 m
	check(s.loaded["far"] and lvl.has_node("Pois/far/Mesh"), "loads within 150 m, content intact")
	s.update_now([Vector3(400, 0, 0)])  # near edge at 380 m
	check(not s.loaded["near"], "near unloads past 200 m")
	s.update_now([Vector3(0, 0, 190)])  # near edge 170 m: inside hysteresis, far edge > 200 m
	check(not s.loaded["near"] and s.loaded["far"] == false, "far out at ~420 m; near still out (170 > 150)")
	s.update_now([Vector3(0, 0, 160)])  # near edge 140 m
	check(s.loaded["near"], "near back")
	s.update_now([Vector3(0, 0, 210)])  # near edge 190 m: inside the 150+50 hysteresis
	check(s.loaded["near"], "hysteresis keeps it at 190 m")
	s.update_now([Vector3(0, 0, 230)])  # near edge 210 m
	check(not s.loaded["near"], "out past 200 m")
	QualityPresets.level = QualityPresets.Level.HIGH
	check_near(ZoneStreamer.load_radius(), 250.0, 0.01, "High loads at 250 m")
	lvl.free()
	QualityPresets.level = saved


func test_visibility_ranges_per_preset() -> void:
	var saved := QualityPresets.level
	var lvl := _level()
	QualityPresets.level = QualityPresets.Level.LOW
	ZoneStreamer.apply_ranges(lvl)
	var m := lvl.get_node("Pois/near/Mesh") as MeshInstance3D
	check_near(m.visibility_range_end, 90.0, 0.01, "Low fades props at 90 m")
	QualityPresets.level = QualityPresets.Level.HIGH
	ZoneStreamer.apply_ranges(lvl)
	check_near(m.visibility_range_end, 220.0, 0.01, "High at 220 m")
	lvl.free()
	QualityPresets.level = saved
