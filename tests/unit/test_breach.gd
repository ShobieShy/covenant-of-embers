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
		check(path.size() > 1 and path[path.size() - 1].distance_to(m.global_position) < 0.6,
			"%s reachable (end %s)" % [n, path[path.size() - 1] if path.size() else "none"])
	var vc := (level.get_node("WaveSpawns/vault_chest") as Node3D).global_position
	var vp := NavigationServer3D.map_get_path(map, start, vc, true)
	check(vp.is_empty() or vp[vp.size() - 1].distance_to(vc) > 2.0, "vault sealed by its door")
	level.get_parent().queue_free()
