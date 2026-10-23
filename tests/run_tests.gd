extends SceneTree
## Minimal headless test runner (no addon needed).
## godot --headless --path . -s res://tests/run_tests.gd
## Runs every tests/unit/test_*.gd: each `test_*` method of a RefCounted script.
## A test fails if it calls `fail(msg)` / a failed `check()`. Exit code = failures.
## Tests run on the first physics frame (not in _initialize) so the root viewport is
## inside its World3D and PhysicsDirectSpaceState3D queries work on added scenes.

var failures := 0
var passed := 0
var _ran := false

func _physics_process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_all()
	return false

func _run_all() -> void:
	var dir := DirAccess.open("res://tests/unit")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			var t = script.new()
			t.set_meta("errors", [])
			t.runner_tree = self
			t.call(name)
			var errs: Array = t.get_meta("errors")
			if errs.is_empty():
				passed += 1
				print("  ok   %s::%s" % [f, name])
			else:
				failures += 1
				print("  FAIL %s::%s: %s" % [f, name, "; ".join(errs)])
	print("[tests] %d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)
