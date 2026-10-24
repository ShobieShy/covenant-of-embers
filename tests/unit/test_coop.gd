extends TestCase
## Step 79 done check: two in-process ENet sessions with a CoopWorld each. The host's
## enemy shows up as a puppet on the client (same type, pose converges), poses make
## RemotePlayers both ways, a client hit lands on the host's enemy, the host's kill kills
## the puppet (and is announced on the client's own EventBus, so its own loot/XP roll),
## and a bite on the client's RemotePlayer reaches the client's player.

var _port := 25400 + randi_range(0, 300) * 2


class FakePlayer:
	extends Node3D
	var hits: Array = []
	var downed := false

	func alive() -> bool:
		return true

	func invulnerable() -> bool:
		return false

	func on_enemy_attack(_from: Variant, bite: Gnawer.Bite) -> void:
		hits.append(bite.damage)


func _wait(cond: Callable, frames := 300) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


## {root, h, c, hw, cw, hp, cp, henemies, cenemies}
func _coop_pair() -> Dictionary:
	_port += 1
	var w := Node3D.new()
	w.name = "CoopTest%d" % _port
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	h.name = "Host"
	var c := NetSession.new()
	c.name = "Client"
	w.add_child(h)
	w.add_child(c)
	check(h.host(NetTransport.make("enet"), _port, {"name": "H"}), "host")
	check(c.join(NetTransport.make("enet"), "127.0.0.1:%d" % _port, {"name": "C"}), "join")
	check(await _wait(func(): return h.roster.size() == 2 and c.state == NetSession.State.LOBBY), "lobby")
	h.set_ready(true)
	c.set_ready(true)
	await _wait(func(): return h.all_ready())
	check(h.start_game(), "start")
	check(await _wait(func(): return c.state == NetSession.State.IN_GAME), "client in game")
	var d := {"root": w, "h": h, "c": c}
	for side in ["h", "c"]:
		var p := FakePlayer.new()
		w.add_child(p)
		p.global_position = Vector3(0, 0, 0) if side == "h" else Vector3(3, 0, 0)
		var en := Node3D.new()
		w.add_child(en)
		var cw := CoopWorld.new()
		cw.auto_tick = false
		w.add_child(cw)
		d[side + "p"] = p
		d[side + "enemies"] = en
		d[side + "w"] = cw
	return d


func _tick_both(d: Dictionary, n := 1) -> void:
	for i in n:
		(d["hw"] as CoopWorld).tick(1.0 / 60.0)
		(d["cw"] as CoopWorld).tick(1.0 / 60.0)
		await runner_tree.process_frame


func test_puppets_poses_hits_kills_and_hurt() -> void:
	var d := await _coop_pair()
	var table := EnemyTable.load_default()
	var real := Enemy.new()
	real.setup(table.find("earth_training_dummy"))
	(d["henemies"] as Node).add_child(real)
	real.global_position = Vector3(5, 0, -4)
	var stray := Enemy.new()  # a client-side spawn gets removed: the host owns enemies
	stray.setup(table.find("gnawer"))
	(d["cenemies"] as Node).add_child(stray)
	var hw: CoopWorld = d["hw"]
	var cw: CoopWorld = d["cw"]
	hw.setup(d["h"], d["hp"], d["henemies"], table)
	cw.setup(d["c"], d["cp"], d["cenemies"], table)
	check(hw.host and not cw.host, "roles")
	var cid := (d["c"] as NetSession).my_id()
	for i in 120:
		await _tick_both(d)
		if cw.puppets.size() == 1 and hw.proxies.has(cid) and cw.proxies.has(1):
			break
	await _tick_both(d, 30)
	check(not is_instance_valid(stray) or stray.is_queued_for_deletion(), "client spawner emptied")
	check(cw.puppets.size() == 1, "one puppet (%d)" % cw.puppets.size())
	var pup: Enemy = cw.puppets.values()[0] if cw.puppets.size() > 0 else null
	check(pup != null and pup.def.id == "earth_training_dummy", "same type")
	check(pup != null and pup.global_position.distance_to(real.global_position) < 0.2, "pose converged")
	check(
		hw.proxies.has(cid) and (hw.proxies[cid] as RemotePlayer).global_position.distance_to(Vector3(3, 0, 0)) < 0.3,
		"host sees client"
	)
	check(cw.proxies.has(1), "client sees host")
	# A client hit reaches the host's enemy.
	var before := real.health
	cw.send_hit(pup, 5.0, ElementTable.Element.FIRE)
	check(
		await _wait(func(): return real.health < before), "hit applied on host (%.1f -> %.1f)" % [before, real.health]
	)
	check(hw.hits_applied == 1, "one hit applied")
	# The host's kill kills the puppet; the client's bus hears it (its own loot/XP roll).
	var kills_before := GameEvents.bus().kills
	real.apply_damage(real.health + 10.0, ElementTable.Element.FIRE)
	for i in 60:
		await _tick_both(d)
		if pup.dead:
			break
	check(pup.dead, "puppet died with the host's enemy")
	check(GameEvents.bus().kills >= kills_before + 2, "kill announced on both peers")
	# Dummy respawn on the host brings the puppet back.
	real.reset()
	for i in 60:
		await _tick_both(d)
		if not pup.dead:
			break
	check(not pup.dead, "puppet back after host reset")
	# A bite on the client's RemotePlayer (host side) lands on the client's player.
	var b := Gnawer.Bite.new()
	b.damage = 7.0
	hw.route_attack(hw.proxies[cid], b)
	check(await _wait(func(): return (d["cp"] as FakePlayer).hits.size() == 1), "client hurt")
	check(cw.hurts_taken == 1 and (d["hp"] as FakePlayer).hits.is_empty(), "only the client")
	hw.route_attack(d["hp"], b)
	check((d["hp"] as FakePlayer).hits == [7.0], "host's own bite stays local")
	# Nearest target: the client's proxy is nearer to an enemy at x=4.
	check(hw.nearest_target(Vector3(4, 0, 0)) == hw.proxies[cid], "nearest = remote")
	(d["c"] as NetSession).leave()
	(d["h"] as NetSession).leave()
	(d["root"] as Node).queue_free()
	await runner_tree.process_frame
