extends SceneTree
## Minimal headless test runner (no addon needed).
## godot --headless --path . -s res://tests/run_tests.gd
## Runs every tests/unit/test_*.gd: each `test_*` method of a RefCounted script.
## A test fails if it calls `fail(msg)` / a failed `check()`. Exit code = failures.
## Tests run on the first physics frame (not in _initialize) so the root viewport is
## inside its World3D and PhysicsDirectSpaceState3D queries work on added scenes, and on
## the *second* one: during the first, Node.get_physics_process_delta_time() is still 0, so
## CharacterBody3D.move_and_slide() (which uses it) would not move (step 3).
## A test file that fails to parse counts as a failure (step 8); runtime SCRIPT ERRORs
## inside a test don't stop it, so tools/run_tests.sh also fails on any such log line.
## A test may `await runner_tree.physics_frame` (step 12: the NavigationServer syncs a
## freshly baked navmesh only on later physics frames); the runner awaits each test, and
## tools/run_tests.sh runs it with --fixed-fps 60 so every frame is exactly one 1/60 s
## physics tick, run as fast as the CPU allows.

## 0.3.1 test tiers: the classic level-flow tests run only at releases
## (TEST_CLASSIC=1 adds them, TEST_CLASSIC=only runs just them; tools/run_tests.sh --classic).
## A file maps to the test methods that are classic, or [] for the whole file.
const CLASSIC := {
	"test_level.gd": [],
	"test_flow.gd": [],
	"test_hub.gd": [],
	"test_town.gd": ["test_all_exits_link"],
	"test_vault.gd": ["test_chest_opens_after_boss"],
}

var failures := 0
var passed := 0
var _frames := 0


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_run_all()
	return false


func _run_all() -> void:
	GameFlow.open_world = false  # OW11c-3: unit tests build classic levels unless they opt in
	var dir := DirAccess.open("res://tests/unit")
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var only := OS.get_environment("TEST_ONLY")  # step 95: e.g. TEST_ONLY=test_player.gd
	if only != "":
		files = files.filter(func(f: String) -> bool: return f in only.split(","))
	var classic := OS.get_environment("TEST_CLASSIC")
	if classic == "only":
		files = files.filter(func(f: String) -> bool: return CLASSIC.has(f))
	elif classic != "1":
		files = files.filter(
			func(f: String) -> bool: return not (CLASSIC.has(f) and CLASSIC[f].is_empty())
		)
	for f in files:
		var script := load("res://tests/unit/" + f) as GDScript
		if script == null or not script.can_instantiate():
			# A parse error used to skip the whole file silently (step 8 fix).
			failures += 1
			print("  FAIL %s: script failed to load/compile" % f)
			continue
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			if CLASSIC.has(f) and not CLASSIC[f].is_empty():
				var is_classic: bool = name in CLASSIC[f]
				if (
					(classic == "only" and not is_classic)
					or (classic != "1" and classic != "only" and is_classic)
				):
					continue
			var t = script.new()
			t.set_meta("errors", [])
			t.runner_tree = self
			await t.call(name)
			var errs: Array = t.get_meta("errors")
			if errs.is_empty():
				passed += 1
				print("  ok   %s::%s" % [f, name])
			else:
				failures += 1
				print("  FAIL %s::%s: %s" % [f, name, "; ".join(errs)])
	print("[tests] %d passed, %d failed" % [passed, failures])
	_sweep_user_leftovers()
	# 0.3.1 tiers: let queued frees land and short sounds finish before quitting, so a
	# TEST_ONLY subset doesn't end on "resources still in use at exit" (a playing Ogg
	# playback still holds its stream).
	for _i in 4:
		await process_frame
	await create_timer(1.0, true, false, true).timeout
	quit(1 if failures > 0 else 0)


## QA: UserDir.write_atomic keeps <file>.bak (and a crash can leave .tmp); most tests remove
## only their .json. Sweep test-owned leftovers so direct runs don't litter the shared user://.
func _sweep_user_leftovers() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		return
	for f in d.get_files():
		if f.begins_with("test_") and (f.ends_with(".bak") or f.ends_with(".tmp")):
			d.remove(f)
