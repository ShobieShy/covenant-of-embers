extends Node3D
## Entry scene. `--seconds N` (after `--`) quits after N seconds and reports
## frames and physics ticks, the Godot counterpart of the old `covenant --seconds`.

var _seconds := -1.0
var _elapsed := 0.0
var _frames := 0
var _ticks := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seconds")
	if i >= 0 and i + 1 < args.size():
		_seconds = float(args[i + 1])
	print("[main] Covenant of Embers on Godot %s, renderer %s" % [
		Engine.get_version_info().string,
		ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	# Until the player exists (step 3) the camera sits at the level's PlayerStart eye.
	var eye := get_node_or_null("Level/PlayerStart/Eye") as Node3D
	var cam := get_node_or_null("Camera3D") as Camera3D
	if eye and cam:
		cam.global_transform = eye.global_transform
		print("[main] level %s, %d boxes, eye at %s" % [
			$Level.get_meta("level_id", "?"), $Level.get_node("Boxes").get_child_count(), cam.global_position])

func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _seconds > 0.0 and _elapsed >= _seconds:
		print("[main] %d frames, %d physics ticks in %.2f s" % [_frames, _ticks, _elapsed])
		get_tree().quit(0)

func _physics_process(_delta: float) -> void:
	_ticks += 1
