class_name MainLabyrinth
extends RefCounted
## Helpers extracted from scripts/core/main.gd so that file stays under the line limit.
## Behavior is unchanged; the original type keeps the same methods.


## L2: a boss floor whose boss is down gets its waystone (FastTravel.DEEP_POINTS).
static func _lab_waystone(h: Main, fl: LabyrinthFloor) -> void:
	var player := h.get_node_or_null("Player") as Player
	var spot := fl.get_node_or_null("WaystoneSpot") as Node3D
	if spot and h.labyrinth.bosses.has(String(spot.get_meta(&"boss", ""))):
		for p in FastTravel.DEEP_POINTS:
			if int(FastTravel.DEEP_POINTS[p]["floor"]) == fl.floor_no and not fl.has_node("Waystone_" + p):
				var w := Waystone.new(p, h.fast_travel)
				w.name = "Waystone_" + p
				w.player = player
				fl.add_child(w)
				w.global_position = spot.global_position
				w.opened.connect(h.open_map)


## L3: the floor's goblins (and the King) under their own spawner, freed with the floor. An
## elite room is saved dead once its whole pack is down; the King's kill opens the waystone.
static func _lab_enemies(h: Main, fl: Node3D, player: Player) -> void:
	if h.coop and not h.coop.host:
		return  # L4: a joiner's goblins are the host's puppets (CoopWorld snapshots)
	var old := h.get_node_or_null("LabyrinthEnemies")
	if old:
		old.name = "LabyrinthEnemies_old"
		old.queue_free()
	var sp := EnemySpawner.new()
	sp.name = "LabyrinthEnemies"
	h.add_child(sp)
	var marks := fl.get_node_or_null("EnemySpawns")
	var packs := {}
	for e in sp.setup(fl, player):
		var m := marks.get_node_or_null(NodePath(String(e.name))) if marks else null
		var elite := String(m.get_meta(&"lab_elite", "")) if m else ""
		var boss := String(m.get_meta(&"lab_boss", "")) if m else ""
		if elite != "":
			packs[elite] = int(packs.get(elite, 0)) + 1
		var pad := int(m.get_meta(&"pad", fl.get("floor_no"))) if m else int(fl.get("floor_no"))
		ActLoot.tag(e, pad)
		if pad >= LabGate.SUMP and e is Gnawer and fl is BlightcoilCavern:
			var gn := e as Gnawer
			gn.cavern_sense = true
			gn.has_home = true
			gn.home_pad = e.global_position
			if gn.nav:
				gn.nav.set_navigation_map((fl as BlightcoilCavern).nav_map())
		if e is Blightmaw and fl is BlightcoilCavern:
			(e as Blightmaw).crown_global_y = (fl as BlightcoilCavern).pad_global(LabGate.CROWN).y
			(e as Blightmaw).phase_changed.connect(
				func(_b, ph: int) -> void:
					if ph >= 2 and fl is BlightcoilCavern:
						(fl as BlightcoilCavern).spawn_crown_vines()
			)
		if e.def and e.def.id == "spore_husk" and fl is BlightcoilCavern:
			e.died.connect(
				func(dead: Enemy, _el) -> void:
					if fl is BlightcoilCavern and is_instance_valid(fl):
						(fl as BlightcoilCavern).spawn_puff(dead.global_position)
			)
		e.died.connect(h._on_lab_kill.bind(fl, elite, boss, packs))
	fl.tree_exiting.connect(sp.queue_free, CONNECT_ONE_SHOT)


static func _on_lab_kill(
	h: Main, _e: Enemy, _el: ElementTable.Element, fl: Node3D, elite: String, boss: String, packs: Dictionary
) -> void:
	var floor_no := int(fl.get("floor_no"))
	if elite != "":
		packs[elite] = int(packs[elite]) - 1
		if int(packs[elite]) <= 0:
			h.labyrinth.kill_elite(floor_no, elite)
	if boss != "":
		var first := not h.labyrinth.bosses.has(boss)
		h.labyrinth.defeat_boss(boss)
		if fl is BlightcoilCavern and is_instance_valid(fl):
			(fl as BlightcoilCavern).note_boss_dead()
			if first:
				_lab_boss_chest(h, fl, _e, first)
		elif fl is LabyrinthFloor and is_instance_valid(fl):
			_lab_boss_chest(h, fl, _e, first)
			_lab_waystone(h, fl)
		elif fl is SlagworksFloor and is_instance_valid(fl):
			(fl as SlagworksFloor).note_boss_dead()
			if first:
				_lab_boss_chest(h, fl, _e, first)
		elif fl is SunkenFloor and is_instance_valid(fl):
			(fl as SunkenFloor).note_boss_dead()
			if first:
				_lab_boss_chest(h, fl, _e, first)
		print("[labyrinth] %s defeated" % boss)


## L4: secret-room chests, one tier above the floor (ActLoot.chest_rarity); opened ones
## are kept per floor in the save (shown open, no loot) until the floor is remixed.
static func _lab_chests(h: Main, fl: Node3D, player: Player) -> Array[VaultChest]:
	var out: Array[VaultChest] = []
	var marks := fl.get_node_or_null(^"Chests")
	if marks == null:
		return out
	for m in marks.get_children():
		var id := String(m.name)
		var c := VaultChest.new()
		c.name = "Chest_" + id
		c.player = player
		c.dropper = h.get_node_or_null("LootDropper") as LootDropper
		c.floor_rarity = ActLoot.chest_rarity(int(fl.get("floor_no")), bool(m.get_meta(&"secret", false)))
		c.set_meta(&"tier", "secret" if m.get_meta(&"secret", false) else "normal")
		c.set_meta(&"chest_id", id)
		c.unlock()
		fl.add_child(c)
		c.global_transform = (m as Node3D).global_transform
		var floor_no := int(fl.get("floor_no"))
		if h.labyrinth and h.labyrinth.chest_open(floor_no, id):
			c.open_chest_quiet()
		else:
			c.opened.connect(func(_d: Array[LootDrop]) -> void: h.labyrinth.open_chest(floor_no, id))
		out.append(c)
	return out


## L4: the Act boss leaves an open chest where it fell: Unique floor on the first clear,
## Rare on repeats (ActLoot.boss_rarity), in the boss's element.
static func _lab_boss_chest(h: Main, fl: Node3D, e: Enemy, first: bool) -> VaultChest:
	var c := VaultChest.new()
	c.name = "BossChest"
	c.player = h.get_node_or_null("Player") as Player
	c.dropper = h.get_node_or_null("LootDropper") as LootDropper
	c.floor_rarity = ActLoot.boss_rarity(int(fl.get("floor_no")), first)
	c.set_meta(&"tier", "boss")
	if e and e.def:
		c.element = e.def.affinity
	c.unlock()
	fl.add_child(c)
	if e and e.is_inside_tree():
		c.global_position = e.global_position + Vector3(0, 0, 1.5)
	return c


## The loaded level, or the Labyrinth while a floor is built in the Breach.
static func here_id(h: Main) -> String:
	var lin := _linear_interiors(h)
	if lin and lin.current == "labyrinth":
		return "labyrinth"
	return GameFlow.id_of(h.get_node_or_null("Level"))


static func travel(h: Main, to: String, anchor := "") -> void:
	if h.coop and not h.coop.host:
		print("[coop] only the host can travel")  # step 91: the host's world decides
		return
	if to == "labyrinth" and not FastTravel.is_deep(anchor):
		var floor := LabGate.resolve(h.labyrinth, h.act_choice)
		if floor < 0:
			_open_act_picker(h)
			return
		h._pending_floor = floor
		if h.gate_vote:
			h.gate_vote.act_name = LabGate.banner(floor)
	elif FastTravel.is_deep(anchor):
		h._pending_floor = int(FastTravel.info(anchor).get("floor", 0))
	if h.gate_vote and h.coop and h.coop.host:
		var who := h.get_node_or_null("Player") as Node3D
		if h.gate_vote.begin(to, anchor, who.global_position if who else Vector3.ZERO):
			return
	_commit_travel(h, to, anchor)


## Host picks Goblin Warrens floor 1 or the Blightcoil Sump. A joiner never sees this.
static func pick_act(h: Main, floor_no: int) -> void:
	h.act_choice = floor_no
	if h.act_picker:
		h.act_picker.queue_free()
		h.act_picker = null
	travel(h, "labyrinth")


static func _open_act_picker(h: Main) -> void:
	if h.act_picker and is_instance_valid(h.act_picker):
		return
	h.act_picker = CanvasLayer.new()
	h.act_picker.name = "ActPicker"
	h.add_child(h.act_picker)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	h.act_picker.add_child(box)
	for floor_no in LabGate.choices(h.labyrinth):
		var b := Button.new()
		b.text = LabGate.choice_label(floor_no)
		b.pressed.connect(h.pick_act.bind(floor_no))
		box.add_child(b)
	print("[labyrinth] choose an act")


static func _commit_travel(h: Main, to: String, anchor := "") -> void:
	var floor := h._pending_floor if to == "labyrinth" else _travel_floor(h, anchor)
	if to == "labyrinth" and floor <= 0:
		floor = LabGate.resolve(h.labyrinth, h.act_choice)
	if to == "labyrinth" and floor < 0:
		return  # the crater path does not send checkpoint 0 once the picker exists
	h._pending_floor = 0
	h.act_choice = -1
	if h.coop and h.coop.host:
		Coop.session.send("travel", {"to": to, "floor": floor if to == "labyrinth" else _travel_floor(h, anchor)})
	if to == "labyrinth":
		h.save_game()
		_enter_linear_labyrinth(h, floor)
		return
	var player := h.get_node_or_null("Player") as Player
	if player and to == "mage_association":
		player.gear.refill()
	if player:
		var d := SaveGame.capture(player, h.progress())
		d["progress"]["level_id"] = to
		d["progress"]["anchor"] = anchor  # step 155: "" = the new level's PlayerStart
		d["progress"].erase("map_version")
		SaveGame.write(d, GameFlow.save_path)
	GameFlow.travel(h.get_tree(), to)


static func _travel_floor(_h: Main, anchor: String) -> int:
	var info := FastTravel.info(anchor)
	return int(info.get("floor", 0)) if FastTravel.is_deep(anchor) else 0


static func _linear_interiors(h: Main) -> Interiors:
	return h.get_node_or_null("LinearInteriors") as Interiors


## The Breach crater portal: build the Labyrinth floor in this level (no scene change).
static func _ensure_lab_sync(h: Main) -> void:
	if GameFlow.id_of(h.get_node_or_null("Level")) != "breach":
		return
	var ints := _linear_interiors(h)
	if ints == null:
		ints = Interiors.new()
		ints.name = "LinearInteriors"
		ints.level_local = true
		ints.labyrinth = h.labyrinth
		h.add_child(ints)
		ints.floor_entered.connect(h._on_linear_floor)
		ints.rested.connect(h._on_lab_rest)
	elif not ints.rested.is_connected(h._on_lab_rest):
		ints.rested.connect(h._on_lab_rest)
	if h.coop and Coop.session and h.get_node_or_null("LabyrinthSync") == null:
		var ls := LabyrinthSync.new()
		ls.name = "LabyrinthSync"
		h.add_child(ls)
		ls.setup(Coop.session, ints, h.coop.host)


static func _enter_linear_labyrinth(h: Main, floor := 0) -> void:
	_ensure_lab_sync(h)
	var ints := _linear_interiors(h)
	if ints == null:
		return
	if floor > 0:
		ints.floor_no = floor
		h.labyrinth.current = floor
	if ints.current == "labyrinth":
		return
	await ints.enter("labyrinth")


static func _on_lab_rest(h: Main, _at: Vector3) -> void:
	var ints := _linear_interiors(h)
	if ints and ints.cavern:
		h.labyrinth.current = 7
		ints.floor_no = 7
		ints.cavern.floor_no = 7
	elif ints and ints.slag:
		h.labyrinth.current = ints.floor_no
	var player := h.get_node_or_null("Player") as Player
	if player:
		player.clear_blight_status()
	h.save_game()


static func _on_blight_pad(h: Main, checkpoint: int, waystone_id: String) -> void:
	var ints := _linear_interiors(h)
	h.labyrinth.current = checkpoint
	h.labyrinth.reach(checkpoint)
	if ints:
		ints.floor_no = checkpoint
		if ints.cavern:
			ints.cavern.floor_no = checkpoint
			var player := h.get_node_or_null("Player") as Player
			if player:
				player.spawn_feet = ints.cavern.pad_global(checkpoint)
			if ints.cavern.hazard:
				ints.cavern.hazard.last_pad = ints.cavern.pad_global(checkpoint)
		elif ints.slag:
			var player := h.get_node_or_null("Player") as Player
			if player:
				player.spawn_feet = ints.slag.pad_global()
	if h.fast_travel:
		h.fast_travel.attune(waystone_id)
	h.save_game()


static func _on_linear_floor(h: Main, _n: int) -> void:
	var ints := _linear_interiors(h)
	var player := h.get_node_or_null("Player") as Player
	if ints and ints.cavern:
		_enter_cavern_runtime(h, ints.cavern, player)
		return
	if ints and ints.slag:
		_enter_slag_runtime(h, ints.slag, player)
		return
	if ints and ints.sunken:
		_enter_sunken_runtime(h, ints.sunken, player)
		return
	var fl := ints.lab_floor if ints else null
	if fl == null:
		return
	_lab_waystone(h, fl)
	_lab_loot_parent_linear(h, fl)
	_lab_enemies(h, fl, player)
	_lab_chests(h, fl, player)


static func _enter_slag_runtime(h: Main, fl: SlagworksFloor, player: Player) -> void:
	DialogueDB.bosses = h.labyrinth.bosses
	if h.quests:
		h.quests.known_bosses = h.labyrinth.bosses
	if not fl.pad_reached.is_connected(h._on_blight_pad):
		fl.pad_reached.connect(h._on_blight_pad)
	fl.place_story(h.story_flags)
	_wire_spirit(h, fl, player)
	if player:
		player.spawn_feet = fl.pad_global()
		if fl.on_pad(player.global_position):
			_on_blight_pad(h, fl.floor_no, fl.waystone_id)
	_lab_loot_parent_linear(h, fl)
	_lab_enemies(h, fl, player)
	_lab_chests(h, fl, player)


static func _enter_sunken_runtime(h: Main, fl: SunkenFloor, player: Player) -> void:
	DialogueDB.bosses = h.labyrinth.bosses
	if h.quests:
		h.quests.known_bosses = h.labyrinth.bosses
	if not fl.pad_reached.is_connected(h._on_blight_pad):
		fl.pad_reached.connect(h._on_blight_pad)
	if player:
		player.spawn_feet = fl.pad_global()
	_lab_enemies(h, fl, player)
	if h.labyrinth.bosses.has(SunkenFloor.BOSS) and fl.floor_no == SunkenFloor.LAST:
		fl.note_boss_dead()
		var spot := fl.get_node_or_null("WaystoneSpot") as Node3D
		if spot and h.fast_travel and not fl.has_node("Waystone_sunken_nave"):
			var w := Waystone.new("sunken_nave", h.fast_travel)
			w.name = "Waystone_sunken_nave"
			w.player = player
			fl.add_child(w)
			w.global_position = spot.global_position
			w.opened.connect(h.open_map)


static func _enter_cavern_runtime(h: Main, cav: BlightcoilCavern, player: Player) -> void:
	DialogueDB.bosses = h.labyrinth.bosses
	if h.quests:
		h.quests.known_bosses = h.labyrinth.bosses
	if not cav.pad_reached.is_connected(h._on_blight_pad):
		cav.pad_reached.connect(h._on_blight_pad)
	cav.place_marks(h.story_flags)
	_wire_mother(h, cav, player)
	if player:
		player.spawn_feet = cav.pad_global(cav.floor_no)
	_lab_loot_parent_linear(h, cav)
	_lab_enemies(h, cav, player)
	_lab_chests(h, cav, player)
	if h.labyrinth.bosses.has(LabGate.BOSS):
		cav.note_boss_dead()
		_free_matriarch(h)


static func _wire_spirit(h: Main, fl: SlagworksFloor, player: Player) -> void:
	if fl.floor_no != 11 or h.get_node_or_null("Npc_ScrapSpirit"):
		return
	var mark := fl.get_node_or_null("ScrapSpirit") as Node3D
	if mark == null:
		return
	h._ensure_dialogue()
	var n := Npc.new("Scrap-spirit")
	n.name = "Npc_ScrapSpirit"
	n.player = player
	h.add_child(n)
	n.global_position = mark.global_position


static func _wire_mother(h: Main, cav: BlightcoilCavern, player: Player) -> void:
	if cav.get_node_or_null("Npc_VerdantMother"):
		return
	var mark := cav.get_node_or_null("VerdantMother") as Node3D
	if mark == null:
		return
	h._ensure_dialogue()
	var n := Npc.new("Verdant Mother")
	n.name = "Npc_VerdantMother"
	n.player = player
	h.add_child(n)
	n.global_position = mark.global_position
	n.talked.connect(h._on_npc_talked)
	h.npcs.append(n)


static func _free_matriarch(h: Main) -> void:
	var sp := h.get_node_or_null("LabyrinthEnemies")
	if sp == null:
		return
	for e in sp.get_children():
		if e is Blightmaw:
			(e as Node).queue_free()


static func _lab_loot_parent_linear(h: Main, fl: Node3D) -> void:
	var ld := h.get_node_or_null("LootDropper") as LootDropper
	if ld:
		ld.parent = fl
