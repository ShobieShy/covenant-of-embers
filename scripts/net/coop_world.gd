class_name CoopWorld
extends Node
## Co-op in the game scene (BUILD_PLAN step 79). The host simulates the world:
##  - every peer sends its pose 20x/s (unreliable); others show it as a RemotePlayer;
##  - the host's enemies hunt the nearest living player (local or remote); a bite on a
##    remote player is sent to its owner ("hurt") and resolved there (i-frames, shield);
##  - the host snapshots its enemies 20x/s (id, type, pose, health, dead); clients show
##    brainless puppets (plain Enemy bodies, their own spawner switched off);
##  - a client's bolt on a puppet is predicted locally and sent to the host ("hit"),
##    which applies it to the real enemy; deaths go out reliably ("kill");
##  - loot is instanced: every peer's own EventBus.enemy_killed rolls that peer's drops
##    and XP from its own rng (PLAN §30.2), so nobody steals anyone's loot.

const SNAP_HZ := 20.0
const MAX_ENEMIES := 64  ## per snapshot
const HP_PER_EXTRA_PLAYER := 0.6  ## step 80: enemy health +60 pct per extra player
const LAST_STAND := 15.0  ## s downed before bleeding out
const REVIVE_RANGE := 2.5  ## m, a living teammate this close revives
const REVIVE_TIME := 3.0  ## s of standing there
const REVIVE_HEALTH := 0.3  ## fraction of max health after a revive

var session: NetSession
var player: Node3D  ## the local Player (or a stand-in with the same methods in tests)
var enemies: Node  ## host: the EnemySpawner (its children); client: its spawner, off
var table: EnemyTable
var host := false
var auto_tick := true
var proxies := {}  ## peer -> RemotePlayer
var puppets := {}  ## id -> Enemy (client)
var by_id := {}  ## id -> Enemy (host)
var puppet_hp := {}  ## id -> health the host last reported (client)
var _snap_dead := {}  ## id -> true once a host snapshot showed it dead (client, step 94)
var kills_seen := 0  ## puppet deaths counted on this client (step 94)
var _ids := {}  ## Enemy -> id (host)
var _wired := {}  ## Enemy -> true (attacks rerouted, death hooked)
var _next_id := 1
var _snap_left := 0.0
var snaps_sent := 0
var snaps_seen := 0
var hits_sent := 0
var hits_applied := 0
var hurts_sent := 0
var hurts_taken := 0
var kills_relayed := 0
var poses_sent := 0
var poses_seen := 0
var revive_progress := 0.0
var revives := 0


func setup(s: NetSession, p: Node3D, enemy_root: Node, t: EnemyTable = null) -> void:
	session = s
	player = p
	enemies = enemy_root
	table = t if t != null else EnemyTable.load_default()
	host = s.is_host()
	if &"last_stand" in player:
		player.set(&"last_stand", LAST_STAND)
	s.message.connect(_on_message)
	s.roster_changed.connect(_drop_gone)
	if not host and enemies:
		enemies.process_mode = Node.PROCESS_MODE_DISABLED
		for c in enemies.get_children():
			if c is Enemy:
				c.queue_free()


func _physics_process(dt: float) -> void:
	if auto_tick:
		tick(dt)


func tick(dt: float) -> void:
	if session == null or not is_instance_valid(session) or session.state != NetSession.State.IN_GAME:
		return
	_snap_left -= dt
	if _snap_left <= 0.0:
		_snap_left = 1.0 / SNAP_HZ
		send_pose()
		if host:
			send_snapshot()
	if host:
		_wire_and_target()
	_tick_revive(dt)
	for pr: RemotePlayer in proxies.values():
		pr.smooth(dt)
	if not host:
		for e: Enemy in puppets.values():
			var want: Variant = e.get_meta(&"net_pos", null)
			if want is Vector3:
				e.global_position = e.global_position.lerp(want, 1.0 - exp(-RemotePlayer.SMOOTH * dt))


## --- poses -------------------------------------------------------------------------


func local_pose() -> Dictionary:
	var d := {"p": player.global_position, "y": player.rotation.y, "n": session.local_info.get("name", "Player")}
	d["a"] = bool(player.call(&"alive")) if player.has_method(&"alive") else true
	d["i"] = bool(player.call(&"invulnerable")) if player.has_method(&"invulnerable") else false
	d["d"] = bool(player.get(&"downed")) if &"downed" in player else false
	var h: Variant = player.get(&"health")
	if h is Health:
		d["h"] = (h as Health).value
		d["m"] = (h as Health).max_value()
	var pr: Variant = player.get(&"progression")
	if pr != null:
		d["l"] = int(pr.get(&"level"))
	return d


func send_pose() -> void:
	poses_sent += 1
	session.send("pose", local_pose(), 0, false)


func proxy(peer: int) -> RemotePlayer:
	if not proxies.has(peer):
		var r := RemotePlayer.new()
		r.name = "Remote%d" % peer
		r.peer = peer
		add_child(r)
		proxies[peer] = r
	return proxies[peer]


func _drop_gone() -> void:
	for peer in proxies.keys():
		if not session.roster.has(peer):
			(proxies[peer] as Node).queue_free()
			proxies.erase(peer)


## Every living player an enemy may hunt (host).
func targets() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if player and (not player.has_method(&"alive") or bool(player.call(&"alive"))):
		out.append(player)
	for pr: RemotePlayer in proxies.values():
		if pr.alive():
			out.append(pr)
	return out


func nearest_target(from: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for t in targets():
		var d := t.global_position.distance_squared_to(from)
		if d < bd:
			bd = d
			best = t
	return best


## Step 80: enemy health multiplier for the players in the session.
func health_scale() -> float:
	return 1.0 + HP_PER_EXTRA_PLAYER * maxf(0.0, session.roster.size() - 1)


## Step 80: a downed local player is revived by a living teammate standing beside them
## for REVIVE_TIME (each peer decides for its own player).
func _tick_revive(dt: float) -> void:
	if player == null or not bool(player.get(&"downed")):
		revive_progress = 0.0
		return
	var helper := false
	for pr: RemotePlayer in proxies.values():
		if pr.alive() and pr.global_position.distance_to(player.global_position) <= REVIVE_RANGE:
			helper = true
			break
	revive_progress = revive_progress + dt if helper else maxf(0.0, revive_progress - dt)
	if revive_progress >= REVIVE_TIME and player.has_method(&"revive"):
		revive_progress = 0.0
		if bool(player.call(&"revive", REVIVE_HEALTH)):
			revives += 1
			session.send("revived", {})


## --- host: enemies -------------------------------------------------------------------


func enemy_id(e: Enemy) -> int:
	if not _ids.has(e):
		_ids[e] = _next_id
		by_id[_next_id] = e
		_next_id += 1
	return _ids[e]


func host_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	if enemies == null:
		return out
	for c in enemies.get_children():
		if c is Enemy and is_instance_valid(c) and not c.is_queued_for_deletion():
			out.append(c)
	return out


func _wire_and_target() -> void:
	for e in host_enemies():
		if not _wired.has(e):
			_wired[e] = true
			e.died.connect(_on_host_died)
			e.tree_exiting.connect(_forget.bind(e))
			e.scale_health(health_scale())
			if e is Gnawer and player and player.has_method(&"on_enemy_attack"):
				var g := e as Gnawer
				var own := Callable(player, &"on_enemy_attack")
				if g.attacked.is_connected(own):
					g.attacked.disconnect(own)
				g.attacked.connect(_on_attack)
		if e is Gnawer and not e.dead:
			var g := e as Gnawer
			var t := nearest_target(g.global_position)
			if t != null:
				g.target = t


func _forget(e: Enemy) -> void:
	_wired.erase(e)
	if _ids.has(e):
		by_id.erase(_ids[e])
		_ids.erase(e)


func _on_attack(g: Gnawer, bite: Gnawer.Bite) -> void:
	route_attack(g.target, bite, g)


## A bite on `target`: the local player takes it here; a RemotePlayer's owner gets "hurt".
func route_attack(target: Node3D, bite: Gnawer.Bite, from: Gnawer = null) -> void:
	if target is RemotePlayer:
		hurts_sent += 1
		var d := {"dmg": bite.damage, "el": int(bite.element), "dodged": bite.dodged, "from": bite.from}
		session.send("hurt", d, (target as RemotePlayer).peer)
	elif player and player.has_method(&"on_enemy_attack"):
		player.call(&"on_enemy_attack", from, bite)


func send_snapshot() -> void:
	var list: Array = []
	for e in host_enemies():
		if list.size() >= MAX_ENEMIES:
			break
		list.append([enemy_id(e), e.def.id, e.global_position, e.rotation.y, e.health, e.max_health(), e.dead])
	snaps_sent += 1
	session.send("snap", {"e": list}, 0, false)


func _on_host_died(e: Enemy, element: ElementTable.Element) -> void:
	kills_relayed += 1
	session.send("kill", {"id": enemy_id(e), "el": int(element)})


## --- client: puppets -----------------------------------------------------------------


func _apply_snapshot(list: Array) -> void:
	snaps_seen += 1
	var seen := {}
	for row: Array in list:
		var id := int(row[0])
		seen[id] = true
		var e: Enemy = puppets.get(id)
		if e == null or not is_instance_valid(e):
			var d := table.find(String(row[1]))
			if d == null:
				continue
			e = Enemy.new()
			e.setup(d)
			e.name = "Puppet%d" % id
			e.set_meta(&"net_id", id)
			e.hold_death = true  # step 94: only the host kills
			e.died.connect(func(_e, _el): kills_seen += 1)
			add_child(e)
			e.global_position = row[2]
			e.damaged.connect(_on_puppet_hit)
			puppets[id] = e
		if e.def.max_health > 0.0:
			e.health_scale = maxf(0.01, float(row[5]) / e.def.max_health)
		e.set_meta(&"net_pos", row[2])
		e.rotation.y = float(row[3])
		var hp := float(row[4])
		puppet_hp[id] = hp
		var host_dead := bool(row[6])
		if host_dead and not e.dead:
			e.confirm_kill(e.def.affinity)
		elif not host_dead and e.dead and _snap_dead.get(id, false):
			# A training dummy came back on the host. Step 94: only after a snapshot saw it
			# dead; a stale "alive" snapshot overtaken by the reliable "kill" must not revive
			# it (that counted the boss kill twice on the client).
			e.reset()
			e.hold_death = true
			e.global_position = row[2]
		_snap_dead[id] = host_dead
		if not e.dead:
			e.health = minf(e.health, hp) if e.health > 0.0 else hp
	for id in puppets.keys():
		if not seen.has(id):
			var gone: Enemy = puppets[id]
			if is_instance_valid(gone):
				gone.queue_free()
			puppets.erase(id)
			puppet_hp.erase(id)
			_snap_dead.erase(id)


func _on_puppet_hit(e: Enemy, h: SpellBolts.Hit) -> void:
	if h == null or h.result == null:
		return
	send_hit(e, h.result.amount, h.element)


## The client's hit on a puppet goes to the host (the puppet already showed it).
func send_hit(e: Enemy, amount: float, element: ElementTable.Element) -> void:
	hits_sent += 1
	session.send("hit", {"id": int(e.get_meta(&"net_id", 0)), "amt": amount, "el": int(element)}, 1)


## --- messages ------------------------------------------------------------------------


func _on_message(from: int, kind: String, data: Dictionary) -> void:
	match kind:
		"pose":
			poses_seen += 1
			proxy(from).apply_pose(data)
		"snap":
			if not host and from == 1:
				_apply_snapshot(data.get("e", []))
		"kill":
			if not host:
				var e: Enemy = puppets.get(int(data.get("id", 0)))
				if e and is_instance_valid(e) and not e.dead:
					e.confirm_kill(int(data.get("el", 0)) as ElementTable.Element)
		"hit":
			if host:
				var e: Enemy = by_id.get(int(data.get("id", 0)))
				if e and is_instance_valid(e) and not e.dead:
					hits_applied += 1
					e.apply_damage(
						maxf(0.0, float(data.get("amt", 0.0))), int(data.get("el", 0)) as ElementTable.Element
					)
		"hurt":
			if from == 1 and player and player.has_method(&"on_enemy_attack"):
				hurts_taken += 1
				var b := Gnawer.Bite.new()
				b.damage = float(data.get("dmg", 0.0))
				b.element = int(data.get("el", 0)) as ElementTable.Element
				b.dodged = bool(data.get("dodged", false))
				b.from = data.get("from", Vector3.ZERO)
				player.call(&"on_enemy_attack", null, b)
