extends TestCase
## Step 76 done check: every Settings option survives save/load and is applied
## (player toggles, reduced motion, colour-blind palettes, subtitles).

const FILE := "user://test_settings.cfg"


func _player() -> Player:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 400, 2300), 0.0)
	return p


func _cleanup() -> void:
	Accessibility.reset()
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FILE))


func test_each_option_saved() -> void:
	var s := Settings.new()
	s.invert_y = true
	s.hip_fov = 95.0
	s.focus_toggle = true
	s.crouch_toggle = true
	s.reduced_motion = true
	s.head_bob = 0.3
	s.aim_sensitivity = 2.0
	s.master_volume = 0.5
	s.sfx_volume = 0.4
	s.music_volume = 0.2
	s.colorblind = Accessibility.Mode.TRITANOPIA
	s.subtitles = false
	s.subtitle_scale = 1.5
	check(s.save(FILE) == OK, "saved")
	var l := Settings.load_from(FILE)
	for k in s._options():
		check(l.get(k) == s.get(k), "option %s round-trips" % k)
	check(Settings.new()._options().size() == 17, "17 options (step 134: quality)")
	_cleanup()


func test_options_applied() -> void:
	var p := _player()
	var s := Settings.new()
	s.reduced_motion = true
	s.focus_toggle = true
	s.crouch_toggle = true
	s.invert_y = true
	s.colorblind = Accessibility.Mode.DEUTERANOPIA
	s.subtitles = false
	s.subtitle_scale = 2.0
	s.apply_to(p)
	check(p.feel.reduced_motion, "reduced motion wired")
	check(p.focus_toggle and p.crouch_toggle and p.invert_y, "toggles wired")
	check(Accessibility.colorblind == Accessibility.Mode.DEUTERANOPIA, "palette mode applied")
	check(not Accessibility.subtitles and Accessibility.font_size() == 32, "subtitles applied")
	p.queue_free()
	_cleanup()


func test_palettes_distinct_and_used() -> void:
	var rt := RarityTable.load_default()
	var et := ElementTable.load_default()
	var base_rare := rt.color("rare")
	var base_fire := et.color(ElementTable.Element.FIRE)
	for m in [Accessibility.Mode.DEUTERANOPIA, Accessibility.Mode.PROTANOPIA, Accessibility.Mode.TRITANOPIA]:
		Accessibility.colorblind = m
		var seen := {}
		for id in Rarity.IDS:
			seen[rt.color(id).to_html()] = true
		check(seen.size() == Rarity.IDS.size(), "rarity colours distinct in mode %d" % m)
		seen = {}
		for e in ElementTable.COUNT:
			seen[et.color(e).to_html()] = true
		check(seen.size() == ElementTable.COUNT, "element colours distinct in mode %d" % m)
	check(rt.color("rare") != base_rare or et.color(ElementTable.Element.FIRE) != base_fire, "palette overrides data")
	Accessibility.reset()
	check(rt.color("rare") == base_rare and et.color(ElementTable.Element.FIRE) == base_fire, "off = data colours")


func test_dialogue_subtitles() -> void:
	var ui := DialogueUI.new()
	runner_tree.root.add_child(ui)
	Accessibility.subtitles = false
	Accessibility.subtitle_scale = 1.5
	ui._on_line("Bob", "Hello")
	check(not ui.text_label.visible, "subtitles off hides line")
	check(ui.text_label.get_theme_font_size("font_size") == 24, "scale applied")
	Accessibility.subtitles = true
	ui._on_line("Bob", "Hello")
	check(ui.text_label.visible, "subtitles on shows line")
	ui.queue_free()
	_cleanup()
