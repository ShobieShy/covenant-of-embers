extends TestCase
## Step 65 done check: Eldoria (Town Square + Mage Association) loads headless, every exit
## links to a real level (and each level is reachable back), and every NPC is talkable.

const FILE := "user://test_town_save.json"
const TOWN := ["town_square", "mage_association"]


func _game(level: String) -> Node:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.level_id = level
	GameFlow.load_save = false
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(9000, 0, 0)
	runner_tree.root.add_child(g)
	return g


func _restore() -> void:
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


func _targets(level: String) -> Array:
	var g := _game(level)
	var out: Array = []
	for gt: LevelGate in g.gates:
		out.append(gt.target)
	g.free()
	return out


func test_all_exits_link() -> void:
	var links := {}
	for id in TOWN + ["midden"]:
		links[id] = _targets(id)
		for t in links[id]:
			check(GameFlow.LEVELS.has(t), "%s exit -> %s is a level" % [id, t])
	check(
		links["town_square"].has("mage_association") and links["town_square"].has("midden"),
		"square: Association + Landfill"
	)
	check(links["mage_association"] == ["town_square"], "Association leads back to the square")
	check(links["midden"].has("town_square"), "the Landfill leads back to town")
	var g := _game("town_square")
	check(GameFlow.id_of(g.get_node("Level")) == "town_square", "town square level id")
	(g.gates[0] as LevelGate).use()
	check(GameFlow.level_id == g.gates[0].target and GameFlow.load_save, "exit travels with the save")
	g.free()
	_restore()


func test_npcs_talkable() -> void:
	var db := DialogueDB.load_default()
	var speakers := db.speakers()
	for id in TOWN:
		var g := _game(id)
		check(not g.npcs.is_empty(), "%s has townsfolk" % id)
		for n: Npc in g.npcs:
			check(speakers.has(n.speaker), "%s has dialogue" % n.speaker)
			n.talk()
			check(g.dialogue.active and g.dialogue.speaker() == n.speaker, "%s talks" % n.speaker)
			g.dialogue.end()
		g.free()
	_restore()
