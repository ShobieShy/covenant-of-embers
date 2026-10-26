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

	var healed := 0.0

	func on_ally_heal(a: float) -> void:
		healed += a

	func revive(_f: float) -> bool:
		downed = false
		return true


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
	# Step 94: a stale "alive" snapshot overtaken by the kill must not revive (and recount) it.
	var pid: int = cw.puppets.keys()[0]
	var seen := cw.kills_seen
	cw._snap_dead[pid] = false
	cw._apply_snapshot([[pid, pup.def.id, pup.global_position, 0.0, 5.0, pup.max_health(), false]])
	check(pup.dead and cw.kills_seen == seen, "stale snapshot ignored (no double kill)")
	# Dummy respawn on the host brings the puppet back (after the client saw it dead in a
	# snapshot; step 94: a stale alive snapshot alone must not revive it).
	await _tick_both(d, 20)
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


const PLAYER_SCENE := "res://scenes/player/player.tscn"


## Step 80: last stand -> bleed out -> respawn countdown; revive puts you up where you fell.
func test_downed_revive_and_bleed_out() -> void:
	var p := (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.last_stand = 2.0
	p.take_enemy_hit(99999.0, ElementTable.Element.FIRE)
	check(not p.alive() and p.downed, "downed, not dead-dead")
	check(p.revive(0.3), "revive works")
	check(p.alive() and not p.downed and p.revives == 1, "revived")
	check_near(p.health.value, p.health.max_value() * 0.3, 0.5, "30 pct health after revive")
	p.protection_left = 0.0
	p.take_enemy_hit(99999.0, ElementTable.Element.FIRE)
	check(p.downed, "down again")
	var input := PlayerInput.new()
	for i in 130:
		p.tick(input, 1.0 / 60.0)
	check(not p.downed and p.bleed_outs == 1 and not p.alive(), "bled out after 2 s")
	check(p.respawn_left > 0.0, "respawn countdown running")
	p.queue_free()
	await runner_tree.process_frame


## Step 80: enemy health x1.6 for 2 players (fraction kept), and a teammate beside a
## downed player revives them after REVIVE_TIME; party frames list the other player.
func test_scaling_revive_and_party_frames() -> void:
	var d := await _coop_pair()
	var table := EnemyTable.load_default()
	var real := Enemy.new()
	real.setup(table.find("gnawer"))
	(d["henemies"] as Node).add_child(real)
	var hw: CoopWorld = d["hw"]
	var cw: CoopWorld = d["cw"]
	hw.setup(d["h"], d["hp"], d["henemies"], table)
	cw.setup(d["c"], d["cp"], d["cenemies"], table)
	await _tick_both(d, 3)
	check_near(real.max_health(), real.def.max_health * 1.6, 0.01, "x1.6 health")
	check_near(real.health, real.max_health(), 0.01, "full")
	var frames := PartyFrames.new()
	(d["root"] as Node).add_child(frames)
	frames.bind(hw)
	for i in 60:
		await _tick_both(d)
		if hw.proxies.size() == 1 and cw.proxies.size() == 1:
			break
	frames.refresh()
	var cid := (d["c"] as NetSession).my_id()
	check(frames.row_text(cid).begins_with("C"), "party row: %s" % frames.row_text(cid))
	# The client's (fake) player goes down next to the host: revived after 3 s.
	var cp: FakePlayer = d["cp"]
	cp.downed = true
	(d["hp"] as Node3D).global_position = cp.global_position + Vector3(1, 0, 0)
	for i in 400:
		await _tick_both(d)
		if cw.revives > 0:
			break
	check(cw.revives == 1, "revived by the host standing beside")
	(d["c"] as NetSession).leave()
	(d["h"] as NetSession).leave()
	(d["root"] as Node).queue_free()
	await runner_tree.process_frame


## Step 108: a Light heal on a RemotePlayer reaches its owner; a client's Dark hit carries
## its part bonus and the host rolls the conversion; the ally flag reaches the puppet, and
## a client's Light heal on that puppet heals the host's brute.
func test_light_heal_and_dark_convert() -> void:
	var d := await _coop_pair()
	var table := EnemyTable.load_default()
	var real := Enemy.create(table.find("gnawer"), Transform3D(Basis(), Vector3(6, 0, -6)))
	(d["henemies"] as Node).add_child(real)
	(real as Gnawer).auto_tick = false
	var hw: CoopWorld = d["hw"]
	var cw: CoopWorld = d["cw"]
	hw.setup(d["h"], d["hp"], d["henemies"], table)
	cw.setup(d["c"], d["cp"], d["cenemies"], table)
	var cid := (d["c"] as NetSession).my_id()
	for i in 120:
		await _tick_both(d)
		if cw.puppets.size() == 1 and hw.proxies.has(cid):
			break
	(hw.proxies[cid] as RemotePlayer).light_healed.emit(12.0)
	check(await _wait(func(): return (d["cp"] as FakePlayer).healed == 12.0), "client healed by host's Light")
	var pup: Enemy = cw.puppets.values()[0]
	MagicEffects.dark_roll = func() -> float: return 0.02
	cw.send_hit(pup, 1.0, ElementTable.Element.DARK, 0.0)
	await _wait(func(): return hw.hits_applied == 1)
	check(not real.is_ally(), "roll 0.02 vs 1%: no")
	cw.send_hit(pup, 1.0, ElementTable.Element.DARK, 0.015)
	check(await _wait(func(): return real.is_ally()), "with +1.5% the host converts it")
	MagicEffects.dark_roll = Callable()
	for i in 60:
		await _tick_both(d)
		if pup.is_ally():
			break
	check(pup.is_ally(), "puppet shows the ally")
	real.health = 3.0
	var h := SpellBolts.Hit.new()
	h.collider = pup
	h.source = d["cp"]
	h.element = ElementTable.Element.LIGHT
	h.damage = 10.0
	check(MagicEffects.intercept(h), "client Light on ally puppet intercepted")
	check(await _wait(func(): return is_equal_approx(real.health, 11.0)), "host brute healed 8 (%.1f)" % real.health)
	(d["c"] as NetSession).leave()
	(d["h"] as NetSession).leave()
	(d["root"] as Node).queue_free()
	await runner_tree.process_frame


## Step 142 (Brands B8): PROTOCOL 2; the pose carries the held brand's FX (bits, meter,
## colour) and the RemotePlayer shows it; a client's blast/chain damage on a puppet
## (MagicEffects._hurt) reaches the host's real enemy as a "hit".
func test_brand_fx_and_blast_hits() -> void:
	check(NetSession.PROTOCOL == 2, "protocol 2 (brands)")
	check(NetSession.version().ends_with("/p2"), "older builds can't join")
	var d := await _coop_pair()
	var table := EnemyTable.load_default()
	var real := Enemy.new()
	real.setup(table.find("earth_training_dummy"))
	(d["henemies"] as Node).add_child(real)
	real.global_position = Vector3(5, 0, -4)
	var hw: CoopWorld = d["hw"]
	var cw: CoopWorld = d["cw"]
	hw.setup(d["h"], d["hp"], d["henemies"], table)
	cw.setup(d["c"], d["cp"], d["cenemies"], table)
	var cid := (d["c"] as NetSession).my_id()
	for i in 120:
		await _tick_both(d)
		if cw.puppets.size() == 1 and hw.proxies.has(cid) and cw.proxies.has(1):
			break
	var rp: RemotePlayer = hw.proxies[cid]
	rp.apply_pose({"p": Vector3(3, 0, 0), "bf": [BrandFX.BIT_HOT | BrandFX.BIT_VENT, 1.0, "ff7326"]})
	check(rp.brand_fx != null and rp.brand_fx.bits == 3 and rp.brand_fx.puffs == 1, "remote heat + vent steam")
	rp.apply_pose({"p": Vector3(3, 0, 0)})
	check(rp.brand_fx.bits == 0 and not rp.brand_fx.glow.visible, "no bf = unbranded")
	check(CoopWorld.brand_fx_of(d["cp"]).is_empty(), "no caster: nothing sent")
	var pup: Enemy = cw.puppets.values()[0]
	var before := real.health
	MagicEffects._hurt(pup, 4.0, ElementTable.Element.EARTH)
	await _tick_both(d, 2)
	check(await _wait(func(): return real.health < before), "blast hit reaches the host")
	await _tick_both(d, 2)
	check(cw.brand_hits_sent == 1 and hw.brand_hits_sent == 0, "sent once, by the client")
	check(MagicEffects.puppet_hits.is_empty(), "queue drained")
	(d["c"] as NetSession).leave()
	(d["h"] as NetSession).leave()
	(d["root"] as Node).queue_free()
	await runner_tree.process_frame
