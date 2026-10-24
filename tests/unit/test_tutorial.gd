extends TestCase
## Step 67 done check: the tutorial quest chain end to end on gameplay events.
## Bob's arrival (starter_gear_given) -> reach the Landfill -> 3 Gnawers -> The Filth ->
## Joe's Trash -> filth_defeated -> talk to Bob -> tutorial_done + the Fast Travel crystal.

const E := ElementTable.Element


func _kill(id: String) -> void:
	var e := Enemy.create(EnemyTable.load_default().find(id), Transform3D.IDENTITY)
	GameEvents.bus().enemy_killed.emit(e, E.FIRE)
	e.free()


func test_chain() -> void:
	var flags := StoryFlags.new()
	var q := QuestLog.create(flags)
	var d := QuestDriver.make(q)
	runner_tree.root.add_child(d)
	check(QuestDriver.reach_id("midden") == "landfill", "the Midden is the Landfill")
	flags.set_flag("permit_given")
	d.reached("old_oak")
	check(q.state("a_new_home") == "done", "A New Home done in the Oak")
	flags.set_flag("bob_arrived")
	flags.set_flag("starter_gear_given")  # MentorArrival
	check(q.state("the_landfill") == "active", "Bob's task starts")
	_kill("gnawer")
	check(q.current_objective("the_landfill").get("kind") == "reach", "kills before the Landfill don't count")
	d.reached("midden")
	for i in 3:
		_kill("gnawer")
	check(q.current_objective("the_landfill").get("target") == "the_filth", "then The Filth")
	GameEvents.bus().quest_item_collected.emit(null, "joes_discards")
	check(q.state("the_landfill") == "active", "the trash only counts after the boss")
	_kill("the_filth")
	GameEvents.bus().quest_item_collected.emit(null, "joes_discards")
	check(q.state("the_landfill") == "done" and flags.has("filth_defeated"), "Landfill done")
	check(q.state("report_to_bob") == "active", "report to Bob")
	var ft := FastTravel.new(flags)
	check(not ft.unlocked(), "no fast travel yet")
	d.talked("Bob")
	check(q.state("report_to_bob") == "done" and flags.has("tutorial_done"), "tutorial done")
	check(ft.unlocked(), "Bob's crystal unlocks fast travel")
	var saved := q.to_dict()
	var q2 := QuestLog.create(StoryFlags.new())
	q2.from_dict(saved)
	check(q2.state("report_to_bob") == "done" and q2.flags.has("tutorial_done"), "chain saved")
	d.free()
