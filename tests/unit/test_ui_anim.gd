extends TestCase
## 0.3.1 P1: UiAnim is instant headless, so open/close leave `visible` final at once, a
## CanvasLayer panel's Control children end fully opaque, and close() runs its callback.


func test_instant_open_close() -> void:
	check(UiAnim.instant(), "headless runs are instant")
	var layer := CanvasLayer.new()
	var panel := PanelContainer.new()
	layer.add_child(panel)
	runner_tree.root.add_child(layer)
	layer.visible = false
	panel.modulate.a = 0.3
	UiAnim.open(layer)
	check(layer.visible and panel.modulate.a == 1.0, "open: shown, opaque")
	var done := [false]
	UiAnim.close(layer, func() -> void: done[0] = true)
	check(not layer.visible and done[0], "close: hidden, callback ran")
	check(panel.modulate.a == 1.0, "close leaves the panel ready to reopen")
	layer.free()


func test_count_up_and_controls() -> void:
	var l := Label.new()
	runner_tree.root.add_child(l)
	UiAnim.count_up(l, 3, 120, "%d g")
	check(l.text == "120 g", "count_up lands on the final value")
	UiAnim.pulse(l)
	UiAnim.shake(l)
	check(l.scale == Vector2.ONE, "pulse/shake are no-ops headless")
	var c := Control.new()
	UiAnim.open(c)  # not in the tree: still just shows
	check(c.visible, "open outside the tree")
	c.free()
	l.free()


func test_panels_close_at_once() -> void:
	var p := PauseMenu.new()
	runner_tree.root.add_child(p)
	p.open()
	check(p.visible, "pause opens")
	p.close()
	check(not p.visible, "pause closes at once headless")
	p.free()


func _wait(sec: float) -> void:
	await runner_tree.create_timer(sec, true, false, true).timeout


func _frames(n: int) -> void:
	for _i in n:
		await runner_tree.process_frame


func test_reopen_during_close_fade() -> void:  # QA round 9 (2)
	UiAnim.force_motion = true
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	runner_tree.root.add_child(p)
	p.visible = false
	UiAnim.open(p)
	check(UiAnim.is_shown(p), "open: shown")
	await _wait(0.3)
	UiAnim.close(p)
	check(p.visible and not UiAnim.is_shown(p), "closing: still drawn, but counts as shut")
	check(p.mouse_filter == Control.MOUSE_FILTER_IGNORE, "closing: ignores the mouse")
	UiAnim.open(p)
	check(UiAnim.is_shown(p) and p.mouse_filter == Control.MOUSE_FILTER_STOP, "reopen wins")
	await _wait(0.4)
	check(p.visible and p.modulate.a == 1.0, "the old close did not hide it later")
	UiAnim.close(p)
	await _wait(0.4)
	check(not p.visible and not UiAnim.closing(p), "a full close hides and clears the flag")
	check(p.mouse_filter == Control.MOUSE_FILTER_STOP, "mouse filter restored")
	UiAnim.force_motion = false
	p.free()


func test_open_rereads_home_and_tweens_are_unscaled() -> void:  # QA round 9 (4)(5)
	UiAnim.force_motion = true
	var p := Control.new()
	runner_tree.root.add_child(p)
	p.visible = false
	p.position = Vector2(10, 10)
	UiAnim.open(p)
	var t: Tween = p.get_meta(&"ui_anim_tween")
	await _wait(0.3)
	UiAnim.close(p)
	await _wait(0.3)
	p.position = Vector2(200, 50)  # a relayout while hidden (window resize)
	UiAnim.open(p)
	check(
		p.position.is_equal_approx(Vector2(200, 50 + UiAnim.SLIDE_PX)), "slides from the new spot"
	)
	await _wait(0.3)
	check(p.position.is_equal_approx(Vector2(200, 50)), "rests at the new spot, not the old")
	check(t != null, "a tween was made")
	Engine.time_scale = 0.05
	UiAnim.close(p)
	await runner_tree.create_timer(0.3, true, false, true).timeout  # 0.3 s of real time
	var hidden := not p.visible
	Engine.time_scale = 1.0
	check(hidden, "the close fade ignores Engine.time_scale")
	UiAnim.force_motion = false
	p.free()


func test_pulse_shake_count_restart() -> void:  # QA round 9 (1)
	UiAnim.force_motion = true
	var l := Label.new()
	runner_tree.root.add_child(l)
	l.position = Vector2(30, 0)
	UiAnim.shake(l)
	await _frames(3)
	UiAnim.shake(l)
	await _wait(0.4)
	check(is_equal_approx(l.position.x, 30.0), "a shake mid-shake ends at rest")
	UiAnim.pulse(l)
	await _frames(2)
	UiAnim.pulse(l)
	await _wait(0.4)
	check(l.scale.is_equal_approx(Vector2.ONE), "a pulse mid-pulse ends at scale 1")
	UiAnim.count_up(l, 0, 1000, "%d", 0.3)
	await _frames(2)
	UiAnim.count_up(l, 0, 5, "%d", 0.1)
	await _wait(0.5)
	check(l.text == "5", "the newer count wins")
	UiAnim.force_motion = false
	l.free()
