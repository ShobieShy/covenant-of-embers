extends TestCase
## 0.9.2: one tracked quest, main versus side, the Choir quest, and saved bounties.


func test_main_tracks_and_side_does_not_steal() -> void:
	var f := StoryFlags.new()
	var q := QuestLog.create(f)
	check(q.kind_of("joes_marks") == "side" and q.kind_of("the_landfill") == "main", "kinds")
	f.set_flag("permit_given")
	check(q.tracked == "a_new_home", "the main quest is tracked")
	f.set_flag("starter_gear_given")
	check(q.tracked == "the_landfill", "the next main takes the tracker")
	f.set_flag("verdant_met")
	check(q.state("joes_marks") == "active" and q.tracked != "joes_marks", "a side quest does not steal it")
	q.track("joes_marks")
	check(q.tracked == "joes_marks" and q.tracker_text().contains("Joe"), "Track can follow the side quest")
	check(q.recommended("the_slagworks") == 34, "Forgemaw's level")
	check(q.recommended("the_sunken_ruins") == 46, "the Choir's level")


func test_sunken_starts_when_forgemaw_is_known() -> void:
	var q := QuestLog.create()
	q.known_bosses = ["forgemaw"]
	q.check_auto_start()
	check(q.state("the_sunken_ruins") == "active" and q.tracked == "the_sunken_ruins", "Choir quest starts")
	q.known_bosses = ["forgemaw", "drowned_choir"]
	var q2 := QuestLog.create()
	q2.known_bosses = ["forgemaw", "drowned_choir"]
	q2.check_auto_start()
	check(q2.state("the_sunken_ruins") == "done", "already dead, already done")


func test_old_save_without_tracked_still_loads() -> void:
	var f := StoryFlags.new()
	var q := QuestLog.create(f)
	f.set_flag("permit_given")
	var d := q.to_dict()
	d.erase("tracked")
	var q2 := QuestLog.create()
	q2.from_dict(d)
	check(q2.state("a_new_home") == "active" and q2.tracked == "a_new_home", "missing tracked picks the main quest")
	check(SaveGame.VERSION == 1, "save version stays 1")


func test_bounties_round_trip_and_character_file() -> void:
	var b := Bounties.new()
	b.note("heap")
	b.note("heap")
	var b2 := Bounties.new()
	b2.from_dict(b.to_dict())
	var p := Player.new()
	check(b2.claim(p, "heap"), "saved count still pays")
	var path := CharacterSave.path_for("side carry")
	check(CharacterSave.write(p, path) == OK, "plain character")
	var raw: Dictionary = SaveGame.read(path)["data"]
	check((raw["progress"] as Dictionary).is_empty(), "no extra progress when there is none")
	var side := {"active": {"joes_marks": {"step": 0, "have": 1, "opt": {}}}, "done": []}
	check(CharacterSave.write(p, path, false, {"side": side, "bounties": b2.to_dict()}) == OK, "side written")
	raw = SaveGame.read(path)["data"]
	check(not (raw["progress"] as Dictionary).has("flags"), "the character file does not carry story flags")
	check(
		(raw["progress"] as Dictionary).has("side") and (raw["progress"] as Dictionary).has("bounties"),
		"side and bounties"
	)
	var loaded := CharacterSave.load_into(Player.new(), path)
	check((loaded["side"] as Dictionary)["active"].has("joes_marks"), "side comes back")
	check(int((loaded["bounties"] as Dictionary)["heap"]) == 0, "the claim spent the saved count")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	p.free()
