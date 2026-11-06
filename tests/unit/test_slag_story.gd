extends TestCase
## U5: the Scrap-spirit's two lines and the three slag seals. Act II marks stay put.


func test_spirit_lines_and_quests() -> void:
	DialogueDB.bosses = []
	var flags := StoryFlags.new()
	var db := DialogueDB.load_default()
	var intro := db.pick("Scrap-spirit", flags)
	check(intro.get("id", "") == "scrap_intro", "the intro matches before Forgemaw")
	var q := QuestLog.create(flags)
	q.known_bosses = []
	var runner := DialogueRunner.new(db, flags)
	check(runner.start("Scrap-spirit"), "the spirit can be talked to")
	while runner.advance():
		pass
	check(flags.has("scrap_met"), "the talk sets scrap_met")
	check(q.state("the_slagworks") == "active", "the kill quest starts")
	check(q.current_objective("the_slagworks")["target"] == "forgemaw", "the objective is Forgemaw")
	check(q.state("joes_seals") == "active", "the seal quest starts")
	DialogueDB.bosses = ["forgemaw"]
	var after := db.pick("Scrap-spirit", flags)
	check(after.get("id", "") == "scrap_after", "post-boss wins once Forgemaw is in bosses")
	check(db.pick("Scrap-spirit", flags).get("id", "") != "scrap_intro", "the intro does not match")
	var again := DialogueRunner.new(db, flags)
	again.start("Scrap-spirit")
	while again.advance():
		pass
	again.start("Scrap-spirit")
	check(again.text() == String((after["repeats"] as Array)[0]), "the repeat line is the second talk")
	var late_flags := StoryFlags.new()
	var late := QuestLog.create(late_flags)
	late.known_bosses = ["forgemaw"]
	late_flags.set_flag("scrap_met")
	check(late.state("the_slagworks") == "done", "the kill is already complete")
	DialogueDB.bosses = []


func test_seals_any_order_and_marks_stay_separate() -> void:
	var flags := StoryFlags.new()
	var q := QuestLog.create(flags)
	flags.set_flag("seal:railhead_rail")
	flags.set_flag("scrap_met")
	check(q.active.has("joes_seals"), "the seal quest starts")
	check(int(q.active["joes_seals"]["have"]) == 1, "a seal already burned counts")
	check(q.state("joes_marks") == "available" or not q.active.has("joes_marks"), "seals do not start the mark quest")
	var mark_flags := StoryFlags.new()
	mark_flags.set_flag("seal:railhead_rail")
	mark_flags.set_flag("verdant_met")
	var seals_only := QuestLog.create(mark_flags)
	seals_only.check_auto_start()
	check(seals_only.active.has("joes_marks"), "the mark quest still starts from verdant_met")
	check(int(seals_only.active["joes_marks"]["have"]) == 0, "a seal flag does not increase the mark count")
	var bark := StoryFlags.new()
	bark.set_flag("mark:sump_bark")
	bark.set_flag("verdant_met")
	var marks := QuestLog.create(bark)
	marks.check_auto_start()
	check(int(marks.active["joes_marks"]["have"]) == 1, "a mark flag still seeds Act II")
	var fresh := StoryFlags.new()
	var done := QuestLog.create(fresh)
	for id in ["crucible_rail", "railhead_rail", "overlook_rail"]:
		fresh.set_flag("seal:" + id)
	fresh.set_flag("scrap_met")
	check(done.state("joes_seals") == "done", "three seals in any order finish the quest")
	var floor := SlagworksFloor.make(11, LabyrinthState.fresh(2))
	runner_tree.root.add_child(floor)
	floor.place_story(fresh)
	check(floor.get_node_or_null("ScrapSpirit") != null, "the spirit is on the Overlook")
	check(floor.get_node_or_null("Seal_overlook_rail") == null, "a collected seal does not spawn again")
	var other := SlagworksFloor.make(9, LabyrinthState.fresh(2))
	other.place_story(StoryFlags.new())
	check(other.get_node_or_null("ScrapSpirit") == null, "the spirit is not on the Railhead")
	check(other.get_node_or_null("Seal_railhead_rail") != null, "the Railhead seal spawns when the flag is unset")
	var crucible := SlagworksFloor.make(13, LabyrinthState.fresh(2))
	crucible.place_story(StoryFlags.new())
	check(crucible.get_node_or_null("ScrapSpirit") == null, "the spirit is not on the crucible")
	floor.free()
	other.free()
	crucible.free()
