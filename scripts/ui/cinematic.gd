class_name Cinematic
extends Node
## Step 110: an in-engine cinematic - a camera moving through `shots` with letterbox bars,
## a caption and "Hold Esc to skip". Holding Esc (ui_cancel / pause) for SKIP_HOLD s skips;
## a skip still ends with `finished(id, true)`, so its beat's flags still apply. Only the
## host (or solo) may skip (Q22). While it plays the player has no control and saving waits
## (main.save_game checks `playing`). With --shots, each shot is screenshotted halfway in.
## A shot: {from: Vector3, to: Vector3, look: Vector3, s: float, text: String}.

signal finished(id: String, skipped: bool)

const SKIP_HOLD := 1.0
const BAR := 0.12  ## letterbox height (viewport fraction)
const BAR_IN := 0.5  ## step 133: letterbox slide-in seconds
const FADE := 0.4  ## step 133: fade from black at the start, to black before the end

static var playing: Cinematic = null

var id := ""
var shots: Array = []
var shot := -1
var shot_t := 0.0
var held := 0.0
var can_skip := true
var player: Player
var camera: Camera3D
var caption: Label
var hint: Label
var shooter: Screenshots
var _shot_taken := false
var _layer: CanvasLayer
var bars: Array[ColorRect] = []
var fade: ColorRect
var elapsed := 0.0


static func make(cid: String, list: Array, p: Player) -> Cinematic:
	var c := Cinematic.new()
	c.id = cid
	c.name = "Cinematic_" + cid
	c.shots = list
	c.player = p
	c.can_skip = not Coop.is_client()
	return c


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	playing = self
	camera = Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0 - BAR
		bar.anchor_bottom = BAR if top else 1.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_layer.add_child(bar)
		bars.append(bar)
	fade = ColorRect.new()
	fade.name = "Fade"
	fade.color = Color.BLACK
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(fade)
	_animate(0.0)
	caption = _label(28, 1.0 - BAR - 0.1, HORIZONTAL_ALIGNMENT_CENTER)
	hint = _label(14, 1.0 - BAR * 0.5, HORIZONTAL_ALIGNMENT_RIGHT)
	hint.text = "Hold Esc to skip" if can_skip else "The host can skip"
	if player:
		player.ui_open = true
	shooter = get_parent().get_node_or_null("Screenshots") as Screenshots
	_next_shot()


func _label(px: int, at: float, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.anchor_left = 0.05
	l.anchor_right = 0.95
	l.anchor_top = at
	l.anchor_bottom = at
	l.horizontal_alignment = align
	l.add_theme_font_size_override(&"font_size", px)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 6)
	_layer.add_child(l)
	return l


func _next_shot() -> void:
	shot += 1
	shot_t = 0.0
	_shot_taken = false
	if shot >= shots.size():
		_end(false)
		return
	caption.text = String(shots[shot].get("text", ""))
	_place(0.0)
	camera.make_current()


func _place(k: float) -> void:
	var s: Dictionary = shots[shot]
	var a: Vector3 = s.get("from", Vector3.ZERO)
	var b: Vector3 = s.get("to", a)
	camera.global_position = a.lerp(b, smoothstep(0.0, 1.0, k))
	var look: Vector3 = s.get("look", a + Vector3.FORWARD)
	if not camera.global_position.is_equal_approx(look):
		camera.look_at(look, Vector3.UP)


func _process(delta: float) -> void:
	if shot < 0 or shot >= shots.size():
		return
	if can_skip and (Input.is_action_pressed(&"ui_cancel") or Input.is_key_pressed(KEY_ESCAPE)):
		held += delta
		hint.text = "Skipping... %d%%" % int(100.0 * minf(1.0, held / SKIP_HOLD))
		if held >= SKIP_HOLD:
			skip()
			return
	elif held > 0.0:
		held = 0.0
		hint.text = "Hold Esc to skip"
	var dur := maxf(0.1, float(shots[shot].get("s", 3.0)))
	shot_t += delta
	elapsed += delta
	_animate(dur)
	_place(minf(1.0, shot_t / dur))
	if not _shot_taken and shot_t >= dur * 0.5:
		_shot_taken = true
		if shooter:
			shooter.take("cine_%s_%d" % [id, shot])
	if shot_t >= dur:
		_next_shot()


## Step 133 (FX F7): letterbox bars slide in over BAR_IN s; fade from black over the first FADE s
## and to black over the last FADE s of the final shot.
func _animate(dur: float) -> void:
	var k := smoothstep(0.0, 1.0, clampf(elapsed / BAR_IN, 0.0, 1.0)) * BAR
	if bars.size() == 2:
		bars[0].anchor_bottom = k
		bars[1].anchor_top = 1.0 - k
	var a := 1.0 - clampf(elapsed / FADE, 0.0, 1.0)
	if shot == shots.size() - 1 and dur > FADE * 2.0:
		a = maxf(a, clampf((shot_t - (dur - FADE)) / FADE, 0.0, 1.0))
	if fade:
		fade.color.a = a


## Ends now (flags still apply). False when this peer may not skip.
func skip() -> bool:
	if not can_skip or shot >= shots.size():
		return false
	_end(true)
	return true


func _end(skipped: bool) -> void:
	shot = shots.size()
	if playing == self:
		playing = null
	if player and is_instance_valid(player):
		player.ui_open = false
		if player.camera:
			player.camera.make_current()
	print("[cinematic] %s %s" % [id, "skipped" if skipped else "done"])
	finished.emit(id, skipped)
	queue_free()


func _exit_tree() -> void:
	if playing == self:
		playing = null
