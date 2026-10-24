extends TestCase
## Step 59 done check: gold (Q4: Magewar gold, start 50). Kills drop gold that auto-collects,
## salvage pays gold + Dust, the Old Oak respec costs gold, and gold survives a save.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const E := ElementTable.Element

var _w: Node3D


func _world() -> Node3D:
	_w = Node3D.new()
	_w.position = Vector3(7000, 0, 7000)  # away from other tests' pickups
	runner_tree.root.add_child(_w)
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(100, 1, 100)
	cs.shape = s
	b.add_child(cs)
	b.position = Vector3(0, -0.5, 0)
	_w.add_child(b)
	return _w


func _player(w: Node3D) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return p


func test_start_and_wallet() -> void:
	var inv := Inventory.new()
	check(inv.gold == 50, "start with 50 gold")
	check(not inv.spend_gold(51) and inv.gold == 50, "can't overspend")
	check(inv.spend_gold(20) and inv.gold == 30, "spend")
	inv.add_gold(-5)
	check(inv.gold == 30, "negative add ignored")


func test_gold_amounts() -> void:
	var t := EnemyTable.load_default()
	var r := LootDropper.make_peer_rng("g", 1)
	var gn := t.find("gnawer")
	for i in 50:
		var g := LootDropper.gold_for(gn, r)
		check(g >= 1 and g <= ceili(gn.gold_base() * 1.25), "gnawer gold in range: %d" % g)
	check(t.find("the_filth").gold_base() == 120, "The Filth pays 120 base")
	var d := EnemyDef.new()
	d.gold_drop = 0
	check(LootDropper.gold_for(d, r) == 0, "0 stays 0")


func test_kill_drops_gold_that_auto_collects() -> void:
	var w := _world()
	var p := _player(w)
	p.tick(PlayerInput.hold([]), DT)
	var dr := LootDropper.new()
	dr.seed_base = "test_gold"
	w.add_child(dr)
	var ahead := p.forward_for(0.0)
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"), Transform3D(Basis(), p.position + ahead * 2.5))
	w.add_child(e)
	e.apply_damage(100000.0, E.FIRE)
	var coins: Array = w.get_children().filter(
		func(n: Node) -> bool: return n is LootPickup and (n as LootPickup).auto == LootPickup.Auto.GOLD
	)
	check(coins.size() == 1 and dr.gold_spawned == 1, "one gold pickup")
	var amount: int = (coins[0] as LootPickup).amount if coins.size() == 1 else 0
	for i in 90:
		p.tick(PlayerInput.hold([&"forward"]), DT)
		await runner_tree.physics_frame
	check(p.inventory.gold == 50 + amount, "walked over: %d gold (+%d)" % [p.inventory.gold, amount])
	_w.queue_free()


func test_salvage_pays_gold() -> void:
	var inv := Inventory.new()
	var part := WieldablePart.new()
	part.rarity = "rare"
	inv.add(part)
	var v := CraftingExtras.salvage_value(part)
	check(CraftingExtras.salvage(inv, part) == "", "salvaged")
	check(inv.dust == v and inv.gold == 50 + 2 * v, "dust %d + gold %d" % [inv.dust, inv.gold])


func test_respec_price_and_save() -> void:
	var w := _world()
	var p := _player(w)
	check(p.respec_price() == 0, "nothing spent: free")
	p.add_xp(5000)
	var sid := ""
	for id in p.skills.tree.skills:
		if p.spend_skill(String(id)):
			sid = String(id)
			break
	check(sid != "", "spent a point")
	check(p.respec_price() == 25, "first respec 25 gold")
	p.inventory.gold = 10
	check(p.respec_skills() == -1 and p.skills.spent() == 1, "can't afford: nothing refunded")
	p.inventory.gold = 60
	check(p.respec_skills() == 1 and p.inventory.gold == 35, "paid 25")
	p.spend_skill(sid)
	check(p.respec_price() == 50, "second respec 50")
	p.inventory.gold = 1234
	var d := SaveGame.capture(p, {})
	var q := _player(w)
	SaveGame.apply(q, d)
	check(q.inventory.gold == 1234, "gold saved: %d" % q.inventory.gold)
	var old := d.duplicate(true)
	(old["player"] as Dictionary).erase("gold")
	SaveGame.apply(q, old)
	check(q.inventory.gold == 50, "old saves start at 50")
	_w.queue_free()
