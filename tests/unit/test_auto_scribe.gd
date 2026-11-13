extends TestCase
## The Clerk's Auto-Scribe™. Before the grant, Esc only pauses. After it, the menu opens.
## A finished intro picks the flag up without a save-version bump.


func test_pause_until_the_clerk() -> void:
	var flags := StoryFlags.new()
	var e := EchoMenu.new()
	e.flags = flags
	runner_tree.root.add_child(e)
	e.open("map")
	check(not e.is_open(), "the scribe stays shut")
	e.open()
	check(e.is_open() and runner_tree.paused and e.tab_id() == "settings", "Esc still pauses on Settings")
	check(e.title_label.text == "Paused", "it is not the scribe yet")
	var quit := false
	for b in e.find_children("*", "Button", true, false):
		if (b as Button).text == "Quit":
			quit = true
	check(quit, "quit is on the pause screen")
	e.close()
	flags.set_flag(IntroDirector.SCRIBE)
	e.open("map")
	check(e.is_open() and e.tab_id() == "map" and e.title_label.text == "Auto-Scribe™", "the scribe opens")
	e.free()
	runner_tree.paused = false


func test_old_intro_save_receives_it() -> void:
	var f := StoryFlags.new()
	f.set_flag(IntroDirector.DONE)
	IntroDirector.ensure_scribe(f)
	check(f.has(IntroDirector.SCRIBE), "a finished intro has the scribe")
	var early := StoryFlags.new()
	early.set_flag("joe_expelled")
	IntroDirector.ensure_scribe(early)
	check(not early.has(IntroDirector.SCRIBE), "before the Clerk, still locked")
	check(SaveGame.VERSION == 1, "save version stays 1")
