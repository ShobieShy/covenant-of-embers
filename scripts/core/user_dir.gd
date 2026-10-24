class_name UserDir
extends RefCounted
## Per-OS user data (BUILD_PLAN step 83). project.godot sets a custom user dir, so user://
## is %APPDATA%\covenant-of-embers on Windows and ~/.local/share/covenant-of-embers on
## Linux. migrate_legacy() copies files from the old default Godot location
## (<data>/godot/app_userdata/Covenant of Embers) once, never overwriting or deleting.
## write_atomic(): temp file + rename so an interrupted save never leaves a half file.

const DIR_NAME := "covenant-of-embers"
const LEGACY_NAME := "Covenant of Embers"
const FILES := ["save.json", "keybinds.cfg"]


static func legacy_dir() -> String:
	return OS.get_data_dir().path_join("godot/app_userdata").path_join(LEGACY_NAME)


static func expected_dir() -> String:
	return OS.get_data_dir().path_join(DIR_NAME)


## Copies legacy files that don't exist yet in user://; returns the names copied.
static func migrate_legacy(from := legacy_dir(), to := "user://") -> PackedStringArray:
	var copied := PackedStringArray()
	var src := ProjectSettings.globalize_path(from)
	var dst := ProjectSettings.globalize_path(to)
	if src.simplify_path() == dst.simplify_path() or not DirAccess.dir_exists_absolute(src):
		return copied
	for f in FILES:
		var a := src.path_join(f)
		var b := dst.path_join(f)
		if FileAccess.file_exists(a) and not FileAccess.file_exists(b):
			if DirAccess.copy_absolute(a, b) == OK:
				copied.append(f)
	return copied


static func write_atomic(path: String, text: String) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	var real := ProjectSettings.globalize_path(path)
	var real_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(real + ".bak")
		DirAccess.rename_absolute(real, real + ".bak")
	var err := DirAccess.rename_absolute(real_tmp, real)
	if err != OK and FileAccess.file_exists(real + ".bak"):
		DirAccess.rename_absolute(real + ".bak", real)
	return err
