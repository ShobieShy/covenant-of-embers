extends TestCase
## 0.8.4: Second Wind. A lethal hit puts you down. You can still cast. A kill gets you
## up with a fraction of health. No kill, and the old respawn countdown starts after the
## window. A direct revive (the co-op teammate path) still works.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const E := ElementTable.Element


func _player() -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(0, 40, 2400), 0.0)
	return p


func _floor(p: Player) -> StaticBody3D:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(40, 1, 40)
	cs.shape = s
	b.add_child(cs)
	b.position = p.global_position + Vector3(0, -0.5, 0)
	p.get_parent().add_child(b)
	return b


func test_cast_kill_and_bleed() -> void:
	var p := _player()
	p.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	p.take_enemy_hit(99999.0, E.FIRE)
	check(not p.alive() and p.downed and p.downed_left > 7.0, "solo window is 8 s")
	var casts := p.caster.casts
	p.tick(PlayerInput.hold([&"action_primary"], [&"action_primary"]), DT)
	check(p.caster.casts == casts + 1 and p.downed, "a downed player can still cast")
	var hud := Hud.new()
	runner_tree.root.add_child(hud)
	hud.bind(p)
	hud.refresh(DT)
	check(hud.death_label.text.contains("Second Wind"), "banner: %s" % hud.death_label.text)
	check(is_zero_approx(hud.death_overlay.color.a), "the overlay does not black out the fight")
	check(hud.crosshair.visible, "crosshair stays up")
	var e := Enemy.create(
		EnemyTable.load_default().find("heap"), Transform3D(Basis.IDENTITY, p.global_position + Vector3(3, 0, 0))
	)
	e.auto_tick = false
	p.get_parent().add_child(e)
	e.apply_damage(100000.0, E.FIRE)
	check(p.alive() and not p.downed and p.second_wind_revives == 1, "a kill gets you up")
	check_near(p.health.value, p.health.max_value() * Player.SECOND_WIND_HEALTH, 0.6, "fraction of health")
	check(p.health.shield == 0.0, "no shield yet")
	p.protection_left = 0.0
	p.take_enemy_hit(99999.0, E.FIRE)
	check(p.revive(0.3) and p.alive() and not p.downed, "a teammate revive still works")
	p.protection_left = 0.0
	p.last_stand = 0.4
	p.take_enemy_hit(99999.0, E.FIRE)
	check(p.downed and p.downed_left <= 0.4, "co-op keeps its own window")
	var ticks := 0
	while p.downed and ticks < 60:
		p.tick(PlayerInput.hold(), DT)
		ticks += 1
	check(p.bleed_outs == 1 and not p.alive(), "no kill: bleed out, then the respawn countdown")
	check(p.respawn_left > 0.0, "respawn countdown started")
	e.free()
	hud.free()
	p.free()


func test_crawl_and_no_jump() -> void:
	var p := _player()
	var floor := _floor(p)
	for i in 5:
		p.tick(PlayerInput.hold(), DT)
	p.take_enemy_hit(99999.0, E.FIRE)
	var jumps := p.jumps
	var at := p.global_position
	for i in 40:
		p.tick(PlayerInput.hold([&"forward"], [&"jump"]), DT)
	check(p.jumps == jumps, "no jump while down")
	check(p.global_position.distance_to(at) > 0.4, "a slow crawl (%.2f m)" % p.global_position.distance_to(at))
	check(not p.sprinting and not p.sliding(), "no sprint or slide")
	floor.free()
	p.free()
