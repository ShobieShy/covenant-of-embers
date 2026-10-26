class_name EnemySpawner
extends Node3D
## Step 14: the level's enemies and waves (BUILD_PLAN step 14). Owns every enemy it spawns
## (they are its children):
##  - setup(level, player): one enemy per EnemySpawns marker (Enemy.spawn_at_markers);
##    every Gnawer/Heap hunts `player` and its bites/slams go to player.on_enemy_attack;
##  - deaths (Enemy.died, which also fires EventBus.enemy_killed once per death): a
##    marker enemy with `respawn_s` (the training dummies) is reset() to full health at
##    its marker that long later; any other dead enemy is freed FREE_DELAY_TICKS ticks
##    after the death (the death tick's listeners, damage numbers and deferred collision
##    changes are done with it by then);
##  - waves (the level's Waves node, generated from [waves] / [[wave]] / [[spawn_point]]):
##    once the player's feet are within trigger_radius (on the XZ plane) of
##    trigger_center and the navmesh has synced, wave 0 spawns delay_s later; each next
##    wave spawns its delay_s after the previous one is cleared (all its enemies dead).
##    A wave's enemies at one spawn point stand on a WAVE_RING m ring around it (one
##    enemy: on the point), facing the point's yaw.
## Signals mirror to the EventBus (enemy_spawned, wave_started, wave_cleared,
## waves_completed). auto_tick off (tests): tick(dt) by hand also ticks its enemies.
##
## Magewar reference (read-only): no spawner or waves exist there (enemies are placed in
## the scenes; the Storyline's "unending waves" is flavour), and dead enemies stay in the
## tree. Waves, freeing and respawning are plan design.

signal wave_started(index: int, wave_id: String)
signal wave_cleared(index: int, wave_id: String)
signal waves_completed

enum WaveState { WAITING, DELAY, ACTIVE, DONE }

const WAVE_RING := 1.5  ## m; tools/toml_to_scene.py WAVE_RING must match
const FREE_DELAY_TICKS := 2  ## a dead non-respawning enemy is freed this many ticks on
const EPS := 1e-6  ## timers: n x 1/60 leaves float dust

var auto_tick := true
var player: Player
var table: EnemyTable
var level: Node
var nav: LevelNavigation
var waves: Array[Dictionary] = []  ## {id, delay_s, enemies: [{enemy, count, at}]}
var trigger_center := Vector3.ZERO  ## global
var trigger_radius := 0.0
var wave_state := WaveState.WAITING
var wave_index := -1  ## the wave delaying / alive (-1: not triggered)
var delay_left := 0.0
var wave_alive: Array[Enemy] = []
var vigil_tier := 0  ## step 58: wave enemies roll Elites affixes for this tier
var elite_rng := RandomNumberGenerator.new()
var elites := 0
var ticks := 0
var spawned := 0  ## enemies placed (markers + waves; not respawns)
var kills := 0  ## deaths seen
var freed := 0
var respawns := 0
var waves_cleared := 0
var skipped: Array = []  ## enemy ids with no EnemyDef
var _respawn_s := {}  ## Enemy -> s (marker enemies that come back)
var _home := {}  ## Enemy -> Transform3D (its marker, local)
var _respawning: Array[Dictionary] = []  ## {enemy, left}
var _dying: Array[Dictionary] = []  ## {enemy, at}
## Step 161: zone camps (Level/Camps): {name, center (global), radius, respawn_s, enemies,
## alive: Array[Enemy], wait (s until it may respawn), spawned (times)}.
var camps: Array[Dictionary] = []
var camp_spawns := 0


## Spawns the marker enemies of `level` and reads its waves. Returns the marker enemies.
func setup(lvl: Node, p: Player, t: EnemyTable = null) -> Array[Enemy]:
	level = lvl
	player = p
	table = t if t != null else EnemyTable.load_default()
	nav = level.get_node_or_null("Navigation") as LevelNavigation
	var got := Enemy.spawn_at_markers(level, self, table, skipped)
	spawned += got.size()
	var markers := level.get_node_or_null("EnemySpawns")
	for e in got:
		var m := markers.get_node_or_null(NodePath(String(e.name))) if markers else null
		var r := float(m.get_meta(&"respawn_s", 0.0)) if m else 0.0
		if r > 0.0:
			_respawn_s[e] = r
			_home[e] = e.transform
		_adopt(e)
	_read_waves()
	_read_camps()
	return got


func _read_camps() -> void:
	camps.clear()
	var h := level.get_node_or_null("Camps") if level else null
	for c in h.get_children() if h else []:
		var n := c as Node3D
		(
			camps
			. append(
				{
					"name": String(n.name),
					"center": n.global_position if n.is_inside_tree() else n.position,
					"radius": float(n.get_meta(&"radius", 4.0)),
					"respawn_s": float(n.get_meta(&"respawn_s", 600.0)),
					"enemies": n.get_meta(&"enemies", []),
					"alive": [] as Array[Enemy],
					"wait": 0.0,
					"spawned": 0,
				}
			)
		)


## Step 161: the players a camp can see (local + co-op teammates).
func _players() -> Array:
	var out: Array = []
	if player != null and player.alive():
		out.append(player)
	if is_inside_tree():
		for r in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
			if r.alive():
				out.append(r)
	return out


## Step 161: a cleared camp waits respawn_s, then repopulates once a player is within
## CampLeash.ACTIVATE m; pulled members snap home (CampLeash.enforce).
func _tick_camps(dt: float) -> void:
	if camps.is_empty():
		return
	var ps: Array = _players() if ticks % 15 == 0 else []
	for c in camps:
		var alive: Array = c["alive"]
		for i in range(alive.size() - 1, -1, -1):
			var e := alive[i] as Enemy
			if not is_instance_valid(e) or e.is_queued_for_deletion() or not e.alive():
				alive.remove_at(i)
		if alive.is_empty() and int(c["spawned"]) > 0 and float(c["wait"]) <= 0.0 and c.get("cleared") != true:
			c["wait"] = float(c["respawn_s"])
			c["cleared"] = true
		# Q6: a cleared camp counts down only while every player is away (CampLeash.ACTIVATE);
		# a zone reload re-reads the camps, so it is full again.
		if ticks % 15 == 0:
			c["near"] = not ps.is_empty() and CampLeash.camp_active(c["center"], ps)
		if c.get("near") != true:
			c["wait"] = maxf(0.0, float(c["wait"]) - dt)
		if not alive.is_empty():
			CampLeash.enforce(alive)
		elif float(c["wait"]) <= 0.0 and ticks % 15 == 0 and c.get("near") == true:
			spawn_camp(c)


func spawn_camp(c: Dictionary) -> Array[Enemy]:
	var out: Array[Enemy] = []
	var total := 0
	for g in c["enemies"]:
		total += int(g.get("count", 1))
	var spots := ring_spots(c["center"], total)
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	var n := 0
	for g in c["enemies"]:
		var d := table.find(String(g["enemy"]))
		if d == null:
			skipped.append("%s@%s" % [g["enemy"], c["name"]])
			continue
		for k in int(g.get("count", 1)):
			var e := Enemy.create(d, inv * Transform3D(Basis(), spots[n]))
			e.name = "camp_%s_%s_%d_%d" % [c["name"], d.id, int(c["spawned"]) + 1, n + 1]
			n += 1
			add_child(e)
			CampLeash.home(e, spots[n - 1])
			_adopt(e)
			out.append(e)
	(c["alive"] as Array).append_array(out)
	c["spawned"] = int(c["spawned"]) + 1
	c["cleared"] = false
	camp_spawns += 1
	return out


func _read_waves() -> void:
	waves.clear()
	var wn := level.get_node_or_null("Waves")
	if wn == null:
		return
	var origin := (
		(level as Node3D).global_transform
		if level is Node3D and (level as Node3D).is_inside_tree()
		else Transform3D.IDENTITY
	)
	trigger_center = origin * (wn.get_meta(&"trigger_center", Vector3.ZERO) as Vector3)
	trigger_radius = float(wn.get_meta(&"trigger_radius", 0.0))
	for c in wn.get_children():
		waves.append(
			{"id": String(c.name), "delay_s": float(c.get_meta(&"delay_s", 0.0)), "enemies": c.get_meta(&"enemies", [])}
		)


## Where n wave enemies at one spawn point stand (toml_to_scene.py ring_spots): one on
## the point, more on a ring of WAVE_RING m, the first north (-Z) of it, clockwise seen
## from above.
static func ring_spots(center: Vector3, n: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if n <= 1:
		out.append(center)
		return out
	for i in n:
		var a := TAU * i / n
		out.append(center + Vector3(WAVE_RING * sin(a), 0.0, -WAVE_RING * cos(a)))
	return out


func alive_count() -> int:
	var n := 0
	for c in get_children():
		if c is Enemy and not (c as Enemy).dead and not c.is_queued_for_deletion():
			n += 1
	return n


func current_wave_id() -> String:
	return String(waves[wave_index]["id"]) if wave_index >= 0 and wave_index < waves.size() else ""


func _adopt(e: Enemy) -> void:
	e.died.connect(_on_died)
	if e is Ooze:  # step 55: its halves join the spawner (and the wave it was in)
		(e as Ooze).split.connect(_on_split)
	if e is Gnawer:
		var g := e as Gnawer
		g.auto_tick = auto_tick
		if player:
			g.target = player
			if not g.attacked.is_connected(player.on_enemy_attack):
				g.attacked.connect(player.on_enemy_attack)
	GameEvents.bus().enemy_spawned.emit(e)


func _on_split(parent: Ooze, halves: Array) -> void:
	var in_wave := wave_alive.has(parent)
	for h: Enemy in halves:
		add_child(h)
		_adopt(h)
		if in_wave:
			wave_alive.append(h)
	if parent.puddle:
		add_child(parent.puddle)


func _on_died(e: Enemy, _element: ElementTable.Element) -> void:
	kills += 1
	wave_alive.erase(e)
	if _respawn_s.has(e):
		_respawning.append({"enemy": e, "left": float(_respawn_s[e])})
	else:
		_dying.append({"enemy": e, "at": ticks})


func _physics_process(delta: float) -> void:
	if auto_tick:
		tick(delta)


func tick(dt: float) -> void:
	ticks += 1
	if not auto_tick:
		for c in get_children():
			if c is Gnawer and not c.is_queued_for_deletion():
				(c as Gnawer).tick(dt)
			elif c is Enemy and not c.is_queued_for_deletion():
				(c as Enemy).tick(dt)
	# Free the dead (not the respawning).
	for i in range(_dying.size() - 1, -1, -1):
		var d := _dying[i]
		if ticks - int(d["at"]) >= FREE_DELAY_TICKS:
			var e := d["enemy"] as Enemy
			_dying.remove_at(i)
			if is_instance_valid(e):
				e.queue_free()
				freed += 1
	# Respawn training dummies.
	for i in range(_respawning.size() - 1, -1, -1):
		var r := _respawning[i]
		r["left"] = float(r["left"]) - dt
		if float(r["left"]) <= EPS:
			var e := r["enemy"] as Enemy
			_respawning.remove_at(i)
			if is_instance_valid(e):
				e.reset(_home[e])
				respawns += 1
				GameEvents.bus().enemy_spawned.emit(e)
	_tick_waves(dt)
	_tick_camps(dt)


## Step 155: any player triggers it, the local one or a co-op teammate (RemotePlayer).
func triggered() -> bool:
	if trigger_radius <= 0.0:
		return false
	if player != null and player.alive() and _inside(player.global_position):
		return true
	if is_inside_tree():
		for r in get_tree().get_nodes_in_group(RemotePlayer.GROUP):
			if r.alive() and _inside((r as Node3D).global_position):
				return true
	return false


func _inside(at: Vector3) -> bool:
	var d := at - trigger_center
	return Vector2(d.x, d.z).length() <= trigger_radius and absf(d.y) <= 3.0


func _tick_waves(dt: float) -> void:
	if waves.is_empty():
		return
	match wave_state:
		WaveState.WAITING:
			if triggered() and (nav == null or nav.map_ready()):
				_begin_wave(0)
		WaveState.DELAY:
			delay_left -= dt
			if delay_left <= EPS:
				_spawn_wave()
		WaveState.ACTIVE:
			if wave_alive.is_empty():
				var id := current_wave_id()
				waves_cleared += 1
				wave_cleared.emit(wave_index, id)
				GameEvents.bus().wave_cleared.emit(wave_index, id)
				if wave_index + 1 < waves.size():
					_begin_wave(wave_index + 1)
				else:
					wave_state = WaveState.DONE
					waves_completed.emit()
					GameEvents.bus().waves_completed.emit()


func _begin_wave(i: int) -> void:
	wave_index = i
	delay_left = float(waves[i]["delay_s"])
	wave_state = WaveState.DELAY
	if delay_left <= EPS:
		_spawn_wave()


func _spawn_wave() -> void:
	var w := waves[wave_index]
	var id := String(w["id"])
	var points := level.get_node_or_null("WaveSpawns")
	var per_point := {}
	for g in w["enemies"]:
		per_point[g["at"]] = int(per_point.get(g["at"], 0)) + int(g.get("count", 1))
	var used := {}
	var inv := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for g in w["enemies"]:
		var at := String(g["at"])
		var m := points.get_node_or_null(NodePath(at)) as Node3D if points else null
		var d := table.find(String(g["enemy"]))
		if m == null or d == null:
			skipped.append("%s@%s" % [g["enemy"], at])
			continue
		var mx := m.global_transform if m.is_inside_tree() else m.transform
		var spots := ring_spots(mx.origin, int(per_point[at]))
		for k in int(g.get("count", 1)):
			var n := int(used.get(at, 0))
			used[at] = n + 1
			var affix := Elites.roll(elite_rng, vigil_tier)
			if affix != "":
				elites += 1
			var e := Enemy.create(Elites.apply(d, affix), inv * Transform3D(mx.basis, spots[n]))
			e.name = "%s_%s_%s_%d" % [id, at, d.id, n + 1]  # unique: n counts per point
			add_child(e)
			spawned += 1
			wave_alive.append(e)
			_adopt(e)
	wave_state = WaveState.ACTIVE
	wave_started.emit(wave_index, id)
	GameEvents.bus().wave_started.emit(wave_index, id)
