extends TestCase
## 0.3.1 P6 (L1): main menu title fade, hover nudge and save-slot cards.


func test_slot_card() -> void:
	var n := SaveGame.SLOTS
	var path := SaveGame.slot_path(n)
	if FileAccess.file_exists(path):
		check(true, "slot %d in use here; card test skipped" % n)
		return
	check(MainMenu.slot_card(n).ends_with("(empty)"), "empty slot card")
	var d := {
		"version": SaveGame.VERSION,
		"saved_at": "2026-10-28T17:05:00",
		"player": {"level": 12, "name": "Ash"},
		"progress": {"level_id": "old_oak"},
	}
	check(SaveGame.write(d, path) == OK, "wrote a test save")
	var c := MainMenu.slot_card(n)
	check(c.begins_with("Slot %d\n" % n), "slot line")
	check(
		c.contains("Ash, Lv 12") and c.contains("The Old Oak") and c.contains("Saved 2026-10-28"),
		"card: %s" % c
	)
	check(not c.contains("0m") and not c.contains("h "), "no playtime line when the save has none: %s" % c)
	d["playtime_s"] = 0.0
	check(SaveGame.write(d, path) == OK, "wrote a zero playtime")
	var zero := MainMenu.slot_card(n)
	check(not zero.contains("0m"), "zero playtime stays off the card: %s" % zero)
	d["playtime_s"] = 3600 + 23 * 60
	check(SaveGame.write(d, path) == OK, "wrote an hour of play")
	var played := MainMenu.slot_card(n)
	check(played.contains("1h 23m"), "playtime on the card: %s" % played)
	check(played.contains("Ash, Lv 12") and played.contains("Saved 2026-10-28"), "the rest of the card stays")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for f in [path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func test_title_and_hover() -> void:
	var m: MainMenu = (load(GameFlow.MENU) as PackedScene).instantiate()
	runner_tree.root.add_child(m)
	check(
		m.title_label != null and is_equal_approx(m.title_label.modulate.a, 1.0),
		"title shown (instant headless)"
	)
	var b: Button = m.buttons["settings"]
	b.mouse_entered.emit()
	check(m.hovers == 1, "hover nudges")
	check(m.slot_buttons[0].text.begins_with("Slot 1"), "slot card text")
	m.free()
