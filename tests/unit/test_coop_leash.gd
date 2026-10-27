extends TestCase
## OW9: co-op leash (warn 300 m, pull 400 m) and host-side streaming around partners.


func test_states() -> void:
	check(CoopLeash.state_for(10) == CoopLeash.State.OK, "close is fine")
	check(CoopLeash.state_for(350) == CoopLeash.State.WARN, "warns past 300 m")
	check(CoopLeash.state_for(401) == CoopLeash.State.PULL, "pulls past 400 m")


func test_warn_then_pull() -> void:
	var l := CoopLeash.new()
	var p := Node3D.new()
	runner_tree.root.add_child(p)
	runner_tree.root.add_child(l)
	var said: Array = []
	l.player = p
	l.host_pos = func() -> Variant: return Vector3(100, 5, 100)
	l.height_fn = func(_x: float, _z: float) -> float: return 7.0
	l.hint = func(t: String) -> void: said.append(t)
	p.global_position = Vector3(100, 0, 450)
	check(l.check() == CoopLeash.State.WARN and said.size() == 1, "one warning")
	l.check()
	check(said.size() == 1, "not repeated every check")
	p.global_position = Vector3(100, 0, 600)
	check(l.check() == CoopLeash.State.PULL and l.pulls == 1, "pulled")
	var flat := Vector2(p.global_position.x - 100, p.global_position.z - 100).length()
	check(
		absf(flat - CoopLeash.LAND) < 0.01 and p.global_position.z > 100,
		"lands beside the host, on its side"
	)
	check(is_equal_approx(p.global_position.y, 7.0), "on the ground")
	l.host_pos = func() -> Variant: return null
	p.global_position = Vector3(9999, 0, 0)
	check(l.check() == CoopLeash.State.OK, "no host proxy yet: no pull")
	l.free()
	p.free()


func test_streamer_partners() -> void:
	var s := WorldStreamer.new()
	runner_tree.root.add_child(s)
	var rs: Array = []
	for i in 5:
		var r := RemotePlayer.new()
		runner_tree.root.add_child(r)
		r.global_position = Vector3(1000 + i, 0, 0)
		rs.append(r)
	var base := s.viewers().size()
	check(
		base == s.viewers().filter(func(v: Vector3) -> bool: return v.x < 900).size(),
		"no partners without a host session"
	)
	s.stream_partners = true
	var far := s.viewers().filter(func(v: Vector3) -> bool: return v.x >= 1000)
	check(
		far.size() == CoopLeash.MAX_PLAYERS - 1,
		"the host streams around partners, capped (%d)" % far.size()
	)
	for r in rs:
		r.free()
	s.free()
