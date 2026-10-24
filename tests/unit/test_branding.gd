extends TestCase
## Step 84: project version shown in the menu, icon files present and wired.


func test_version_string() -> void:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	check(v == "0.1.0", "project version is 0.1.0 (got %s)" % v)
	check(MainMenu.version_string() == "v0.1.0", "menu version string")


func test_menu_shows_version() -> void:
	var m: MainMenu = (load(GameFlow.MENU) as PackedScene).instantiate()
	runner_tree.root.add_child(m)
	check(m.version_label != null and m.version_label.text == "v0.1.0", "menu has version label")
	m.queue_free()


func test_icons() -> void:
	check(FileAccess.file_exists("res://assets/branding/icon.png"), "icon.png exists")
	check(FileAccess.file_exists("res://assets/branding/icon.ico"), "icon.ico exists")
	check(String(ProjectSettings.get_setting("application/config/icon")) == "res://assets/branding/icon.png", "project icon set")
	var ico := FileAccess.get_file_as_bytes("res://assets/branding/icon.ico")
	check(ico.size() > 6 and ico[2] == 1 and ico[4] >= 4, "ico has >= 4 sizes")
