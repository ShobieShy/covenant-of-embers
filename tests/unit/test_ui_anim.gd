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
