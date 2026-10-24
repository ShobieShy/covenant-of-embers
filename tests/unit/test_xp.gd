extends TestCase
## Step 27 done check: XP curve values and level-up hooks (Magewar add_xp / _level_up).
##  - thresholds 100, 150, 225, 337, 505; overflow carries; one big grant = several levels;
##  - a level-up: Breath 105/105 and Mana 105/105 (from 40 mana), health unchanged;
##  - kills grant the def's xp_reward (Gnawer 5, Heap 15) to players within 80 m;
##    training dummies and far players get nothing.

const E := ElementTable.Element
const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _player(at: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(at, 0.0)
	return p


func test_curve() -> void:
	var expect := [100, 150, 225, 337, 505, 757]
	for i in expect.size():
		check(
			Progression.threshold(i + 1) == expect[i],
			"threshold L%d = %d (%d)" % [i + 1, expect[i], Progression.threshold(i + 1)]
		)
	var pr := Progression.new()
	check(pr.level == 1 and pr.xp == 0 and pr.xp_to_next == 100, "start")
	check(pr.add_xp(99) == 0 and pr.level == 1, "99 XP: still 1")
	check(pr.add_xp(11) == 1 and pr.level == 2 and pr.xp == 10 and pr.xp_to_next == 150, "overflow carries")
	var pr2 := Progression.new()
	check(
		pr2.add_xp(100 + 150 + 225 + 5) == 3 and pr2.level == 4 and pr2.xp == 5 and pr2.xp_to_next == 337, "multi-level"
	)
	check(pr2.add_xp(0) == 0 and pr2.add_xp(-5) == 0 and pr2.total_xp == 480, "no negative XP")


func test_level_up_hooks() -> void:
	var p := _player(Vector3(0, 200, 1200))
	var hp := p.health.max_value()
	p.mana.value = 40.0
	p.breath.value = 30.0
	check(p.add_xp(100) == 1 and p.progression.level == 2, "level 2")
	check_near(p.breath.value, 105.0, 1e-4, "Breath value")
	check_near(p.breath.max_value(), 105.0, 1e-4, "Breath max")
	check_near(p.mana.value, 105.0, 1e-4, "Mana value")
	check_near(p.mana.max_value(), 105.0, 1e-4, "Mana max")
	check_near(p.health.max_value(), hp, 1e-4, "health unchanged (Magewar)")
	p.apply_bonuses()  # re-applying gear keeps the level bonus
	check_near(p.mana.max_value(), 105.0, 1e-4, "level bonus survives apply_bonuses")
	p.queue_free()


func test_kill_xp() -> void:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var near := _player(Vector3(0, 0, 0))
	var far := _player(Vector3(200, 0, 0))
	var xr := XpRewarder.new()
	w.add_child(xr)
	var table := EnemyTable.load_default()
	var gx: int = table.find("gnawer").xp_reward
	var hx: int = table.find("heap").xp_reward
	check(gx == 5 and hx == 15, "Magewar rewards (%d, %d)" % [gx, hx])
	for id in ["gnawer", "heap", "earth_training_dummy"]:
		var e := Enemy.create(table.find(id), Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
		e.process_mode = Node.PROCESS_MODE_DISABLED
		w.add_child(e)
		e.apply_damage(100000.0, E.FIRE)
		e.queue_free()
	check(near.progression.total_xp == 20, "near player got 20 (%d)" % near.progression.total_xp)
	check(far.progression.total_xp == 0, "far player got nothing")
	check(xr.kills_seen == 3 and xr.granted == 20, "rewarder counts")
	near.queue_free()
	far.queue_free()
	w.queue_free()


func test_resolve_catch_up() -> void:
	check(Progression.resolve_multiplier(5, 5) == 1.0, "no gap: no bonus")
	check(Progression.resolve_multiplier(7, 5) == 1.0, "ahead: no bonus")
	check(Progression.resolve_multiplier(4, 5) == 1.25, "1 level behind: +25%")
	check(Progression.resolve_multiplier(3, 5) == 1.5, "2 behind: +50% (shrinks as it closes)")
	check(Progression.resolve_multiplier(1, 20) == 2.0, "capped at +100%")
	check(Progression.threshold(2) == 150, "level curve unchanged")
	await runner_tree.process_frame  # earlier tests' rewarders are gone
	var w := Node3D.new()
	w.position = Vector3(5000, 0, -9000)
	runner_tree.root.add_child(w)
	var lead := _player(w.position)
	var trail := _player(w.position + Vector3(2, 0, 0))
	lead.add_xp(100 + 150 + 225)  # level 4
	check(lead.progression.level == 4, "lead at 4")
	var xr := XpRewarder.new()
	w.add_child(xr)
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D(Basis.IDENTITY, Vector3(5, 0, 0)))
	e.process_mode = Node.PROCESS_MODE_DISABLED
	w.add_child(e)
	var lead_before := lead.progression.total_xp
	e.apply_damage(100000.0, E.FIRE)
	check(lead.progression.total_xp - lead_before == 5, "the leader gets the plain 5")
	check(trail.progression.total_xp == int(5 * 1.75), "trailing 3 levels: +75%% (%d)" % trail.progression.total_xp)
	check(xr.resolve_bonus == int(5 * 1.75) - 5, "bonus counted")
	lead.queue_free()
	trail.queue_free()
	w.queue_free()
