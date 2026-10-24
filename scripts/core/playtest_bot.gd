class_name PlaytestBot
extends Node
## Scripted playtest bot (BUILD_PLAN step 40), `--autoplay` after `--`. It plays the slice
## through the real Player controller (PlayerInput each physics tick, its own look/aim):
##   Midden: walk, cast at and kill enemies, walk over their loot, craft at the Assembly
##   Station (bot-supplied base + parts, the real station rules), save, take the gate;
##   Breach: enter the arena, clear the waves and the Warden, open the vault chest, loot, save.
## Prints "[playtest] PASS ..." and quits 0, or "[playtest] FAIL <why>" and quits 1. The
## stage survives the scene change (static). Fixed spread seed: runs are reproducible.

const MIDDEN_KILLS := 2
const SIM_LIMIT := 900.0  ## simulated seconds for the whole run
const STAGE_LIMIT := 300.0

static var stage := "midden_walk"
static var total_time := 0.0
static var stats := {"kills": 0, "pickups": 0, "casts": 0, "crafted": "", "saves": 0, "deaths": 0}
static var log_lines := PackedStringArray()

var main: Node
var player: Player
var t := 0.0
var _input := PlayerInput.new()
var _walk_start := Vector3.ZERO
var _done := false


static func reset_run() -> void:
	stage = "midden_walk"
	total_time = 0.0
	stats = {"kills": 0, "pickups": 0, "casts": 0, "crafted": "", "saves": 0, "deaths": 0}
	log_lines = PackedStringArray()


func setup(m: Node, p: Player) -> void:
	main = m
	player = p
	player.set_spread_seed(40)
	player.bot_input = func() -> PlayerInput: return _input
	_walk_start = player.global_position
	GameEvents.bus().enemy_killed.connect(_on_kill)
	player.pickups.collected.connect(func(_pk, _w): stats["pickups"] += 1)
	player.died.connect(func(_p): stats["deaths"] += 1)
	note("start %s in %s" % [stage, GameFlow.id_of(m.get_node("Level"))])


func _exit_tree() -> void:
	if GameEvents.bus().enemy_killed.is_connected(_on_kill):
		GameEvents.bus().enemy_killed.disconnect(_on_kill)


static func note(s: String) -> void:
	log_lines.append(s)
	print("[playtest] " + s)


func _on_kill(e: Enemy, _el) -> void:
	if e and e.def and not e.def.ai.is_empty():
		stats["kills"] += 1
		note("killed %s (%d) at %.1f s" % [e.def.id, stats["kills"], total_time])


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
		"%s kills %d, pickups %d, casts %d, crafted %s, saves %d, deaths %d, level %d, %.0f s simulated"
		% [
			"PASS" if ok else "FAIL " + why,
			stats["kills"],
			stats["pickups"],
			stats["casts"],
			stats["crafted"],
			stats["saves"],
			stats["deaths"],
			player.progression.level,
			total_time
		]
	)
	note(summary)
	get_tree().quit.call_deferred(0 if ok else 1)


## Look at `at` (yaw + pitch from the eye).
func look_at_point(at: Vector3) -> void:
	var d := at - player.eye_position()
	var yaw := atan2(-d.x, -d.z)
	var pitch := atan2(d.y, Vector2(d.x, d.z).length())
	player.set_look(yaw, pitch)


func nearest_enemy() -> Enemy:
	var best: Enemy = null
	var bd := INF
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e == null or not e.alive() or e.def.ai.is_empty():
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


## Walk to (or fight) `e`: aim at its body centre, fire, close in beyond 10 m.
func fight(e: Enemy) -> void:
	look_at_point(e.global_position + Vector3(0, e.def.size.y * 0.5, 0))
	var held := ["action_primary"]
	if e.global_position.distance_to(player.global_position) > 10.0:
		held.append("forward")
	if player.mana.value < 5.0 and player.loadout.active == Loadout.Slot.STAFF:
		_input = PlayerInput.hold(held, ["slot_2"])
	else:
		_input = PlayerInput.hold(held, ["action_primary"] if int(t * 60.0) % 2 == 0 else [])


func walk_to(at: Vector3) -> void:
	look_at_point(at + Vector3(0, 1.0, 0))
	player.set_look(player.yaw, 0.0)
	_input = PlayerInput.hold(["forward"])


func _physics_process(delta: float) -> void:
	if _done or player == null:
		return
	t += delta
	total_time += delta
	stats["casts"] = maxi(stats["casts"], player.loadout.casters[0].casts + player.loadout.casters[1].casts)
	if total_time > SIM_LIMIT:
		_finish(false, "run over %.0f s in stage %s" % [SIM_LIMIT, stage])
		return
	if t > STAGE_LIMIT:
		_finish(false, "stage %s over %.0f s" % [stage, STAGE_LIMIT])
		return
	_input = PlayerInput.hold()
	match stage:
		"midden_walk":
			_input = PlayerInput.hold(["forward"])
			if t > 1.0:
				var moved := player.global_position.distance_to(_walk_start)
				if moved < 1.0:
					_finish(false, "did not move (%.2f m)" % moved)
					return
				note("walked %.1f m" % moved)
				_goto("midden_fight")
		"midden_fight", "breach_fight":
			var e := nearest_enemy()
			if e:
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
					_enter_arena()
			if stage == "midden_fight" and stats["kills"] >= MIDDEN_KILLS and e == null:
				_goto("midden_loot")
		"midden_loot", "breach_loot":
			var pk := nearest_pickup()
			if pk and t < 20.0:
				if pk.global_position.distance_to(player.eye_position()) < 2.5:
					look_at_point(pk.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
					_input = PlayerInput.hold([], ["interact"] if int(t * 60.0) % 2 == 0 else [])
				else:
					walk_to(pk.global_position)
			else:
				note("loot: %d pickup(s) so far" % stats["pickups"])
				if stage == "breach_loot" and stats["pickups"] == 0:
					_finish(false, "picked up none of the vault loot")
					return
				_goto("midden_craft" if stage == "midden_loot" else "breach_save")
		"midden_craft":
			_craft()
			_goto("midden_save")
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
			if c.global_position.distance_to(player.global_position) > 1.8 and t < 30.0:
				walk_to(c.global_position)
			else:
				if not c.in_reach(player):
					player.global_position = c.global_position + Vector3(0, 0.2, 1.0)
				var drops := c.open_chest()
				note("vault chest opened: %d drop(s)" % drops.size())
				if drops.is_empty():
					_finish(false, "vault chest gave nothing")
					return
				_goto("breach_loot")


## No enemy left and the waves not done: stand in the wave trigger (the bot teleports;
## walking the greybox needs no testing here).
func _enter_arena() -> void:
	var sp := main.get_node_or_null("Enemies") as EnemySpawner
	if sp == null:
		return
	if not sp.triggered() and t > 0.5:
		if player.global_position.distance_to(sp.trigger_center) > sp.trigger_radius * 0.5:
			player.global_position = sp.trigger_center + Vector3(0, 1.0, 0)
			player.velocity = Vector3.ZERO
			note("into the wave trigger at %s" % sp.trigger_center)


func _craft() -> void:
	var st: AssemblyStation = main.get_node_or_null("AssemblyStation")
	var base := WieldableInstance.load_base("earthward_battlestaff")
	var parts: Array = []
	for id in ["primordial_fire_head", "mythic_water_exterior", "basic_earth_interior", "rare_air_handle"]:
		parts.append(WieldablePart.load_part(id))
	player.inventory.add(base)
	for prt in parts:
		player.inventory.add(prt)
	var built := st.assemble(player, base, parts) if st else null
	if built == null:
		_finish(false, "craft refused: %s" % (st.last_error if st else "no station"))
		return
	stats["crafted"] = built.display_name()
	player.inventory.remove(built)
	player.equip(built)
	note("crafted + equipped %s (dmg %.1f)" % [built.display_name(), built.damage()])
