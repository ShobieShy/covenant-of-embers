extends TestCase
## Step 68 done check: waystones attune, the crystal travels between attuned points (with
## the autosave travel), and it is locked before the tutorial ends.

const FILE := "user://test_fast_travel_save.json"


func test_locked_attune_travel() -> void:
	var ft := FastTravel.new()
	var went: Array = []
	ft.traveled.connect(func(p: String, lv: String) -> void: went.append([p, lv]))
	check(ft.attune("town_market") and ft.attuned("town_gate") and not ft.attune("town_gate"), "market merges into the hub")
	check(not ft.attune("nowhere"), "unknown points refused")
	check(not ft.travel("town_gate") and ft.last_error.contains("no Teleportation"), "no crystal")
	ft.flags.set_flag(FastTravel.CRYSTAL)
	check(not ft.travel("town_gate") and ft.last_error.contains("activated"), "locked before the tutorial ends")
	ft.flags.set_flag(FastTravel.TUTORIAL_DONE)
	check(not ft.travel("breach") and ft.last_error.contains("attuned"), "unattuned refused")
	check(ft.travel("town_gate") and went == [["town_gate", "town_square"]], "travel to the hub")
	ft.attune("breach")
	ft.attune("landfill")
	ft.attune("landfill_camp")
	check(ft.destinations() == PackedStringArray(["town_gate", "breach"]), "hub and Breach, not the Landfill stones")
	check(ft.attuned("landfill"), "the camp stone merges into the Landfill stone")
	var f2 := StoryFlags.new()
	f2.from_dict(ft.flags.to_dict())
	check(FastTravel.new(f2).attuned("landfill"), "attunement saved with the flags")
	check(not ft.can_travel("slagworks_crucible"), "the crucible stone is refused until the pad is stepped on")
	check(int(FastTravel.info("slagworks_railhead")["floor"]) == 9, "railhead floor")
	check(int(FastTravel.info("warrens_hall")["floor"]) == 5, "warrens hall stays floor 5")


func test_in_game_waystone_and_map() -> void:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.level_id = "town_square"
	GameFlow.load_save = false
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(-9000, 0, 0)
	runner_tree.root.add_child(g)
	var p := g.get_node("Player") as Player
	var w: Waystone = g.waystone
	check(w != null and w.point == "town_gate", "town square has the town gate waystone")
	p.global_position = w.global_position
	check(w.check_attune() and g.fast_travel.attuned("town_gate"), "walking up attunes")
	g.fast_travel.attune("breach")
	g.open_map("town_gate")
	var ui: FastTravelUI = g.travel_ui
	check(ui.visible and p.ui_open, "map opens")
	check((ui.buttons["breach"] as Button).disabled, "locked before the tutorial ends (greyed)")
	check(not ui.press("breach"), "refused")
	check(g.world_map_ui.labels.has("line0"), "closed levels show the level sheet")
	g.story_flags.set_flag(FastTravel.CRYSTAL)
	g.story_flags.set_flag(FastTravel.TUTORIAL_DONE)
	g.open_map("town_gate")
	check(
		(ui.buttons["town_gate"] as Button).disabled and not (ui.buttons["breach"] as Button).disabled, "here greyed"
	)
	check(ui.press("breach") and not ui.visible and not p.ui_open, "travel closes the map")
	check(GameFlow.level_id == "breach" and GameFlow.load_save, "travelled to the Breach with the save")
	g.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))
