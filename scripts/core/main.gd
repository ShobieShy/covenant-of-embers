extends Node3D
## Entry scene. `--seconds N` (after `--`) quits after N seconds and reports
## frames and physics ticks, the Godot counterpart of the old `covenant --seconds`.

var _boss_spawner: EnemySpawner  # step 57
var _seconds := -1.0
var _elapsed := 0.0
var _frames := 0
var _ticks := 0
var settings: Settings   # step 32
var pause_menu: PauseMenu   # step 39
var breach: Breach          # step 39: the Breach room logic when the Breach is loaded
var gate: LevelGate         # step 39: travel gate (Midden -> Breach -> back)
var gates: Array[LevelGate] = []  # step 65: every travel gate here (level [[exit]]s, or the defaults)
var vendors := {}  # step 61: speaker -> Vendor
var vendor_ui: VendorUi
var shop_pending := ""
var npcs: Array[Npc] = []  # step 65: level [[npc]]s
var story_flags := StoryFlags.new()
var dialogue: DialogueRunner
var quests: QuestLog  # step 67: the tutorial chain (saved in progress["quests"])
var quest_driver: QuestDriver
var quest_ui: QuestTrackerUI
var _loaded_quests := {}
var dialogue_ui: DialogueUI
var stash: Stash  # step 66: the Old Oak's shared stash (own file, every slot)
var mentor_played := false
var fast_travel: FastTravel  # step 68
var waystone: Waystone
var travel_ui: FastTravelUI
var world_map: WorldMap  # step 69
var world_map_ui: WorldMapUI
var load_warnings := PackedStringArray()
var coop: CoopWorld  # step 79: set when a co-op session is running
var intro: IntroDirector  # step 109: set while the intro runs

func _ready() -> void:
	UiTheme.apply(get_tree().root)  # t60u: in-game screens too, even when main runs without the menu
	var args := OS.get_cmdline_user_args()
	var i := args.find("--seconds")
	if i >= 0 and i + 1 < args.size():
		_seconds = float(args[i + 1])
	print("[main] Covenant of Embers on Godot %s, renderer %s" % [
		Engine.get_version_info().string,
		ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	# Step 21: hotfix balance patches from user://patches/*.json (sorted, all-or-nothing each).
	var patch_log := BalancePatch.apply_dir("user://patches")
	print("[patches] %d applied, %d rejected" % [BalancePatch.applied.size(), patch_log.size()])
	for m in patch_log:
		push_warning("[patches] " + m)
	_swap_level(GameFlow.level_id)
	# The player spawns at the level's PlayerStart (feet), facing its yaw; its Head sits
	# at PlayerStart/Eye (1.5 m).
	var start := get_node_or_null("Level/PlayerStart") as Node3D
	var player := get_node_or_null("Player") as Player
	if start and player:
		player.spawn(start.global_position, deg_to_rad(float(start.get_meta("yaw_deg", 0.0))))
		# Step 7: the Apprentice Fire Staff in hand, bolts into the scene's SpellBolts.
		# Step 10: the Swift Wind Wand in the wand slot (slot_2 / mouse wheel).
		player.bolts = get_node_or_null("Bolts") as SpellBolts
		player.equip(WieldableInstance.load_base("apprentice_fire_staff"))
		player.equip(WieldableInstance.load_base("swift_wind_wand"))
		# Step 11: the level's training dummies at its EnemySpawns markers and floating
		# damage numbers on every resolved hit. Step 12: the Gnawer spawns there too and
		# hunts the player over the level's baked navmesh. Step 13: the Heap (a Gnawer
		# subclass) too; every bite/slam not dodged (dash i-frames) hits the player's
		# shield, then health (Player.on_enemy_attack); he respawns at PlayerStart.
		# Step 14: an EnemySpawner owns them (the node keeps the old "Enemies" name): it
		# wires target + attacks, frees the dead, respawns the dummies (3 s) and runs the
		# level's waves once the player walks onto the midden mound.
		var spawner := EnemySpawner.new()
		spawner.name = "Enemies"
		add_child(spawner)
		var spawned := spawner.setup($Level, player)
		var skipped := spawner.skipped
		# Step 22: kills drop rarity-coloured pickups with a light beam (not dummies).
		var dropper := LootDropper.new()
		dropper.name = "LootDropper"
		add_child(dropper)
		# Step 27: kill XP to players within 80 m (Magewar kill reward service).
		var xp := XpRewarder.new()
		xp.name = "XpRewarder"
		add_child(xp)
		var numbers := DamageNumbers.new()
		numbers.name = "DamageNumbers"
		add_child(numbers)
		numbers.connect_bolts(player.bolts)
		# Step 29: HUD (CanvasLayer 2, above the viewmodel overlay).
		var hud := Hud.new()
		add_child(hud)
		hud.bind(player, spawner)
		_boss_spawner = spawner
		if spawner.trigger_radius > 0.0 and spawner.waves.any(func(w): return String(w["id"]) == Filth.WAVE_ID):
			ArenaLock.attach(spawner, Filth.WAVE_ID)  # step 57: walls during The Filth
		GameEvents.bus().wave_started.connect(_on_wave_started)  # step 57: boss-door checkpoint
		var audio := GameAudio.new()   # step 37: Kenney SFX on the SFX/UI buses
		audio.name = "GameAudio"
		add_child(audio)
		audio.bind(player)
		var inv_ui := InventoryUi.new()   # step 30: Tab
		inv_ui.name = "InventoryUi"
		add_child(inv_ui)
		inv_ui.bind(player)
		var sk_ui := SkillsUi.new()   # step 72: K
		sk_ui.name = "SkillsUi"
		sk_ui.can_respec = can_respec
		add_child(sk_ui)
		sk_ui.bind(player)
		# Step 31: an Assembly Station beside the start (E opens it) + its screen.
		# Step 46: at the level's WaveSpawns/station marker (Breach entrance), else beside the start.
		AssemblyStation.place(self, $Level, player.spawn_feet + Vector3(2.0, 0.0, -1.0))
		var st_ui := StationUi.new()
		st_ui.name = "StationUi"
		add_child(st_ui)
		st_ui.bind(player)
		# Step 32: saved bindings + options (user://keybinds.cfg), applied at spawn.
		settings = Settings.load_from()
		settings.apply_input_map()
		settings.apply_to(player)
		_setup_flow(player)
		if Coop.active():
			_setup_coop(player, spawner)
		print("[enemies] %d spawned (%s), %d skipped (%s)" % [spawned.size(),
			", ".join(spawned.map(func(e: Enemy) -> String: return e.def.id)), skipped.size(), ", ".join(skipped)])
		var nav := $Level.get_node_or_null("Navigation") as LevelNavigation
		print("[nav] %s navmesh: %d polygon(s), %d bake(s)" % [$Level.name,
			nav.polygon_count() if nav else 0, nav.bakes if nav else 0])
		print("[waves] %d wave(s) (%s), trigger r %.1f m at %s" % [spawner.waves.size(),
			", ".join(spawner.waves.map(func(w: Dictionary) -> String: return String(w["id"]))),
			spawner.trigger_radius, spawner.trigger_center])
		var rt := RarityTable.load_default()
		var staff := player.loadout.wieldable(Loadout.Slot.STAFF)
		print("[loot] %d rarities (%s), %d Magewar parts, staff %s %s x%.2f" % [rt.rarities.size(),
			", ".join(Array(Rarity.IDS).map(func(r: String) -> String: return "%s #%s" % [rt.display_name(r), rt.color(r).to_html(false)])),
			WieldablePart.list_ids().size(), staff.rarity().display_name if staff else "-",
			staff.display_name() if staff else "empty", staff.rarity().multiplier if staff else 0.0])
		var sample := PartRoller.from_seed(16, WieldablePart.PartType.HEAD, "rare")
		print("[parts] rolled seed 16 rare Head: %s (%s), dmg %.2f, acc %.2f, %d gem slot(s)" % [sample.display_name,
			sample.id, sample.damage_bonus, sample.accuracy_bonus, sample.gem_slots])
		var built := Assembly.assemble(WieldableInstance.load_base("earthward_battlestaff").def, ["primordial_fire_head",
			"mythic_water_exterior", "basic_earth_interior", "rare_air_handle", "unique_void_charm"].map(
			func(id: String) -> WieldablePart: return WieldablePart.load_part(id)))
		print("[assembly] Earthward + 5 Magewar parts: %s, dmg %.1f, %.4f s, acc %.0f %%, %d gem slot(s), draw %.3f s" % [
			built.display_name(), built.damage(), built.cooldown(), built.accuracy(), built.gem_slots(),
			built.draw_seconds(player.loadout.swap_seconds)])
		var heap_def := EnemyTable.load_default().find("heap")
		var drop_rng := RandomNumberGenerator.new()
		drop_rng.seed = 18
		var drop_names := PackedStringArray()
		for d in DropRoller.roll_enemy(drop_rng, heap_def):
			drop_names.append(d.describe())
		print("[drops] %d pool(s); Heap (level %d) kill, seed 18: %s" % [DropRoller.default_pools().pools.size(),
			heap_def.level, ", ".join(drop_names)])
		var eq_rng := RandomNumberGenerator.new()
		eq_rng.seed = 19
		var robes := EquipmentRoller.roll(eq_rng, EquipmentItem.Slot.CLOTHES, "rare", ElementTable.Element.FIRE)
		var grim := EquipmentItem.load_item("novice_grimoire")
		print("[equipment] %d Magewar templates, %d potions; seed 19 %s: health %.1f, mana %.1f, resist %.0f %%; %s +%.0f mana +%.1f/s" % [
			EquipmentItem.list_ids().size(), ConsumableItem.list_ids().size(), robes.display_name, robes.health_bonus, robes.mana_bonus,
			robes.elemental_resistance * 100.0, grim.display_name, grim.mana_bonus, grim.mana_regen_bonus])
		var code := ItemCodes.encode(built)
		var back := ItemCodes.decode(code)
		print("[codes] %s -> %s (%s, dmg %.1f); robes %s; 3 mana potions %s" % [built.display_name(), code,
			(back.item as WieldableInstance).display_name() if back.ok() else back.error,
			(back.item as WieldableInstance).damage() if back.ok() else 0.0, ItemCodes.encode(robes),
			ItemCodes.encode(ConsumableItem.load_item("mana_potion"), 3)])
		print("[main] level %s, %d boxes, player at %s, eye %s" % [
			$Level.get_meta("level_id", "?"), $Level.get_node("Boxes").get_child_count(),
			player.global_position, player.camera.global_position])

## Step 39: replaces the scene's Level (the Midden) with the GameFlow level before anything
## reads it (spawn point, navmesh, waves).
func _swap_level(id: String) -> void:
	var old := get_node_or_null("Level")
	if old and GameFlow.id_of(old) == id:
		return
	var lv := (load(GameFlow.level_scene(id)) as PackedScene).instantiate()
	if old:
		remove_child(old)
		old.free()
	lv.name = "Level"
	add_child(lv)
	move_child(lv, 0)
	QualityPresets.apply_level(lv)  # step 134

## Step 39: Breach logic, the travel gate, the pause menu (+ its settings screen), and the
## save load when the flow asks for it.
func _setup_flow(player: Player) -> void:
	var here := GameFlow.id_of($Level)
	if here == "breach":
		breach = Breach.new()
		breach.name = "Breach"
		add_child(breach)
		breach.setup($Level, player)
		breach.chest.dropper = get_node_or_null("LootDropper") as LootDropper   # vault loot lands as pickups
	_setup_exits(player, here)
	_setup_npcs(player)
	ZoneChests.setup(self, $Level, here, player, story_flags, get_node_or_null("LootDropper") as LootDropper)  # step 158
	EmberArt.dress($Level, here)  # step 163: decals, skyline, landmark art slots
	var s_ui := SettingsUi.new()
	s_ui.name = "SettingsUi"
	s_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(s_ui)
	s_ui.setup(settings, player)
	pause_menu = PauseMenu.new()
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)
	pause_menu.bind(player, s_ui)
	pause_menu.save_requested.connect(save_game)
	var fresh := not GameFlow.load_save
	var saved_progress := {}
	if Coop.is_client():
		# Step 91: a client plays its own portable character, never the host's slot.
		var cr := CharacterSave.load_into(player, Coop.character)
		fresh = cr.has("error")
		print("[character] %s: %s" % [Coop.character, cr.get("error", "loaded level %d" % player.progression.level)])
	elif GameFlow.load_save:
		var r := SaveGame.read(GameFlow.save_path)
		if r.has("error"):
			push_warning("[save] " + String(r["error"]))
		else:
			load_warnings = SaveGame.apply(player, r["data"])
			saved_progress = (r["data"] as Dictionary).get("progress", {})
			story_flags.from_dict((r["data"] as Dictionary).get("progress", {}).get("flags", {}))
			_loaded_quests = (r["data"] as Dictionary).get("progress", {}).get("quests", {})
			if breach and (r["data"] as Dictionary).get("progress", {}).get("vault_open", false):
				breach.restore_open()   # step 47: rooms cleared, gate + vault stay open
			print("[save] loaded %s (level %d, %d warning(s))" % [GameFlow.save_path, player.progression.level, load_warnings.size()])
	_spawn_at_anchor(player, saved_progress)
	if fresh:
		_apply_new_identity(player)
		if not Coop.is_client():
			_start_intro(player)
	if IntroDirector.active(story_flags):
		intro = IntroDirector.new()
		add_child(intro)
		intro.setup(self, player, story_flags, here)
	_setup_quests(player, here)
	if here == "old_oak":
		_setup_hub(player)
	_setup_fast_travel(player, here)
	for g in get_tree().get_nodes_in_group(FlagGate.GROUP):  # step 156: intro soft-blocks
		if is_ancestor_of(g):
			(g as FlagGate).bind(story_flags)
	if story_flags.has("rusty_dagger"):
		add_child(DaggerGlow.make(player))  # step 113
	print("[flow] level %s, gate to %s" % [here, gate.target])
	Screenshots.attach(self, here)   # step 41: --shots <dir>
	if OS.get_cmdline_user_args().has("--autoplay"):   # step 40
		var bot := PlaytestBot.new()
		bot.name = "PlaytestBot"
		add_child(bot)
		bot.setup(self, player)

## Step 65: a LevelGate per level [[exit]]; levels without exits keep the step 39 gate
## (Midden <-> Breach), and the Midden (the Landfill) also gets the gate back to town.
func _setup_exits(player: Player, here: String) -> void:
	var exits := $Level.get_node_or_null("Exits")
	var spots: Array = []
	if exits and exits.get_child_count() > 0:
		for m in exits.get_children():
			spots.append([String(m.get_meta("to", "midden")), (m as Node3D).global_position])
	else:
		spots.append(["midden" if here == "breach" else "breach", player.spawn_feet + Vector3(-3.0, 0.0, -1.0)])
		if here == "midden":
			spots.append(["town_square", player.spawn_feet + Vector3(3.0, 0.0, -1.0)])
	for i in spots.size():
		var g := LevelGate.new(spots[i][0])
		g.name = "Gate" if i == 0 else "Gate%d" % (i + 1)
		g.player = player
		add_child(g)
		g.global_position = spots[i][1]
		g.used.connect(travel)
		g.blocked.connect(_on_gate_blocked)  # step 111
		gates.append(g)
	gate = gates[0]

func _on_gate_blocked(text: String) -> void:
	var hud := get_node_or_null("Hud")
	if hud:
		hud.show_hint(text)

## Step 65: level [[npc]]s become talkable Npcs wired to one DialogueRunner + DialogueUI.
func _setup_npcs(player: Player) -> void:
	var holder := $Level.get_node_or_null("NPCs")
	if holder == null or holder.get_child_count() == 0:
		return
	_ensure_dialogue()
	for m in holder.get_children():
		var n := Npc.new(String(m.get_meta("speaker", "")))
		n.name = "Npc_" + String(m.name)
		n.player = player
		add_child(n)
		n.global_transform = (m as Node3D).global_transform
		n.talked.connect(_on_npc_talked)
		npcs.append(n)

## Step 61: vendors talk first; their shop opens when that dialogue ends.
func _on_npc_talked(speaker: String) -> void:
	shop_pending = speaker if Vendor.for_speaker(speaker) else ""
	if not talk_to(speaker) and shop_pending != "":
		open_shop(shop_pending)
		shop_pending = ""

func _on_dialogue_ended(_id: String) -> void:
	if shop_pending != "":
		var s := shop_pending
		shop_pending = ""
		open_shop(s)

## Step 61: one Vendor per speaker for this visit; the shop screen is made on first use.
func open_shop(speaker: String) -> bool:
	var player := get_node_or_null("Player") as Player
	if player == null:
		return false
	if not vendors.has(speaker):
		vendors[speaker] = Vendor.for_speaker(speaker)
	if vendor_ui == null:
		vendor_ui = VendorUi.new()
		vendor_ui.name = "VendorUi"
		add_child(vendor_ui)
		vendor_ui.bind(player)
	vendor_ui.open(vendors[speaker])
	return true

func _ensure_dialogue() -> void:
	if dialogue:
		return
	dialogue = DialogueRunner.new(DialogueDB.load_default(), story_flags)
	dialogue.ended.connect(_on_dialogue_ended)
	dialogue_ui = DialogueUI.new()
	var layer := CanvasLayer.new()
	layer.name = "DialogueLayer"
	add_child(layer)
	layer.add_child(dialogue_ui)
	dialogue_ui.bind(dialogue)

## Step 66: the Old Oak hub - the shared stash, and Bob's first-night arrival (once).
func _setup_hub(player: Player) -> void:
	stash = Stash.load_shared()
	_ensure_dialogue()
	if intro == null:  # step 113: the intro plays Bob's night itself (after the moss bed)
		mentor_played = MentorArrival.play(story_flags, player, dialogue, self, player.spawn_feet + Vector3(0, 0, -3))
	if story_flags.has(MentorArrival.FLAG):  # step 67: Bob stays in the Oak to report back to
		spawn_bob(player)


func spawn_bob(player: Player) -> Npc:
	var bob := get_node_or_null("Npc_Bob") as Npc
	if bob:
		return bob
	bob = Npc.new("Bob")
	bob.name = "Npc_Bob"
	bob.player = player
	add_child(bob)
	bob.global_position = player.spawn_feet + Vector3(1.5, 0, -3)
	bob.talked.connect(talk_to)
	npcs.append(bob)
	return bob

## Step 68: this level's waystone (if it has a point) + the crystal's map screen.
func _setup_fast_travel(player: Player, here: String) -> void:
	fast_travel = FastTravel.new(story_flags)
	fast_travel.traveled.connect(_on_fast_travel)
	var layer := CanvasLayer.new()
	layer.name = "TravelLayer"
	add_child(layer)
	travel_ui = FastTravelUI.new()
	layer.add_child(travel_ui)
	travel_ui.closed.connect(_on_map_closed)
	world_map = WorldMap.new(story_flags)  # step 69: the Elyria map beside the crystal's
	world_map.visit_level(here)
	world_map_ui = WorldMapUI.new()
	layer.add_child(world_map_ui)
	var point := String(FastTravel.LEVEL_POINT.get(here, ""))
	if point.is_empty():
		return
	waystone = Waystone.new(point, fast_travel)
	waystone.name = "Waystone"
	waystone.player = player
	add_child(waystone)
	var marker := get_node_or_null("Level/Waystones/" + point) as Node3D  # step 155
	var start := get_node_or_null("Level/PlayerStart") as Node3D
	var base := start.global_position if start else player.spawn_feet
	waystone.global_position = marker.global_position if marker else base + Vector3(0.0, 0.0, -2.5)
	waystone.opened.connect(open_map)
	var holder := get_node_or_null("Level/Waystones")  # step 158: a zone's extra waystones
	for m in holder.get_children() if holder else []:
		var p := String(m.name)
		if p != point and String(FastTravel.POINTS.get(p, {}).get("level", "")) == here:
			var w := Waystone.new(p, fast_travel)
			w.name = "Waystone_" + p
			w.player = player
			add_child(w)
			w.global_position = (m as Node3D).global_position
			w.opened.connect(open_map)

func open_map(point := "") -> void:
	if IntroDirector.refuse(self, "map"):  # step 112: dormant until Bob's crystal
		return
	var player := get_node_or_null("Player") as Player
	if player:
		player.ui_open = true
	travel_ui.show_map(fast_travel, point)
	world_map_ui.show_map(world_map)

func _on_map_closed() -> void:
	world_map_ui.visible = false
	var player := get_node_or_null("Player") as Player
	if player:
		player.ui_open = false

func _on_fast_travel(point: String, level: String) -> void:
	travel(level, point)

## Step 155: a save's anchor (or the co-op host's waystone) instead of PlayerStart.
func _spawn_at_anchor(player: Player, saved: Dictionary) -> void:
	var forced := GameFlow.spawn_anchor
	GameFlow.spawn_anchor = ""
	var n := MapAnchors.spawn_node($Level, saved, IntroDirector.beat(story_flags), forced)
	if n:
		player.spawn(n.global_position, deg_to_rad(float(n.get_meta("yaw_deg", 0.0))))
		print("[spawn] at anchor %s" % n.name)

## Step 71: skill respec is only offered at the Old Oak; step 59: it costs Player.respec_price() gold.
func can_respec() -> bool:
	return GameFlow.id_of($Level) == "old_oak"

func respec_skills() -> int:
	var player := get_node_or_null("Player") as Player
	if player == null or not can_respec():
		return -1
	return player.respec_skills()

func talk_to(speaker: String) -> bool:
	var ok := dialogue != null and not dialogue.active and dialogue.start(speaker)
	if ok and quest_driver:
		quest_driver.talked(speaker)  # step 67
	return ok


## Step 67: the quest log (loaded from the save), its driver and the on-screen tracker;
## entering this level counts as "reach".
func _setup_quests(player: Player, here: String) -> void:
	quests = QuestLog.create(story_flags)
	quests.player = player
	if not _loaded_quests.is_empty():
		quests.from_dict(_loaded_quests)
	quests.check_auto_start()
	quest_driver = QuestDriver.make(quests)
	add_child(quest_driver)
	var layer := CanvasLayer.new()
	layer.name = "QuestLayer"
	add_child(layer)
	quest_ui = QuestTrackerUI.new()
	layer.add_child(quest_ui)
	quest_ui.bind(quests)
	quest_driver.reached(here)

## Step 79: the host simulates; clients mirror its enemies and send their hits.
## Step 57: The Filth's wave moves the player's respawn point to the boss door.
func _on_wave_started(_i: int, id: String) -> void:
	var p := get_node_or_null("Player") as Player
	if p != null and is_instance_valid(_boss_spawner):
		Filth.checkpoint(p, id, _boss_spawner.trigger_center)


func _setup_coop(player: Player, spawner: EnemySpawner) -> void:
	coop = CoopWorld.new()
	coop.name = "CoopWorld"
	add_child(coop)
	coop.setup(Coop.session, player, spawner, spawner.table)
	var frames := PartyFrames.new()  # step 80
	frames.name = "PartyFrames"
	add_child(frames)
	frames.bind(coop)
	Coop.session.message.connect(_on_coop_message)
	var sync := IntroSync.new()  # step 117: host-authoritative intro beats
	add_child(sync)
	sync.setup(Coop.session, story_flags, player, coop.host)
	if coop.host:
		sync.push()
	if not Coop.session.ended.is_connected(_on_coop_ended):
		Coop.session.ended.connect(_on_coop_ended)
	print("[coop] %s, %d player(s)" % ["hosting" if coop.host else "joined", Coop.session.roster.size()])


## Step 91: the host's travel moves everyone; clients follow with their character.
func _on_coop_message(_from: int, kind: String, data: Dictionary) -> void:
	if kind == "travel" and Coop.is_client():
		save_game()
		GameFlow.travel(get_tree(), String(data.get("to", "midden")))


func _on_coop_ended(reason: String) -> void:
	print("[coop] session ended: %s" % reason)
	if coop and not coop.host:
		save_game()  # step 91: the client keeps its character
	Coop.end(reason)
	GameFlow.to_menu(get_tree())


func progress() -> Dictionary:
	var player := get_node_or_null("Player") as Node3D
	return {"level_id": GameFlow.id_of($Level), "vault_open": breach.open if breach else false,
		"anchor": MapAnchors.nearest($Level, player.global_position) if player else "",
		"map_version": MapAnchors.version_of($Level),
		"flags": story_flags.to_dict(), "quests": quests.to_dict() if quests else {}}

func save_game() -> Error:
	var player := get_node_or_null("Player") as Player
	if player == null:
		return ERR_UNAVAILABLE
	if Cinematic.playing:  # step 110: never mid-cinematic
		print("[save] not during a cinematic")
		return ERR_BUSY
	if coop and not coop.host:
		var cerr := CharacterSave.write(player, Coop.character, story_flags.has(IntroDirector.DONE))  # step 91: never the host slot
		print("[save] character %s: %s" % [Coop.character, error_string(cerr)])
		return cerr
	if stash:
		stash.save()
	var err := SaveGame.write(SaveGame.capture(player, progress()), GameFlow.save_path)
	print("[save] wrote %s: %s" % [GameFlow.save_path, error_string(err)])
	return err

## Autosave, then load `to` with the saved state.
func travel(to: String, anchor := "") -> void:
	if coop and not coop.host:
		print("[coop] only the host can travel")  # step 91: the host's world decides
		return
	if coop:
		Coop.session.send("travel", {"to": to})
	var player := get_node_or_null("Player") as Player
	if player:
		var d := SaveGame.capture(player, progress())
		d["progress"]["level_id"] = to
		d["progress"]["anchor"] = anchor  # step 155: "" = the new level's PlayerStart
		d["progress"].erase("map_version")
		SaveGame.write(d, GameFlow.save_path)
	GameFlow.travel(get_tree(), to)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and pause_menu:
		save_game()

func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	if _seconds > 0.0 and _elapsed >= _seconds:
		print("[main] %d frames, %d physics ticks in %.2f s" % [_frames, _ticks, _elapsed])
		var player := get_node_or_null("Player") as Player
		if player:
			print("[player] feet %s, Breath %.1f/%.0f, %d jump(s), %d slide(s), %d dash(es)" % [
				player.global_position, player.breath.value, player.breath.max_value(),
				player.jumps, player.slides, player.dash.dashes])
			var bolts := player.bolts
			print("[cast] %s, %d cast(s), %d bolt(s) hit, %d fizzled, mana %.1f/%.0f, %d refused" % [
				player.caster.wieldable.display_name() if player.caster.wieldable else "empty hands",
				player.caster.casts, bolts.hits if bolts else 0, bolts.fizzled if bolts else 0,
				player.mana.value, player.mana.max_value(), player.caster.mana_refused])
			print("[focus] fov %.1f, accuracy %.0f %%, hip cone %.2f deg, bloom %.2f deg" % [
				player.focus.fov, player.accuracy(),
				player.spread.cone_deg(player.accuracy(), player.spread_stance()), player.spread.bloom])
			var hp := player.health
			print("[health] health %.1f/%.0f, shield %.1f/%.0f, %d hit(s) taken, %d ignored, %d death(s), %d respawn(s)" % [
				hp.value, hp.max_value(), hp.shield, hp.shield_max, player.hits_taken, player.hits_ignored,
				player.deaths, player.respawns])
			var alive := 0
			for e in get_tree().get_nodes_in_group(Enemy.GROUP):
				alive += 1
			var dn := get_node_or_null("DamageNumbers") as DamageNumbers
			print("[enemies] %d alive, %d damage number(s) shown" % [alive, dn.spawned if dn else 0])
			for g in get_tree().get_nodes_in_group(Enemy.GROUP):
				if g is Gnawer:
					var gn := g as Gnawer
					print("[%s] %s %s at %.1f m, %d bite(s), %d dodged, %d transition(s), travelled %.1f m" % [
						"heap" if gn is Heap else "gnawer", gn.name, Gnawer.state_name(gn.state), gn.distance, gn.bites, gn.dodged,
						gn.transitions.size(), gn.travelled])
			var sp := get_node_or_null("Enemies") as EnemySpawner
			if sp:
				print("[waves] state %s, wave %d/%d, %d spawned, %d kill(s), %d freed, %d respawn(s); bus %d kill(s), %d player hit(s)" % [
					EnemySpawner.WaveState.keys()[sp.wave_state], sp.wave_index + 1, sp.waves.size(), sp.spawned,
					sp.kills, sp.freed, sp.respawns, GameEvents.bus().kills, GameEvents.bus().player_hits])
			var lo := player.loadout
			print("[loadout] in hand %s, staff %s, wand %s, %d swap(s), viewmodel %s at %s, overlay %s" % [
				"wand" if lo.active == Loadout.Slot.WAND else "staff",
				lo.wieldable(Loadout.Slot.STAFF).display_name() if lo.wieldable(Loadout.Slot.STAFF) else "empty",
				lo.wieldable(Loadout.Slot.WAND).display_name() if lo.wieldable(Loadout.Slot.WAND) else "empty",
				lo.swaps, "shown" if player.viewmodel.visible else "hidden",
				player.viewmodel.model.position,
				"on" if player.viewmodel.render_viewport else "off (headless)"])
		if coop:
			print("[coop] %s: %d snapshot(s) sent, %d seen, %d puppet(s), %d remote player(s), %d hit(s) sent, %d applied, %d hurt sent, %d taken, poses %d/%d" % [
				"host" if coop.host else "client", coop.snaps_sent, coop.snaps_seen, coop.puppets.size(), coop.proxies.size(),
				coop.hits_sent, coop.hits_applied, coop.hurts_sent, coop.hurts_taken, coop.poses_sent, coop.poses_seen])
		get_tree().quit(0)

func _physics_process(_delta: float) -> void:
	_ticks += 1


## Step 73: a new character takes the menu's archetype / name / colour (or --archetype ...).
## Step 109: a New Game runs the intro (Bob hands over the staff later) or skips to its end state.
func _start_intro(player: Player) -> void:
	var mode := GameFlow.intro_mode
	GameFlow.intro_mode = ""
	if mode == GameFlow.INTRO_PLAY:
		IntroDirector.start(story_flags)
		IntroDirector.strip_weapons(player)
		player.inventory.gold = 0  # step 111: the Clerk hands over the 50 gold grant
	elif mode == GameFlow.INTRO_SKIP:
		IntroDirector.apply_skip(story_flags, player)

func _apply_new_identity(player: Player) -> void:
	var idn := GameFlow.new_identity.duplicate()
	idn.merge(GameFlow.identity_from_args(OS.get_cmdline_user_args()), true)
	if idn.is_empty():
		return
	var arch := String(idn.get("archetype", Archetype.DEFAULT))
	var nm := String(idn.get("name", ""))
	if nm.is_empty() and Coop.is_client():
		nm = Coop.character.get_file().get_basename().trim_prefix("character_")
	player.set_character(arch, nm, idn.get("color", null))
	print("[character] %s the %s" % [player.character_name, Archetype.label(player.archetype)])
