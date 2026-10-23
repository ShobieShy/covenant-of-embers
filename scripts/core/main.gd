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
		# Step 11: the level's training dummies at its EnemySpawns markers (the Gnawer
		# waits for step 12's AI) and floating damage numbers on every resolved hit.
		var enemies := Node3D.new()
		enemies.name = "Enemies"
		add_child(enemies)
		var skipped: Array = []
		var spawned := Enemy.spawn_at_markers($Level, enemies, EnemyTable.load_default(), skipped)
		var numbers := DamageNumbers.new()
		numbers.name = "DamageNumbers"
		add_child(numbers)
		numbers.connect_bolts(player.bolts)
		print("[enemies] %d spawned (%s), %d skipped (%s)" % [spawned.size(),
			", ".join(spawned.map(func(e: Enemy) -> String: return e.def.id)), skipped.size(), ", ".join(skipped)])
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
			var alive := 0
			for e in get_tree().get_nodes_in_group(Enemy.GROUP):
				alive += 1
			var dn := get_node_or_null("DamageNumbers") as DamageNumbers
			print("[enemies] %d alive, %d damage number(s) shown" % [alive, dn.spawned if dn else 0])
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
