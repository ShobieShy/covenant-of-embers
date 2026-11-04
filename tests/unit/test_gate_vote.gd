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
