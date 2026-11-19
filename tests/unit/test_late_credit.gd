extends TestCase
## A co-op hit that arrives after the death pays loot and XP once. It does not kill again.


func test_protocol_bumps_for_credit() -> void:
	check(NetSession.PROTOCOL == 7, "protocol 7")
	check(NetSession.version().ends_with("/p7"), "a p6 peer cannot join")


func test_death_then_credit_does_not_double_loot() -> void:
	var table := EnemyTable.load_default()
	var def := table.find("gnawer")
	var holder := Node3D.new()
	runner_tree.root.add_child(holder)
	var dropper := LootDropper.new()
	dropper.rng = LootDropper.make_peer_rng("late", 2)
	dropper.gold_rng = LootDropper.make_peer_rng("late:gold", 2)
	holder.add_child(dropper)
	var e := Enemy.new()
	e.setup(def)
	e.set_meta(&"net_id", 7)
	holder.add_child(e)
	e.confirm_kill(def.affinity)
	var first := dropper.spawned + dropper.gold_spawned
	check(first > 0, "the death rolled loot")
	check(not dropper.pay_corpse(7, def, e.global_position, e.level()), "same corpse is refused")
	check(dropper.spawned + dropper.gold_spawned == first, "no second pile")
	check(dropper.pay_corpse(8, def, Vector3(4, 0, 0), 1), "a different corpse still pays")
	holder.free()


func test_credit_xp_is_once() -> void:
	var table := EnemyTable.load_default()
	var def := table.find("gnawer")
	var holder := Node3D.new()
	runner_tree.root.add_child(holder)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	holder.add_child(p)
	var xp := XpRewarder.new()
	holder.add_child(xp)
	var before := p.progression.total_xp
	check(xp.pay_corpse(3, def), "the late hit pays")
	check(p.progression.total_xp > before, "XP moved")
	var mid := p.progression.total_xp
	check(not xp.pay_corpse(3, def), "the same corpse does not pay again")
	check(p.progression.total_xp == mid, "XP stayed")
	holder.free()
