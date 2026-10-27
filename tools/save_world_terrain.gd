extends SceneTree
## OW2: loads build/world/world_height.f32 + world_control.u32 (tools/build_world.py) into one
## Terrain3DData and saves its region files to res://world/terrain/ (one terrain-*.res per
## 256 m region). Run after build_world.py; tools/build_world.sh does all three steps.

const SRC := "res://build/world/"
const DST := "res://world/terrain/"


func _initialize() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "world.json"))
	var g: Array = meta["grid"]
	var w := int(g[0])
	var h := int(g[1])
	var hb := FileAccess.get_file_as_bytes(SRC + "world_height.f32")
	var cb := FileAccess.get_file_as_bytes(SRC + "world_control.u32")
	if hb.size() != w * h * 4 or cb.size() != w * h * 4:
		push_error("save_world_terrain: build/world is stale or missing; run tools/build_world.py")
		quit(1)
		return
	var himg := Image.create_from_data(w, h, false, Image.FORMAT_RF, hb)
	var cimg := Image.create_from_data(w, h, false, Image.FORMAT_RF, cb)
	var t: Node3D = ClassDB.instantiate(&"Terrain3D")
	t.set(&"vertex_spacing", float(meta["spacing"]))
	var cam := Camera3D.new()
	root.add_child(cam)
	t.call(&"set_camera", cam)
	root.add_child(t)
	await process_frame
	var o: Array = meta["origin"]
	var data: Object = t.get(&"data")
	data.call(&"import_images", [himg, cimg, null], Vector3(float(o[0]), 0, float(o[1])), 0.0, 1.0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	for f in DirAccess.get_files_at(DST):
		if f.begins_with("terrain") and f.ends_with(".res"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DST + f))  # our own output only
	data.call(&"save_directory", DST)
	var n := 0
	for f in DirAccess.get_files_at(DST):
		n += int(f.ends_with(".res"))
	var info := {
		"regions": n, "layers": meta["layers"], "origin": o, "grid": g, "spacing": meta["spacing"]
	}
	info["hash"] = hash([hb, cb])
	var j := FileAccess.open(DST + "world_terrain.json", FileAccess.WRITE)
	j.store_string(JSON.stringify(info, "  "))
	j.close()
	print("[save_world_terrain] %d regions -> %s (hash %d)" % [n, DST, info["hash"]])
	quit(0)
