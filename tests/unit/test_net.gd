extends TestCase
## Step 78 done check: two headless ENet peers in one process (each NetSession has its own
## SceneMultiplayer): connect, lobby roster, ready-up, host-only start, messages both ways,
## the host leaving ends the client's session; the version gate rejects; Steam reports
## itself unavailable (headless never starts it) without crashing.

var _port := 24790 + randi_range(0, 400) * 2


func _wait(cond: Callable, frames := 240) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


func _pair() -> Array:
	_port += 1
	var w := Node.new()
	w.name = "NetTest%d" % _port
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	h.name = "Host"
	var c := NetSession.new()
	c.name = "Client"
	w.add_child(h)
	w.add_child(c)
	return [w, h, c]


func test_address_parse() -> void:
	check(NetAddress.parse("10.0.0.5:7777") == {"host": "10.0.0.5", "port": 7777}, "ip:port")
	check(NetAddress.parse("example.org")["port"] == NetTransport.DEFAULT_PORT, "default port")
	check(NetAddress.parse("[::1]:900") == {"host": "::1", "port": 900}, "ipv6")
	check(NetAddress.parse("").has("error") and NetAddress.parse("a:b").has("error"), "errors")
	check(NetAddress.parse("a:70000").has("error"), "port range")


func test_lobby_ready_start_and_host_leave() -> void:
	var s := _pair()
	var h: NetSession = s[1]
	var c: NetSession = s[2]
	check(h.host(EnetTransport.new(), _port, {"name": "Host"}), "host: %s" % h.last_reason)
	check(h.is_host() and h.roster.size() == 1, "host roster")
	check(c.join(EnetTransport.new(), "127.0.0.1:%d" % _port, {"name": "Guest"}), "join")
	check(await _wait(func(): return c.state == NetSession.State.LOBBY and h.roster.size() == 2), "lobby")
	check(c.roster.size() == 2 and not c.is_host(), "client sees both")
	check(not h.start_game(), "no start before everyone is ready")
	h.set_ready(true)
	c.set_ready(true)
	check(await _wait(func(): return h.all_ready() and c.all_ready()), "ready-up syncs")
	check(not c.start_game(), "clients cannot start")
	var got := []
	c.message.connect(func(from, k, d): got.append([from, k, d]))
	h.message.connect(func(from, k, d): got.append([from, k, d]))
	check(h.start_game(), "host starts")
	check(await _wait(func(): return c.state == NetSession.State.IN_GAME), "client in game")
	check(h.state == NetSession.State.IN_GAME, "host in game")
	h.send("ping", {"n": 1})
	c.send("pong", {"n": 2}, 1)
	check(await _wait(func(): return got.size() >= 2), "messages both ways (%d)" % got.size())
	var reasons := []
	c.ended.connect(func(r): reasons.append(r))
	h.leave()
	check(await _wait(func(): return not reasons.is_empty()), "host leaving ends the client")
	check(reasons == ["host left"] and c.state == NetSession.State.ENDED, "reason")
	s[0].queue_free()


func test_version_gate() -> void:
	var s := _pair()
	var h: NetSession = s[1]
	var c: NetSession = s[2]
	h.host(EnetTransport.new(), _port, {"name": "Host"})
	var fails := []
	c.failed.connect(func(r): fails.append(r))
	c.join(EnetTransport.new(), "127.0.0.1:%d" % _port, {"name": "Old"})
	c.local_info["version"] = "0.0.0/p0"
	check(await _wait(func(): return not fails.is_empty()), "rejected")
	check(String(fails[0]).begins_with("version mismatch"), "reason: %s" % [fails])
	check(h.roster.size() == 1, "host roster unchanged")
	h.leave()
	s[0].queue_free()


func test_join_nobody_times_out() -> void:
	var s := _pair()
	var c: NetSession = s[2]
	c.join(EnetTransport.new(), "127.0.0.1:%d" % (_port + 500), {"name": "Lost"})
	c._connect_left = 0.3
	check(await _wait(func(): return c.state == NetSession.State.IDLE), "gives up")
	check(c.last_reason != "", "explains: %s" % c.last_reason)
	s[0].queue_free()


func test_steam_unavailable_headless() -> void:
	var t := SteamTransport.new()
	check(not t.available(), "not started in tests")
	check(not t.init(), "headless never inits: " + t.last_error)
	check(t.host(1) == null and t.join(1) == null and t.last_error != "", "no peer, an error")
	var missing := SteamTransport.new()
	missing.singleton_name = "SteamMissingForTest"
	check(not missing.has_extension() and not missing.init(), "missing extension handled")
	check(missing.describe() == "steam (not installed)", missing.describe())
	check(NetTransport.make("steam") is SteamTransport and NetTransport.make("enet") is EnetTransport, "factory")
	var s := _pair()
	check(not (s[1] as NetSession).host(t, 1, {}), "session reports steam failure")
	s[0].queue_free()
