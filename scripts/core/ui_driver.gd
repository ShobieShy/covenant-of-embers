class_name UiDriver
extends Node
## Graphical UI smoke (step 41): `--ui-test <dir>` (after `--`) drives the real game through
## injected keyboard/mouse events (Input.parse_input_event, the same path real input takes):
## menu -> New Run -> walk/turn/fire -> Esc pause -> Main Menu -> Continue -> Esc -> Quit.
## Screenshots of each beat go to <dir>. Uses user://playtest_save.json, never the real save.

const STEPS := [
	[2.0, "shot", "menu"],
	[0.5, "key", KEY_ENTER, "new run"],
	[4.0, "shot", "midden_start"],
	[0.0, "hold", KEY_W, 2.5],
	[0.0, "mouse_move", 400.0],
	[1.0, "click", 6],
	[1.5, "shot", "midden_walked"],
	[0.0, "hold", KEY_D, 1.5],
	[2.0, "key", KEY_TAB, "inventory"],
	[1.0, "shot", "inventory"],
	[0.5, "key", KEY_ESCAPE, "close inv"],
	[1.0, "key", KEY_ESCAPE, "pause"],
	[1.0, "shot", "pause"],
	[0.5, "key", KEY_DOWN, ""],
	[0.2, "key", KEY_DOWN, ""],
	[0.2, "key", KEY_DOWN, ""],
	[0.3, "key", KEY_ENTER, "main menu"],
	[2.0, "shot", "menu_after_save"],
	[0.3, "key", KEY_DOWN, ""],
	[0.3, "key", KEY_ENTER, "continue"],
	[4.0, "shot", "continued"],
	[60.0, "shot", "stable_60s"],
	[0.5, "key", KEY_ESCAPE, "pause"],
	[0.5, "key", KEY_DOWN, ""],
	[0.2, "key", KEY_DOWN, ""],
	[0.2, "key", KEY_DOWN, ""],
	[0.2, "key", KEY_DOWN, ""],
	[0.3, "key", KEY_ENTER, "quit"],
]

var dir := ""
var _i := 0
var _wait := 0.0
var _holds := {}  # keycode -> seconds left


static func attach(tree: SceneTree) -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--ui-test")
	if i < 0 or i + 1 >= args.size() or tree.root.has_node("UiDriver"):
		return
	GameFlow.save_path = "user://playtest_save.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameFlow.save_path))
	var d := UiDriver.new()
	d.name = "UiDriver"
	d.dir = args[i + 1]
	d.process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(d.dir)
	tree.root.add_child.call_deferred(d)
	print("[ui-test] start")


func _process(delta: float) -> void:
	for k in _holds.keys():
		_holds[k] -= delta
		if _holds[k] <= 0.0:
			_key(k, false)
			_holds.erase(k)
	if _i >= STEPS.size():
		return
	_wait += delta
	var s: Array = STEPS[_i]
	if _wait < s[0]:
		return
	_wait = 0.0
	_i += 1
	match s[1]:
		"shot":
			var img := get_viewport().get_texture().get_image()
			var path := dir.path_join("ui_%02d_%s.png" % [_i, s[2]])
			print(
				(
					"[ui-test] shot %s %s scene=%s paused=%s"
					% [
						path,
						error_string(img.save_png(path)),
						get_tree().current_scene.name if get_tree().current_scene else "-",
						get_tree().paused
					]
				)
			)
		"key":
			_key(s[2], true)
			_key(s[2], false)
			if s[3] != "":
				print("[ui-test] key %s (%s)" % [OS.get_keycode_string(s[2]), s[3]])
		"hold":
			_key(s[2], true)
			_holds[s[2]] = s[3]
			print("[ui-test] hold %s %.1fs" % [OS.get_keycode_string(s[2]), s[3]])
		"mouse_move":
			var m := InputEventMouseMotion.new()
			m.relative = Vector2(s[2], 0)
			m.screen_relative = m.relative
			Input.parse_input_event(m)
		"click":
			for n in s[2]:
				for pressed in [true, false]:
					var b := InputEventMouseButton.new()
					b.button_index = MOUSE_BUTTON_LEFT
					b.pressed = pressed
					b.position = get_viewport().get_visible_rect().size / 2
					Input.parse_input_event(b)
			print("[ui-test] clicked %d" % s[2])


func _key(code: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)
