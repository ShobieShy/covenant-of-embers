extends TestCase
## OW4b: the whole-world navmesh (tools/bake_world_nav.gd, one NavigationMesh per 128 m
## cell) streams with the cells, and its tiles join across cell seams and zone strips:
## a path exists from the town square to the Midden.

const TOWN := Vector3(0, 0, 0)
const MIDDEN := Vector3(576, 0, 0)


func test_nav_fresh() -> void:
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/nav/nav.json"))
	check(info is Dictionary, "nav.json present (tools/bake_world_nav.gd)")
	if not info is Dictionary:
		return
	for k in info["cells"]:
		check(ResourceLoader.exists("res://world/nav/%s.res" % k), "nav tile %s on disk" % k)


func test_town_to_midden_path() -> void:
	var s := WorldStreamer.new()
	s.cells_dir = "res://world/__none__/"  # nav only: keep this test light
	runner_tree.root.add_child(s)
	var pts: Array[Vector3] = []
	for i in 6:
		pts.append(TOWN.lerp(MIDDEN, i / 5.0))
	s.viewer_override = pts
	s.flush()
	check(not s.nav.is_empty(), "nav tiles streamed (%d)" % s.nav.size())
	var m := s.get_world_3d().navigation_map
	for i in 120:
		await runner_tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(m) > 2:
			var a := NavigationServer3D.map_get_closest_point(m, TOWN)
			var b := NavigationServer3D.map_get_closest_point(m, MIDDEN)
			var p := NavigationServer3D.map_get_path(m, a, b, true)
			if not p.is_empty() and p[p.size() - 1].distance_to(b) < 1.0:
				break
	var a := NavigationServer3D.map_get_closest_point(m, TOWN)
	var b := NavigationServer3D.map_get_closest_point(m, MIDDEN)
	var p := NavigationServer3D.map_get_path(m, a, b, true)
	check(
		a.distance_to(TOWN * Vector3(1, 0, 1) + Vector3(0, a.y, 0)) < 20.0,
		"town on the navmesh (%s)" % a
	)
	check(
		b.distance_to(MIDDEN * Vector3(1, 0, 1) + Vector3(0, b.y, 0)) < 20.0,
		"Midden on the navmesh (%s)" % b
	)
	check(not p.is_empty(), "a path exists")
	if p.is_empty():
		s.free()
		return
	check(
		p[p.size() - 1].distance_to(b) < 1.0, "path reaches the Midden (ends %s)" % p[p.size() - 1]
	)
	var length := 0.0
	for i in range(1, p.size()):
		length += p[i].distance_to(p[i - 1])
	check(length < a.distance_to(b) * 2.0, "path is not absurd (%.0f m)" % length)
	s.free()
