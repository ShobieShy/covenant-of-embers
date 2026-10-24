extends TestCase
## Every ASSETS.toml entry is in the in-game credits; the CC BY wizard line is exact.


func test_every_asset_credited() -> void:
	var assets := LevelToml.load_file("res://ASSETS.toml")
	var lines := CreditsUi.load_lines()
	var all := "\n".join(lines)
	for a in assets.get("asset", []):
		var n := String((a as Dictionary).get("name", "")).c_unescape()
		check(all.contains(n), "credited: %s" % n)
	check(lines.size() == (assets.get("asset", []) as Array).size(), "one credit line per asset")
	check(all.contains('"Animated Wizard" by Quaternius, CC BY 3.0'), "exact Joe attribution")


func test_menu_has_credits() -> void:
	var m: MainMenu = (load(GameFlow.MENU) as PackedScene).instantiate()
	runner_tree.root.add_child(m)
	check(m.buttons.has("credits"), "credits button")
	m.press("credits")
	check(m.credits_ui.visible, "credits panel opens")
	m.queue_free()
