extends Node3D
## Entry scene. `--seconds N` (after `--`) quits after N seconds and reports
## frames and physics ticks, the Godot counterpart of the old `covenant --seconds`.

var _seconds := -1.0
var _elapsed := 0.0
var _frames := 0
var _ticks := 0

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
