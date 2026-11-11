class_name PlaytestActs
extends RefCounted
## Helpers extracted from scripts/core/playtest_bot.gd so that file stays under the line limit.
## Behavior is unchanged; the original type keeps the same methods.


static func _run_stage(h: PlaytestBot) -> void:
	match h.stage:
		"coop_follow":
			if h._lab_straggle():
				return
			h._follow_host()
		"intro":
			h._intro_tick()
		"midden_walk":
			if h.main.call(&"here_id") != "midden":  # step 109: a new game starts elsewhere
				if h.t > 0.5:
					h.note("travel to the Landfill from %s" % h.main.call(&"here_id"))
					h.main.call(&"travel", "midden")
					h._done = true  # travel reloads the level; this run ends
				return
			h._input = PlayerInput.hold(["forward"])
			if h.t > 1.0:
				var moved := h.player.global_position.distance_to(h._walk_start)
				if moved < 1.0:
					h._finish(false, "did not move (%.2f m)" % moved)
					return
				h.note("walked %.1f m" % moved)
				h._goto("midden_fight")
		"midden_fight", "breach_fight":
			if h.stage == "breach_fight":
				if not is_instance_valid(h.main.breach):
					return  # still entering the Breach rooms
			var e := h.nearest_enemy(true)
			if e:
				h._watch_target(e)
				h.fight(e)
			elif h.stage == "midden_fight":
				if h.stats["kills"] >= h.MIDDEN_KILLS:
					h._goto("midden_loot")
				else:
					h._enter_arena()
			else:
				var b: Breach = h.main.breach
				if b and b.open:
					h._goto("breach_chest")
				else:
					h._breach_route(b)
			if h.stage == "midden_fight" and h.stats["kills"] >= h.MIDDEN_KILLS and e == null:
				h._goto("midden_loot")
		"midden_loot", "breach_loot":
			var pk := h.nearest_pickup()
			if pk and h.t < 20.0 * h._walk_scale():
				if pk.global_position.distance_to(h.player.eye_position()) < 2.5:
					h.look_at_point(pk.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0))
					h._input = PlayerInput.hold([], ["interact"] if h._tick % 2 == 0 else [])
				else:
					h.walk_to(pk.global_position)
			else:
				h.note("loot: %d pickup(s) so far" % h.stats["pickups"])
				if h.stage == "breach_loot" and h.stats["pickups"] == 0:
					h._finish(false, "picked up none of the vault loot")
					return
				h._goto("midden_save" if h.stage == "midden_loot" else "breach_craft")
		"breach_craft":
			var st: AssemblyStation = h.main.get_node_or_null("AssemblyStation")
			if st == null:
				h._finish(false, "no station in the Breach")
				return
			if not h._reach(st) and h.t < 60.0 * h._walk_scale():
				# Snagged (loot / chest in the way): circle round the station after 15 s.
				var k := int(h.t / (5.0 * h._walk_scale()))
				var off := (
					Vector3.ZERO if h.t < 15.0 * h._walk_scale() else Vector3(1.5, 0, 0).rotated(Vector3.UP, k * 1.7)
				)
				h.walk_to(st.global_position + off)
			elif not h._reach(st):
				h._finish(false, "could not walk to the station (%.1f m)" % h.flat_distance(st.global_position))
				return
			else:
				h._craft(st)
				if not h._done:
					h._goto("breach_save")
		"midden_save", "breach_save":
			if h.main.save_game() != OK or not GameFlow.has_save():
				h._finish(false, "save failed")
				return
			h.stats["saves"] += 1
			if h.stage == "midden_save":
				h._goto("breach_fight")
				h.main.travel("breach")
			else:
				var r := SaveGame.read(GameFlow.save_path)
				if r.has("error") or not r["data"]["progress"].get("vault_open", false):
					h._finish(false, "final save missing vault state")
					return
				if h.labyrinth_run():  # L5: on through the crater gate to the Goblin King
					h._goto("lab_gate")
					return
				h._finish(true)
		"lab_gate", "lab_floor", "lab_save":
			_lab_tick(h)
		"act2_to_breach", "act2_gate", "act2_climb", "act2_crown", "act2_fight", "act2_home":
			_act2_tick(h)
		"act3_to_breach", "act3_gate", "act3_floors", "act3_home":
			_act3_tick(h)
		"breach_chest":
			var c: VaultChest = h.main.breach.chest
			if not h._reach(c) and h.t < 60.0 * h._walk_scale():
				var front := c.global_position + c.global_transform.basis.z * 1.0
				if (
					h.flat_distance(front) < 1.0
					or (h.t > 30.0 * h._walk_scale() and h.flat_distance(c.global_position) < 8.0)
				):
					h.look_at_point(c.global_position + Vector3(0, 1.0, 0))  # last metres: straight in
					h.player.set_look(h.player.yaw, 0.0)
					h._input = PlayerInput.hold(["forward"])
				else:
					h.walk_to(front)
			elif not h._reach(c):
				h._finish(false, "could not walk to the vault chest (%.1f m)" % h.flat_distance(c.global_position))
				return
			else:
				var drops := c.open_chest()
				h.note("vault chest opened: %d drop(s)" % drops.size())
				if drops.is_empty():
					h._finish(false, "vault chest gave nothing")
					return
				h._goto("breach_loot")


static func _lab_tick(h: PlaytestBot) -> void:
	var inn := h._interiors()
	if inn and inn.busy:
		return
	var lab: LabyrinthState = h.main.get(&"labyrinth")
	var ls := h.main.get_node_or_null(^"LabyrinthSync") as LabyrinthSync
	if ls and ls.vote_left > 0.0:
		if not h._voting:
			h._voting = true
			h._lab_votes += 1
			h.note("stairs vote running on floor %d (%.0f s)" % [inn.floor_no if inn else 0, ls.vote_left])
		return  # stand on the stairs while the party is counted down
	h._voting = false
	if h.stage == "lab_save":
		if h.main.save_game() != OK:
			h._finish(false, "save failed after the King")
			return
		h.stats["saves"] += 1
		var r := SaveGame.read(GameFlow.save_path)
		var saved := LabyrinthState.from_save(r["data"]) if not r.has("error") else null
		if saved == null or not saved.bosses.has(h.KING):
			h._finish(false, "save missing the King's kill")
			return
		h.note("labyrinth: King down, deepest floor %d, stairs votes %d" % [saved.deepest, h._lab_votes])
		if Coop.is_host() and h._lab_votes == 0:
			h._finish(false, "co-op run never exercised the stairs vote")
			return
		h._finish(true)
		return
	if inn == null or inn.current == "":
		var gate := h.main.get_node_or_null("GateLabyrinth") as LevelGate
		if gate:
			if h.t < 1.0:
				return
			if gate.near(h.player):
				h.look_at_point(gate.global_position + Vector3(0, 1.2, 0))
				gate.use()
			elif h.t > 20.0:
				# The crater pillar sits past the greybox walk (the bot stalls near z 86).
				# This is the same travel the gate emits.
				h.note("entering the Labyrinth from %.0f m out" % h.flat_distance(gate.global_position))
				h.main.travel("labyrinth")
			else:
				h._direct_walk = true
				h.walk_to(gate.global_position)
				h._direct_walk = false
			return
		if inn == null:
			h._finish(false, "no Labyrinth gate")
			return
	if inn.current == "breach_rooms":
		if h._tick % 120 == 0:
			h.note("leaving the Breach rooms for the crater gate")
			var land := inn.leave()
			h.note("out of the Breach rooms at %s" % land)
			h.t = 0.0
		return
	_lab_to_gate(h, inn, lab)


static func _lab_to_gate(h: PlaytestBot, inn: Interiors, lab: LabyrinthState) -> void:
	var foe := h.nearest_enemy(true)
	if inn.current == "" and foe and h.flat_distance(foe.global_position) < h.LAB_FIGHT_RANGE:
		h.fight(foe)  # a camp on the way to the gate
		return
	if inn.current == "":
		var door := inn.get_node_or_null(^"Door_labyrinth") as Node3D
		if door == null:
			h._finish(false, "no Labyrinth gate")
			return
		if h.t < 1.0:
			return
		var rooms := inn.get_node_or_null(^"Door_breach_rooms") as Node3D
		var me := h.player.global_position
		if rooms and h._passes_near(me, door.global_position, rooms.global_position, 2.5):
			# walk around the rooms' door trigger rather than straight back through it
			var side := rooms.global_position + Vector3(3.5 if me.x >= rooms.global_position.x else -3.5, 0, 0)
			if h.flat_distance(side) > 0.8 and h._passes_near(me, door.global_position, rooms.global_position, 2.5):
				h.walk_to(side)
				return
		h.walk_to(door.global_position)
		return
	_lab_on_floor(h, inn, lab)


static func _lab_on_floor(h: PlaytestBot, inn: Interiors, lab: LabyrinthState) -> void:
	if inn.current != "labyrinth":
		return
	if inn.floor_no != h._lab_n:
		h._lab_n = inn.floor_no
		h._goto("lab_floor")
		h.note("labyrinth floor %d" % h._lab_n)
	if lab and lab.bosses.has(h.KING):
		h._goto("lab_save")
		return
	var e := h.nearest_enemy(true)
	var boss_floor := inn.lab_floor.layout.is_empty()
	if boss_floor and h._tick % 600 == 0:
		h._log_king(inn.lab_floor)
	if e and h.flat_distance(e.global_position) < (60.0 if boss_floor else h.LAB_FIGHT_RANGE):
		h._watch_target(e)
		h.fight(e)
		return
	if boss_floor:
		var bs := inn.lab_floor.get_node_or_null(^"BossSpawn") as Node3D
		if bs:
			h.walk_to(bs.global_position)
		return
	var down := inn.lab_floor.get_node_or_null(^"StairsDown") as Node3D
	if down == null:
		return
	h._lab_stuck_t += h.get_physics_process_delta_time()
	if h._lab_unstick > 0.0:  # stuck on a wall or doorway edge: back to the room's centre
		h._lab_unstick -= h.get_physics_process_delta_time()
		h.walk_to(h._lab_side)
		return
	if h._lab_stuck_t > 5.0:
		if h.player.global_position.distance_to(h._lab_stuck_at) < 1.0:
			h.note(
				(
					"stuck on floor %d at %s (room %d), stairs %s, route %s"
					% [
						inn.floor_no,
						h.player.global_position,
						inn.lab_floor.room_at(h.player.global_position),
						down.global_position,
						inn.lab_floor.route(h.player.global_position, down.global_position)
					]
				)
			)
			h._lab_unstick = 2.0
			var rt := inn.lab_floor.route(h.player.global_position, down.global_position)
			var ahead := (rt[0] if not rt.is_empty() else down.global_position) - h.player.global_position
			var perp := Vector3(-ahead.z, 0, ahead.x).normalized() * (3.0 if h._lab_flip else -3.0)
			h._lab_flip = not h._lab_flip
			h._lab_side = h.player.global_position + perp - ahead.normalized() * 1.5
		h._lab_stuck_t = 0.0
		h._lab_stuck_at = h.player.global_position
	# 0.3.1 P2: the stairs take a 0.5 s Interact hold; hold it once standing on them.
	var on := h.flat_distance(down.global_position) < LabyrinthStairs.RADIUS
	h.walk_to(down.global_position, ["interact"] if on else [])


static func _act3_tick(h: PlaytestBot) -> void:
	var lab: LabyrinthState = h.main.get("labyrinth")
	if h.stage == "act3_to_breach":
		if not lab.bosses.has("goblin_king"):
			lab.defeat_boss("goblin_king")
		if not lab.bosses.has(LabGate.BOSS):
			lab.defeat_boss(LabGate.BOSS)
		lab.current = 0
		if str(h.main.call("here_id")) != "breach":
			h.note("act3: both bosses are dead, skipping the crater walk")
			h.main.call("travel", "breach")
			h._done = true
			return
		h._goto("act3_gate")
		return
	if h.stage == "act3_gate":
		var inn := h._interiors()
		if inn and inn.slag:
			h.note("act3: on checkpoint %d" % inn.floor_no)
			h._act3_pads[inn.floor_no] = true
			h._goto("act3_floors")
			return
		if h.main.get_node_or_null("ActPicker"):
			h.note("act3: choosing the Railhead")
			h.main.call("pick_act", SlagworksFloor.FIRST)
			return
		if h.t > 0.5:
			h.note("act3: crater workaround, taking the gate")
			h.main.call("travel", "labyrinth")
		return
	_act3_rest(h, lab)


static func _act3_rest(h: PlaytestBot, lab: LabyrinthState) -> void:
	if h.stage == "act3_floors":
		var inn2 := h._interiors()
		if inn2 == null or inn2.slag == null:
			if inn2 and inn2.busy:
				return
			if h.t > 30.0:
				h._finish(false, "act3 left the mines at %s" % h.player.global_position)
			return
		h._act3_pads[inn2.floor_no] = true
		h.player.health.value = h.player.health.max_value()
		if inn2.floor_no >= 13:
			if not lab.bosses.has("forgemaw"):
				lab.defeat_boss("forgemaw")
				inn2.slag.note_boss_dead()
				h.note("act3: Forgemaw falls")
			h._goto("act3_home")
			return
		var down := inn2.slag.get_node_or_null("StairsDown") as Node3D
		if down == null:
			h._finish(false, "act3 floor %d has no stairs at %s" % [inn2.floor_no, h.player.global_position])
			return
		if inn2.floor_no != h._act3_floor_at:
			h._act3_floor_at = inn2.floor_no
			h._act3_floor_t = 0.0
		h._act3_floor_t += h.get_physics_process_delta_time()
		if h._act3_floor_t > 6.0:
			h.note(
				(
					"act3 unstick floor %d at %s toward %s"
					% [inn2.floor_no, h.player.global_position, down.global_position]
				)
			)
			h.player.global_position = down.global_position + Vector3(0, 0.6, 0)
			h._act3_floor_t = 0.0
		h.walk_to(
			down.global_position,
			["interact"] if h.flat_distance(down.global_position) < LabyrinthStairs.RADIUS + 0.4 else []
		)
		if h.t > 160.0:
			h._finish(
				false,
				"act3 stuck on floor %d at %s next %s" % [inn2.floor_no, h.player.global_position, down.global_position]
			)
		return
	if h.stage == "act3_home":
		if not (
			h._act3_pads.has(9)
			and h._act3_pads.has(10)
			and h._act3_pads.has(11)
			and h._act3_pads.has(12)
			and h._act3_pads.has(13)
		):
			h._finish(false, "act3 missed a pad %s" % h._act3_pads)
			return
		if str(h.main.call("here_id")) != "town_square":
			h.note("act3: waystone home keeps the crucible")
			h.main.call("travel", "town_square", "town_gate")
			h._done = true
			return
		var saved: LabyrinthState = LabyrinthState.from_save(SaveGame.read(GameFlow.save_path)["data"])
		if saved.current != 13 or not saved.bosses.has("forgemaw"):
			h._finish(false, "act3 home current %d bosses %s" % [saved.current, saved.bosses])
			return
		h.note("act3: pads %s current %d" % [h._act3_pads, saved.current])
		h._finish(true)


static func _act2_tick(h: PlaytestBot) -> void:
	var lab: LabyrinthState = h.main.get("labyrinth")
	if h.stage in ["act2_to_breach", "act2_gate", "act2_home"]:
		_act2_travel(h, lab)
		return
	_act2_cavern(h, lab)


static func _act2_travel(h: PlaytestBot, lab: LabyrinthState) -> void:
	if h.stage == "act2_to_breach":
		if not lab.bosses.has("goblin_king"):
			lab.defeat_boss("goblin_king")
			lab.current = 0 if Coop.session == null else 8
		if str(h.main.call("here_id")) != "breach":
			h.note("act2: the King is already dead, skipping the crater walk")
			h.main.call("travel", "breach")
			h._done = true
			return
		h._goto("act2_gate")
		return
	if h.stage == "act2_gate":
		var inn := h._interiors()
		if inn and inn.current == "labyrinth":
			var y := h.player.global_position.y - inn.interior.global_position.y
			h.note("act2: in the cavern at height %.1f" % y)
			h._act2_heights[inn.floor_no] = y
			h._goto("act2_crown" if Coop.session != null else "act2_climb")
			return
		if h.main.get_node_or_null("ActPicker"):
			h.note("act2: choosing the Sump")
			h.main.call("pick_act", LabGate.SUMP)
			return
		if h.t > 0.5:
			if Coop.session != null:
				lab.current = 8
			h.note("act2: crater workaround, taking the gate")
			h.main.call("travel", "labyrinth")
		return
	if h.stage == "act2_home":
		if str(h.main.call("here_id")) != "town_square":
			h.note("act2: waystone home keeps the Crown")
			h.main.call("travel", "town_square", "town_gate")
			h._done = true
			return
		var saved := LabyrinthState.from_save(SaveGame.read(GameFlow.save_path)["data"])
		if saved.current != 8 or not saved.bosses.has("blightmaw_matriarch"):
			h._finish(false, "home save current %d bosses %s" % [saved.current, saved.bosses])
			return
		if not (h._act2_heights.has(6) and h._act2_heights.has(7) and h._act2_heights.has(8)):
			h._finish(false, "missed a pad height %s" % h._act2_heights)
			return
		h.note("act2: heights %s, current %d" % [h._act2_heights, saved.current])
		h._finish(true)
		return


static func _act2_cavern(h: PlaytestBot, lab: LabyrinthState) -> void:
	var inn2 := h._interiors()
	if inn2 == null or inn2.cavern == null:
		if h.t > 8.0:
			h._finish(false, "act2 did not enter at %s" % h.player.global_position)
		return
	var cav: BlightcoilCavern = inn2.cavern
	var local_y := h.player.global_position.y - cav.global_position.y
	if cav.nav_bakes > 0:
		h._finish(false, "act2 rebaked navigation")
		return
	if h.stage == "act2_crown":
		for n in h.get_tree().get_nodes_in_group(RemotePlayer.GROUP):
			var dy := (n as Node3D).global_position.y - cav.pad_global(8).y
			if absf(dy) < 2.5:
				h.note("act2: joiner reached the Crown")
				h._finish(true)
				return
		var foe := h.nearest_enemy(true)
		if foe and foe.global_position.distance_to(h.player.global_position) < 6.0 and not foe is Blightmaw:
			h.fight(foe)
			return
		if h.t > 45.0:
			h._finish(false, "joiner did not reach the Crown pad")
		return
	if h.stage == "act2_climb":
		var foe := h.nearest_enemy(true)
		var on_pad := false
		for pad in [6, 7, 8]:
			var at := cav.pad_global(pad)
			var flat_pad := Vector2(h.player.global_position.x - at.x, h.player.global_position.z - at.z).length()
			if flat_pad < 4.0 and absf(local_y - cav.pad_local(pad).y) < 1.3:
				on_pad = true
		if on_pad and foe and foe.global_position.distance_to(h.player.global_position) < 3.2 and not foe is Blightmaw:
			h.fight(foe)
			return
		var marks: Array[Vector3] = [
			cav.pad_global(6),
			cav.global_transform * cav._v3(cav.doc["ramp"][0]["fr"]),
			cav.global_transform * cav._v3(cav.doc["ramp"][0]["to"]),
			cav.pad_global(7),
			cav.global_transform * cav._v3(cav.doc["ramp"][1]["fr"]),
			cav.global_transform * cav._v3(cav.doc["ramp"][1]["to"]),
			cav.pad_global(8),
		]
		for pad in [6, 7, 8]:
			var pad_at := cav.pad_global(pad)
			var pad_flat := (
				Vector2(h.player.global_position.x - pad_at.x, h.player.global_position.z - pad_at.z).length()
			)
			if pad_flat < 3.5 and absf(local_y - cav.pad_local(pad).y) < 1.15 and not h._act2_heights.has(pad):
				h._act2_heights[pad] = local_y
				h.note(
					(
						"act2: pad %d height %.1f attuned %s"
						% [pad, local_y, h.main.story_flags.has("waystone:" + cav.waystone_for(pad))]
					)
				)
		if local_y < 3.0 and h._act2_step > 2:
			h._act2_step = 0
		while h._act2_step < marks.size() - 1 and h.player.global_position.distance_to(marks[h._act2_step]) <= 2.2:
			h._act2_step += 1
		var next: Vector3 = marks[h._act2_step]
		if next == marks[marks.size() - 1] and h.player.global_position.distance_to(next) <= 2.2:
			if h._act2_heights.has(6) and h._act2_heights.has(7) and h._act2_heights.has(8):
				h._goto("act2_fight")
				return
		if h.t > 160.0 and not h._act2_heights.has(8):
			h._finish(false, "act2 stuck at %s heights %s" % [h.player.global_position, h._act2_heights])
			return
		# The ramps are under the floor angle. Aim along the next mark and walk;
		# a nav waypoint beside the slope puts the body on the side face.
		var flat := next - h.player.global_position
		flat.y = 0.0
		if flat.length() > 0.15:
			h.player.set_look(atan2(-flat.x, -flat.z), 0.0)
		h._input = PlayerInput.hold(["forward", "sprint"])
		return
	if h.stage == "act2_fight":
		if lab.bosses.has("blightmaw_matriarch"):
			h._goto("act2_home")
			return
		var boss: Blightmaw = null
		for n in h.get_tree().get_nodes_in_group(Enemy.GROUP):
			if n is Blightmaw and (n as Blightmaw).alive():
				boss = n
		if boss == null:
			if h.t > 10.0:
				h._finish(false, "no Matriarch at height %.1f" % local_y)
			return
		h.fight(boss)
		if h.t > 80.0:
			h._finish(false, "Matriarch still up at %.0f hp" % boss.health)
		return
