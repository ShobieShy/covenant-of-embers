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
	for n in ["vault_door", "boss_dais", "corridor_west", "vault_back", "switch_gate"]:
		check(level.get_node_or_null("Boxes/" + n) != null, "has %s" % n)
	for n in ["boss_dais", "west_wing", "east_wing", "vault_chest"]:
		check(level.get_node_or_null("WaveSpawns/" + n) != null, "spawn %s" % n)
	check(level.get_node("Waves").get_child_count() == 3, "three waves (the boss last)")
	check(level.get_node("Encounters").get_child_count() == 6, "six room encounters (step 162)")
	check(level.get_node("Switches").get_child_count() == 3, "three levers (step 162)")
	level.free()


func test_navmesh_and_spawns_reachable() -> void:
	var level := _load(Vector3(3000, 0, -3000))
	var nav := level.get_node("Navigation") as LevelNavigation
	check(nav != null and nav.polygon_count() > 0, "navmesh baked")
	var t0 := Time.get_ticks_msec()  # step 162: the 220x320 m zone syncs in real seconds
	while not nav.map_ready() and Time.get_ticks_msec() - t0 < 20000:
		await runner_tree.physics_frame
	check(nav.map_ready(), "navmesh synced")
	var map := nav.get_navigation_map()
	var start := (level.get_node("PlayerStart") as Node3D).global_position
	var dais := (level.get_node("WaveSpawns/boss_dais") as Node3D).global_position
	check(not _reaches(map, start, dais, 0.6), "arena sealed by the switch gate")
	for n in ["den_north", "gallery_west", "gallery_east", "cistern_north"]:
		var m := (level.get_node("WaveSpawns/" + n) as Node3D).global_position
		check(_reaches(map, start, m, 0.6), "room spot %s reachable" % n)
	for s in level.get_node("Switches").get_children():
		check(
			_reaches(map, start, (s as Node3D).global_position, 1.0), "lever %s reachable" % s.name
		)
	var b := Breach.new()
	level.get_parent().add_child(b)
	b.setup(level, null, false)
	b.open_gate()
	await _synced(nav)
	map = nav.get_navigation_map()
	for n in ["boss_dais", "west_wing", "east_wing"]:
		var m := (level.get_node("WaveSpawns/" + n) as Node3D).global_position
		check(_reaches(map, start, m, 0.6), "%s reachable once the gate is open" % n)
	# QA-2: co-op host stalled 30 s at (0, 0, 59.7) going for the warden: the den doorway
	# must path through to the dais once the gate is open.
	var den := level.global_transform * Vector3(-0.25, 0.0, 59.7)
	var dais2 := (level.get_node("WaveSpawns/boss_dais") as Node3D).global_position
	var dp := NavigationServer3D.map_get_path(map, den, dais2, true)
	var dl := 0.0
	for i in range(1, dp.size()):
		dl += dp[i].distance_to(dp[i - 1])
	check(_reaches(map, den, dais2, 0.6) and dl < 80.0, "den doorway to dais: %.0f m" % dl)
	var vc := (level.get_node("WaveSpawns/vault_chest") as Node3D).global_position
	check(not _reaches(map, start, vc, 2.0), "vault sealed by its door")
	b.open_vault()
	await _synced(nav)
	check(_reaches(nav.get_navigation_map(), start, vc, 1.5), "vault reachable after it opens")
	check(not (level.get_node("Boxes/switch_gate") as StaticBody3D).visible, "gate stays open")
	level.get_parent().queue_free()


func _reaches(map: RID, a: Vector3, b: Vector3, tol: float) -> bool:
	var path := NavigationServer3D.map_get_path(map, a, b, true)
	return path.size() > 1 and path[path.size() - 1].distance_to(b) < tol


func _synced(nav: LevelNavigation) -> void:
	var t0 := Time.get_ticks_msec()
	while not nav.map_ready() and Time.get_ticks_msec() - t0 < 20000:
		await runner_tree.physics_frame


## Step 47: room encounters fire on their triggers and clear; the levers stay inert until
## every room is clear, and the gate opens once both are pulled.
func test_rooms_and_levers() -> void:
	var level := _load(Vector3(-6000, 0, -6000))
	var w := level.get_parent()
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn((level.get_node("PlayerStart") as Node3D).global_position, 0.0)
	var b := Breach.new()
	w.add_child(b)
	b.setup(level, p, false)
	await _synced(level.get_node("Navigation") as LevelNavigation)
	check(b.encounters.size() == 6 and b.switches.size() == 3, "6 rooms, 3 levers")
	check(not b.rooms_cleared() and b.next_encounter() == b.encounters[0], "first room first")
	check(not b.switches[0].press(), "lever inert while rooms hold enemies")
	for e in b.encounters:
		e.tick(0.1)
		check(e.wave_state == EnemySpawner.WaveState.WAITING, "%s waits for the player" % e.name)
		p.spawn(e.trigger_center, 0.0)
		e.tick(0.1)
		check(e.wave_state != EnemySpawner.WaveState.WAITING, "%s triggers in its room" % e.name)
		for i in 60:
			e.tick(1.0 / 60.0)
		check(e.wave_alive.size() > 0, "%s spawned" % e.name)
		for k in 10:  # oozes split: keep killing until the room is empty
			for en in e.wave_alive.duplicate():
				en.apply_damage(1000.0, ElementTable.Element.FIRE)
			e.tick(0.1)
		check(e.cleared(), "%s cleared" % e.name)
	check(b.rooms_cleared(), "rooms cleared")
	check(b.switches.all(func(x: BreachSwitch) -> bool: return x.armed), "levers armed")
	check(b.switches[0].press() and not b.gate_open, "one lever is not enough")
	check(b.switches[1].press() and not b.gate_open, "two levers are not enough")
	check(b.switches[2].press() and b.gate_open, "all three levers open the gate")
	w.queue_free()


## Step 46: the Breach entrance has a reachable Assembly Station; crafting there works and the
## shared prompt shows only within reach.
func test_station_in_breach() -> void:
	var level := _load(Vector3(-3000, 0, 3000))
	var w := level.get_parent()
	var start := (level.get_node("PlayerStart") as Node3D).global_position
	var st := AssemblyStation.place(w, level, start)
	var marker := level.get_node_or_null(AssemblyStation.MARKER) as Node3D
	check(
		marker != null and st.global_position.distance_to(marker.global_position) < 0.01,
		"placed on the marker"
	)
	check(st.global_position.distance_to(start) > 1.0, "not on top of the start")
	var nav := level.get_node("Navigation") as LevelNavigation
	var t0 := Time.get_ticks_msec()  # step 162: the 220x320 m zone syncs in real seconds
	while not nav.map_ready() and Time.get_ticks_msec() - t0 < 20000:
		await runner_tree.physics_frame
	var path := NavigationServer3D.map_get_path(
		nav.get_navigation_map(), start, st.global_position, true
	)
	check(
		path.size() > 1 and path[path.size() - 1].distance_to(st.global_position) < 1.5,
		"station reachable"
	)
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
	check(
		AssemblyStation.prompt_for(p) == "[F] Magic Assembly Station",
		"prompt: %s" % AssemblyStation.prompt_for(p)
	)
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
