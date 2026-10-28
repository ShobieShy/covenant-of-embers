extends TestCase
## Labyrinth L2a: progress.labyrinth save block, migration of old saves, per-floor state.

const FIX := "res://tests/fixtures/saves_v1/"


func _fixture(n: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIX + n + ".json"))


func test_old_saves_get_a_block() -> void:
	var town := LabyrinthState.from_save(_fixture("town_square"))
	check(
		town.deepest == 0 and town.cleared.is_empty() and town.save_seed > 0,
		"no Breach visit: nothing reached"
	)
	var br := LabyrinthState.from_save(_fixture("breach"))
	check(
		br.deepest == 1, "a save that visited the Breach has floor 1 reached (got %d)" % br.deepest
	)
	check(LabyrinthState.from_save({}).save_seed > 0, "empty save gets a seed")


func test_v1_fixture_round_trip() -> void:
	var s := LabyrinthState.from_save(_fixture("labyrinth"))
	check(s.save_seed == 987654 and s.deepest == 3 and s.cleared == [1, 2], "fields")
	check(
		s.remix_of(1) == 1 and s.chest_open(1, "c_hoard") and s.elite_dead(2, "war_chief"),
		"floor state"
	)
	var again := LabyrinthState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	check(JSON.stringify(again.to_dict()) == JSON.stringify(s.to_dict()), "JSON round trip")
	check(
		s.floor_seed(1) == FloorGen.floor_seed(987654, "warrens", 1, 1), "floor seed uses the remix"
	)


func test_sanitises_bad_data() -> void:
	var s := LabyrinthState.from_dict(
		{
			"save_seed": -5,
			"deepest": -2,
			"cleared": [0, 2, 2, "x"],
			"floors": {"0": {}, "a": 1, "3": {"chests": [1, 1]}}
		}
	)
	check(s.save_seed == 1 and s.deepest == 0, "clamped")
	check(s.cleared == [2], "cleared deduped, bad ids dropped (%s)" % [s.cleared])
	check(s.floors.keys() == ["3"] and s.floors["3"]["chests"] == ["1"], "bad floors dropped")


func test_progress_rules() -> void:
	var s := LabyrinthState.fresh(42)
	check(not s.remix(1), "an uncleared floor can't be remixed")
	s.reach(2)
	s.open_chest(1, "a")
	s.kill_elite(1, "e")
	s.clear_floor(1)
	check(s.deepest == 2 and s.cleared == [1], "reach and clear")
	var before := s.floor_seed(1)
	check(s.remix(1) and s.floor_seed(1) != before, "remix re-rolls the layout")
	check(not s.chest_open(1, "a") and not s.elite_dead(1, "e"), "remix restocks the floor")
	s.defeat_boss("goblin_king")
	s.defeat_boss("goblin_king")
	s.open_shortcut("willowbrook")
	check(s.bosses == ["goblin_king"] and s.shortcuts.size() == 1, "boss and gate")


const GAME_FILE := "user://test_labyrinth_save.json"
const GAME_STASH := "user://test_labyrinth_stash.json"


func _game(load_save: bool) -> Node:
	GameFlow.dry_run = true
	GameFlow.save_path = GAME_FILE
	Stash.shared_path = GAME_STASH
	GameFlow.level_id = "old_oak"
	GameFlow.load_save = load_save
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	g.position = Vector3(0, 0, -9000)
	runner_tree.root.add_child(g)
	return g


func test_running_game_saves_and_loads_the_block() -> void:
	var g := _game(false)
	var lab: LabyrinthState = g.labyrinth
	check(lab != null and lab.save_seed > 0, "a fresh run has a labyrinth block")
	lab.clear_floor(2)
	lab.open_chest(2, "hoard_nook")
	lab.defeat_boss("goblin_king")
	var seed_value := lab.save_seed
	check(g.save_game() == OK, "saved")
	g.free()
	var r := SaveGame.read(GAME_FILE)
	var blk: Dictionary = r["data"]["progress"].get("labyrinth", {})
	check(
		int(blk.get("v", 0)) == LabyrinthState.V and int(blk.get("save_seed", 0)) == seed_value,
		"block in the file"
	)
	check(
		int(blk.get("deepest", 0)) == 2 and blk.get("bosses", []) == ["goblin_king"],
		"progress in the file"
	)
	var g2 := _game(true)
	var lab2: LabyrinthState = g2.labyrinth
	check(
		lab2.save_seed == seed_value and lab2.cleared == [2] and lab2.chest_open(2, "hoard_nook"),
		"loaded back"
	)
	g2.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.load_save = false
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)
	Stash.shared_path = Stash.PATH
	for f in [GAME_FILE, GAME_STASH]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
