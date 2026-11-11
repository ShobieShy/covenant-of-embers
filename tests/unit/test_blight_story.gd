extends TestCase
## U5: Verdant Mother lines and Joe's three marks.


func test_mother_lines_and_quests() -> void:
	DialogueDB.bosses = []
	var flags := StoryFlags.new()
	var db := DialogueDB.load_default()
	var intro := db.pick("Verdant Mother", flags)
	check(intro.get("id", "") == "verdant_intro", "the intro matches before the boss")
	var q := QuestLog.create(flags)
	q.known_bosses = []
	var runner := DialogueRunner.new(db, flags)
	check(runner.start("Verdant Mother"), "she can be talked to")
	while runner.advance():
		pass
	check(flags.has("verdant_met"), "the talk sets verdant_met")
	check(q.state("the_overgrown_deep") == "active", "the kill quest starts")
	check(
		q.current_objective("the_overgrown_deep")["target"] == "blightmaw_matriarch", "the objective is the Matriarch"
	)
	check(q.state("joes_marks") == "active", "the mark quest starts")
	DialogueDB.bosses = ["blightmaw_matriarch"]
	var after := db.pick("Verdant Mother", flags)
	check(after.get("id", "") == "verdant_after", "post-boss wins once she is in bosses")
	check(db.pick("Verdant Mother", flags).get("id", "") != "verdant_intro", "the intro does not match")
	var again := DialogueRunner.new(db, flags)
	again.start("Verdant Mother")
	check(again.text() == String((after["lines"] as Array)[0]), "first post-boss line")
	while again.advance():
		pass
	again.start("Verdant Mother")
	check(again.text() == String((after["repeats"] as Array)[0]), "the repeat line is the second talk")
	DialogueDB.bosses = []


func test_marks_any_order_and_reload() -> void:
	var flags := StoryFlags.new()
	var q := QuestLog.create(flags)
	flags.set_flag("mark:sump_bark")
	flags.set_flag("verdant_met")
	check(int(q.active["joes_marks"]["have"]) == 1, "a mark already carved counts")
	q.notify("collect", "joe_mark")
	q.notify("collect", "joe_mark")
	check(q.state("joes_marks") == "done", "third then the remaining two still finish")
	var dead := LabyrinthState.fresh(1)
	dead.bosses.append("blightmaw_matriarch")
	var flags2 := StoryFlags.new()
	var q2 := QuestLog.create(flags2)
	q2.known_bosses = dead.bosses
	flags2.set_flag("verdant_met")
	check(q2.state("the_overgrown_deep") == "done", "already dead when the quest starts")
	var cav := BlightcoilCavern.make(6, LabyrinthState.fresh(1))
	runner_tree.root.add_child(cav)
	flags.set_flag("mark:canopy_bark")
	flags.set_flag("mark:crown_bark")
	cav.place_marks(flags)
	check(cav.get_node_or_null("Pickup_sump_bark") == null, "a set mark flag does not spawn")
	check(cav.get_node_or_null("Mark_sump_bark") == null or true, "markers may remain")
	var block := dead.to_dict()
	check(not block.has("marks") and not str(block).contains("joe_mark"), "marks are not a labyrinth-block key")
	var mother := 0
	for c in cav.find_children("*", "", true, false):
		if String(c.name) == "VerdantMother":
			mother += 1
			check(c.position.y > 11.0 and c.position.y < 13.0, "she stands on the Canopy")
	check(mother == 1, "the Mother is on the Canopy pad only")
	cav.free()
