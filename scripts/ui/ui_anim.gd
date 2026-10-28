class_name UiAnim
extends RefCounted
## 0.3.1 polish (P1): one shared helper for UI motion, so every panel moves the same way.
##  - open: show, then fade in plus an 8 px slide up over 0.15 s;
##  - close: fade out over 0.1 s, then hide;
##  - pulse / shake / count_up for HUD feedback.
## Every animation is instant under reduced motion and when the DisplayServer is headless
## (tests and bot runs), so `visible` is already final when open()/close() return there.
## A CanvasLayer has no modulate, so its direct Control children move instead.
## While a close fade runs the panel counts as shut (is_shown() is false) and ignores the
## mouse, so a toggle reopens it at once (QA round 9). Tweens run while paused and ignore
## Engine.time_scale. open() re-reads each panel's resting position every time (no stale
## spot after a window resize); a running pulse/shake/count_up is stopped by the next one.

const OPEN_S := 0.15
const CLOSE_S := 0.1
const SLIDE_PX := 8.0

static var reduced_motion := false  ## Settings.apply_to() keeps this in sync
static var force_motion := false  ## tests: animate even headless


static func instant() -> bool:
	if force_motion:
		return false
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


## Open and not fading out: what a panel's is_open() / toggle() should read.
static func is_shown(n: Node) -> bool:
	return n != null and n.get(&"visible") == true and not closing(n)


static func closing(n: Node) -> bool:
	return n != null and n.get_meta(&"ui_anim_closing", false)


static func _kill(n: Node, key := &"ui_anim_tween") -> void:
	if n.has_meta(key):
		var t: Tween = n.get_meta(key)
		if t and t.is_valid():
			t.kill()
		n.remove_meta(key)


## Stops a fade in or out where it is and puts the panel back at rest (shown or not).
static func _settle(n: Node, ts: Array[CanvasItem]) -> void:
	var t: Tween = n.get_meta(&"ui_anim_tween") if n.has_meta(&"ui_anim_tween") else null
	var moving := t != null and t.is_valid() and t.is_running()
	_kill(n)
	_end_closing(n, ts)
	for c in ts:
		c.modulate.a = 1.0
		if moving and c.has_meta(&"ui_anim_home"):  # only undo our own slide, not a relayout
			(c as Control).position = c.get_meta(&"ui_anim_home")


static func _end_closing(n: Node, ts: Array[CanvasItem]) -> void:
	if not closing(n):
		return
	n.remove_meta(&"ui_anim_closing")
	for c in ts:
		if c.has_meta(&"ui_anim_mouse"):
			(c as Control).mouse_filter = c.get_meta(&"ui_anim_mouse")
			c.remove_meta(&"ui_anim_mouse")


static func _tween(n: Node, key := &"ui_anim_tween") -> Tween:
	_kill(n, key)
	var t := n.create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # the pause menu animates while paused
	t.set_ignore_time_scale(true)  # slow-mo / hitstop must not slow the UI
	t.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	n.set_meta(key, t)
	return t


## Show `n` with the open motion.
static func open(n: Node) -> void:
	if n == null:
		return
	var ts := _targets(n)
	_settle(n, ts)  # a reopen during the close fade: back to rest first
	n.visible = true
	if instant() or not n.is_inside_tree() or ts.is_empty():
		return
	var t := _tween(n).set_parallel(true)
	for c in ts:
		var ctl := c as Control
		var home := ctl.position  # re-read on every open (window resizes, anchor changes)
		c.set_meta(&"ui_anim_home", home)
		c.modulate.a = 0.0
		ctl.position = home + Vector2(0, SLIDE_PX)
		t.tween_property(c, "modulate:a", 1.0, OPEN_S)
		t.tween_property(ctl, "position", home, OPEN_S)


## Hide `n` after the close fade; `done` (optional) runs once it is hidden.
static func close(n: Node, done := Callable()) -> void:
	if n == null:
		return
	var ts := _targets(n)
	if closing(n):
		return  # already fading out
	if instant() or not n.is_inside_tree() or not n.visible or ts.is_empty():
		_settle(n, ts)
		n.visible = false
		if done.is_valid():
			done.call()
		return
	_settle(n, ts)
	n.set_meta(&"ui_anim_closing", true)
	for c in ts:  # no clicks on a panel that is going away
		var ctl := c as Control
		c.set_meta(&"ui_anim_mouse", ctl.mouse_filter)
		ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _tween(n).set_parallel(true)
	for c in ts:
		t.tween_property(c, "modulate:a", 0.0, CLOSE_S)
	t.chain().tween_callback(
		func() -> void:
			_settle(n, ts)
			n.visible = false
			if done.is_valid():
				done.call()
	)


## A quick scale pop (badges, counters).
static func pulse(c: Control, amount := 0.15) -> void:
	if c == null or instant() or not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE
	var t := _tween(c, &"ui_anim_pulse")
	t.tween_property(c, "scale", Vector2.ONE * (1.0 + amount), 0.08)
	t.tween_property(c, "scale", Vector2.ONE, 0.12)


## A short horizontal shake (refused actions).
static func shake(c: Control, px := 6.0) -> void:
	if c == null or instant() or not c.is_inside_tree():
		return
	if c.has_meta(&"ui_anim_shake_x"):  # a shake mid-shake starts from the rest spot
		c.position.x = c.get_meta(&"ui_anim_shake_x")
	var home := c.position
	c.set_meta(&"ui_anim_shake_x", home.x)
	var t := _tween(c, &"ui_anim_shake")
	t.finished.connect(func() -> void: c.remove_meta(&"ui_anim_shake_x"))
	for dx in [px, -px, px * 0.5, 0.0]:
		t.tween_property(c, "position:x", home.x + dx, 0.04)


## Count a label's number from `from` to `to` (gold, XP); instant sets the final text.
static func count_up(l: Label, from: int, to: int, fmt := "%d", seconds := 0.4) -> void:
	if l == null:
		return
	_kill(l, &"ui_anim_count")
	if instant() or not l.is_inside_tree() or from == to:
		l.text = fmt % to
		return
	var t := _tween(l, &"ui_anim_count")
	t.tween_method(
		func(v: float) -> void: l.text = fmt % int(round(v)), float(from), float(to), seconds
	)
