extends TestCase
## Labyrinth L1: the GDScript floor generator matches tools/labyrinth_gen.py and keeps the rules.


func test_kit_loads() -> void:
	var kit := FloorGen.load_kit()
	check(not kit.has("error"), "warrens kit parses: %s" % kit.get("error", ""))
	check(kit["kit"]["id"] == "warrens" and int(kit["kit"]["act"]) == 1, "Act I kit")
	for kind in ["start", "normal", "elite", "rest", "secret", "exit"]:
		var n := 0
		for r: Dictionary in kit["room"]:
			if r["kind"] == kind:
				n += 1
				check(
					r["size"][0] <= kit["kit"]["slot"] and r["size"][1] <= kit["kit"]["slot"],
					"%s fits a slot" % r["id"]
				)
		check(n > 0, "kit has a %s room" % kind)


func test_matches_python_golden() -> void:
	var kit := FloorGen.load_kit()
	var lines := (
		FileAccess
		. get_file_as_string("res://tests/fixtures/labyrinth/warrens_golden.txt")
		. strip_edges()
		. split("\n")
	)
	check(lines.size() == 40, "40 golden floors")
	var bad := 0
	for line in lines:
		var p := line.split(" ", false, 3)
		var s := FloorGen.floor_seed(int(p[0]), "warrens", int(p[1]), int(p[2]))
		if FloorGen.signature(FloorGen.generate(kit, s)) != p[3]:
			bad += 1
			if bad == 1:
				fail(
					(
						"golden mismatch: %s\n  got %s"
						% [line, FloorGen.signature(FloorGen.generate(kit, s))]
					)
				)
	check(bad == 0, "all golden floors match (%d bad)" % bad)


func test_rules_on_many_seeds() -> void:
	var kit := FloorGen.load_kit()
	for s in 300:
		var fl := FloorGen.generate(kit, FloorGen.floor_seed(s, "warrens", 1 + s % 4))
		var kinds := {}
		var cells := {}
		for r: Dictionary in fl["rooms"]:
			kinds[r["kind"]] = int(kinds.get(r["kind"], 0)) + 1
			cells[r["cell"]] = true
		check(
			(
				kinds.get("start") == 1
				and kinds.get("exit") == 1
				and kinds.get("elite") == 1
				and kinds.get("rest") == 1
			),
			"one of each key room"
		)
		check(int(kinds.get("secret", 0)) in [1, 2], "1-2 secrets")
		check(cells.size() == fl["rooms"].size(), "no overlap")
		check(fl["edges"].size() == fl["rooms"].size() - 1, "tree")
		for i in fl["rooms"].size():
			check(not FloorGen.doors(fl, i).has(-1), "edges join neighbours")


func test_seed_is_stable_and_remix_changes() -> void:
	var kit := FloorGen.load_kit()
	var a := FloorGen.signature(FloorGen.generate(kit, FloorGen.floor_seed(7, "warrens", 1)))
	check(
		a == FloorGen.signature(FloorGen.generate(kit, FloorGen.floor_seed(7, "warrens", 1))),
		"same seed, same floor"
	)
	check(
		a != FloorGen.signature(FloorGen.generate(kit, FloorGen.floor_seed(7, "warrens", 1, 1))),
		"remix re-rolls"
	)
	check(
		a != FloorGen.signature(FloorGen.generate(kit, FloorGen.floor_seed(7, "warrens", 2))),
		"floors differ"
	)


func test_exit_doorway_never_opens_onto_stair_well() -> void:
	var kit := FloorGen.load_kit()
	var bad := 0
	var south := 0
	for s in 2000:
		for fno: int in kit["kit"]["floors"]:
			var fl := FloorGen.generate(kit, FloorGen.floor_seed(s, "warrens", fno))
			var ex := -1
			for i in fl["rooms"].size():
				if fl["rooms"][i]["kind"] == "exit":
					ex = i
			var d := FloorGen.doors(fl, ex)
			var row := int(fl["stair_row"])
			south += row
			if d.size() != 1 or (row == 0 and d.has(0)) or (row == 1 and d.has(2)):
				bad += 1
	check(bad == 0, "exit doorway clear of the stair row on 8000 floors (%d bad)" % bad)
	check(south > 0, "some floors move the hole south (%d)" % south)
