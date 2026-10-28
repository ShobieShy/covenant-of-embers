extends TestCase
## Step 62 done check: data-driven dialogue.
##  - dialogue.toml loads; Bob, Crazy Joe and 3 townsfolk speak; bad data is rejected;
##  - branching on flags (Bob intro -> waiting -> after The Filth -> late; pity -> awe);
##  - repeat lines cycle after the first talk; choices set flags and play a reply;
##  - the DialogueUI follows the runner (speaker, text, choice buttons).


func _talk_through(r: DialogueRunner, speaker: String) -> Array:
	var said := []
	r.line_shown.connect(func(_s: String, t: String) -> void: said.append(t))
	r.start(speaker)
	var guard := 0
	while r.active and guard < 100:
		if r.awaiting_choice():
			r.choose(0)
		else:
			r.advance()
		guard += 1
	return said


func test_loads() -> void:
	var r := DialogueDB.from_file(DialogueDB.DEFAULT_PATH)
	check(not r.has("error"), "dialogue.toml loads (%s)" % r.get("error", ""))
	var db: DialogueDB = r.get("db")
	for sp in ["Bob", "Crazy Joe", "Bored Guard", "Potion Merchant", "Grizzled Patron"]:
		check(db.speakers().has(sp), "%s speaks" % sp)
	check(DialogueDB.from_text('[[dialogue]]\nid = "a"\nspeaker = "X"').has("error"), "no lines rejected")
	check(DialogueDB.from_text('[[choice]]\ndialogue = "nope"\ntext = "x"').has("error"), "unknown choice rejected")


func test_branching_on_flags() -> void:
	var f := StoryFlags.new()
	var r := DialogueRunner.new(null, f)
	check(r.db.pick("Bob", f)["id"] == "bob_intro", "first: intro")
	var said := _talk_through(r, "Bob")
	check(said[0] == "...Who are you? Why are you in my tree?", "Magewar's first Bob line")
	check(f.has("bob_met") and f.has("starter_gear_given") and f.has("asked_bob_why"), "intro + choice flags")
	check(r.db.pick("Bob", f)["id"] == "bob_waiting", "then: waiting")
	f.set_flag("filth_defeated")
	check(r.db.pick("Bob", f)["id"] == "bob_after_filth", "after The Filth")
	_talk_through(r, "Bob")
	check(f.has("crystal_given") and r.db.pick("Bob", f)["id"] == "bob_late", "then late")
	var g := StoryFlags.new()
	check(r.db.pick("Bored Guard", g)["id"] == "guard_pity", "guard pity at first")
	g.set_flag("filth_defeated")
	check(r.db.pick("Bored Guard", g)["id"] == "guard_awe", "awe later")


func test_repeat_lines() -> void:
	var r := DialogueRunner.new()
	var first := _talk_through(r, "Bored Guard")
	check(first.size() == 2, "first talk: full lines (%d)" % first.size())
	var reps := []
	for i in 3:
		reps.append_array(_talk_through(r, "Bored Guard"))
	check(reps.size() == 3, "repeats: one line per talk (%d)" % reps.size())
	if reps.size() == 3:
		check(reps[0] != reps[1] and reps[2] == reps[0], "repeats cycle")


func test_choice_and_ui() -> void:
	var r := DialogueRunner.new()
	var ui := DialogueUI.new()
	runner_tree.root.add_child(ui)
	ui.bind(r)
	r.start("Bob")
	check(ui.visible and ui.speaker_label.text == "Bob" and ui.text_label.text == r.text(), "UI shows the line")
	while not r.awaiting_choice() and r.active:
		r.advance()
	check(ui.button_texts().size() == 2, "2 choice buttons")
	r.choose(1)
	check(ui.text_label.text == "Good. Less talking, more landfill." and not r.flags.has("asked_bob_why"), "reply")
	r.advance()
	check(not r.active and not ui.visible, "ended, UI hidden")
	ui.queue_free()


func test_typewriter_skip_and_advance() -> void:  # 0.3.1 P3
	UiAnim.force_motion = true
	var r := DialogueRunner.new()
	var ui := DialogueUI.new()
	runner_tree.root.add_child(ui)
	ui.bind(r)
	r.start("Bob")
	var first := r.text()
	check(ui.typing() and ui.text_label.visible_characters == 0, "a line starts typing")
	check(not ui.arrow.visible, "no continue arrow while typing")
	ui._process(0.1)
	check(ui.text_label.visible_characters == int(DialogueUI.CPS * 0.1), "45 chars/s")
	check(ui.press_interact() and not ui.typing() and r.text() == first, "1st press completes")
	check(ui.arrow.visible, "the continue arrow shows once the line is done")
	ui.press_interact()
	check(r.text() != first or not r.active, "2nd press advances")
	while r.active and not r.awaiting_choice():
		ui.complete()
		r.advance()
	ui.complete()
	check(ui.button_texts().size() == 2 and not ui.arrow.visible, "choices after the line")
	check(DialogueUI.speaker_color("Bob") == DialogueUI.speaker_color("Bob"), "stable colour")
	DialogueUI.instant_text = true
	r.choose(0)
	check(not ui.typing(), "instant text setting skips the typewriter")
	DialogueUI.instant_text = false
	UiAnim.force_motion = false
	ui.free()


func test_choices_wait_for_typing() -> void:  # 0.3.1 P3
	UiAnim.force_motion = true
	var r := DialogueRunner.new()
	var ui := DialogueUI.new()
	runner_tree.root.add_child(ui)
	ui.bind(r)
	r.start("Bob")
	while r.active and not r.awaiting_choice():
		r.advance()
	check(ui.typing() and ui.button_texts().is_empty(), "choices held while the line types")
	ui._process(100.0)
	check(not ui.typing() and ui.button_texts().size() == 2, "shown when the line finishes")
	UiAnim.force_motion = false
	ui.free()
