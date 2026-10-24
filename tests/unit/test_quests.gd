extends TestCase
## Step 63 done check: quests, tracker and clue log.
##  - quests.toml loads; bad data rejected;
##  - flags auto-start the chain; kill/collect/talk/reach objectives progress in order;
##  - completion pays xp / dust, sets flags (starting the next quest) and adds a clue;
##  - tracker / clue log text follow; save round-trip through SaveGame progress JSON.


func test_loads_and_rejects() -> void:
	var q := QuestLog.create()
	check(q.order.size() == 3 and q.clue_defs.size() == 3, "3 quests, 3 clues")
	var bad := QuestLog.new()
	bad.flags = StoryFlags.new()
	check(bad.load_text('[[quest]]\nid = "x"') != "", "no objectives rejected")
	check(
		bad.load_text('[[quest]]\nid = "x"\n[[objective]]\nquest = "x"\nkind = "dance"\ntarget = "y"') != "", "bad kind"
	)


func test_progress_and_rewards() -> void:
	var f := StoryFlags.new()
	var q := QuestLog.create(f)
	var p := Player.new()
	q.player = p
	var xp0 := p.progression.total_xp
	f.set_flag("permit_given")
	check(q.state("a_new_home") == "active", "auto-start on permit")
	q.notify("reach", "landfill")
	check(q.state("a_new_home") == "active", "wrong target ignored")
	q.notify("reach", "old_oak")
	check(
		q.state("a_new_home") == "done" and f.has("old_oak_unlocked") and q.clues.has("joes_trash"),
		"done + flag + clue"
	)
	f.set_flag("starter_gear_given")
	q.notify("kill", "gnawer")
	check(q.active["the_landfill"]["step"] == 0, "kill before reach does not count")
	q.notify("reach", "landfill")
	q.notify("kill", "gnawer", 2)
	check(q.tracker_text().contains("Clear the Gnawers (2/3)"), "tracker 2/3: %s" % q.tracker_text())
	q.notify("kill", "gnawer")
	q.notify("collect", "joes_discards")
	check(q.state("the_landfill") == "done" and f.has("filth_defeated"), "landfill done")
	check(q.state("report_to_bob") == "active", "next quest auto-starts")
	check(p.inventory.dust >= 50 and p.progression.total_xp > xp0, "xp + dust paid")
	q.notify("talk", "Bob")
	check(q.state("report_to_bob") == "done" and f.has("tutorial_done") and q.clues.size() == 3, "chain done")
	check(q.clue_log_text().contains("Not Random"), "clue log")
	p.free()


func test_save_round_trip() -> void:
	var f := StoryFlags.new()
	var q := QuestLog.create(f)
	f.set_flag("permit_given")
	q.notify("reach", "old_oak")
	f.set_flag("starter_gear_given")
	q.notify("reach", "landfill")
	q.notify("kill", "gnawer")
	var json := JSON.stringify({"progress": {"quests": q.to_dict()}})
	var back: Dictionary = JSON.parse_string(json)
	var q2 := QuestLog.create()
	q2.from_dict(back["progress"]["quests"])
	check(q2.state("a_new_home") == "done" and q2.state("the_landfill") == "active", "states restored")
	check(
		int(q2.active["the_landfill"]["step"]) == 1 and int(q2.active["the_landfill"]["have"]) == 1, "progress restored"
	)
	check(q2.flags.has("old_oak_unlocked") and q2.clues.has("joes_trash"), "flags + clues restored")
	check(q2.tracker_text() == q.tracker_text(), "same tracker")
	var ui := QuestTrackerUI.new()
	runner_tree.root.add_child(ui)
	ui.bind(q2)
	check(ui.tracker.text.contains("Trash Talk"), "tracker UI")
	ui.toggle_clue_log()
	check(ui.clue_panel.visible and ui.clue_label.text.contains("Joe's Trash"), "clue log UI")
	ui.queue_free()
