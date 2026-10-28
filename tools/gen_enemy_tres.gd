extends SceneTree
## Writes resources/enemies/<name>.tres from data/enemies/<name>.toml (L3: goblins).
## Usage: godot --headless --path . -s res://tools/gen_enemy_tres.gd -- goblins


func _init() -> void:
	for n in OS.get_cmdline_user_args():
		var r := EnemyTable.from_toml_files(["res://data/enemies/%s.toml" % n])
		if r.has("error"):
			push_error(r["error"])
			continue
		var t: EnemyTable = r["table"]
		for d in t.defs:
			d.resource_local_to_scene = false
		print(
			n,
			": ",
			ResourceSaver.save(t, "res://resources/enemies/%s.tres" % n),
			" defs ",
			t.defs.size()
		)
	quit()
