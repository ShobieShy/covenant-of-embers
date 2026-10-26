extends TestCase
## Step 154 (W3): open zones bake 64 m navmesh tiles over the greybox, POIs and the links
## between them; a path crosses tile seams; camps leash at 40 m; the bot's route graph
## chains landmarks; every shipped open-zone level has a fresh offline nav cache.

const C := Vector2(6400, 6400)


func _world() -> Node3D:
	var w := Node3D.new()
	w.set_meta(&"level_id", "nav_tile_test")
	var boxes := Node3D.new()
	boxes.name = "Boxes"
	w.add_child(boxes)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 0.2, 20)
	cs.shape = bs
	sb.add_child(cs)
	sb.position = Vector3(C.x, -0.1, C.y)
	boxes.add_child(sb)
	var z := TerrainZone.new()
	z.name = "Terrain"
	z.size = Vector2(320, 200)
	z.center = C + Vector2(60, 0)
	z.height = 4.0
	z.noise_seed = 3
	z.spacing = 2.0
	z.pads = [Rect2(C.x - 12, C.y - 12, 24, 24), Rect2(C.x + 110, C.y - 12, 24, 24)]
	z.build_on_ready = false
	w.add_child(z)
	var start := Marker3D.new()
	start.name = "PlayerStart"
	start.position = Vector3(C.x, 0, C.y)
	w.add_child(start)
	var pois := Node3D.new()
	pois.name = "Pois"
	var p := Node3D.new()
	p.name = "far_camp"
	p.set_meta(&"center", Vector3(C.x + 122, 0, C.y))
	p.set_meta(&"radius", 10.0)
	pois.add_child(p)
	w.add_child(pois)
	var nav := LevelNavigation.new()
	nav.name = "Navigation"
	nav.bake_on_ready = false
	w.add_child(nav)
	return w


func test_tiles_links_and_seam_path() -> void:
	var w := _world()
	runner_tree.root.add_child(w)
	var nav := w.get_node("Navigation") as LevelNavigation
	nav.bake_now()
	var keys := nav.tile_keys(AABB(Vector3(C.x - 10, -0.2, C.y - 10), Vector3(20, 0.2, 20)))
	check(nav.tiles.size() == keys.size() and keys.size() >= 3, "%d tiles over box, link and POI" % keys.size())
	check(nav.polygon_count() > 0, "tiles have polygons")
	var ok := false
	for i in 120:
		await runner_tree.physics_frame
		if nav.map_ready():
			ok = true
			break
	check(ok, "tiled map syncs")
	var to := Vector3(C.x + 122, 0, C.y)
	var path := NavigationServer3D.map_get_path(nav.get_navigation_map(), Vector3(C.x, 0, C.y), to, true)
	check(path.size() > 1, "a path exists across tile seams")
	if path.size() > 1:
		var end := path[path.size() - 1]
		check(Vector2(end.x - to.x, end.z - to.z).length() < 2.0, "path reaches the far camp (%s)" % end)
	w.queue_free()
	await runner_tree.physics_frame


func test_camp_leash() -> void:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D.IDENTITY)
	w.add_child(e)
	CampLeash.home(e, Vector3(5, 0, 5))
	e.global_position = Vector3(30, 0, 5)
	check(CampLeash.enforce([e]) == 0, "inside 40 m stays")
	e.apply_damage(1.0, ElementTable.Element.FIRE)
	e.global_position = Vector3(50, 0, 5)
	check(CampLeash.enforce([e]) == 1, "45 m out goes home")
	check(e.global_position.distance_to(Vector3(5, 0, 5)) < 0.01, "back at its spot")
	check_near(e.health, e.max_health(), 0.01, "healed on leash")
	w.free()


func test_route_graph_chains_landmarks() -> void:
	var g := RouteGraph.new()
	g.points = [Vector3.ZERO, Vector3(100, 0, 0), Vector3(200, 0, 0), Vector3(300, 0, 0)]
	g.build()
	check(g.next_waypoint(Vector3(1, 0, 0), Vector3(300, 0, 0)) == Vector3(100, 0, 0), "first leg to the next landmark")
	check(g.next_waypoint(Vector3(101, 0, 0), Vector3(300, 0, 0)) == Vector3(200, 0, 0), "then the next")
	check(g.next_waypoint(Vector3(250, 0, 0), Vector3(300, 0, 0)) == Vector3(300, 0, 0), "short hop goes straight")


func test_shipped_nav_caches_fresh() -> void:
	for id in ["mage_association", "town_square", "old_oak", "midden", "breach"]:
		var lvl := (load(GameFlow.level_scene(id)) as PackedScene).instantiate()
		var tz := lvl.get_node_or_null(^"Terrain") as TerrainZone
		if tz == null:
			lvl.free()
			continue
		tz.build_on_ready = false
		(lvl.get_node(^"Navigation") as LevelNavigation).bake_on_ready = false
		runner_tree.root.add_child(lvl)
		check(
			(lvl.get_node(^"Navigation") as LevelNavigation).cache_fresh(),
			"%s nav cache fresh (tools/bake_nav.gd)" % id
		)
		lvl.free()
