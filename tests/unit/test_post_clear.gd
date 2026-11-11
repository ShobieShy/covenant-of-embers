extends TestCase
## 0.8.8: Vigil tier matches its curves, remix stays off an uncleared floor,
## toys spend gold, bounties pay, the mantle is cosmetic, and barks are lines.


func test_tier_curves_and_gate() -> void:
	PostClear.forgemaw_clear = false
	PostClear.tier = 0
	check(PostClear.set_tier(4) == 0, "Forgemaw gates the dial")
	PostClear.note_clear()
	check(PostClear.set_tier(4) == 4, "tier 4 after the clear")
	var v := PostClear.vigil()
	check(
		is_equal_approx(v.enemy_health_mult() / v._omen_product("enemy_health"), 1.0 + Vigil.HEALTH_PER_TIER * 4),
		"health curve"
	)
	check(
		is_equal_approx(v.enemy_damage_mult() / v._omen_product("enemy_damage"), 1.0 + Vigil.DAMAGE_PER_TIER * 4),
		"damage curve"
	)
	var src := RarityTable.load_default()
	var shifted := v.table_for(src)
	var basic_src := src.find("basic").drop_weight
	var basic_got := shifted.find("basic").drop_weight
	var want := basic_src / (1.0 + Vigil.BASIC_DROP_PER_TIER * 4.0)
	check(is_equal_approx(basic_got, want), "basic weight is the documented curve")
	var lab := LabyrinthState.fresh()
	check(not lab.remix(1), "an uncleared floor does not remix")
	lab.clear_floor(1)
	check(lab.remix(1) and lab.remix_of(1) == 1, "a cleared floor can remix")
	PostClear.tier = 0
	check(is_equal_approx(PostClear.scale_damage(10.0), 10.0), "tier 0 leaves damage alone")
	check(is_equal_approx(PostClear.scale_health(30.0), 30.0), "tier 0 leaves health alone")


func test_toys_bounties_mantle_and_barks() -> void:
	var p := _player()
	p.inventory.gold = 40
	check(HubToys.vend(p) and p.inventory.gold == 32, "vendor spends gold")
	check(HubToys.open_chest(p) and p.inventory.gold == 7, "chest spends gold without a key")
	p.inventory.gold = 20
	p.quest_items.append(HubToys.KEY)
	var gold := p.inventory.gold
	check(
		HubToys.open_chest(p) and p.inventory.gold == gold and not p.quest_items.has(HubToys.KEY), "key opens the chest"
	)
	var before := p.health.max_value()
	Mantle.wear(p)
	check(p.get_node_or_null("Mantle") != null and is_equal_approx(p.health.max_value(), before), "mantle has no stat")
	var board := Bounties.new()
	board.note("gnawer")
	board.note("gnawer")
	check(not board.claim(p, "gnawer"), "short a kill")
	board.note("gnawer")
	var pay := p.inventory.gold
	check(board.claim(p, "gnawer") and p.inventory.gold == pay + 12, "bounty pays")
	check(board.claim(p, "gnawer") == false, "the count was spent")
	board.note("gnawer")
	board.note("gnawer")
	board.note("gnawer")
	check(board.claim(p, "gnawer"), "repeatable")
	var e := Enemy.create(EnemyTable.load_default().find("gnawer"))
	runner_tree.root.add_child(e)
	e.damaged.emit(e, SpellBolts.Hit.new())
	check(String(e.get_meta(&"bark_kind")) == "hurt", "hurt bark")
	e.died.emit(e, ElementTable.Element.FIRE)
	check(String(e.get_meta(&"bark_kind")) == "death", "death bark")
	check(not String(e.get_meta(&"bark")).is_empty(), "the line is text")
	PostClear.tier = 0
	PostClear.forgemaw_clear = false
	p.free()
	e.free()


func _player() -> Player:
	var p: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(Vector3(12000, 0, 12000), 0.0)
	return p
