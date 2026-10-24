extends TestCase
## Step 83 done check: per-OS user dir, atomic save write, legacy migration never overwrites.


func test_custom_user_dir() -> void:
	check(
		bool(ProjectSettings.get_setting("application/config/use_custom_user_dir")), "custom dir on"
	)
	check(
		OS.get_user_data_dir().simplify_path() == UserDir.expected_dir().simplify_path(),
		"user dir %s vs %s" % [OS.get_user_data_dir(), UserDir.expected_dir()]
	)


func test_atomic_write_replaces_and_survives_stale_tmp() -> void:
	var p := "user://test_atomic.json"
	FileAccess.open(p + ".tmp", FileAccess.WRITE).store_string("half")  # interrupted earlier
	check(UserDir.write_atomic(p, "one") == OK, "first write")
	check(UserDir.write_atomic(p, "two") == OK, "second write")
	check(FileAccess.get_file_as_string(p) == "two", "content replaced")
	check(FileAccess.get_file_as_string(p + ".bak") == "one", "previous kept as .bak")
	check(not FileAccess.file_exists(p + ".tmp"), "no temp left")
	for f in [p, p + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func test_save_uses_atomic_write() -> void:
	var p := "user://test_atomic_save.json"
	check(SaveGame.write({"version": SaveGame.VERSION}, p) == OK, "write")
	check(not SaveGame.read(p).has("error"), "readable")
	for f in [p, p + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func test_migrate_never_overwrites() -> void:
	var src := "user://test_legacy"
	var dst := "user://test_new"
	for d in [src, dst]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	FileAccess.open(src + "/save.json", FileAccess.WRITE).store_string("old")
	FileAccess.open(src + "/keybinds.cfg", FileAccess.WRITE).store_string("oldkeys")
	FileAccess.open(dst + "/keybinds.cfg", FileAccess.WRITE).store_string("newkeys")
	var got := UserDir.migrate_legacy(src, dst)
	check(got == PackedStringArray(["save.json"]), "copied only missing: %s" % [got])
	check(FileAccess.get_file_as_string(dst + "/keybinds.cfg") == "newkeys", "not overwritten")
	check(FileAccess.file_exists(src + "/save.json"), "legacy kept")
	for d in [src, dst]:
		for f in ["save.json", "keybinds.cfg"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(d + "/" + f))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(d))
