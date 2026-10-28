class_name UiAnim
extends RefCounted
## 0.3.1 polish (P1): one shared helper for UI motion, so every panel moves the same way.
##  - open: show, then fade in plus an 8 px slide up over 0.15 s;
##  - close: fade out over 0.1 s, then hide;
##  - pulse / shake / count_up for HUD feedback.
## Every animation is instant under reduced motion and when the DisplayServer is headless
## (tests and bot runs), so `visible` is already final when open()/close() return there.
## A CanvasLayer has no modulate, so its direct Control children move instead.

const OPEN_S := 0.15
const CLOSE_S := 0.1
const SLIDE_PX := 8.0

static var reduced_motion := false  ## Settings.apply_to() keeps this in sync


static func instant() -> bool:
	return reduced_motion or DisplayServer.get_name() == "headless"


static func _targets(n: Node) -> Array[CanvasItem]:
	var out: Array[CanvasItem] = []
	if n is Control:
		out.append(n)
	elif n is CanvasLayer:
		for c in n.get_children():
			if c is Control:
				out.append(c)
	return out


static func _kill(n: Node) -> void:
	if n.has_meta(&"ui_anim_tween"):
		var t: Tween = n.get_meta(&"ui_anim_tween")
		if t and t.is_valid():
			t.kill()
		n.remove_meta(&"ui_anim_tween")


static func _tween(n: Node) -> Tween:
	_kill(n)
	var t := n.create_tween().set_parallel(true)
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # the pause menu animates while paused
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	n.set_meta(&"ui_anim_tween", t)
	return t


static func _home(c: CanvasItem) -> Vector2:
	if not c.has_meta(&"ui_anim_home"):
		c.set_meta(&"ui_anim_home", (c as Control).position)
	return c.get_meta(&"ui_anim_home")


## Show `n` with the open motion.
static func open(n: Node) -> void:
	if n == null:
		return
	n.visible = true
	var ts := _targets(n)
	if instant() or not n.is_inside_tree() or ts.is_empty():
		_kill(n)
		for c in ts:
			c.modulate.a = 1.0
		return
	var t := _tween(n)
	for c in ts:
		var ctl := c as Control
		var home := _home(c)
		c.modulate.a = 0.0
		ctl.position = home + Vector2(0, SLIDE_PX)
		t.tween_property(c, "modulate:a", 1.0, OPEN_S)
		t.tween_property(ctl, "position", home, OPEN_S)


## Hide `n` after the close fade; `done` (optional) runs once it is hidden.
static func close(n: Node, done := Callable()) -> void:
	if n == null:
		return
	var ts := _targets(n)
	if instant() or not n.is_inside_tree() or not n.visible or ts.is_empty():
		_kill(n)
		n.visible = false
		for c in ts:
			c.modulate.a = 1.0
			if c.has_meta(&"ui_anim_home"):
				(c as Control).position = c.get_meta(&"ui_anim_home")
		if done.is_valid():
			done.call()
		return
	var t := _tween(n)
	for c in ts:
		t.tween_property(c, "modulate:a", 0.0, CLOSE_S)
	t.chain().tween_callback(
		func() -> void:
			n.visible = false
			for c in ts:
				c.modulate.a = 1.0
			if done.is_valid():
				done.call()
	)


## A quick scale pop (badges, counters).
static func pulse(c: Control, amount := 0.15) -> void:
	if c == null or instant() or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var t := c.create_tween()
	t.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.12)


## A short horizontal shake (refused actions).
static func shake(c: Control, px := 6.0) -> void:
	if c == null or instant() or not c.is_inside_tree():
		return
	var home := _home(c)
	var t := c.create_tween()
	for dx in [px, -px, px * 0.5, 0.0]:
		t.tween_property(c, "position:x", home.x + dx, 0.04)


## Count a label's number from `from` to `to` (gold, XP); instant sets the final text.
static func count_up(l: Label, from: int, to: int, fmt := "%d", seconds := 0.4) -> void:
	if l == null:
		return
	if instant() or not l.is_inside_tree() or from == to:
		l.text = fmt % to
		return
	var t := l.create_tween()
	t.tween_method(
		func(v: float) -> void: l.text = fmt % int(round(v)), float(from), float(to), seconds
	)
