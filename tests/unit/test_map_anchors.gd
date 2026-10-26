extends TestCase
## Step 155 done check (TERRAIN_MAPS_PLAN section 10): anchors, map_version migration,
## v1 fixture saves, the co-op terrain hash, interest management and camp activation.

const FILE := "user://test_anchor_save.json"
const STASH := "user://test_anchor_stash.json"

var _port := 27600 + randi_range(0, 300) * 2


func _level(version: int, waystone := true) -> Node3D:
	var lvl := Node3D.new()
	var t := Node3D.new()
	t.name = "Terrain"
	t.set_script(load("res://scripts/world/terrain_zone.gd"))
	t.set(&"build_on_ready", false)
	t.set(&"map_version", version)
	lvl.add_child(t)
	var anchors := Node3D.new()
	anchors.name = "Anchors"
	lvl.add_child(anchors)
	for a in [["camp", "", Vector3(10, 0, 0)], ["joe_beat", "meet_joe", Vector3(20, 0, 0)]]:
		var m := Marker3D.new()
		m.name = a[0]
		m.position = a[2]
		if not String(a[1]).is_empty():
			m.set_meta(&"beat", a[1])
		anchors.add_child(m)
	if waystone:
		var ws := Node3D.new()
		ws.name = "Waystones"
		lvl.add_child(ws)
		var w := Marker3D.new()
		w.name = "landfill"
		w.position = Vector3(30, 0, 0)
		ws.add_child(w)
	return lvl


func _name(n: Node) -> String:
	return String(n.name) if n else "<start>"


func test_spawn_rules() -> void:
	var v1 := _level(1)
	var v2 := _level(2)
	var v2_bare := _level(2, false)
	runner_tree.root.add_child(v1)
	runner_tree.root.add_child(v2)
	runner_tree.root.add_child(v2_bare)
	check(MapAnchors.version_of(v2) == 2 and MapAnchors.version_of(Node3D.new()) == 1, "map_version read")
	check(_name(MapAnchors.spawn_node(v1, {})) == "<start>", "v1 save on a v1 map: PlayerStart as before")
	check(_name(MapAnchors.spawn_node(v1, {"anchor": "camp", "map_version": 1})) == "camp", "saved anchor")
	check(_name(MapAnchors.spawn_node(v1, {"anchor": "landfill", "map_version": 1})) == "landfill", "waystone anchor")
	check(_name(MapAnchors.spawn_node(v2, {"anchor": "camp"}, "meet_joe")) == "camp", "travel save (no version)")
	check(_name(MapAnchors.spawn_node(v2, {}, "meet_joe")) == "joe_beat", "newer map: intro beat anchor")
	check(_name(MapAnchors.spawn_node(v2, {"anchor": "camp", "map_version": 1})) == "landfill", "newer map: waystone")
	check(_name(MapAnchors.spawn_node(v2_bare, {})) == "<start>", "newer map, no waystone: PlayerStart")
	check(_name(MapAnchors.spawn_node(v1, {}, "", "landfill")) == "landfill", "co-op: host's waystone")
	check(_name(MapAnchors.spawn_node(v1, {}, "", "gone")) == "landfill", "co-op: unknown anchor -> waystone")
	check(MapAnchors.nearest(v1, Vector3(12, 0, 0)) == "camp", "nearest anchor")
	check(MapAnchors.nearest(v1, Vector3(500, 0, 0)).is_empty(), "nothing near")
	check(MapAnchors.nearest_waystone(v1, Vector3(-100, 0, 0)) == "landfill", "nearest waystone")
	for n in [v1, v2, v2_bare]:
		n.free()


func _cleanup() -> void:
	for f in [FILE, STASH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Saves from before step 155 (no anchor / map_version) load at PlayerStart and save back
## with the new keys.
func test_v1_fixture_saves_load() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	Stash.shared_path = STASH
	for lvl in ["midden", "old_oak", "breach", "town_square"]:
		var raw := FileAccess.get_file_as_string("res://tests/fixtures/saves_v1/%s.json" % lvl)
		check(not raw.is_empty() and not raw.contains('"anchor"'), "%s fixture is pre-155" % lvl)
		var fa := FileAccess.open(FILE, FileAccess.WRITE)
		fa.store_string(raw)
		fa.close()
		GameFlow.level_id = lvl
		GameFlow.load_save = true
		var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
		g.position = Vector3(0, 0, -9000)
		runner_tree.root.add_child(g)
		var p := g.get_node("Player") as Player
		var start := g.get_node("Level/PlayerStart") as Node3D
		check(p.spawn_feet.distance_to(start.global_position) < 0.01, "%s: PlayerStart" % lvl)
		check(g.load_warnings.is_empty(), "%s: no warnings %s" % [lvl, g.load_warnings])
		check(g.story_flags.has("tutorial_done"), "%s: flags kept" % lvl)
		var pr: Dictionary = g.progress()
		check(pr.has("anchor") and int(pr["map_version"]) == 1, "%s: new keys %s" % [lvl, pr])
		g.free()
	GameFlow.dry_run = false
	GameFlow.load_save = false
	GameFlow.level_id = "midden"
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	Stash.shared_path = Stash.PATH
	_cleanup()


func test_terrain_hash() -> void:
	var a := Compat.terrain_fingerprint()
	check(a.length() == 16, "terrain fingerprint")
	check(Compat.terrain_rows().size() >= 1, "rows")
	Compat._terrain_cached = ""
	check(Compat.terrain_fingerprint() == a, "stable")


func _wait(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


func test_terrain_mismatch_rejected() -> void:
	_port += 1
	var w := Node.new()
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	h.name = "H155"
	var c := NetSession.new()
	c.name = "C155"
	w.add_child(h)
	w.add_child(c)
	check(h.host(NetTransport.make("enet"), _port, {"name": "H"}), "host")
	Compat.terrain_override = "ffffffffffffffff"
	check(c.join(NetTransport.make("enet"), "127.0.0.1:%d" % _port, {"name": "C"}), "join")
	Compat.terrain_override = ""
	check(await _wait(func(): return c.state == NetSession.State.IDLE), "rejected")
	check(c.last_reason.contains("map data mismatch"), c.last_reason)
	check(h.roster.size() == 1, "not admitted")
	h.leave("done")
	for i in 3:
		await runner_tree.process_frame
	w.queue_free()


func test_interest_and_camp_activation() -> void:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var cw := CoopWorld.new()
	cw.table = EnemyTable.load_default()
	w.add_child(cw)
	var all: Array[Enemy] = []
	for x in [0.0, 100.0, 149.0, 151.0, 400.0]:
		var e := Enemy.new()
		e.setup(cw.table.find("gnawer"))
		w.add_child(e)
		e.global_position = Vector3(x, 0, 0)
		all.append(e)
	check(cw.interest_rows(all, Vector3.ZERO).size() == 3, "only enemies within 150 m")
	check(cw.interest_rows(all, Vector3(400, 0, 0)).size() == 1, "far peer sees its own area")
	check(cw.interest_rows(all, null).size() == 5, "no pose yet: everything")
	var a := Node3D.new()
	var b := Node3D.new()
	w.add_child(a)
	w.add_child(b)
	b.global_position = Vector3(300, 0, 0)
	check(CampLeash.camp_active(Vector3(70, 0, 0), [a, b]), "a player within 80 m wakes the camp")
	check(not CampLeash.camp_active(Vector3(150, 0, 0), [a, b]), "nobody within 80 m")
	check(CampLeash.camp_active(Vector3(250, 0, 0), [a, b]), "any player counts")
	w.free()
