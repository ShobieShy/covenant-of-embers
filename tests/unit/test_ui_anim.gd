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


func test_pause_menu_unpauses_after_fade() -> void:  # QA round 10 (1)
	UiAnim.force_motion = true
	var p := PauseMenu.new()
	runner_tree.root.add_child(p)
	p.open()
	check(runner_tree.paused, "open pauses")
	await _wait(0.3)
	p.close()
	check(runner_tree.paused and p.visible, "still paused while the menu fades")
	await _wait(0.4)
	check(not runner_tree.paused and not p.visible, "unpaused once the fade is done")
	UiAnim.force_motion = false
	runner_tree.paused = false
	p.free()


func test_centre_at_any_size() -> void:  # QA round 10 (3)
	for res in [
		Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(1024, 600)
	]:
		var vp := SubViewport.new()
		vp.size = res
		runner_tree.root.add_child(vp)
		var c := PanelContainer.new()
		c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		c.custom_minimum_size = Vector2(1040, 600)
		c.position = Vector2(-520, -300)
		vp.add_child(c)
		UiAnim.centre(c)
		var sz := c.size * c.scale
		var mid := c.position + sz / 2.0
		check_near(mid.x, res.x / 2.0, 1.0, "%s: centred across" % res)
		check_near(mid.y, res.y / 2.0, 1.0, "%s: centred down" % res)
		check(c.position.x >= 0.0 and c.position.y >= 0.0, "%s: on screen" % res)
		check(c.position.x + sz.x <= res.x and c.position.y + sz.y <= res.y, "%s: fits" % res)
		vp.free()


func test_vote_panel_grows_both_ways() -> void:  # QA round 10 (2)
	var b := VoteBanner.new()
	runner_tree.root.add_child(b)
	check(b.panel.anchor_left == 0.5 and b.panel.anchor_right == 0.5, "top-centre anchors")
	check(b.panel.grow_horizontal == Control.GROW_DIRECTION_BOTH, "grows both ways")
	b.panel.visible = true
	b.label.text = "Waiting for party: 9 s\nNot at the stairs: Somebody Long"
	await _wait(0.1)
	var vw := b.panel.get_viewport_rect().size.x
	check_near(b.panel.position.x + b.panel.size.x / 2.0, vw / 2.0, 1.0, "centred after sizing")
	b.free()


class FakeSync:
	extends LabyrinthSync
	var t := 9.0

	func left() -> float:
		return t

	func missing() -> Array[String]:
		return ["Somebody With A Long Name"]

	func party_size() -> int:
		return 2


func test_vote_banner_centred_through_refresh() -> void:  # QA round 11 (1) and (2)
	UiAnim.force_motion = true
	var s := FakeSync.new()
	var b := VoteBanner.new()
	b.sync = s
	runner_tree.root.add_child(b)
	b.set_process(false)
	b.refresh()  # the real path: text, size, then open() with the slide
	await _wait(UiAnim.OPEN_S + 0.1)
	var vw := b.panel.get_viewport_rect().size.x
	check(b.panel.size.x > 200.0, "sized to the long text: %.0f" % b.panel.size.x)
	check_near(b.panel.position.x + b.panel.size.x / 2.0, vw / 2.0, 1.0, "centred after the slide")
	s.t = -1.0
	var ends := 0
	for i in 20:  # every frame of the close fade
		var was := UiAnim.closing(b.panel) or not b.panel.visible
		b.refresh()
		if not was and UiAnim.closing(b.panel):
			ends += 1
		await _wait(1.0 / 60.0)
	check(ends == 1 and not b.panel.visible, "closed once (%d)" % ends)
	UiAnim.force_motion = false
	b.free()
	s.free()
