extends TestCase
## Step 69 done check: Elyria region states (barrier towns vs ~60 % wild land, wild areas
## locked), saved with the story flags and shown on the map screen.

const FILE := "user://test_world_map_save.json"
const STASH := "user://test_world_map_stash.json"


func test_states_saved() -> void:
	var m := WorldMap.new()
	check(absf(m.wild_share() - 0.6) < 0.001, "wild land ~60 %")
	for id in ["eldoria", "luminar", "willowbrook", "stonehaven"]:
		check(WorldMap.REGIONS[id]["barrier"], "%s under a barrier" % id)
	for id in ["whispering_woods", "shattered_peaks", "crimson_sea"]:
		check(m.state(id) == WorldMap.State.LOCKED, "%s locked" % id)
	check(m.visit_level("town_square") and m.state("eldoria") == WorldMap.State.VISITED, "visiting marks visited")
	check(not m.discover("eldoria"), "never lowered")
	check(m.discover("whispering_woods") and m.state("whispering_woods") == WorldMap.State.KNOWN, "discovered")
	var f := StoryFlags.new()
	f.from_dict(JSON.parse_string(JSON.stringify(m.flags.to_dict())))
	var m2 := WorldMap.new(f)
	check(
		m2.state("eldoria") == WorldMap.State.VISITED and m2.state("whispering_woods") == WorldMap.State.KNOWN, "saved"
	)
	check(m2.state("crimson_sea") == WorldMap.State.LOCKED, "still locked after load")


func test_shown_in_game() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	Stash.shared_path = STASH
	GameFlow.level_id = "old_oak"
	GameFlow.load_save = false
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(0, 0, -9000)
	runner_tree.root.add_child(g)
	check(g.world_map.state("eldoria") == WorldMap.State.VISITED, "the Old Oak visits Eldoria")
	g.open_map("old_oak")
	var ui: WorldMapUI = g.world_map_ui
	check(ui.visible and (ui.labels["eldoria"] as Label).text == "Eldoria (barrier town): Visited", "shown visited")
	check((ui.labels["crimson_sea"] as Label).text == "Crimson Sea (wild land): Locked", "shown locked")
	g.save_game()
	g.free()
	var r := SaveGame.read(FILE)
	check(int(r["data"]["progress"]["flags"].get("region:eldoria", 0)) == 3, "region state in the save")
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	Stash.shared_path = Stash.PATH
	for f in [FILE, STASH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
