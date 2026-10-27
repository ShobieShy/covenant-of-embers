class_name PlaytestBot
extends Node
## Scripted playtest bot (BUILD_PLAN step 40), `--autoplay` after `--`. It plays the slice
## through the real Player controller (PlayerInput each physics tick, its own look/aim):
##   Midden: walk, cast at and kill enemies, walk over their loot, save, take the gate;
##   Breach: walk into the arena, clear the waves and the Warden, walk to and open the vault
##   chest, loot, walk back to the entrance Assembly Station and craft from parts it looted
##   (its own starting staff/wand as the base), save.
## Step 48: it never teleports; every walk follows the level navmesh (NavigationServer3D
## paths, re-planned every REPLAN s) and `teleports` stays 0.
## Prints "[playtest] PASS ..." and quits 0, or "[playtest] FAIL <why>" and quits 1. The
## stage survives the scene change (static). Fixed spread seed: runs are reproducible.

const MIDDEN_KILLS := 2
const SIM_LIMIT := 2400.0  ## simulated seconds for the whole run
const STAGE_LIMIT := 600.0
const REPLAN := 0.5

static var stage := "midden_walk"
static var total_time := 0.0
static var stats := {
	"kills": 0,
	"pickups": 0,
	"casts": 0,
	"crafted": "",
	"saves": 0,
	"deaths": 0,
	"teleports": 0,
	"looted_parts": 0
}
static var log_lines := PackedStringArray()
static var save_cleared := false  ## QA: main_menu cleared the bot save this process
static var coop_started := false
static var brand_turn := 0  ## step 143: next brand in the staff rotation
static var brands_used := PackedStringArray()
static var trees_used := PackedStringArray()  ## step 151: skill trees the bot spent points in
static var coop_totals := {"hits_sent": 0, "hits_applied": 0, "snaps_seen": 0, "poses_seen": 0}  ## step 93: the menu wiped the bot files once

var main: Node
var player: Player
var t := 0.0
var _input := PlayerInput.new()
var _walk_start := Vector3.ZERO
var _done := false
var _path := PackedVector3Array()
var _path_goal := Vector3.INF
var _replan_left := 0.0


static func reset_run() -> void:
	stage = "midden_walk"
	total_time = 0.0
	stats = {
		"kills": 0,
		"pickups": 0,
		"casts": 0,
		"crafted": "",
		"saves": 0,
		"deaths": 0,
		"teleports": 0,
		"looted_parts": 0
	}
	log_lines = PackedStringArray()
	brand_turn = 0
	brands_used = PackedStringArray()
	trees_used = PackedStringArray()
	intro_beats = PackedStringArray()


var _ow_travel := false  ## OW11b: an in-world trip to the Landfill is under way


func setup(m: Node, p: Player) -> void:
	main = m
	player = p
	player.set_spread_seed(40)
	player.bot_input = func() -> PlayerInput: return _input
	_walk_start = player.global_position
	GameEvents.bus().enemy_killed.connect(_on_kill)
	player.progression.leveled_up.connect(func(_l): spend_points())  # step 151
	player.pickups.collected.connect(func(_pk, _w): stats["pickups"] += 1)
	player.died.connect(func(_p): stats["deaths"] += 1)
	if Coop.is_client():  # step 93: the joiner follows the host and fights its enemies
		stage = "coop_follow"
		Coop.session.message.connect(_on_coop_bot_message)
		Coop.session.ended.connect(func(r: String): _client_done("session ended: " + r))
	elif stage == "midden_walk" and IntroDirector.live and IntroDirector.active(IntroDirector.live):
		stage = "intro"  # step 118: a new game plays the prologue first
	if not Coop.is_client() and stage != "intro":
		next_brand()
	note("start %s in %s" % [stage, m.call(&"here_id")])


## Step 143: the bot fights with branded staffs, one brand after another (a basic staff with
## that brand's Head; next one at each level start and every second kill).
func next_brand() -> void:
	var all := BrandTable.load_default().brands
	var b: Brand = all[brand_turn % all.size()]
	brand_turn += 1
	var parts: Array[WieldablePart] = [
		PartRoller.from_seed(40 + brand_turn, WieldablePart.PartType.HEAD, "basic", b.element)
	]
	for id in ["basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id))
	var w := Assembly.assemble(WieldableInstance.load_base("apprentice_fire_staff").def, parts)
	if w == null or w.brand() != b:
		return
	player.equip(w)
	player.loadout.select(Loadout.Slot.STAFF)
	if not brands_used.has(b.id):
		brands_used.append(b.id)
	spend_points()
	note("brand staff: %s (%s)" % [b.display_name, b.fire_mode_name()])


## Step 151: spends free skill points, Core first up to CORE_POINTS, then the held brand's element tree.
const CORE_POINTS := 10


func spend_points() -> void:
	var sk := player.skills
	var lv := player.progression.level
	var guard := 64
	while sk.available(lv) > 0 and guard > 0:
		guard -= 1
		var spent := false
		if sk.core_spent() < CORE_POINTS and sk.tree != null:
			for sid in sk.tree.skills:
				if sk.why_not(sid, lv).is_empty() and player.spend_skill(sid):
					spent = true
					_used("core")
					break
		if not spent:
			var w := player.loadout.wieldable()
			var el := ElementTable.id_of(w.element()) if w != null else "arcane"
			var t := SkillTree.element_tree(el)
			if t != null:
				for sid in t.skills:
					if (
						sk.el_why_not(el, sid, lv).is_empty()
						and player.spend_element_skill(el, sid)
					):
						spent = true
						_used(el)
						break
		if not spent:
			return


static func _used(tree: String) -> void:
	if not trees_used.has(tree):
		trees_used.append(tree)


func _exit_tree() -> void:
	var cw: CoopWorld = main.get(&"coop") if is_instance_valid(main) else null
	if cw and not _done:  # step 93: counters live per level; keep the run's totals
		_bank(cw)
	if GameEvents.bus().enemy_killed.is_connected(_on_kill):
		GameEvents.bus().enemy_killed.disconnect(_on_kill)


static func note(s: String) -> void:
	log_lines.append(s)
	print("[playtest] " + s)


func _on_kill(e: Enemy, _el) -> void:
	if e and e.def and not e.def.ai.is_empty():
		stats["kills"] += 1
		note("killed %s (%d) at %.1f s" % [e.def.id, stats["kills"], total_time])
		if (
			stats["kills"] % 2 == 0
			and not Coop.is_client()
			and stage not in ["intro", "breach_craft", "craft"]
		):
			next_brand()


func _foe_desc(e: Enemy) -> String:
	if e == null:
		return "none"
	return (
		"%s at %s hp %.0f (%.1f m)"
		% [e.name, e.global_position, e.health, flat_distance(e.global_position)]
	)


func _goto(s: String) -> void:
	stage = s
	t = 0.0
	note("-> " + s)


func _finish(ok: bool, why := "") -> void:
	if _done:
		return
	_done = true
	player.bot_input = Callable()
	var summary := (
		"%s kills %d, pickups %d, casts %d, crafted %s, saves %d, deaths %d, teleports %d, level %d, %.0f s simulated, brands %s, trees %s"
		% [
			"PASS" if ok else "FAIL " + why,
			stats["kills"],
			stats["pickups"],
			stats["casts"],
			stats["crafted"],
			stats["saves"],
			stats["deaths"],
			stats["teleports"],
			player.progression.level,
			total_time,
			",".join(brands_used),
			",".join(trees_used),
		]
	)
	note(summary)
	var cw: CoopWorld = main.get(&"coop") if main else null
	if cw:
		_bank(cw)
	if not coop_totals.values().all(func(v): return v == 0):
		note("coop totals %s" % [coop_totals])
	if ok and Coop.is_host():
		Coop.session.send("bot_done", {})  # step 93: let the joiner finish before we drop the link
		await get_tree().create_timer(1.0).timeout
	get_tree().quit.call_deferred(0 if ok else 1)


## --- step 93: co-op joiner -----------------------------------------------------------


static func _bank(cw: CoopWorld) -> void:
	for k: String in coop_totals:
		coop_totals[k] += int(cw.get(k))


func _on_coop_bot_message(_from: int, kind: String, _data: Dictionary) -> void:
	if kind == "bot_done":
		_client_done("host finished the slice")


func _client_done(why: String) -> void:
	if _done or stage != "coop_follow":
		return
	var cw: CoopWorld = main.get(&"coop") if is_instance_valid(main) else null
	if cw and Coop.active():
		main.call(&"save_game")
	stats["saves"] += 1
	note("joiner: " + why)
	if stats["casts"] == 0:
		_finish(false, "joiner never cast")
	elif (
		cw
		and (
			coop_totals["hits_sent"] + cw.hits_sent == 0
			or coop_totals["snaps_seen"] + cw.snaps_seen == 0
			or coop_totals["poses_seen"] + cw.poses_seen == 0
		)
	):
		_finish(false, "joiner saw no co-op traffic")
	elif not FileAccess.file_exists(Coop.character):
		_finish(false, "joiner's character file missing")
	else:
		_finish(true)


func _follow_host() -> void:
	var cw: CoopWorld = main.get(&"coop")
	var e := nearest_enemy(true)
	if e and e.global_position.distance_to(player.global_position) < 25.0:
		fight(e)
		return
	if cw and cw.proxies.has(1):
		var h := (cw.proxies[1] as Node3D).global_position
		if flat_distance(h) > 4.0:
			walk_to(h)


## t60u: interaction is by look, so once near an interactable, aim the camera at it first.
func _reach(n: Node3D) -> bool:
	if n.near(player):
		look_at_point(Interaction.aim_point(n))
	return n.in_reach(player)


## Look at `at` (yaw + pitch from the eye).
func look_at_point(at: Vector3) -> void:
	var d := at - player.eye_position()
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	player.set_look(yaw, pitch)


## `foes_only` skips corrupted allies (a converted gnawer nearer than the Filth used to stall the beat).
## OW11b: a foe fought for UNREACHABLE_S without its hp moving is skipped from then on.
const UNREACHABLE_S := 45.0
var _unreachable := {}
var _target: Enemy
var _target_hp := 0.0
var _target_s := 0.0


func _watch_target(e: Enemy) -> void:
	var hp := float(e.hits)
	if e != _target or hp != _target_hp:
		_target = e
		_target_hp = hp
		_target_s = 0.0
		return
	_target_s += get_physics_process_delta_time()
	if _target_s > UNREACHABLE_S:
		_unreachable[e] = true
		note("skipping unreachable %s" % _foe_desc(e))


func nearest_enemy(foes_only := false) -> Enemy:
	var best: Enemy = null
	var bd := INF
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or not e.alive() or e.def.ai.is_empty() or (foes_only and e.is_ally()):
			continue
		if _unreachable.has(e):  # OW11b: e.g. a camp behind a sealed flag gate
			continue
		var d := e.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func nearest_pickup() -> Node3D:
	var best: Node3D = null
	var bd := 30.0
	for n in get_tree().get_nodes_in_group(LootPickup.GROUP):
		if (n as LootPickup).is_auto() or n.is_queued_for_deletion():
			continue  # orbs / dust / potions collect on the way; the bot goes for items
		var d := (n as Node3D).global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = n
	return best


## Walk to (or fight) `e`: aim at its body centre, fire, close in beyond 10 m; with no clear
## line (a pillar in the way) walk towards it on the navmesh instead.
## Step 96: a target that takes no hit for STALL_S while we shoot at it (seen at --time-scale 4:
## an idle Breach wing Gnawer 8.9 m away ate 400 s of misses) gets closed in on, shooting.
const STALL_S := 4.0
## Step 96: physics ticks; fire-button edges alternate on this, not on int(t * 60) (at
## --time-scale 4 that only ever saw even numbers, so the bot never re-pressed and stopped casting).
var _tick := 0
var _fight_target: Enemy = null
var _fight_hits := 0
var _fight_stall := 0.0
var _los_noted: Enemy = null  ## QA: one note per target the bot keeps walking at without a line


## Step 96: at --time-scale N the player covers ~1/N of the ground per game second (seen:
## 1 m/s instead of 4 at 4x), so walking budgets scale with it.
func _walk_scale() -> float:
	return maxf(1.0, Engine.time_scale)


func fight(e: Enemy) -> void:
	if e != _fight_target or e.hits != _fight_hits:
		_fight_target = e
		_fight_hits = e.hits
		_fight_stall = 0.0
	_fight_stall += get_physics_process_delta_time()
	var aim := e.global_position + Vector3(0, e.def.size.y * 0.5, 0)
	if not has_line_to(aim):
		if _fight_stall > 30.0 and _los_noted != e:  # QA: name the target a long stall is on
			_los_noted = e
			note(
				(
					"no line to %s for %.0f s: enemy %s, feet %s, ally %s"
					% [
						e.def.id,
						_fight_stall,
						e.global_position,
						player.global_position,
						e.is_ally()
					]
				)
			)
		walk_to(e.global_position)
		return
	if (
		Engine.time_scale > 1.0
		and _fight_stall > STALL_S
		and flat_distance(e.global_position) > 2.0
	):
		walk_to(e.global_position, ["action_primary"])
		look_at_point(aim)
		if _tick % 2 == 1:
			_input = PlayerInput.hold(["forward", "action_primary"], ["action_primary"])
		return
	look_at_point(e.global_position + Vector3(0, e.def.size.y * 0.5, 0))
	var held := ["action_primary"]
	if e.global_position.distance_to(player.global_position) > 10.0:
		held.append("forward")
	var m := player.caster.fire_mode() if player.caster != null else null
	if (
		player.mana.value < 5.0
		and player.loadout.active == Loadout.Slot.STAFF
		and not (m is HeatMode)
	):
		_input = PlayerInput.hold(held, ["slot_2"])
	elif m is ChargeMode:  # step 143: hold to a full charge, then let go for one tick
		if m.charge >= 1.0:
			held.erase("action_primary")
		_input = PlayerInput.hold(held, [] if m.charge > 0.0 else ["action_primary"])
	elif m is HeatMode and m.meter() >= 0.9:  # vent before the lockout
		_input = PlayerInput.hold(held, ["reload"])
	elif m is HeatMode or m is SpinMode:  # hold the trigger
		_input = PlayerInput.hold(held, ["action_primary"] if _tick % 30 == 0 else [])
	else:
		_input = PlayerInput.hold(held, ["action_primary"] if _tick % 2 == 0 else [])


## Walk towards `at` along the level navmesh (straight when the map has no path).
func has_line_to(at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(player.eye_position(), at, 1)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


var _stuck_from := Vector3.ZERO
var _stuck_s := 0.0
var _unstick_s := 0.0

var _route: RouteGraph
var _route_level: Node


func walk_to(at: Vector3, held: Array = []) -> void:
	var lvl := main.get_node_or_null("Level")
	if lvl and lvl.has_node("Pois"):  # step 154: open zones route long walks via landmarks
		if _route == null or _route_level != lvl:
			_route = RouteGraph.from_level(lvl)
			_route_level = lvl
		at = _route.next_waypoint(player.global_position, at)
	_replan_left -= get_physics_process_delta_time()
	if _replan_left <= 0.0 or _path_goal.distance_to(at) > 0.5:
		_replan_left = REPLAN
		_path_goal = at
		_path = PackedVector3Array()
		var nav := main.get_node_or_null("Level/Navigation") as LevelNavigation
		var ow := main.get_node_or_null("OpenWorld")
		if ow and ow.get(&"interiors") and ow.interiors.interior:  # OW11b: indoors
			nav = ow.interiors.interior.get_node_or_null("Navigation") as LevelNavigation
		if nav and nav.map_ready():
			_path = NavigationServer3D.map_get_path(
				nav.get_navigation_map(), player.global_position, at, true
			)
		elif ow:  # OW11b: the streamed world cells' nav
			var wm := player.get_world_3d().navigation_map
			if NavigationServer3D.map_get_iteration_id(wm) > 0:
				_path = NavigationServer3D.map_get_path(wm, player.global_position, at, true)
	var next := at
	var feet := player.global_position
	# Step 118: start from the waypoint nearest the feet (a long, wiggly path otherwise hands back
	# an already-passed point and the bot turns round every few ticks).
	var from := 0
	for i in _path.size():
		if _path[i].distance_squared_to(feet) < _path[from].distance_squared_to(feet):
			from = i
	for i in range(from, _path.size()):
		if Vector2(_path[i].x - feet.x, _path[i].z - feet.z).length() > 0.6:
			next = _path[i]
			break
	look_at_point(next + Vector3(0, 1.0, 0))
	player.set_look(player.yaw, 0.0)
	# Step 96: wedged (no 0.3 m of progress in 1.5 s): jump and sidestep for 0.6 s.
	var dt := get_physics_process_delta_time()
	if feet.distance_to(_stuck_from) > 0.3:
		_stuck_from = feet
		_stuck_s = 0.0
	else:
		_stuck_s += dt
	if _stuck_s > 1.5:
		_unstick_s = 0.6
		_stuck_s = 0.0
		_replan_left = 0.0
	if _unstick_s > 0.0:
		_unstick_s -= dt
		_input = PlayerInput.hold(
			["forward", "right" if int(total_time / 3.0) % 2 == 0 else "left"] + held, ["jump"]
		)
		return
	_input = PlayerInput.hold(["forward"] + held)


func flat_distance(at: Vector3) -> float:
	return Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()


func _physics_process(delta: float) -> void:
	if _done or player == null:
		return
	_tick += 1
	if player.alive():
		t += delta  # step 93: stage timers pause while down / respawning (co-op last stand)
	total_time += delta
	stats["casts"] = maxi(
		stats["casts"], player.loadout.casters[0].casts + player.loadout.casters[1].casts
	)
	if total_time > SIM_LIMIT:
		_finish(false, "run over %.0f s in stage %s" % [SIM_LIMIT, stage])
		return
	if t > STAGE_LIMIT and stage != "coop_follow":  # the joiner follows as long as the host plays
		_finish(
			false,
			(
				"stage %s over %.0f s at %s in %s, nearest foe %s"
				% [
					stage,
					STAGE_LIMIT,
					player.global_position,
					main.call(&"here_id"),
					_foe_desc(nearest_enemy(true))
				]
			)
		)
		return
	_input = PlayerInput.hold()
	match stage:
		"coop_follow":
			_follow_host()
		"intro":
			_intro_tick()
		"midden_walk":
			if main.call(&"here_id") != "midden":  # step 109: a new game starts elsewhere
				if t > 0.5 and not _ow_travel:
					note("travel to the Landfill from %s" % main.call(&"here_id"))
					main.call(&"travel", "midden")
					_ow_travel = main.get_node_or_null("OpenWorld") != null  # OW11b: no reload
					_done = not _ow_travel
				return
			if _ow_travel:  # OW11b: landed in the world's Landfill; walk from here
				var ow: OpenWorld = main.get_node("OpenWorld")
				if ow.travel.busy:
					return
				_ow_travel = false
				_walk_start = player.global_position
				_goto("midden_walk")
				return
			_input = PlayerInput.hold(["forward"])
			if t > 1.0:
				var moved := player.global_position.distance_to(_walk_start)
				if moved < 1.0:
					_finish(false, "did not move (%.2f m)" % moved)
					return
				note("walked %.1f m" % moved)
				_goto("midden_fight")
		"midden_fight", "breach_fight":
			if stage == "breach_fight" and main.breach == null:
				return  # OW11b: still entering the Breach rooms
			var e := nearest_enemy(true)
			if e:
				_watch_target(e)
				fight(e)
			elif stage == "midden_fight":
				if stats["kills"] >= MIDDEN_KILLS:
					_goto("midden_loot")
				else:
					_enter_arena()
			else:
				var b: Breach = main.breach
				if b and b.open:
					_goto("breach_chest")
				else:
					_breach_route(b)
			if stage == "midden_fight" and stats["kills"] >= MIDDEN_KILLS and e == null:
				_goto("midden_loot")
		"midden_loot", "breach_loot":
			var pk := nearest_pickup()
			if pk and t < 20.0 * _walk_scale():
				if pk.global_position.distance_to(player.eye_position()) < 2.5:
					look_at_point(pk.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
					_input = PlayerInput.hold([], ["interact"] if _tick % 2 == 0 else [])
				else:
					walk_to(pk.global_position)
			else:
				note("loot: %d pickup(s) so far" % stats["pickups"])
				if stage == "breach_loot" and stats["pickups"] == 0:
					_finish(false, "picked up none of the vault loot")
					return
				_goto("midden_save" if stage == "midden_loot" else "breach_craft")
		"breach_craft":
			var st: AssemblyStation = main.get_node_or_null("AssemblyStation")
			if st == null:
				_finish(false, "no station in the Breach")
				return
			if not _reach(st) and t < 60.0 * _walk_scale():
				# Snagged (loot / chest in the way): circle round the station after 15 s.
				var k := int(t / (5.0 * _walk_scale()))
				var off := (
					Vector3.ZERO
					if t < 15.0 * _walk_scale()
					else Vector3(1.5, 0, 0).rotated(Vector3.UP, k * 1.7)
				)
				walk_to(st.global_position + off)
			elif not _reach(st):
				_finish(
					false,
					"could not walk to the station (%.1f m)" % flat_distance(st.global_position)
				)
				return
			else:
				_craft(st)
				if not _done:
					_goto("breach_save")
		"midden_save", "breach_save":
			if main.save_game() != OK or not GameFlow.has_save():
				_finish(false, "save failed")
				return
			stats["saves"] += 1
			if stage == "midden_save":
				_goto("breach_fight")
				main.travel("breach")
			else:
				var r := SaveGame.read(GameFlow.save_path)
				if r.has("error") or not r["data"]["progress"].get("vault_open", false):
					_finish(false, "final save missing vault state")
					return
				_finish(true)
		"breach_chest":
			var c: VaultChest = main.breach.chest
			if not _reach(c) and t < 60.0 * _walk_scale():
				var front := c.global_position + c.global_transform.basis.z * 1.0
				if (
					flat_distance(front) < 1.0
					or (t > 30.0 * _walk_scale() and flat_distance(c.global_position) < 8.0)
				):
					look_at_point(c.global_position + Vector3(0, 1.0, 0))  # last metres: straight in
					player.set_look(player.yaw, 0.0)
					_input = PlayerInput.hold(["forward"])
				else:
					walk_to(front)
			elif not _reach(c):
				_finish(
					false,
					"could not walk to the vault chest (%.1f m)" % flat_distance(c.global_position)
				)
				return
			else:
				var drops := c.open_chest()
				note("vault chest opened: %d drop(s)" % drops.size())
				if drops.is_empty():
					_finish(false, "vault chest gave nothing")
					return
				_goto("breach_loot")


## Step 47: clear the rooms in order, pull every lever, then on to the arena.
func _breach_route(b: Breach) -> void:
	if b == null:
		_enter_arena()
		return
	var enc := b.next_encounter()
	if enc:
		if enc.wave_state == EnemySpawner.WaveState.WAITING:
			walk_to(enc.trigger_center)
		return
	for sw in b.switches:
		if not sw.is_pressed:
			if _reach(sw):
				if sw.press():
					note("pulled lever %s" % sw.name)
			else:
				walk_to(sw.global_position)
			return
	_enter_arena()


## No enemy left and the waves not done: walk into the wave trigger.
func _enter_arena() -> void:
	var sp := main.get_node_or_null("Enemies") as EnemySpawner
	if stage.begins_with("breach") and main.get_node_or_null("BreachEnemies"):
		sp = main.get_node("BreachEnemies") as EnemySpawner  # OW11b: the rooms' own waves
	if sp == null:
		return
	if not sp.triggered() and flat_distance(sp.trigger_center) > sp.trigger_radius * 0.5:
		walk_to(sp.trigger_center)


## Craft at `st` from looted parts only: the bot's own bare staff/wand (moved to the backpack)
## as the base, the best-rarity looted part per slot. Fails when the loot can't make a build.
func _craft(st: AssemblyStation) -> void:
	var looted: Array[WieldablePart] = []
	for it in player.inventory.items:
		if it is WieldablePart:
			looted.append(it)
	stats["looted_parts"] = looted.size()
	looted.sort_custom(func(a, b): return Rarity.parse(a.rarity) > Rarity.parse(b.rarity))
	var tried := PackedStringArray()
	for slot in [Loadout.Slot.STAFF, Loadout.Slot.WAND]:
		var base := player.loadout.wieldable(slot)
		if base == null or base.assembled:
			continue
		var parts: Array = []
		var used := {}
		for prt in looted:
			if Assembly.allows(base.type(), prt.part_type) and not used.has(prt.part_type):
				used[prt.part_type] = true
				parts.append(prt)
		var errs := st.check(base, parts)
		if not errs.is_empty():
			tried.append("%s: %s" % [base.display_name(), errs[0]])
			continue
		if player.inventory.is_full():
			# A long run can fill the backpack with parts; drop one this build won't use.
			for it in looted:
				if not parts.has(it):
					player.inventory.remove(it)
					break
		var built: WieldableInstance = null
		var ui := main.get_node_or_null("StationUi") as StationUi
		if ui and ui.player == player:
			# t60u: like a player: draw it, open the station (the held staff auto-loads as the
			# base), fit the parts, Assemble, close (the new staff goes back in hand).
			player.loadout.select(slot)
			player.loadout.active = slot
			ui.open(st)
			if ui.base != base:
				ui.close()
				tried.append("%s: not auto-loaded (%s)" % [base.display_name(), ui.status.text])
				continue
			for prt in parts:
				ui.pick(prt)
			built = ui.assemble()
			var why_not := ui.status.text
			ui.close()
			if built == null or player.loadout.wieldable(slot) != built:
				_finish(false, "station UI craft refused: %s" % why_not)
				return
			note("station UI: %s auto-loaded as the base" % base.display_name())
		else:
			if not player.unequip_wieldable_to_inventory(slot):
				tried.append("%s: backpack full" % base.display_name())
				continue
			built = st.assemble(player, base, parts)
			if built == null:
				_finish(false, "craft refused: %s" % st.last_error)
				return
			player.equip_from_inventory(built)
		stats["crafted"] = built.display_name()
		note(
			(
				"crafted + equipped %s from %d looted part(s) (dmg %.1f)"
				% [built.display_name(), parts.size(), built.damage()]
			)
		)
		return
	if tried.is_empty() and not String(stats["crafted"]).is_empty():
		note("no bare base left: %s was crafted in the prologue" % stats["crafted"])  # step 118
		return
	var why := "looted parts make no build (%d part(s); %s)" % [looted.size(), "; ".join(tried)]
	if Coop.active():  # step 93: co-op kill order changes the loot rolls; crafting is solo-checked
		stats["crafted"] = "none (co-op loot)"
		note("craft skipped in co-op: " + why)
		return
	_finish(false, why)


## --- step 118: the prologue, beats 1-13 -------------------------------------------------
## Plays each beat the way a player would: watch a second of every cinematic then skip it,
## confirm the appraisal, click through dialogue (first choice), walk the navmesh to the
## objective marker and Interact, fight the yard and the Filth, pick up and craft the part.

static var intro_beats := PackedStringArray()
var _intro_beat := ""
var _cine_t := 0.0
var _talk_cd := 0.0


func _intro_director() -> IntroDirector:
	return main.get_node_or_null("IntroDirector") as IntroDirector


func _intro_tick() -> void:
	var d := _intro_director()
	if d == null or not IntroDirector.active(d.flags):
		note("prologue done: %d beat(s) %s" % [intro_beats.size(), ",".join(intro_beats)])
		if intro_beats.size() < IntroDirector.BEATS.size():
			_finish(false, "prologue skipped beats (%s)" % ",".join(intro_beats))
		else:
			_goto("midden_walk")
		return
	var b := d.current()
	if b != _intro_beat:
		_intro_beat = b
		if not intro_beats.has(b):
			intro_beats.append(b)
		t = 0.0
		note(
			(
				"intro beat %s (%d/%d) in %s"
				% [b, intro_beats.size(), IntroDirector.BEATS.size(), d.here]
			)
		)
	_talk_cd -= get_physics_process_delta_time()
	if t > 240.0:  # a stalled beat fails fast with where the bot was and what it aimed at
		_finish(
			false,
			(
				"intro beat %s stalled in %s: feet %s, target %s"
				% [b, d.here, player.global_position, d.target_point()]
			)
		)
		return
	_intro_shot(b)
	if _intro_ui(d):
		return
	if (
		d.here == IntroDirector.LEVEL.get(b, d.here)
		and b in ["combat", "filth"]
		and _intro_fight(d, b)
	):
		return
	if b == "crafting" and d.here == "midden" and _intro_craft(d):
		return
	if _arena_held(d):
		return
	_intro_interact(d)


## With --shots: one screenshot per beat 1 s in, and one 0.7 s into every cinematic (before the skip).
func _intro_shot(b: String) -> void:
	var sh := main.get_node_or_null("Screenshots") as Screenshots
	if sh == null:
		return
	var dt := get_physics_process_delta_time()
	if Cinematic.playing and _cine_t < 0.7 and _cine_t + dt >= 0.7:
		sh.take("cine_" + b)
	elif t >= 1.0 and t - dt < 1.0:
		sh.take("beat_" + b)


## Cinematics (watch 1 s, skip), the appraisal, dialogue (first choice). True while busy.
func _intro_ui(d: IntroDirector) -> bool:
	if Cinematic.playing:
		_cine_t += get_physics_process_delta_time()
		if _cine_t > 1.0:
			Cinematic.playing.skip()
		return true
	_cine_t = 0.0
	if d.creator:
		d.choose_identity(
			{
				"archetype": player.archetype,
				"name": player.character_name,
				"color": player.character_color
			}
		)
		return true
	var dlg: DialogueRunner = main.get(&"dialogue")
	if dlg and dlg.active:
		if _talk_cd <= 0.0:
			_talk_cd = 0.3
			if dlg.awaiting_choice():
				dlg.choose(0)
			else:
				dlg.advance()
		return true
	return false


func _intro_fight(d: IntroDirector, b: String) -> bool:
	var e := nearest_enemy(true)
	if e:
		fight(e)
		return true
	if b != "filth":
		return false
	for q in get_tree().get_nodes_in_group(QuestPickup.GROUP):  # Joe's trash, after the kill
		walk_to((q as Node3D).global_position)
		return true
	var sp := d.spawner()
	if sp:
		walk_to(sp.trigger_center)
	return true


## A wave gnawer corrupted into an ally stays in its wave; once it turns back it keeps the
## arena walls up after the Filth dies (return_to_bob stalled inside the ring). Clear it.
func _arena_held(d: IntroDirector) -> bool:
	var sp := d.spawner()
	var lock := sp.get_node_or_null(^"ArenaLock") as ArenaLock if sp else null
	if lock == null or not lock.raised():
		return false
	var e := nearest_enemy(true)
	if e:
		fight(e)
	return true


func _intro_craft(d: IntroDirector) -> bool:
	var pk := d.next_pickup()
	if pk:
		if pk.global_position.distance_to(player.eye_position()) < 2.5:
			look_at_point(pk.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
			_input = PlayerInput.hold([], ["interact"] if _tick % 2 == 0 else [])
		else:
			walk_to(pk.global_position)
		return true
	var st := d.station()
	if st and _reach(st):
		_craft(st)
		return true
	return false


## Walk to the objective marker, then Interact with the NPC / gate there.
func _intro_interact(d: IntroDirector) -> void:
	var at: Variant = d.target_point()
	if at == null:
		return
	if flat_distance(at) > 1.8:
		walk_to(at)
		return
	if _talk_cd > 0.0:
		return
	_talk_cd = 1.0
	for n in main.find_children("*", "", true, false):
		if (n is Npc or n is LevelGate) and (n as Node3D).global_position.distance_to(at) < 0.6:
			look_at_point(Interaction.aim_point(n as Node3D))
			if n is Npc:
				(n as Npc).talk()
			else:
				(n as LevelGate).use()
			return
