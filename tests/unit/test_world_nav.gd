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


## The bake must see each content cell's colliders (it once ran before the scene root
## was in the tree and parsed none, so walls were walkable).
func test_cells_have_obstacles() -> void:
	var nav: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://world/nav/nav.json")
	)
	var cells: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://world/cells/cells.json")
	)
	var seen := 0
	for k in cells["cells"]:
		if not nav["cells"].has(k):
			continue
		var e: Variant = nav["cells"][k]
		check(e is Dictionary and e.has("shapes"), "cell %s has obstacle info" % k)
		if e is Dictionary and int(e.get("shapes", 0)) > 0:
			seen += 1
			check(int(e["obstacle_verts"]) > 0, "cell %s nav saw its colliders" % k)
	check(seen > 0, "some cells carve obstacles")


func test_town_to_midden_path() -> void:
	var s := WorldStreamer.new()
	s.cells_dir = "res://world/__none__/"  # nav only: keep this test light
	runner_tree.root.add_child(s)
	var pts: Array[Vector3] = []
	for i in 6:
		pts.append(TOWN.lerp(MIDDEN, i / 5.0))
	s.viewer_override = pts
	for i in 20:  # flush is frame-capped; under full-suite load the nav ring can lag
		s.flush()
		if not s.nav_pending(s.viewers()):
			break
		await runner_tree.process_frame
	check(not s.nav_pending(s.viewers()), "nav ring complete")
	check(not s.nav.is_empty(), "nav tiles streamed (%d)" % s.nav.size())
	# A private map: other tests leave regions on the world's default map.
	var m := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(m, 0.1)
	NavigationServer3D.map_set_cell_height(m, 0.05)
	NavigationServer3D.map_set_active(m, true)
	for r in s.nav.values():
		(r as NavigationRegion3D).set_navigation_map(m)
	# Region syncs run on worker threads; under --fixed-fps 60 frames outrun them, so wait on
	# the wall clock rather than a frame count.
	var until := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < until:
		await runner_tree.physics_frame
		OS.delay_msec(5)
		if NavigationServer3D.map_get_iteration_id(m) > 0:
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
		NavigationServer3D.free_rid(m)
		return
	check(
		p[p.size() - 1].distance_to(b) < 1.0, "path reaches the Midden (ends %s)" % p[p.size() - 1]
	)
	var length := 0.0
	for i in range(1, p.size()):
		length += p[i].distance_to(p[i - 1])
	check(length < a.distance_to(b) * 2.0, "path is not absurd (%.0f m)" % length)
	s.free()
	NavigationServer3D.free_rid(m)
