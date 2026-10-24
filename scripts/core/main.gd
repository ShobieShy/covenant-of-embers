extends Node3D
## Entry scene. `--seconds N` (after `--`) quits after N seconds and reports
## frames and physics ticks, the Godot counterpart of the old `covenant --seconds`.

var _seconds := -1.0
var _elapsed := 0.0
var _frames := 0
var _ticks := 0
var settings: Settings   # step 32
var pause_menu: PauseMenu   # step 39
var breach: Breach          # step 39: the Breach room logic when the Breach is loaded
var gate: LevelGate         # step 39: travel gate (Midden -> Breach -> back)
var gates: Array[LevelGate] = []  # step 65: every travel gate here (level [[exit]]s, or the defaults)
var npcs: Array[Npc] = []  # step 65: level [[npc]]s
var story_flags := StoryFlags.new()
var dialogue: DialogueRunner
var dialogue_ui: DialogueUI
var load_warnings := PackedStringArray()

func _ready() -> void:
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
		var audio := GameAudio.new()   # step 37: Kenney SFX on the SFX/UI buses
		audio.name = "GameAudio"
		add_child(audio)
		audio.bind(player)
		var inv_ui := InventoryUi.new()   # step 30: Tab
		inv_ui.name = "InventoryUi"
		add_child(inv_ui)
		inv_ui.bind(player)
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
		print("[enemies] %d spawned (%s), %d skipped (%s)" % [spawned.size(),
			", ".join(spawned.map(func(e: Enemy) -> String: return e.def.id)), skipped.size(), ", ".join(skipped)])
		var nav := $Level.get_node_or_null("Navigation") as LevelNavigation
		print("[nav] %s navmesh: %d polygon(s), %d bake(s)" % [$Level.name,
			nav.navigation_mesh.get_polygon_count() if nav and nav.navigation_mesh else 0, nav.bakes if nav else 0])
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

## Step 39: Breach logic, the travel gate, the pause menu (+ its settings screen), and the
## save load when the flow asks for it.
func _setup_flow(player: Player) -> void:
	var here := GameFlow.id_of($Level)
	if here == "breach":
		breach = Breach.new()
		breach.name = "Breach"
		add_child(breach)
		breach.setup($Level)
		breach.chest.dropper = get_node_or_null("LootDropper") as LootDropper   # vault loot lands as pickups
	_setup_exits(player, here)
	_setup_npcs(player)
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
	if GameFlow.load_save:
		var r := SaveGame.read(GameFlow.save_path)
		if r.has("error"):
			push_warning("[save] " + String(r["error"]))
		else:
			load_warnings = SaveGame.apply(player, r["data"])
			print("[save] loaded %s (level %d, %d warning(s))" % [GameFlow.save_path, player.progression.level, load_warnings.size()])
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
		gates.append(g)
	gate = gates[0]

## Step 65: level [[npc]]s become talkable Npcs wired to one DialogueRunner + DialogueUI.
func _setup_npcs(player: Player) -> void:
	var holder := $Level.get_node_or_null("NPCs")
	if holder == null or holder.get_child_count() == 0:
		return
	dialogue = DialogueRunner.new(DialogueDB.load_default(), story_flags)
	dialogue_ui = DialogueUI.new()
	var layer := CanvasLayer.new()
	layer.name = "DialogueLayer"
	add_child(layer)
	layer.add_child(dialogue_ui)
	dialogue_ui.bind(dialogue)
	for m in holder.get_children():
		var n := Npc.new(String(m.get_meta("speaker", "")))
		n.name = "Npc_" + String(m.name)
		n.player = player
		add_child(n)
		n.global_transform = (m as Node3D).global_transform
		n.talked.connect(talk_to)
		npcs.append(n)

func talk_to(speaker: String) -> bool:
	return dialogue != null and not dialogue.active and dialogue.start(speaker)

func progress() -> Dictionary:
	return {"level_id": GameFlow.id_of($Level), "vault_open": breach.open if breach else false}

func save_game() -> Error:
	var player := get_node_or_null("Player") as Player
	if player == null:
		return ERR_UNAVAILABLE
	var err := SaveGame.write(SaveGame.capture(player, progress()), GameFlow.save_path)
	print("[save] wrote %s: %s" % [GameFlow.save_path, error_string(err)])
	return err

## Autosave, then load `to` with the saved state.
func travel(to: String) -> void:
	var player := get_node_or_null("Player") as Player
	if player:
		var d := SaveGame.capture(player, progress())
		d["progress"]["level_id"] = to
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
		get_tree().quit(0)

func _physics_process(_delta: float) -> void:
	_ticks += 1
