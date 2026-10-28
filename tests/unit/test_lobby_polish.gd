extends TestCase
## 0.3.1 P6 (L2): join phases, the party frame damage chip and the "host is loading" wait.

const S := NetSession.State


func test_join_phase() -> void:
	check(CoopMenu.join_phase(S.CONNECTING, false) == "Connecting ...", "connecting")
	check(CoopMenu.join_phase(S.LOBBY, false) == "In the lobby", "lobby")
	check(CoopMenu.join_phase(S.LOBBY, true) == "Loading the world ...", "loading")
	check(CoopMenu.join_phase(S.IN_GAME, true) == "In the world", "in world")
	check(CoopMenu.join_phase(S.IDLE, false) == "", "idle: nothing")


func test_chip_math() -> void:
	var c := PartyFrames.chip_step(100.0, 60.0, 0.0, 0.2, 100.0)
	check(c[0] == 100.0 and is_equal_approx(c[1], 0.2), "holds first")
	c = PartyFrames.chip_step(c[0], 60.0, c[1], 0.3, 100.0)
	check(c[0] < 100.0 and c[0] > 60.0, "then drains (%s)" % c[0])
	for i in 60:
		c = PartyFrames.chip_step(c[0], 60.0, c[1], 0.1, 100.0)
	check(is_equal_approx(c[0], 60.0), "lands on health")
	c = PartyFrames.chip_step(60.0, 80.0, 1.0, 0.1, 100.0)
	check(c[0] == 80.0 and c[1] == 0.0, "a heal snaps the chip up")


func test_host_loading_overlay() -> void:
	var cw := CoopWorld.new()
	var f := PartyFrames.new()
	runner_tree.root.add_child(f)
	f.bind(cw)
	f.refresh(1.0)
	check(not f.waiting.visible, "no session (or host): no overlay")
	f.free()
	cw.free()
