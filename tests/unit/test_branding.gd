extends TestCase
## Step 84: project version shown in the menu, icon files present and wired.


func test_version_string() -> void:
	var v := String(ProjectSettings.get_setting("application/config/version", ""))
	check(v == "0.3.3-prealpha", "project version is 0.3.3-prealpha (got %s)" % v)
	check(
		MainMenu.version_string() == "v0.3.3-prealpha" and MainMenu.release_name() == "Pre-Alpha 0.3.3",
		"menu version string"
	)


func test_version_suffix_parsing() -> void:
	check(VersionInfo.release_name("0.1.0-prealpha") == "Pre-Alpha 0.1", "0.1.0 keeps the short name")
	check(VersionInfo.release_name("0.1.1-prealpha") == "Pre-Alpha 0.1.1", "patch shown")
	check(VersionInfo.release_name("1.0.0") == "v1.0.0", "plain release")
	check(VersionInfo.numeric("0.1.1-prealpha") == "0.1.1.0", "numeric PE version drops the suffix")
	var p := VersionInfo.parse("0.1.1-prealpha")
	check(p.patch == 1 and p.pre == "prealpha", "parse")
	check(NetSession.version() == "0.3.3-prealpha/p%d" % NetSession.PROTOCOL, "co-op gate keeps the suffix")


func test_export_presets_version() -> void:
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	var want := VersionInfo.numeric(VersionInfo.current())
	check(cfg.contains('application/file_version="%s"' % want), "Windows file_version %s" % want)
	check(cfg.contains('application/product_version="%s"' % want), "Windows product_version %s" % want)


func test_menu_shows_version() -> void:
	var m: MainMenu = (load(GameFlow.MENU) as PackedScene).instantiate()
	runner_tree.root.add_child(m)
	check(m.version_label != null and m.version_label.text.begins_with("Pre-Alpha 0.3"), "menu has version label")
	m.queue_free()


func test_icons() -> void:
	check(FileAccess.file_exists("res://assets/branding/icon.png"), "icon.png exists")
	check(FileAccess.file_exists("res://assets/branding/icon.ico"), "icon.ico exists")
	check(
		String(ProjectSettings.get_setting("application/config/icon")) == "res://assets/branding/icon.png",
		"project icon set"
	)
	var ico := FileAccess.get_file_as_bytes("res://assets/branding/icon.ico")
	check(ico.size() > 6 and ico[2] == 1 and ico[4] >= 4, "ico has >= 4 sizes")
