extends TestCase
## A new game walks every main-quest step, in order, through the intro and Acts I-V.
## At each step the visible marker (intro mark, then the quest mark) is in the right
## zone, on a real node, off the origin, outside solid geometry, and reachable.
## The minimap pin matches that spot. Zone changes are separate visits.

const FILE := "user://test_storyline_markers.json"

var _flags := {}
var _carried := {}
var _bosses: Array[String] = []


func _reset() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.path_override = FILE
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	GameFlow.level_id = "mage_association"
	_flags = {}
	_carried = {}
	_bosses = []
	for f in [FILE, FILE + ".bak", FILE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _restore() -> void:
	_reset()
	GameFlow.dry_run = false
	GameFlow.path_override = ""
	GameFlow.select_slot(1)


func _beat(id: String, extra: PackedStringArray = PackedStringArray()) -> void:
	var f := StoryFlags.new()
	IntroDirector.start(f)
	if id != "summoning":
		IntroDirector.reach(f, id)
	for e in extra:
		f.set_flag(e)
	_flags = f.to_dict()


func _open(level: String) -> Node:
	GameFlow.level_id = level
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.story_flags.from_dict(_flags)
	if not _carried.is_empty():
		g._loaded_quests = _carried.duplicate(true)
	g.labyrinth.bosses = _strings(_bosses)
	runner_tree.root.add_child(g)
	for _i in 6:
		await runner_tree.physics_frame
	_snap(g)
	return g


func _snap(g: Node) -> void:
	_flags = g.story_flags.to_dict()
	if g.quests:
		_carried = g.quests.to_dict()
	_bosses = _strings(g.labyrinth.bosses)


func _strings(raw: Array) -> Array[String]:
	var out: Array[String] = []
	for item in raw:
		out.append(String(item))
	return out


func _close(g: Node) -> void:
	if is_instance_valid(g):
		g.free()


func test_storyline_markers_from_new_game_through_act_v() -> void:
	_reset()
	await _intro_and_hub()
	await _landfill_and_breach()
	await _acts()
	_restore()


func _intro_and_hub() -> void:
	_beat("grant")
	var hall := await _open("mage_association")
	_mark(hall, "intro grant", "Clerk", "")
	check(hall.intro.current() == "grant", "grant is the active beat")
	_close(hall)
	_beat("welcome", PackedStringArray(["permit_given", "joe_met", "joe_expelled", "identity_chosen"]))
	var road := await _open("mage_association")
	_mark(road, "intro welcome", "", "town_square")
	check(_active(road, "a_new_home"), "the permit starts A New Home")
	_close(road)
	var town := await _open("town_square")
	check(town.intro.current() == "new_home", "town advances welcome to the grove")
	_mark(town, "intro new home", "", "old_oak")
	_close(town)
	var oak := await _open("old_oak")
	_mark(oak, "intro moss bed", "bed", "")
	check(oak.intro.bed != null, "the bed is the marker node")
	_close(oak)
	_beat(
		"back_door",
		PackedStringArray(
			["permit_given", "home_unlocked", "bob_met", "bob_arrived", "starter_gear_given", "landfill_route_open"]
		),
	)
	var sent := await _open("town_square")
	_mark(sent, "intro landfill road", "", "midden")
	check(_active(sent, "the_landfill"), "Bob's kit starts Trash Talk")
	_close(sent)


func _landfill_and_breach() -> void:
	_beat(
		"back_door",
		PackedStringArray(
			[
				"permit_given",
				"home_unlocked",
				"bob_met",
				"bob_arrived",
				"starter_gear_given",
				"landfill_route_open",
				"rusty_dagger",
			]
		),
	)
	var fill := await _open("midden")
	check(fill.intro.current() == "combat", "the landfill door starts the Gnawer beat")
	_mark(fill, "intro gnawers", "gnawer", "")
	check(_objective(fill, "the_landfill") == "gnawer", "Trash Talk is on the Gnawers")
	fill.quests.notify("kill", "gnawer", 3)
	_snap(fill)
	check(_objective(fill, "the_landfill") == "the_filth", "three Gnawers advance to the Filth")
	_close(fill)
	_flags["intro_beat"] = IntroDirector.index_of("filth") + 1
	for id in ["crafted_once", "light_learned", "dark_learned"]:
		_flags[id] = 1
	var filth := await _open("midden")
	check(filth.intro.current() == "filth", "the Filth beat is active")
	_mark(filth, "intro filth", "the_filth", "")
	filth.quests.notify("kill", "the_filth")
	_snap(filth)
	check(_objective(filth, "the_landfill") == "joes_discards", "the Filth drops Joe's Trash")
	_mark(filth, "joe's trash", "joes_discards", "")
	filth.quests.notify("collect", "joes_discards")
	_snap(filth)
	check(filth.quests.state("the_landfill") == "done", "Trash Talk completes")
	check(_active(filth, "report_to_bob"), "the report is offered")
	check(_active(filth, "the_breach"), "the Breach is offered")
	check(filth.quests.tracked == "report_to_bob", "Bob stays tracked until the report")
	_mark(filth, "return to Bob", "", "old_oak")
	_close(filth)
	_flags["intro_beat"] = IntroDirector.index_of("return_to_bob") + 1
	_flags["filth_defeated"] = 1
	var back := await _open("old_oak")
	check(back.intro.current() == "crystal", "the grove moves the return on to Bob")
	_mark(back, "talk to Bob", "Bob", "")
	back.quests.notify("talk", "Bob")
	_snap(back)
	check(back.quests.state("report_to_bob") == "done", "the report completes")
	check(back.quests.tracked == "the_breach", "the Breach is the next tracked quest")
	check(_objective(back, "the_breach") == "breach", "the next step is the crater")
	_close(back)
	IntroDirector.finish(StoryFlags.new())  # flags already live; set the end bits on _flags
	_flags["intro_done"] = 1
	_flags["tutorial_done"] = 1
	_flags["fast_travel_crystal"] = 1
	var gate := await _open("midden")
	check(gate.intro == null, "the intro marker steps aside after the tutorial")
	_mark(gate, "road to the Breach", "", "breach")
	_close(gate)
	var crater := await _open("breach")
	check(_objective(crater, "the_breach") == "breach_warden", "arriving starts the Warden step")
	_mark(crater, "breach warden", "breach_warden", "")
	crater.quests.notify("kill", "breach_warden")
	_snap(crater)
	check(crater.quests.state("the_breach") == "done", "the Warden completes the Breach")
	check(_active(crater, "the_goblin_warrens"), "Act I is offered at the labyrinth gate")
	check(crater.quests.tracked == "the_goblin_warrens", "Act I is tracked")
	_mark(crater, "into the labyrinth", "", "labyrinth")
	_close(crater)


func _acts() -> void:
	var g := await _open("breach")
	var lin: Interiors = g._linear_interiors()
	check(lin != null, "the Breach holds the labyrinth")
	await _floor(g, lin, 1, "Act I", "goblin_king")
	await _floor(g, lin, 4, "Act I stairs", "goblin_king")
	await _floor(g, lin, 5, "Act I king", "goblin_king")
	_boss(g, "goblin_king", "the_goblin_warrens", "the_overgrown_deep")
	await _floor(g, lin, 6, "Act II", "blightmaw_matriarch")
	await _floor(g, lin, 8, "Act II matriarch", "blightmaw_matriarch")
	_boss(g, "blightmaw_matriarch", "the_overgrown_deep", "the_slagworks")
	await _floor(g, lin, 9, "Act III", "forgemaw")
	await _floor(g, lin, 12, "Act III stairs", "forgemaw")
	await _floor(g, lin, 13, "Act III forgemaw", "forgemaw")
	_boss(g, "forgemaw", "the_slagworks", "the_sunken_ruins")
	await _floor(g, lin, 14, "Act IV", "drowned_choir")
	await _floor(g, lin, 17, "Act IV stairs", "drowned_choir")
	await _floor(g, lin, 18, "Act IV choir", "drowned_choir")
	_boss(g, "drowned_choir", "the_sunken_ruins", "the_inverted_spire")
	await _floor(g, lin, 19, "Act V", "storm_warden")
	await _floor(g, lin, 22, "Act V stairs", "storm_warden")
	await _floor(g, lin, 23, "Act V warden", "storm_warden")
	g.quests.notify("kill", "storm_warden")
	g.labyrinth.defeat_boss("storm_warden")
	g.quests.known_bosses = g.labyrinth.bosses
	g.quests.check_auto_start()
	_snap(g)
	check(g.quests.state("the_inverted_spire") == "done", "the Storm Warden completes Act V")
	check(g.quests.tracked == "", "the trail has no further main quest")
	_close(g)


func _floor(g: Node, lin: Interiors, n: int, step: String, boss: String) -> void:
	await lin.enter_floor(n)
	for _i in 4:
		await runner_tree.physics_frame
	check(String(g.call(&"here_id")) == "labyrinth", "%s is inside the labyrinth" % step)
	check(lin.floor_no == n, "%s is floor %d" % [step, n])
	var want := boss if n >= int(QuestWaypoint.BOSS_FLOOR.get(boss, 99)) else ""
	_mark(g, step, want, "")
	print("[storyline] visited %s floor %d" % [step, n])


func _boss(g: Node, boss: String, done_id: String, nxt: String) -> void:
	g.quests.notify("kill", boss)
	g.labyrinth.defeat_boss(boss)
	g.quests.known_bosses = g.labyrinth.bosses
	g.quests.check_auto_start()
	_snap(g)
	check(g.quests.state(done_id) == "done", "%s completes" % done_id)
	check(_active(g, nxt), "%s is offered next" % nxt)
	check(g.quests.tracked == nxt, "%s is tracked" % nxt)
	print("[storyline] %s -> %s" % [done_id, nxt])


func _active(g: Node, id: String) -> bool:
	return g.quests != null and g.quests.state(id) == "active"


func _objective(g: Node, id: String) -> String:
	if g.quests == null:
		return ""
	return String(g.quests.current_objective(id).get("target", ""))


## Visible marker: the intro mark while the prologue has a spot, otherwise the quest mark.
func _spot(g: Node) -> Variant:
	var marker := g.get_node_or_null("QuestMarker") as QuestMarker
	if marker:
		marker._process(0.0)
	var intro: IntroDirector = g.intro
	if intro and intro.target_point() != null:
		return intro.target_point()
	return marker._cached() if marker else null


func _mark(g: Node, step: String, node_id: String, dest: String) -> void:
	var at: Variant = _spot(g)
	if not at is Vector3:
		check(false, "%s has no marker" % step)
		print("[storyline] FAIL %s no marker" % step)
		return
	var pos := at as Vector3
	if pos.length() < 0.05:
		check(false, "%s marker is the origin" % step)
	var node := _node_near(g, pos)
	check(node != null, "%s marker is not on a node (%s)" % [step, pos])
	if node_id != "":
		var match := _match_near(g, pos, node_id)
		check(match != null, "%s wanted %s near %s (closest %s)" % [step, node_id, pos, _node_label(node)])
		if match:
			node = match
	if dest != "":
		check(_gate_toward(g, pos, dest), "%s should point toward %s" % [step, dest])
	check(not _buried(g, pos), "%s marker is inside geometry (%s)" % [step, pos])
	check(_standable(g, pos), "%s marker is not a standing spot (%s)" % [step, pos])
	var mini := g.find_child("Minimap", true, false)
	check(mini != null, "%s map marker is missing" % step)
	if mini:
		var pin: Vector2 = mini.quest_at
		check(pin.distance_to(Vector2(pos.x, pos.z)) < 1.5, "%s map pin %s != %s" % [step, pin, pos])
	print("[storyline] %s -> %s" % [step, _node_label(node)])


func _match_near(g: Node, at: Vector3, id: String) -> Node3D:
	var best: Node3D = null
	var best_d := 4.0
	for n in g.find_children("*", "Node3D", true, false):
		if not _node_is(n, id):
			continue
		var d := (n as Node3D).global_position.distance_to(at)
		if d < best_d:
			best = n
			best_d = d
	return best


func _node_near(g: Node, at: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := 2.5
	for n in g.find_children("*", "Node3D", true, false):
		var d := (n as Node3D).global_position.distance_to(at)
		if d < best_d:
			best = n
			best_d = d
	return best


func _node_is(n: Node3D, id: String) -> bool:
	if n == null:
		return false
	if String(n.name).to_lower() == id.to_lower() or String(n.name).to_lower().begins_with(id.to_lower()):
		return true
	if n is Npc and String(n.get("speaker")) == id:
		return true
	if n is QuestPickup and String((n as QuestPickup).item_id) == id:
		return true
	for key in ["enemy", "lab_boss", "boss"]:
		if String(n.get_meta(key, "")) == id:
			return true
	if id == "breach_warden" and String(n.name) == "boss_dais":
		return true
	if id == "the_filth" or id == "joes_discards":
		return String(n.name) == "north_ledge" or String(n.get_meta(&"enemy", "")) == "the_filth"
	if id == "bed" and "bed" in String(n.name).to_lower():
		return true
	return false


func _node_label(n: Node) -> String:
	if n == null:
		return "<none>"
	var extra := ""
	if n is Npc:
		extra = ":" + String(n.get("speaker"))
	return "%s%s" % [n.name, extra]


func _gate_toward(g: Node, at: Vector3, dest: String) -> bool:
	var here := String(g.call(&"here_id"))
	var hop := ""
	var intro: IntroDirector = g.intro
	if intro and intro.target_point() != null:
		hop = String(IntroDirector.ROUTE.get(here, {}).get(dest, ""))
		if dest == "old_oak" and here == "town_square":
			hop = "old_oak"
	else:
		hop = String(QuestWaypoint.HOP.get(here, {}).get(dest, ""))
		if dest == "old_oak":
			for gt in g.gates:
				if gt.target == "bobs_lab" and gt.global_position.distance_to(at) < 1.5:
					return true
	for gt in g.gates:
		if gt.global_position.distance_to(at) < 1.5 and (gt.target == hop or gt.target == dest):
			return true
	return false


func _space(g: Node) -> PhysicsDirectSpaceState3D:
	var w: World3D = g.get_world_3d()
	return w.direct_space_state if w else null


func _overlaps(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = at
	q.collision_mask = 1
	return not space.intersect_point(q, 1).is_empty()


func _buried(g: Node, at: Vector3) -> bool:
	var space := _space(g)
	if space == null:
		return true
	return _overlaps(space, at + Vector3(0, 0.05, 0)) and _overlaps(space, at - Vector3(0, 0.05, 0))


func _standable(g: Node, at: Vector3) -> bool:
	var space := _space(g)
	if space == null:
		return false
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.6, 0), at + Vector3(0, -3.0, 0), 1)
	if space.intersect_ray(ray).is_empty():
		return false
	var chest := PhysicsPointQueryParameters3D.new()
	chest.position = at + Vector3(0, 0.9, 0)
	chest.collision_mask = 1
	return space.intersect_point(chest, 1).is_empty()
