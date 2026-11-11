extends SceneTree
## One-shot: write resources/enemies/sunken.tres from data/enemies/sunken.toml.


func _init() -> void:
	var r := EnemyTable.from_toml_files(["res://data/enemies/sunken.toml"])
	if r.has("error"):
		push_error(String(r["error"]))
		quit(1)
		return
	var err := ResourceSaver.save(r["table"], "res://resources/enemies/sunken.tres")
	if err != OK:
		push_error("save failed %d" % err)
		quit(1)
		return
	quit(0)
