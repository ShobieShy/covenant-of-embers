extends TestCase
## 0.9.1: the Echo menu opens on Esc, switches tabs, and skips motion when reduced motion is on.


func test_tabs_and_keys() -> void:
	var e := EchoMenu.new()
	runner_tree.root.add_child(e)
	e.open("map")
	check(e.visible and runner_tree.paused and e.tab_id() == "map", "opens on Map")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.pressed = true
	e._unhandled_input(key)
	check(e.tab_id() == "missions", "E moves to the next tab")
	key.physical_keycode = KEY_Q
	e._unhandled_input(key)
	check(e.tab_id() == "map", "Q moves back")
	e.press("character")
	check(e.tab_id() == "character" and e.character_label.text == "No character.", "character tab")
	e.press("resume")
	check(not e.visible and not runner_tree.paused, "resume unpauses")
	e.free()


func test_missions_read_the_current_log() -> void:
	var flags := StoryFlags.new()
	var log := QuestLog.create(flags)
	flags.set_flag("permit_given")
	log.check_auto_start()
	var e := EchoMenu.new()
	e.quests = log
	runner_tree.root.add_child(e)
	e.open("missions")
	check(e.mission_detail.text.contains("A New Home"), "active quest title")
	check(e.mission_detail.text.contains("Find the Old Oak"), "current step")
	check(e.mission_detail.text.contains("20 XP"), "reward already in the data")
	e.free()
	runner_tree.paused = false


func test_reduced_motion_skips_the_slide() -> void:
	UiAnim.force_motion = true
	UiAnim.reduced_motion = true
	var e := EchoMenu.new()
	runner_tree.root.add_child(e)
	e.open("settings")
	check(e._page_tween == null and e.slide.position == Vector2.ZERO, "no page slide")
	check(e.underline.size.y == 2.0, "underline is thin")
	Accessibility.high_contrast = true
	e.show_tab(0)
	check(e.underline.size.y == 4.0, "high contrast thickens the underline")
	Accessibility.high_contrast = false
	UiAnim.reduced_motion = false
	UiAnim.force_motion = false
	e.free()
	runner_tree.paused = false


func test_bounty_claim_is_session_only() -> void:
	var e := EchoMenu.new()
	runner_tree.root.add_child(e)
	e.bounties.note("gnawer")
	e.bounties.note("gnawer")
	e.bounties.note("gnawer")
	var p := Player.new()
	p.inventory.gold = 0
	e.player = p
	e._claim("gnawer")
	check(p.inventory.gold == 12, "claim pays the row")
	check(not e.bounties.claim(p, "gnawer"), "the count was spent")
	p.free()
	e.free()
	runner_tree.paused = false
