extends TestCase
## L4: Act I loot (ActLoot): floor item levels, the goblin pools in drop_pools.tres, party
## drop-chance scaling, Act-tagged enemies and the King's first-clear chest.


class StubMain:
	extends "res://scripts/core/main.gd"

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)


func test_floor_bands() -> void:
	check(ActLoot.act_of(1) == 1, "floor 1 is Act I")
	check(ActLoot.act_of(9) == 0, "floor 9 has no Act yet")
	check(ActLoot.item_level(1) == 5, "floor 1 level 5")
	check(ActLoot.item_level(5) == 12, "King floor level 12")
	check(ActLoot.item_level(4) > ActLoot.item_level(2), "levels rise with depth")
	check(ActLoot.boss_rarity(5, true) == "unique", "first clear Unique")
	check(ActLoot.boss_rarity(5, false) == "rare", "repeat Rare")


func test_pools_validate_and_match_goblins() -> void:
	var dt := DropRoller.default_pools()
	check(dt.validate().is_empty(), "drop_pools valid: %s" % str(dt.validate()))
	for id in ["goblin_grunt", "goblin_archer", "goblin_shaman"]:
		var p := dt.pool_for(id, 7)
		check(p != null and p.id == "act1_goblins", "%s -> act1_goblins" % id)
	var k := dt.pool_for("goblin_king", 12)
	check(k != null and k.drop_chance >= 1.0, "the King always drops from its pool")
	check(dt.pool_for("gnawer", 3).id == "midden_gnawer", "old pools unchanged")


func test_party_chance() -> void:
	check(ActLoot.party_chance(0.2, 1) == 0.2, "solo unchanged")
	check(is_equal_approx(ActLoot.party_chance(0.2, 3), 0.3), "+25 % per extra player")
	check(ActLoot.party_chance(0.9, 4) == 1.0, "capped at 1")
	var hits := [0, 0]
	for i in 2:
		var r := RandomNumberGenerator.new()
		r.seed = 99
		for k in 400:
			var pool_drops := 0
			for d in DropRoller.roll_kill(r, "goblin_grunt", 5, -1, 0.0, null, null, 1 + i * 3):
				if d.kind == LootDrop.Kind.WIELDABLE:
					pool_drops += 1
			hits[i] += pool_drops
	check(hits[1] > hits[0], "a party of 4 gets more pool drops (%d > %d)" % [hits[1], hits[0]])


func test_tagged_enemies_and_boss_chest() -> void:
	var m := StubMain.new()
	m.labyrinth = LabyrinthState.fresh(7)
	m.position = Vector3(0, 900, -4200)
	runner_tree.root.add_child(m)
	var fl := LabyrinthFloor.build(FloorGen.load_kit(), 3, m.labyrinth)
	m.add_child(fl)
	m._lab_enemies(fl, null)
	var es := m.get_node("LabyrinthEnemies").find_children("*", "Enemy", true, false)
	check(not es.is_empty(), "floor 3 spawned")
	var e := es[0] as Enemy
	check(e.level() == ActLoot.item_level(3), "enemy drops at the floor level")
	check(e.has_meta(&"act_element"), "Act-tagged")
	m._on_lab_kill(e, ElementTable.Element.EARTH, fl, "", "goblin_king", {})
	var c := fl.get_node_or_null("BossChest") as VaultChest
	check(
		c != null and not c.locked and c.floor_rarity == "unique", "first clear: open Unique chest"
	)
	c.name = "BossChest_1"
	m._on_lab_kill(e, ElementTable.Element.EARTH, fl, "", "goblin_king", {})
	var c2 := fl.get_node_or_null("BossChest") as VaultChest
	check(c2 != null and c2.floor_rarity == "rare", "repeat clear: Rare chest")
	m.free()
