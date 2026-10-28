extends TestCase
## L5: a co-op teammate (RemotePlayer hitbox) in the line of fire no longer soaks bolts. Only
## a Light bolt stops on them (MagicEffects.intercept heals); any other bolt flies through to
## the enemy behind. Found when the host's shots at the Goblin King hit the joiner in melee.

const E := ElementTable.Element


func test_bolts_pass_teammates() -> void:
	var w := Node3D.new()
	w.position = Vector3(-9100, 0, 7000)
	runner_tree.root.add_child(w)
	var bolts := SpellBolts.new()
	bolts.auto_tick = false
	w.add_child(bolts)
	var foe := Enemy.create(
		EnemyTable.load_default().find("gnawer"), Transform3D(Basis(), Vector3(0, 0, -8))
	)
	w.add_child(foe)
	if foe is Gnawer:
		(foe as Gnawer).auto_tick = false
	var rp := RemotePlayer.new()
	w.add_child(rp)
	rp.position = Vector3(0, 0, -4)
	for i in 3:
		await runner_tree.physics_frame
	var space := w.get_world_3d().direct_space_state
	var from := w.global_position + Vector3(0, 0.4, 0)
	var to := w.global_position + Vector3(0, 0.4, -20)
	var s := SpellBolts.Spawn.new()
	s.element = E.FIRE
	var r: Dictionary = bolts._cast(space, s, from, to)
	check(
		not r.is_empty() and r["collider"] == foe,
		"a Fire bolt passes the teammate and hits the enemy"
	)
	s.element = E.LIGHT
	r = bolts._cast(space, s, from, to)
	check(
		not r.is_empty() and MagicEffects.remote_of(r["collider"]) == rp,
		"a Light bolt still stops on the teammate (to heal them)"
	)
	w.queue_free()
	await runner_tree.process_frame
