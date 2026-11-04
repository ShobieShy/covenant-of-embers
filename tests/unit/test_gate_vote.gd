extends TestCase
## 0.4.0: a co-op level change waits for the party, or 15 seconds, then the host travels.


class FakeSession:
	extends Node
	signal message(from: int, kind: String, data: Dictionary)
	var roster := {1: {"name": "Host"}, 2: {"name": "Joiner"}}
	var sent: Array = []

	func send(kind: String, data: Dictionary, _to := 0, _reliable := true) -> void:
		sent.append([kind, data])
		message.emit(1, kind, data.duplicate(true))


func test_solo_travels_immediately() -> void:
	var s := FakeSession.new()
	s.roster = {1: {"name": "Host"}}
	runner_tree.root.add_child(s)
	var v := GateVote.new()
	runner_tree.root.add_child(v)
	v.setup(s, true)
	check(not v.begin("breach", "", Vector3.ZERO), "one player does not vote")
	check(v.left() < 0.0, "no countdown")
	v.free()
	s.free()


func test_party_vote_times_out_and_can_gather() -> void:
	var s := FakeSession.new()
	runner_tree.root.add_child(s)
	var v := GateVote.new()
	runner_tree.root.add_child(v)
	v.setup(s, true)
	var host := Node3D.new()
	host.name = "HostBody"
	host.add_to_group(Player.GROUP)
	var joiner := Node3D.new()
	joiner.name = "JoinerBody"
	joiner.set_meta(&"player_name", "Ada")
	joiner.add_to_group(&"coop_avatars")
	runner_tree.root.add_child(host)
	runner_tree.root.add_child(joiner)
	joiner.global_position = Vector3(40, 0, 0)
	check(v.begin("midden", "landfill", Vector3.ZERO), "two players vote")
	check(v.missing() == ["Ada"], "Ada is not at the gate")
	check(v.banner != null, "banner exists")
	v.banner.refresh()
	check(v.banner.panel.visible, "the vote banner is up")
	var went := []
	v.decided.connect(func(to: String, anchor: String) -> void: went.append([to, anchor]))
	v.tick(1.0)
	check(went.is_empty() and v.left() < GateVote.VOTE_S, "still waiting")
	joiner.global_position = Vector3.ZERO
	v.tick(0.1)
	check(went == [["midden", "landfill"]], "gathered: travel")
	check(v.left() < 0.0, "vote closed")
	for n in [v, host, joiner, s]:
		n.free()


func test_walking_away_cancels() -> void:
	var s := FakeSession.new()
	runner_tree.root.add_child(s)
	var v := GateVote.new()
	runner_tree.root.add_child(v)
	v.setup(s, true)
	var host := Node3D.new()
	host.add_to_group(Player.GROUP)
	runner_tree.root.add_child(host)
	var joiner := Node3D.new()
	joiner.add_to_group(&"coop_avatars")
	runner_tree.root.add_child(joiner)
	joiner.global_position = Vector3(30, 0, 0)
	v.begin("breach", "", Vector3.ZERO)
	host.global_position = Vector3(30, 0, 0)
	var went := []
	v.decided.connect(func(_t, _a) -> void: went.append(true))
	v.tick(0.2)
	check(went.is_empty() and v.left() < 0.0, "the host left, so the vote stops")
	for n in [v, host, joiner, s]:
		n.free()


func test_freed_reconnecting_body_does_not_pass() -> void:
	var s := FakeSession.new()
	s.roster[2] = {"name": "Ada", "reconnecting": true}
	runner_tree.root.add_child(s)
	var v := GateVote.new()
	runner_tree.root.add_child(v)
	v.setup(s, true)
	var host := Node3D.new()
	host.add_to_group(Player.GROUP)
	var ada := Node3D.new()
	ada.name = "AdaBody"
	ada.set_meta(&"player_name", "Ada")
	ada.add_to_group(&"coop_avatars")
	runner_tree.root.add_child(host)
	runner_tree.root.add_child(ada)
	ada.global_position = Vector3(40, 0, 0)
	v.begin("midden", "", Vector3.ZERO)
	ada.free()
	var went := []
	v.decided.connect(func(to: String, _a: String) -> void: went.append(to))
	v.tick(0.2)
	check(went.is_empty(), "freeing Ada does not travel")
	check(v.missing().has("Ada"), "Ada is still missing (%s)" % [v.missing()])
	s.roster.erase(2)
	v.tick(0.2)
	check(went == ["midden"], "after the reconnect window the host at the gate proceeds")
	for n in [v, host, s]:
		n.free()


func test_vote_timeout_still_travels() -> void:
	var s := FakeSession.new()
	runner_tree.root.add_child(s)
	var v := GateVote.new()
	runner_tree.root.add_child(v)
	v.setup(s, true)
	var host := Node3D.new()
	host.add_to_group(Player.GROUP)
	var ada := Node3D.new()
	ada.set_meta(&"player_name", "Ada")
	ada.add_to_group(&"coop_avatars")
	runner_tree.root.add_child(host)
	runner_tree.root.add_child(ada)
	ada.global_position = Vector3(40, 0, 0)
	v.begin("breach", "town_gate", Vector3.ZERO)
	var went := []
	v.decided.connect(func(to: String, anchor: String) -> void: went.append([to, anchor]))
	v.tick(GateVote.VOTE_S)
	check(went == [["breach", "town_gate"]], "15 s still defaults to yes")
	for n in [v, host, ada, s]:
		n.free()


func test_ready_is_not_logged_as_cancelled() -> void:
	var s := FakeSession.new()
	runner_tree.root.add_child(s)
	var host_vote := GateVote.new()
	var join_vote := GateVote.new()
	runner_tree.root.add_child(host_vote)
	runner_tree.root.add_child(join_vote)
	host_vote.setup(s, true)
	join_vote.setup(s, false)
	var host := Node3D.new()
	host.add_to_group(Player.GROUP)
	var ada := Node3D.new()
	ada.set_meta(&"player_name", "Ada")
	ada.add_to_group(&"coop_avatars")
	runner_tree.root.add_child(host)
	runner_tree.root.add_child(ada)
	host_vote.begin("midden", "", Vector3.ZERO)
	check(join_vote.result == "waiting", "the countdown is not a cancel")
	ada.global_position = Vector3.ZERO
	host_vote.tick(0.1)
	check(join_vote.result == "ready", "a finished vote is ready, not cancelled")
	host_vote.free()
	join_vote.free()
	var host_vote2 := GateVote.new()
	var join_vote2 := GateVote.new()
	runner_tree.root.add_child(host_vote2)
	runner_tree.root.add_child(join_vote2)
	host_vote2.setup(s, true)
	join_vote2.setup(s, false)
	host.global_position = Vector3.ZERO
	ada.global_position = Vector3(40, 0, 0)
	host_vote2.begin("breach", "", Vector3.ZERO)
	host.global_position = Vector3(30, 0, 0)
	host_vote2.tick(0.2)
	check(join_vote2.result == "cancelled", "walking away is still a cancel")
	for n in [host_vote2, join_vote2, host, ada, s]:
		n.free()
