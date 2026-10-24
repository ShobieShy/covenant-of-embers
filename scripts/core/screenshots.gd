class_name Screenshots
extends Node
## Playtest screenshots (step 41): `--shots <dir>` (after `--`) saves the game viewport as
## PNG into <dir> shortly after the scene starts and then every `--shot-every` s (default
## 20). Captures only this game's own frame (not the desktop). No-op headless.

var dir := ""
var every := 20.0
var prefix := "shot"
var taken := 0
var _t := 0.0
var _next := 1.5

static func attach(parent: Node, name_prefix: String) -> Screenshots:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i < 0 or i + 1 >= args.size() or DisplayServer.get_name() == "headless":
		return null
	var s := Screenshots.new()
	s.name = "Screenshots"
	s.dir = args[i + 1]
	s.prefix = name_prefix
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	var j := args.find("--shot-every")
	if j >= 0 and j + 1 < args.size():
		s.every = maxf(1.0, float(args[j + 1]))
	DirAccess.make_dir_recursive_absolute(s.dir)
	parent.add_child(s)
	return s

func _process(delta: float) -> void:
	_t += delta
	if _t >= _next:
		_next = _t + every
		take()

func take(tag := "") -> String:
	var img := get_viewport().get_texture().get_image()
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	var path := dir.path_join("%s_%s_%02d%s.png" % [prefix, stamp, taken, "_" + tag if tag else ""])
	var err := img.save_png(path)
	taken += 1
	print("[shots] %s %s (%dx%d)" % [path, error_string(err), img.get_width(), img.get_height()])
	return path
