extends TestCase
## Step 37 done check: every referenced stream loads, the buses exist, and the hooks fire.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func test_streams_and_buses() -> void:
	for k in GameAudio.SOUNDS:
		check(GameAudio.load_stream(k) != null, "%s loads (%s)" % [k, GameAudio.SOUNDS[k]])
	for b in GameAudio.BUSES:
		check(AudioServer.get_bus_index(b) >= 0, "bus %s" % b)
	GameAudio.apply_volumes(1.0, 0.5, 0.0)
	check(
		absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.01, "sfx volume"
	)
	GameAudio.apply_volumes(1.0, 1.0, 1.0)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))) < 0.01, "music back to 0 dB")


func test_hooks() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 900, 3600)
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	var a := GameAudio.new()
	w.add_child(a)
	a.bind(p)
	p.dash.dashes += 1
	p.landings += 1
	p.last_landing_speed = 6.0
	p.loadout.casters[0].casts += 1
	await runner_tree.physics_frame
	await runner_tree.physics_frame
	for k in ["dash", "land"]:
		check(int(a.played.get(k, 0)) == 1, "%s played once (%s)" % [k, a.played])
	var casts := 0  # P5: the cast plays its element's sound ("cast" with none)
	for k in a.played:
		if String(k) == "cast" or String(k).begins_with("cast_") and String(k) != "cast_fail":
			casts += int(a.played[k])
	check(casts == 1, "cast played once (%s)" % [a.played])
	GameEvents.bus().wave_started.emit(0, "x")
	check(int(a.played.get("wave_start", 0)) == 1, "wave stinger")
	var e := Enemy.create(EnemyTable.load_default().find("heap"), Transform3D(Basis.IDENTITY, Vector3(4, 0, 0)))
	e.auto_tick = false
	w.add_child(e)
	GameEvents.bus().enemy_spawned.emit(e)
	e.apply_damage(1000.0, ElementTable.Element.FIRE)
	check(
		int(a.played.get("enemy_death", 0)) == 1 and int(a.played.get("kill", 0)) >= 1, "death + kill (%s)" % [a.played]
	)
	w.free()
