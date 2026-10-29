extends TestCase
## 0.3.2 C2/C5/C8/C9: join phases, errors, reconnect window, revive hold, party line.


func test_join_phases_and_errors() -> void:
	check(CoopFlow.phase(NetSession.State.CONNECTING, false, false, false) == CoopFlow.PHASE_CONNECTING, "connecting")
	check(CoopFlow.phase(NetSession.State.LOBBY, false, false, false) == CoopFlow.PHASE_HANDSHAKE, "handshake")
	check(CoopFlow.phase(NetSession.State.LOBBY, true, false, false) == CoopFlow.PHASE_WORLD, "world load")
	check(CoopFlow.phase(NetSession.State.IN_GAME, false, false, false) == CoopFlow.PHASE_HOST_LOADING, "host loading")
	check(CoopFlow.phase(NetSession.State.IN_GAME, true, false, false) == CoopFlow.PHASE_IN_WORLD, "in world")
	check(CoopFlow.phase(NetSession.State.IN_GAME, true, true, false) == CoopFlow.PHASE_FAILED, "failure wins")
	check(CoopFlow.phase(NetSession.State.LOBBY, false, false, true) == CoopFlow.PHASE_ENDED, "ended")
	check(CoopFlow.phase_timeout(CoopFlow.PHASE_CONNECTING) == CoopFlow.CONNECT_TIMEOUT, "connect timeout")
	check(CoopFlow.phase_timeout(CoopFlow.PHASE_WORLD) > 0.0, "world timeout")
	check("Version mismatch" in CoopFlow.error_text("version mismatch: host a, you b"), "version")
	check(CoopFlow.error_text("the session is full") == "The host is full.", "full")
	check("Timed out" in CoopFlow.error_text("the host did not answer (check the address, port and firewall)"), "timeout")
	check(CoopFlow.error_text("host left") == "The host left the session.", "host left")
	check(CoopFlow.error_text("") == "Could not join.", "empty")


func test_reconnect_window() -> void:
	var left := CoopFlow.RECONNECT_S
	check(CoopFlow.reconnect_open(left), "opens at 30s")
	left = CoopFlow.reconnect_left(left, 10.0)
	check_near(left, 20.0, 1e-6, "counts down")
	left = CoopFlow.reconnect_left(left, 100.0)
	check(not CoopFlow.reconnect_open(left), "closes at 0")


func test_revive_hold_and_party_line() -> void:
	var step := CoopFlow.revive_step(0.0, true, 1.0, 3.0)
	check_near(float(step["p"]), 1.0, 1e-6, "hold adds")
	check(not bool(step["done"]), "not yet")
	step = CoopFlow.revive_step(2.5, true, 0.5, 3.0)
	check(bool(step["done"]), "completes on the hold")
	step = CoopFlow.revive_step(2.0, false, 0.5, 3.0)
	check_near(float(step["p"]), 1.5, 1e-6, "release drains")
	check(not bool(step["done"]), "release does not finish")
	check(CoopFlow.party_line(1) == "", "solo has no party line")
	check(CoopFlow.party_line(2) == "Party x2: enemies +60% health", "two players")
	check(CoopFlow.party_line(3) == "Party x3: enemies +120% health", "three players")
	var edge := CoopFlow.edge_marker(Vector2(-100, 400), Vector2(800, 600), 16.0)
	check(bool(edge["show"]), "off-screen marker")
	check(CoopFlow.distance_text(12.4) == "12 m", "distance")
