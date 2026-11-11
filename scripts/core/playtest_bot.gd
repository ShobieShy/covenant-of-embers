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
const LAB_LIMIT := 2400.0  ## L5: extra simulated seconds for the Labyrinth leg
const LAB_FIGHT_RANGE := 16.0
const KING := "goblin_king"

static var stage := "midden_walk"
static var total_time := 0.0
static var stats := {
	"kills": 0, "pickups": 0, "casts": 0, "crafted": "", "saves": 0, "deaths": 0, "teleports": 0, "looted_parts": 0
}
static var log_lines := PackedStringArray()
static var save_cleared := false  ## QA: main_menu cleared the bot save this process
static var finished := false  ## OW11c-6: set once the bot has logged its result
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
		"kills": 0, "pickups": 0, "casts": 0, "crafted": "", "saves": 0, "deaths": 0, "teleports": 0, "looted_parts": 0
	}
	log_lines = PackedStringArray()
	brand_turn = 0
	brands_used = PackedStringArray()
	trees_used = PackedStringArray()
	intro_beats = PackedStringArray()


func setup(m: Node, p: Player) -> void:
	main = m
	player = p
	player.set_spread_seed(40)
	player.bot_input = func() -> PlayerInput: return _input
	_walk_start = player.global_position
	GameEvents.bus().enemy_killed.connect(_on_kill)
	player.progression.leveled_up.connect(func(_l): spend_points())  # step 151
	player.pickups.collected.connect(func(_pk, _w): stats["pickups"] += 1)
	player.died.connect(_on_died)
	if Coop.is_client():  # step 93: the joiner follows the host and fights its enemies
		stage = "coop_follow"
		Coop.session.message.connect(_on_coop_bot_message)
		Coop.session.ended.connect(func(r: String): _client_done("session ended: " + r))
	elif stage == "midden_walk" and IntroDirector.active(m.get(&"story_flags")):  # OW11c: before the director
		stage = "intro"  # step 118: a new game plays the prologue first
	if act2_run() and not Coop.is_client() and stage == "midden_walk":
		stage = "act2_to_breach"
	if act3_run() and not Coop.is_client() and stage == "midden_walk":
		stage = "act3_to_breach"
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
					if sk.el_why_not(el, sid, lv).is_empty() and player.spend_element_skill(el, sid):
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
		if stats["kills"] % 2 == 0 and not Coop.is_client() and stage not in ["intro", "breach_craft", "craft"]:
			next_brand()


func _foe_desc(e: Enemy) -> String:
	if e == null:
		return "none"
	return "%s at %s hp %.0f (%.1f m)" % [e.name, e.global_position, e.health, flat_distance(e.global_position)]


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
	# OW11c-6: clean shutdown. End the co-op session (closes the ENet peer), then let a few
	# frames run so queued frees settle before quit (joiner died with a heap double free).
	if Coop.session != null and is_instance_valid(Coop.session):
		if cw and is_instance_valid(cw):
			cw.prepare_shutdown()
		finished = true  # guard: main/menu must not re-host or re-join after this
		Coop.end("done")
		# Frames after close() so the delete queue drops the session before quit.
		# Do not free current_scene from here: this node lives in it, and that await
		# never resumes.
		for i in 8:
			await get_tree().process_frame
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
	if act2_run() and _act2_heights.has("joiner"):
		_finish(true)
		return
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


static var _act2_heights := {}
static var _act2_step := 0


func _follow_host() -> void:
	if act2_run():
		var inn := _interiors()
		if inn and inn.cavern and inn.floor_no == 8:
			var pad_y := inn.cavern.pad_global(8).y
			if absf(player.global_position.y - pad_y) < 2.5 and not _act2_heights.has("joiner"):
				_act2_heights["joiner"] = player.global_position.y - inn.cavern.global_position.y
				var mire := false
				for n in inn.cavern.get_tree().get_nodes_in_group(&"blight_volume"):
					if String(n.get_meta(&"kind", "")) == "mire":
						mire = true
						var d := player.global_position - (n as Node3D).global_position
						if Vector2(d.x, d.z).length() < 2.0:
							_finish(false, "joiner on the Crown is inside the Sump mire")
							return
				note("act2 joiner height %.1f mire %s" % [_act2_heights["joiner"], mire])
				if not mire:
					_finish(false, "act2 cavern has no mire")
					return
				_act2_heights["joiner_at"] = total_time
			if _act2_heights.has("joiner_at") and total_time - float(_act2_heights["joiner_at"]) > 15.0:
				_finish(true)
				return
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
	# A boss still has to die. Dropping the Warden after one lost path left the closed
	# Breach fight with nobody to shoot (0.4.0 linear playtest).
	if _target_s > UNREACHABLE_S and not _is_boss(e):
		_unreachable[e] = true
		note("skipping unreachable %s" % _foe_desc(e))


func _is_boss(e: Enemy) -> bool:
	return e != null and e.def != null and e.def.id in ["breach_warden", "the_filth", "goblin_king"]


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
					% [e.def.id, _fight_stall, e.global_position, player.global_position, e.is_ally()]
				)
			)
		walk_to(e.global_position)
		return
	if Engine.time_scale > 1.0 and _fight_stall > STALL_S and flat_distance(e.global_position) > 2.0:
		walk_to(e.global_position, ["action_primary"])
		look_at_point(aim)
		if _tick % 2 == 1:
			_input = PlayerInput.hold(["forward", "action_primary"], ["action_primary"])
		return
	look_at_point(e.global_position + Vector3(0, e.def.size.y * 0.5, 0))
	var held := ["action_primary"]
	if e.global_position.distance_to(player.global_position) > 10.0:
		held.append("forward")
	elif e is Heap and (e as Heap).winding_up() and flat_distance(e.global_position) < 5.0:
		held.append("back")  # L5: back out of a boss's telegraphed slam instead of eating it
	var m := player.caster.fire_mode() if player.caster != null else null
	if (
		_dry(m)
		and not (
			player.mana.value < 5.0
			and player.loadout.active == Loadout.Slot.STAFF
			and player.loadout.wieldable(Loadout.Slot.WAND) != null
		)
	):
		# QA r7: no casts the mana can't pay for (they were refused by the thousand); keep
		# out of reach and let mana regenerate, then fire again
		held.erase("action_primary")
		held.erase("forward")
		if flat_distance(e.global_position) < 8.0:
			held.append("back")
		_input = PlayerInput.hold(held, [])
		return
	if player.mana.value < 5.0 and player.loadout.active == Loadout.Slot.STAFF and not (m is HeatMode):
		_input = PlayerInput.hold(held, ["slot_2"])
	elif player.loadout.active == Loadout.Slot.WAND and player.mana.value >= 0.6 * player.mana.max_value():
		# L5: back to the staff once mana is up again; before this the bot stayed on the
		# wand until its next brand swap (every second kill), so a long boss fight with no
		# kills was fought with the wand alone (solo8: the King at 148 hp after 600 s)
		_input = PlayerInput.hold(held, ["slot_1"])
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


## QA r7: true when the slot in hand can't pay for its next cast (HeatMode/zero-cost modes never are).
func _dry(m: FireMode) -> bool:
	if player.caster == null or player.caster.wieldable == null or m == null or m.cost_mult() <= 0.0:
		return false
	return player.mana.value < player.caster.wieldable.mana_cost() * m.cost_mult()


## Walk towards `at` along the level navmesh (straight when the map has no path).
func has_line_to(at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(player.eye_position(), at, 1)
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


var _stuck_from := Vector3.ZERO
var _stuck_s := 0.0
var _unstick_s := 0.0

var _route: RouteGraph
var _route_level: Node

var _path_ordered := false


func walk_to(at: Vector3, held: Array = []) -> void:
	var lvl := main.get_node_or_null("Level")
	var indoors := _interiors()
	if _direct_walk or (indoors and indoors.current != ""):
		lvl = null  # indoors, or a direct walk, skips the outdoor landmark route
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
		var nav := main.get_node_or_null("Level/Navigation") as NavigationRegion3D
		var inn := _interiors()
		if inn and inn.interior:
			var inside := inn.interior.get_node_or_null("Navigation") as NavigationRegion3D
			if inside:
				nav = inside
		if inn and inn.cavern:
			var coil := inn.cavern.get_node_or_null("Navigation") as NavigationRegion3D
			if coil:
				nav = coil
		var lf: LabyrinthFloor = inn.lab_floor if inn and inn.current == "labyrinth" else null
		_path_ordered = false
		if lf and is_instance_valid(lf):  # L5: the floors have no navmesh; room-graph route
			_path = lf.route(player.global_position, at)
			_path_ordered = true
		elif nav is LevelNavigation and (nav as LevelNavigation).map_ready():
			_path = NavigationServer3D.map_get_path(nav.get_navigation_map(), player.global_position, at, true)
		elif nav and nav.navigation_mesh and nav.navigation_mesh.get_polygon_count() > 0:
			var map := nav.get_navigation_map()
			if map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0:
				_path = NavigationServer3D.map_get_path(map, player.global_position, at, true)
	# OW11b: a path that ends well short of the goal means the bot is on a nav island (seen on
	# a Breach-rooms ledge 4 m above lever_west): walk straight at the goal and drop off it.
	if not _path.is_empty() and Vector2(_path[-1].x - at.x, _path[-1].z - at.z).length() > 2.0:
		_path = PackedVector3Array()
	var next := at
	var feet := player.global_position
	# Step 118: start from the waypoint nearest the feet (a long, wiggly path otherwise hands back
	# an already-passed point and the bot turns round every few ticks).
	# L5b: not for a labyrinth room route, which loops round: a later room (or the stairs) is
	# often nearer through a wall than the next doorway, and the bot walked into that wall.
	var from := 0
	for i in _path.size() if not _path_ordered else 0:
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
		_input = PlayerInput.hold(["forward", "right" if int(total_time / 3.0) % 2 == 0 else "left"] + held, ["jump"])
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
	var cap_s := OS.get_environment("COE_PLAYTEST_MAX_S")
	if cap_s.is_valid_float() and total_time > cap_s.to_float():
		_finish(true)
		return
	stats["casts"] = maxi(stats["casts"], player.loadout.casters[0].casts + player.loadout.casters[1].casts)
	var limit := SIM_LIMIT + (LAB_LIMIT if labyrinth_run() or act2_run() or act3_run() else 0.0)
	if total_time > limit:
		_finish(false, "run over %.0f s in stage %s" % [limit, stage])
		return
	if t > STAGE_LIMIT and stage != "coop_follow":  # the joiner follows as long as the host plays
		_finish(
			false,
			(
				"stage %s over %.0f s at %s in %s, nearest foe %s"
				% [stage, STAGE_LIMIT, player.global_position, main.call(&"here_id"), _foe_desc(nearest_enemy(true))]
			)
		)
		return
	_input = PlayerInput.hold()
	_run_stage()


func _run_stage() -> void:
	PlaytestActs._run_stage(self)


## --- L5: the Labyrinth leg (`--autoplay --labyrinth`) --------------------------------
## Breach -> out of the rooms -> walk into the crater gate -> each floor: fight foes in
## range, walk the room graph to StairsDown (the co-op stairs gate waits for the joiner)
## -> floor 5: kill the Goblin King -> save; PASS once the save holds his kill.


static func labyrinth_run() -> bool:
	return OS.get_cmdline_user_args().has("--labyrinth")


static func act2_run() -> bool:
	return OS.get_cmdline_user_args().has("--act2")


static func act3_run() -> bool:
	return OS.get_cmdline_user_args().has("--act3")


static var _act3_pads := {}
static var _act3_floor_at := -1
static var _act3_floor_t := 0.0

var _lab_n := 0
var _lab_votes := 0
var _voting := false
const VOTE_FLOOR := 2  ## co-op: the joiner hangs back here so the host's 10 s vote runs live


## Co-op joiner, `--labyrinth`: on VOTE_FLOOR stand still (far from the stairs) so the host's
## stairs start the vote countdown and the floor sync carries this player down when it ends.
func _interiors() -> Interiors:
	return main.get_node_or_null("LinearInteriors") as Interiors


func _lab_straggle() -> bool:
	if not labyrinth_run():
		return false
	var inn := _interiors()
	if inn == null or inn.current != "labyrinth" or inn.floor_no != VOTE_FLOOR:
		return false
	if _lab_n != VOTE_FLOOR:
		_lab_n = VOTE_FLOOR
		note("joiner hangs back on floor %d for the stairs vote" % VOTE_FLOOR)
	_input = PlayerInput.new()
	return true


## True when the flat segment a->b comes within r of c.
static func _passes_near(a: Vector3, b: Vector3, c: Vector3, r: float) -> bool:
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var c2 := Vector2(c.x, c.z)
	var ab := b2 - a2
	var k := clampf((c2 - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (a2 + ab * k).distance_to(c2) < r


var _lab_stuck_t := 0.0
var _lab_stuck_at := Vector3.ZERO
var _lab_unstick := 0.0
var _lab_side := Vector3.ZERO
var _lab_flip := false
var _direct_walk := false


func _lab_tick() -> void:
	PlaytestActs._lab_tick(self)


func _lab_to_gate(inn: Interiors, lab: LabyrinthState) -> void:
	PlaytestActs._lab_to_gate(self, inn, lab)


func _lab_on_floor(inn: Interiors, lab: LabyrinthState) -> void:
	PlaytestActs._lab_on_floor(self, inn, lab)


func _act3_tick() -> void:
	PlaytestActs._act3_tick(self)


func _act3_rest(lab: LabyrinthState) -> void:
	PlaytestActs._act3_rest(self, lab)


func _act2_tick() -> void:
	PlaytestActs._act2_tick(self)


func _act2_travel(lab: LabyrinthState) -> void:
	PlaytestActs._act2_travel(self, lab)


func _act2_cavern(lab: LabyrinthState) -> void:
	PlaytestActs._act2_cavern(self, lab)


func _on_died(_p) -> void:
	stats["deaths"] += 1
	var foe := nearest_enemy(true)
	note(
		(
			"died (%d) at %.0f s, %s, nearest foe %s (%.1f m)"
			% [
				stats["deaths"],
				total_time,
				stage,
				foe.name if foe else "-",
				flat_distance(foe.global_position) if foe else -1.0
			]
		)
	)


## L5: the boss fight's progress every 10 s (King health, his hits taken, our casts/health).
func _log_king(floor_node: Node) -> void:
	for k in floor_node.get_tree().get_nodes_in_group(Enemy.GROUP):
		var gk := k as GoblinKing
		if gk == null:
			continue
		note(
			(
				"king hp %.0f/%.0f taken %.0f hits %d dist %.1f los %s target %s | me hp %.0f mana %.0f slot %s casts %d | staff %s (%s) wand %s refused %d"
				% [
					gk.health,
					gk.max_health(),
					gk.damage_taken,
					gk.hits,
					flat_distance(gk.global_position),
					has_line_to(gk.global_position + Vector3.UP),
					gk.get(&"target").name if gk.get(&"target") else "-",
					player.health.value,
					player.mana.value,
					"staff" if player.loadout.active == Loadout.Slot.STAFF else "wand",
					player.loadout.casters[0].casts + player.loadout.casters[1].casts,
					_slot_name(Loadout.Slot.STAFF),
					_mode_name(Loadout.Slot.STAFF),
					_slot_name(Loadout.Slot.WAND),
					player.loadout.casters[0].mana_refused + player.loadout.casters[1].mana_refused
				]
			)
		)


func _slot_name(slot: int) -> String:
	var w := player.loadout.wieldable(slot)
	return w.display_name() if w else "none"


func _mode_name(slot: int) -> String:
	var m: Object = player.loadout.casters[slot].fire_mode() if player.loadout.wieldable(slot) else null
	return m.get_script().get_global_name() if m and m.get_script() else "-"


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
	var levers: Array = b.switches.filter(func(x): return not x.is_pressed)
	levers.sort_custom(func(a, c): return flat_distance(a.global_position) < flat_distance(c.global_position))  # OW11b: nearest lever first (the loft one when the bot is up there)
	for sw in levers:
		if true:
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
		# QA r7: keep every craft in the summary (the prologue staff and the Breach wand)
		var was := String(stats["crafted"])
		stats["crafted"] = (built.display_name() if was.is_empty() else was + " + " + built.display_name())
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
	return PlaytestIntro._intro_director(self)


func _intro_tick() -> void:
	PlaytestIntro._intro_tick(self)


## With --shots: one screenshot per beat 1 s in, and one 0.7 s into every cinematic (before the skip).
func _intro_shot(b: String) -> void:
	PlaytestIntro._intro_shot(self, b)


## Cinematics (watch 1 s, skip), the appraisal, dialogue (first choice). True while busy.
func _intro_ui(d: IntroDirector) -> bool:
	return PlaytestIntro._intro_ui(self, d)


func _intro_fight(d: IntroDirector, b: String) -> bool:
	return PlaytestIntro._intro_fight(self, d, b)


## A wave gnawer corrupted into an ally stays in its wave; once it turns back it keeps the
## arena walls up after the Filth dies (return_to_bob stalled inside the ring). Clear it.
func _arena_held(d: IntroDirector) -> bool:
	return PlaytestIntro._arena_held(self, d)


func _intro_craft(d: IntroDirector) -> bool:
	return PlaytestIntro._intro_craft(self, d)


## QA r6: Joe's wind wand (joe_landfill, Q21) is optional, so the bot never had a wand and
## fought the King on a dry staff (fight()'s slot_2 swap did nothing; 3 of 4 solo runs timed
## out). Like a player, talk to Joe at his Landfill camp before using his bench.
func _visit_joe(d: IntroDirector) -> bool:
	return PlaytestIntro._visit_joe(self, d)


## Walk to the objective marker, then Interact with the NPC / gate there.
func _intro_interact(d: IntroDirector) -> void:
	PlaytestIntro._intro_interact(self, d)
