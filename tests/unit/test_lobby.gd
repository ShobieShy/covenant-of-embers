extends TestCase
## Step 89 done check: lobby/invite flow against the fake Steam backend: create -> invite
## -> join_requested -> join -> members; full/missing lobbies fail in words; the co-op
## menu drives a real (ENet-carried) session from the fake lobby; join-on-launch arg.

var _port := 26100 + randi_range(0, 300) * 2


func test_fake_lobby_invite_flow() -> void:
	var hub := FakeLobbyBackend.Hub.new()
	var a := FakeLobbyBackend.new(hub, "ana")
	var b := FakeLobbyBackend.new(hub, "bo")
	var got := []
	b.join_requested.connect(func(id: int, who: String): got.append([id, who]))
	check(not a.invite("bo"), "no lobby yet")
	check(a.create_lobby() and a.lobby_id != 0, "created")
	check(a.invite("bo") and got.size() == 1 and got[0][1] == "ana", "invite delivered %s" % [got])
	check(not a.invite("nobody"), "offline friend")
	check(b.join_lobby(int(got[0][0])), "joined")
	check(a.members() == PackedStringArray(["ana", "bo"]), "members %s" % [a.members()])
	for n in ["c", "d"]:
		FakeLobbyBackend.new(hub, n).join_lobby(a.lobby_id)
	var e := FakeLobbyBackend.new(hub, "e")
	check(not e.join_lobby(a.lobby_id) and e.last_error.contains("full"), "full: %s" % e.last_error)
	check(not e.join_lobby(42) and e.last_error.contains("no longer"), "missing lobby")
	b.leave_lobby()
	check(not a.members().has("bo"), "left")
	hub.close()


func test_launch_arg() -> void:
	check(LobbyBackend.launch_lobby(PackedStringArray(["--x", "+connect_lobby", "1234"])) == 1234, "parsed")
	check(LobbyBackend.launch_lobby(PackedStringArray(["+connect_lobby"])) == 0, "missing id")


func test_steam_backend_without_steam() -> void:
	var t := SteamTransport.new()
	t.singleton_name = "NoSuchSteam"
	var s := SteamLobbyBackend.new(t)
	check(not s.available() and not s.create_lobby() and s.last_error.contains("Direct IP"), s.last_error)


func _wait(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


func test_menu_lobby_session() -> void:
	_port += 1
	var hub := FakeLobbyBackend.Hub.new()
	hub.port = _port
	var w := Node.new()
	runner_tree.root.add_child(w)
	var hm := CoopMenu.new()
	var cm := CoopMenu.new()
	hm.lobby = FakeLobbyBackend.new(hub, "host")
	cm.lobby = FakeLobbyBackend.new(hub, "friend")
	w.add_child(hm)
	w.add_child(cm)
	# Two menus in one process: give each its own session node (the game uses one per process).
	hm.session = _own_session(w, "HS", hm)
	cm.session = _own_session(w, "CS", cm)
	cm._ensure_lobby()
	hm.invite_name = "friend"
	hm.press("host_steam")
	check(hm.session.is_host(), "host session from the lobby")
	hm.press("invite_steam")
	check(await _wait(func(): return hm.session.roster.size() == 2), "friend joined through the invite")
	check(cm.session.state == NetSession.State.LOBBY, "client in the lobby")
	cm.session.leave("test done")
	for i in 5:
		await runner_tree.process_frame
	hm.session.leave("test done")
	for i in 5:
		await runner_tree.process_frame
	hm.lobby.leave_lobby()
	cm.lobby.leave_lobby()
	hub.close()
	w.queue_free()


func _own_session(parent: Node, n: String, m: CoopMenu) -> NetSession:
	var s := NetSession.new()
	s.name = n
	parent.add_child(s)
	s.roster_changed.connect(m._on_roster)
	s.failed.connect(m._on_failed)
	s.ended.connect(m._on_ended)
	return s
