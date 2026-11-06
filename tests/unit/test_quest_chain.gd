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
	check(lvl.get_node_or_null("Terrain") == null, "%s is a closed level" % id)
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
	q.notify("talk", "Bob")
	_require_quest(q, "after Bob")
	check(q.current_objective("the_breach").get("target") == "breach", "Bob sends you to the Breach")
	q.notify("reach", "breach")
	_require_quest(q, "the Breach")
	check(q.current_objective("the_breach").get("target") == "labyrinth", "then into the Labyrinth")
	q.notify("reach", "labyrinth")
	_require_quest(q, "Act II")
	check(q.current_objective("the_breach").get("target") == "blightmaw_matriarch", "Act II stays on the quest log")
	_restore()
