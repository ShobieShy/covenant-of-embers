extends SceneTree
## One-shot: write resources/enemies/spire.tres from data/enemies/spire.toml.


func _init() -> void:
	var r := EnemyTable.from_toml_files(["res://data/enemies/spire.toml"])
	if r.has("error"):
		push_error(String(r["error"]))
		quit(1)
		return
	var err := ResourceSaver.save(r["table"], "res://resources/enemies/spire.tres")
	if err != OK:
		push_error("save failed %d" % err)
		quit(1)
		return
	quit(0)
