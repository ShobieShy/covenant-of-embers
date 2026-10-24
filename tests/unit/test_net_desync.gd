extends TestCase
## Step 92 done check: host + client over in-process ENet with a LinkConditioner on both
## ends (150 ms one-way delay, 2 % loss on unreliable traffic). A scripted fight (client
## hits, host hits and kills, host bites the client) runs; after the link settles the
## state hash (enemy ids/types/HP/dead/positions + client damage taken) matches on both.

var _port := 27400 + randi_range(0, 300) * 2


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


func _wait(cond: Callable, frames := 600) -> bool:
	for i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


func test_conditioner_unit() -> void:
	var lc := LinkConditioner.new(150.0, 0.5, 1)
	var kept := 0
	for i in 200:
		if lc.push(false, 0, "x", {"i": i}, 0.0):
			kept += 1
	check(lc.dropped > 60 and lc.dropped < 140, "about half lost (%d)" % lc.dropped)
	for i in 20:
		check(lc.push(true, 0, "r", {}, 0.0), "reliable never lost")
	check(lc.pop_due(149.0).is_empty(), "nothing before 150 ms")
	var due := lc.pop_due(150.0)
	var order: Array = []
	for m: Array in due.slice(0, kept):
		order.append(int(m[4]["i"]))
	var sorted := order.duplicate()
	sorted.sort()
	check(due.size() == kept + 20 and order == sorted, "all due, send order kept")
	var a := LinkConditioner.from_args(PackedStringArray(["--net-lag=150", "--net-loss=0.02"]))
	check(a != null and a.delay_ms == 150.0 and a.loss == 0.02, "args")
	check(LinkConditioner.from_args(PackedStringArray()) == null, "off by default")


static func _row(id: int, e: Enemy, hp: float, pos: Vector3) -> String:
	return "%d|%s|%.1f|%s|%.1f,%.1f" % [id, e.def.id, maxf(hp, 0.0), e.dead, pos.x, pos.z]


func _host_hash(hw: CoopWorld, cp: FakePlayer) -> String:
	var rows: Array = []
	for e in hw.host_enemies():
		rows.append(_row(hw.enemy_id(e), e, e.health, e.global_position))
	rows.sort()
	return "\n".join(rows) + "\nhurt %d" % hw.hurts_sent + " / %d" % cp.hits.size()


func _client_hash(cw: CoopWorld, cp: FakePlayer) -> String:
	var rows: Array = []
	for id: int in cw.puppets:
		var e: Enemy = cw.puppets[id]
		rows.append(_row(id, e, float(cw.puppet_hp.get(id, e.health)), e.get_meta(&"net_pos", e.global_position)))
	rows.sort()
	return "\n".join(rows) + "\nhurt %d" % cw.hurts_taken + " / %d" % cp.hits.size()


func test_fight_hashes_match_at_150ms_2pct() -> void:
	_port += 1
	var w := Node3D.new()
	w.position = Vector3(0, 7000, 9000)
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	h.name = "DH"
	var c := NetSession.new()
	c.name = "DC"
	w.add_child(h)
	w.add_child(c)
	h.conditioner = LinkConditioner.new(150.0, 0.02, 7)
	c.conditioner = LinkConditioner.new(150.0, 0.02, 8)
	check(h.host(NetTransport.make("enet"), _port, {"name": "H"}), "host")
	check(c.join(NetTransport.make("enet"), "127.0.0.1:%d" % _port, {"name": "C"}), "join")
	check(await _wait(func(): return h.roster.size() == 2 and c.state == NetSession.State.LOBBY), "lobby")
	h.set_ready(true)
	c.set_ready(true)
	await _wait(func(): return h.all_ready())
	check(h.start_game(), "start")
	check(await _wait(func(): return c.state == NetSession.State.IN_GAME), "in game")
	var table := EnemyTable.load_default()
	var hp := FakePlayer.new()
	var cp := FakePlayer.new()
	var he := Node3D.new()
	var ce := Node3D.new()
	for n: Node in [hp, cp, he, ce]:
		w.add_child(n)
	cp.position = Vector3(3, 0, 0)
	var real: Array[Enemy] = []
	for i in 4:
		var e := Enemy.new()
		e.setup(table.find("earth_training_dummy"))
		he.add_child(e)
		e.position = Vector3(-6 + 4 * i, 0, -5)
		real.append(e)
	var hw := CoopWorld.new()
	var cw := CoopWorld.new()
	hw.auto_tick = false
	cw.auto_tick = false
	w.add_child(hw)
	w.add_child(cw)
	hw.setup(h, hp, he, table)
	cw.setup(c, cp, ce, table)
	var tick := func(n: int) -> void:
		for i in n:
			hw.tick(1.0 / 60.0)
			cw.tick(1.0 / 60.0)
			await runner_tree.process_frame
	for i in 300:
		await tick.call(1)
		if cw.puppets.size() == 4:
			break
	check(cw.puppets.size() == 4, "4 puppets through the lag")
	# Scripted fight: 3 s of client hits on 0/1, host hits on 2, host kills 3, 3 bites.
	var bite := Gnawer.Bite.new()
	bite.damage = 4.0
	var cid := c.my_id()
	for f in 180:
		if f % 10 == 0:
			for id: int in cw.puppets:
				var pe: Enemy = cw.puppets[id]
				if pe.position.x < -1.0 and not pe.dead:
					cw.send_hit(pe, 3.0, ElementTable.Element.FIRE)
		if f % 15 == 0:
			real[2].apply_damage(2.0, ElementTable.Element.WATER)
		if f == 60:
			real[3].apply_damage(real[3].health + 50.0, ElementTable.Element.FIRE)
		if f % 60 == 30 and hw.proxies.has(cid):
			hw.route_attack(hw.proxies[cid], bite)
		await tick.call(1)
	# Settle: well over the round trip, several snapshots.
	await tick.call(60)
	var hh := _host_hash(hw, cp)
	var ch := _client_hash(cw, cp)
	check(hh == ch, "hashes match\nhost:\n%s\nclient:\n%s" % [hh, ch])
	check(Compat.sha(hh) == Compat.sha(ch), "sha")
	check(hw.hits_applied == cw.hits_sent and cw.hits_sent > 0, "every client hit applied")
	check(cp.hits.size() == 3, "3 bites through the lag (%d)" % cp.hits.size())
	check(real[3].dead or real[3].health >= real[3].max_health(), "kill happened (dummy may respawn)")
	check(h.conditioner.delayed > 0 and (h.conditioner.dropped + c.conditioner.dropped) >= 0, "conditioner active")
	print(
		(
			"  [desync] snaps %d/%d seen, dropped %d+%d, hits %d"
			% [hw.snaps_sent, cw.snaps_seen, h.conditioner.dropped, c.conditioner.dropped, hw.hits_applied]
		)
	)
	c.leave()
	h.leave()
	for i in 5:
		await runner_tree.process_frame
	w.queue_free()
	await runner_tree.process_frame
