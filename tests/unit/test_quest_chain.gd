extends TestCase
## A new game walks the main quest chain on closed levels. A step fails when the
## player has no active quest, or the scene is an open zone or a dead end.

const FILE := "user://test_quest_chain_save.json"


func _reset() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.path_override = FILE
	GameFlow.load_save = false
	GameFlow.intro_mode = ""
	GameFlow.level_id = "midden"
	for f in [FILE, FILE + ".bak", FILE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _restore() -> void:
	_reset()
	GameFlow.dry_run = false
	GameFlow.path_override = ""
	GameFlow.select_slot(1)


func _game(level: String) -> Node:
	GameFlow.level_id = level
	GameFlow.load_save = false
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(4000, 0, 0)
	runner_tree.root.add_child(g)
	return g


func _gate(g: Node, target: String) -> LevelGate:
	for gt in g.gates:
		if gt.target == target:
			return gt
	return null


func _closed(g: Node, id: String) -> void:
	var lvl := g.get_node("Level")
	var terrain := lvl.get_node_or_null("Terrain")
	if id == "town_square" or id == "midden" or id == "mage_association":
		check(terrain != null, "%s is a terrain level" % id)
	else:
		check(terrain == null, "%s is a closed level" % id)
	check(g.gates.size() > 0, "%s has a way out" % id)


func _active(q: QuestLog) -> PackedStringArray:
	var out := PackedStringArray()
	for id in q.order:
		if q.state(id) == "active":
			out.append(id)
	return out


func _require_quest(q: QuestLog, step: String) -> void:
	check(not _active(q).is_empty(), "%s left no active quest (%s)" % [step, q.done])


func test_main_chain_from_a_new_game() -> void:
	_reset()
	GameFlow.new_run(null, GameFlow.INTRO_PLAY)
	check(GameFlow.level_id == "mage_association", "a new game starts in the Mage Association")
	var assoc := _game("mage_association")
	_closed(assoc, "mage_association")
	check(_gate(assoc, "town_square") != null, "the front door leads to town")
	assoc.free()
	var town := _game("town_square")
	_closed(town, "town_square")
	check(town.get_node_or_null("Level/Props/windmill") == null, "the square has no windmill")
	var tailor: Npc = null
	for n in town.npcs:
		if n.speaker == "Tailor":
			tailor = n
	check(tailor != null, "the Tailor is in the square")
	tailor.talk()
	town.dialogue.end()
	check(town.vendor_ui != null and town.vendor_ui.visible, "the Tailor's shop opens")
	check(_gate(town, "mage_association") != null and _gate(town, "midden") != null, "town doors")
	town.vendor_ui.close()
	town.free()
	var oak := _game("old_oak")
	_closed(oak, "old_oak")
	check(_gate(oak, "town_square") != null, "the oak room leads back to town")
	oak.free()
	var fill := _game("midden")
	_closed(fill, "midden")
	var lvl := fill.get_node("Level")
	check(String(lvl.get_meta("level_name", "")) == "The Landfill", "landfill banner name")
	check(WorldMap.level_name("midden") == "The Landfill", "map name")
	check(MainMenu.LOCATION_NAMES["midden"] == "The Landfill", "save label")
	check(String(FastTravel.info("landfill").get("name", "")) == "The Landfill", "waystone name")
	check(lvl.get_node_or_null("Waystones/landfill") != null, "a Landfill waystone stands here")
	var start := lvl.get_node("PlayerStart") as Node3D
	var breach_gate := _gate(fill, "breach")
	check(breach_gate != null, "a road to the real Breach")
	check(breach_gate.global_position.distance_to(start.global_position) > 8.0, "that road is not the arrival marker")
	for gt in fill.gates:
		for c in gt.get_children():
			if c is Label3D:
				var text := (c as Label3D).text.to_lower()
				check(not text.begins_with("gate: breach"), "arrival is not marked Breach (%s)" % text)
	check(WorldMap.level_name("breach") == "The Breach", "the Breach keeps its own name")
	fill.free()
	var breach := _game("breach")
	_closed(breach, "breach")
	check(String(breach.get_node("Level").get_meta("level_name", "")) == "The Breach", "Breach scene name")
	breach.free()
	var flags := StoryFlags.new()
	var q := QuestLog.create(flags)
	flags.set_flag("permit_given")
	_require_quest(q, "permit")
	q.notify("reach", "old_oak")
	flags.set_flag("starter_gear_given")
	_require_quest(q, "Bob's kit")
	q.notify("reach", "landfill")
	q.notify("kill", "gnawer", 3)
	q.notify("kill", "the_filth")
	q.notify("collect", "joes_discards")
	_require_quest(q, "the Filth")
	check(q.state("report_to_bob") == "active", "Bob's report stays open")
	check(q.state("the_breach") == "active", "the Filth hands off to the Breach")
	check(q.current_objective("the_breach").get("target") == "breach", "the north road is the next step")
	check(q.tracked == "report_to_bob", "Bob stays on the marker until the report is done")
	q.notify("talk", "Bob")
	_require_quest(q, "after Bob")
	check(q.state("report_to_bob") == "done", "the report is done")
	check(q.tracked == "the_breach" and q.current_objective("the_breach").get("target") == "breach", "then the crater")
	q.notify("reach", "breach")
	_require_quest(q, "the Breach")
	check(q.current_objective("the_breach").get("target") == "breach_warden", "the Warden is the last Breach step")
	q.notify("kill", "blightmaw_matriarch")
	check(q.current_objective("the_breach").get("target") == "breach_warden", "the Matriarch is not this quest")
	q.notify("kill", "breach_warden")
	check(q.state("the_breach") == "done" and flags.has("warden_defeated"), "the Warden opens the gate")
	flags.set_flag("labyrinth_entered")
	_require_quest(q, "Act I")
	check(q.tracked == "the_goblin_warrens", "Act I is tracked")
	check(q.current_objective("the_goblin_warrens").get("target") == "goblin_king", "Act I is the King")
	q.known_bosses = ["goblin_king"]
	q.notify("kill", "goblin_king")
	q.check_auto_start()
	check(q.state("the_goblin_warrens") == "done", "the King completes Act I")
	check(q.state("the_overgrown_deep") == "active", "Act II starts from the King's death")
	q.known_bosses = ["goblin_king", "blightmaw_matriarch"]
	q.notify("kill", "blightmaw_matriarch")
	q.check_auto_start()
	check(q.state("the_overgrown_deep") == "done", "the Matriarch completes Act II")
	check(q.state("the_slagworks") == "active", "Act III starts from the Matriarch")
	q.known_bosses = ["goblin_king", "blightmaw_matriarch", "forgemaw"]
	q.notify("kill", "forgemaw")
	q.check_auto_start()
	check(q.state("the_slagworks") == "done" and q.state("the_sunken_ruins") == "active", "Act IV starts from Forgemaw")
	q.known_bosses = ["goblin_king", "blightmaw_matriarch", "forgemaw", "drowned_choir"]
	q.notify("kill", "drowned_choir")
	q.check_auto_start()
	check(q.state("the_sunken_ruins") == "done", "the Choir completes Act IV")
	check(q.state("the_inverted_spire") == "active", "Act V starts from the Choir")
	q.notify("kill", "storm_warden")
	check(q.state("the_inverted_spire") == "done", "the Storm Warden completes Act V")
	check(q.tracked == "", "the trail has no further main quest")
	_restore()


func test_old_breach_save_waiting_on_the_matriarch() -> void:
	var open_gate := StoryFlags.new()
	var q := QuestLog.create(open_gate)
	q.vault_was_open = true
	var old := {
		"active": {"the_breach": {"step": 2, "have": 0}}, "done": ["a_new_home", "the_landfill", "report_to_bob"]
	}
	q.from_dict(old)
	check(q.state("the_breach") == "done" and open_gate.has("warden_defeated"), "an open vault finishes the old step")
	var waiting := StoryFlags.new()
	var q2 := QuestLog.create(waiting)
	q2.vault_was_open = false
	q2.from_dict(old)
	check(q2.state("the_breach") == "active", "a shut vault keeps the quest")
	check(q2.current_objective("the_breach").get("target") == "breach_warden", "it now waits on the Warden")


func test_waypoint_marks_the_vault_and_the_next_hop() -> void:
	var dais := Vector3(0, 1, -7)
	var survey := {"points": [{"id": "boss_dais", "at": dais}], "gates": [], "floor": 0}
	var at: Variant = QuestWaypoint.resolve("kill", "breach_warden", "breach", 0, survey)
	check(at is Vector3 and (at as Vector3).is_equal_approx(dais), "the Warden step marks the vault dais")
	var town := {
		"gates":
		[
			{"target": "bobs_lab", "at": Vector3(9, 0, 1)},
			{"target": "old_oak", "at": Vector3(3, 0, 4)},
			{"target": "midden", "at": Vector3(0, 0, 8)},
		],
		"points": [],
		"floor": 0,
	}
	var door: Variant = QuestWaypoint.resolve("reach", "old_oak", "town_square", 0, town)
	check(door is Vector3 and (door as Vector3).is_equal_approx(Vector3(9, 0, 1)), "A New Home marks the lab door")
	var stair := Vector3(2, 0, 2)
	var down := {"points": [], "gates": [], "stairs_down": stair, "floor": 1}
	var hop: Variant = QuestWaypoint.resolve("kill", "goblin_king", "labyrinth", 1, down)
	check(hop is Vector3 and (hop as Vector3).is_equal_approx(stair), "Act I marks the downward stair")
	var done: Variant = QuestWaypoint.resolve("kill", "goblin_king", "labyrinth", 5, {"points": [], "gates": [], "floor": 5})
	check(done == null, "no boss and no stair leaves no mark")
