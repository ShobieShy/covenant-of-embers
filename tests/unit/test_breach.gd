extends TestCase
## Step 33 done check: the Breach loads, bakes its navmesh, and every arena spawn point is
## reachable from the player start on it (the vault one once the vault door is gone).

const SCENE := "res://scenes/levels/breach.tscn"
const TOML := "res://data/levels/breach_slice.toml"


func _load(at: Vector3) -> Node3D:
	var w := Node3D.new()
	w.position = at
	runner_tree.root.add_child(w)
	var level: Node3D = (load(SCENE) as PackedScene).instantiate()
	w.add_child(level)
	return level


func test_layout() -> void:
	var d := LevelToml.load_file(TOML)
	check(not d.has("error"), "TOML parses")
	var level: Node3D = (load(SCENE) as PackedScene).instantiate()
	check(level.get_meta("level_id", "") == "breach_slice", "level id")
	for n in ["vault_door", "boss_dais", "corridor_west", "vault_back"]:
		check(level.get_node_or_null("Boxes/" + n) != null, "has %s" % n)
	for n in ["boss_dais", "west_wing", "east_wing", "vault_chest"]:
		check(level.get_node_or_null("WaveSpawns/" + n) != null, "spawn %s" % n)
	check(level.get_node("Waves").get_child_count() == 3, "three waves (the boss last)")
	level.free()


func test_navmesh_and_spawns_reachable() -> void:
	var level := _load(Vector3(3000, 0, -3000))
	var nav := level.get_node("Navigation") as LevelNavigation
	check(nav != null and nav.navigation_mesh.get_polygon_count() > 0, "navmesh baked")
	for i in 120:
		if nav.map_ready():
			break
		await runner_tree.physics_frame
	check(nav.map_ready(), "navmesh synced")
	var map := nav.get_navigation_map()
	var start := (level.get_node("PlayerStart") as Node3D).global_position
	for n in ["boss_dais", "west_wing", "east_wing"]:
		var m := level.get_node("WaveSpawns/" + n) as Node3D
		var path := NavigationServer3D.map_get_path(map, start, m.global_position, true)
		check(
			path.size() > 1 and path[path.size() - 1].distance_to(m.global_position) < 0.6,
			"%s reachable (end %s)" % [n, path[path.size() - 1] if path.size() else "none"]
		)
	var vc := (level.get_node("WaveSpawns/vault_chest") as Node3D).global_position
	var vp := NavigationServer3D.map_get_path(map, start, vc, true)
	check(vp.is_empty() or vp[vp.size() - 1].distance_to(vc) > 2.0, "vault sealed by its door")
	level.get_parent().queue_free()


## Step 46: the Breach entrance has a reachable Assembly Station; crafting there works and the
## shared prompt shows only within reach.
func test_station_in_breach() -> void:
	var level := _load(Vector3(-3000, 0, 3000))
	var w := level.get_parent()
	var start := (level.get_node("PlayerStart") as Node3D).global_position
	var st := AssemblyStation.place(w, level, start)
	var marker := level.get_node_or_null(AssemblyStation.MARKER) as Node3D
	check(marker != null and st.global_position.distance_to(marker.global_position) < 0.01, "placed on the marker")
	check(st.global_position.distance_to(start) > 1.0, "not on top of the start")
	var nav := level.get_node("Navigation") as LevelNavigation
	for i in 120:
		if nav.map_ready():
			break
		await runner_tree.physics_frame
	var path := NavigationServer3D.map_get_path(nav.get_navigation_map(), start, st.global_position, true)
	check(path.size() > 1 and path[path.size() - 1].distance_to(st.global_position) < 1.5, "station reachable")
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(start, 0.0)
	check(
		AssemblyStation.prompt_for(p).is_empty(),
		"no prompt from the start (%.1f m)" % start.distance_to(st.global_position)
	)
	p.spawn(st.global_position + Vector3(0, 0, 1.5), 0.0)
	check(st.in_reach(p), "in reach beside it")
	check(AssemblyStation.prompt_for(p) == "[E] Magic Assembly Station", "prompt: %s" % AssemblyStation.prompt_for(p))
	var base := WieldableInstance.load_base("apprentice_fire_staff")
	var parts := []
	for id in ["basic_fire_head", "basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id).duplicate())
	p.inventory.add(base)
	for part in parts:
		p.inventory.add(part)
	var made := st.assemble(p, base, parts)
	check(made != null and p.inventory.has(made), "crafted in the Breach: %s" % st.last_error)
	w.queue_free()
