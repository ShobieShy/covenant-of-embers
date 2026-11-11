extends TestCase
## 0.8.5: boss uniques drop from their boss on repeat kills, named rares roll from
## existing types, and the unique effect fires from the weapon in hand.

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSSES := ["the_filth", "blightmaw_matriarch", "forgemaw"]


func test_boss_uniques_drop_from_that_boss_only() -> void:
	for boss in BOSSES:
		var ids := NamedUniques.ids_for(boss)
		check(ids.size() >= 1 and ids.size() <= 2, "%s has 1-2 uniques (%d)" % [boss, ids.size()])
		var hits := {}
		var rng := RandomNumberGenerator.new()
		for seed in 240:
			rng.seed = seed
			var drops := DropRoller.roll_kill(rng, boss, 10, 0)
			for d in drops:
				if d.item is WieldablePart and NamedUniques.is_named((d.item as WieldablePart).id):
					var pid := (d.item as WieldablePart).id
					check(ids.has(pid), "%s dropped %s" % [boss, pid])
					hits[pid] = int(hits.get(pid, 0)) + 1
		var total := 0
		for id in ids:
			check(int(hits.get(id, 0)) > 0, "%s dropped at least one %s" % [boss, id])
			total += int(hits.get(id, 0))
		check(total > 30 and total < 90, "%s dedicated drops %d/240 (about 22%%)" % [boss, total])
	var rng2 := RandomNumberGenerator.new()
	for seed in 40:
		rng2.seed = seed
		for d in DropRoller.roll_kill(rng2, "gnawer", 3, 0):
			if d.item is WieldablePart:
				check(not NamedUniques.is_named((d.item as WieldablePart).id), "a gnawer kill is not a boss unique")


func test_rare_spawn_roll_and_stat_boost() -> void:
	var table := EnemyTable.load_default()
	var areas := {"midden": 0, "blightcoil": 0, "slagworks": 0}
	for entry in RareSpawns.ENTRIES:
		areas[String(entry["area"])] = int(areas[String(entry["area"])]) + 1
		var base := table.find(String(entry["base"]))
		check(base != null, "%s is a shipped enemy" % entry["base"])
		var named := RareSpawns.decorate(base, 0.0)
		check(named.display_name == String(entry["name"]), named.display_name)
		check(named.id == base.id, "still the same enemy type")
		check(named.max_health > base.max_health * 1.5, "health boost")
		check(String(named.get_meta(&"rare_id")) == String(entry["id"]), "rare id")
		check(String(named.get_meta(&"unique_id")) == String(entry["unique"]), "its unique")
		var plain := RareSpawns.decorate(base, 0.9)
		check(plain.display_name == base.display_name, "a high roll stays ordinary")
		var side := RandomNumberGenerator.new()
		# Sweep seeds until the rare's own unique appears.
		var seen := false
		for s in 80:
			side.seed = s
			if NamedUniques.roll_drop(String(entry["id"]), side.state) == String(entry["unique"]):
				seen = true
				break
		check(seen, "%s can drop %s" % [entry["id"], entry["unique"]])
	for area in areas:
		check(int(areas[area]) >= 1 and int(areas[area]) <= 2, "%s has 1-2 rares" % area)


func test_named_unique_effects_and_card() -> void:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	_hold(p, "forgemaws_tooth")
	p.tick(PlayerInput.new(), 1.0 / 60.0)
	check(is_equal_approx(p.caster.conditional_bonus, 6.0), "Forgemaw's Tooth is +6")
	_hold(p, "rotglass_lens")
	p.health.value = p.health.max_value()
	p.tick(PlayerInput.new(), 1.0 / 60.0)
	check(is_equal_approx(p.caster.conditional_bonus, 0.0), "Rotglass is quiet at full health")
	p.health.value = p.health.max_value() * 0.4
	p.tick(PlayerInput.new(), 1.0 / 60.0)
	check(is_equal_approx(p.caster.conditional_bonus, 8.0), "Rotglass below half health")
	_hold(p, "cinder_of_the_heap")
	p.tick(PlayerInput.new(), 1.0 / 60.0)
	p.health.value = 40.0
	var e := Enemy.create(EnemyTable.load_default().find("heap"))
	e.auto_tick = false
	w.add_child(e)
	e.apply_damage(10000.0, ElementTable.Element.FIRE)
	check(is_equal_approx(p.health.value, 46.0), "Cinder heals 6 on a kill (%s)" % p.health.value)
	var card := CompareCard.for_item(WieldablePart.load_part("slagheart"))
	check(card.color.is_equal_approx(NamedUniques.COLOR), "unique colour on the card")
	check(card.flavor.contains("slag"), card.flavor)
	check(card.to_bbcode().contains("While focused"), "effect line")
	var charm := CompareCard.for_item(WieldablePart.load_part("unique_void_charm"))
	check(charm.color.is_equal_approx(NamedUniques.COLOR), "void charm uses the unique colour")
	check(charm.effect.is_empty(), "void charm keeps its own stats, no extra effect line")
	var plain := CompareCard.for_item(WieldablePart.load_part("basic_handle"))
	check(not plain.color.is_equal_approx(NamedUniques.COLOR), "a basic part stays its tier colour")
	var drop := NamedUniques.make_drop("last_coal")
	check(drop.rarity_color().is_equal_approx(NamedUniques.COLOR), "loot beam colour")
	w.free()


func test_unique_codes_round_trip_without_bumping_old_codes() -> void:
	var part := WieldablePart.load_part("cinder_of_the_heap")
	check(part != null and part.validate().is_empty(), "cinder loads")
	var code := ItemCodes.encode(part)
	var back := ItemCodes.decode(code)
	check(back.ok() and back.version == 2, "named unique encodes as index version 2 (%s)" % back.error)
	check(ItemCodes.same_item(part, back.item), "round trip")
	var charm := WieldablePart.load_part("unique_void_charm")
	var old := ItemCodes.decode(ItemCodes.encode(charm))
	check(old.ok() and old.version == 1, "void charm stays an EM1 / version 1 code")
	check(ItemCodes.same_item(charm, old.item), "void charm still decodes")


func test_elite_name_tag_and_health_bar() -> void:
	var table := EnemyTable.load_default()
	var rare := RareSpawns.decorate(table.find("gnawer"), 0.0)
	var e := Enemy.create(rare)
	var tag := e.get_node_or_null("NameTag") as Label3D
	check(tag != null and tag.text == "The Pit Warden", "named rare has a name tag")
	check(e.get_node_or_null("EliteBar") != null, "named rare has a health bar")
	check(e._body_mat.emission_enabled, "named rare glows")
	e.health = e.max_health() * 0.25
	ElitePresence.sync(e)
	check(is_equal_approx((e.get_node("EliteBar") as MeshInstance3D).scale.x, 0.25), "bar tracks health")
	var elite := Enemy.create(Elites.apply(table.find("gnawer"), "burning"))
	var etag := elite.get_node_or_null("NameTag") as Label3D
	check(etag != null and etag.text.begins_with("Burning"), "affix elites are named too")
	check(elite.get_node_or_null("EliteBar") != null, "affix elites have a bar")
	e.free()
	elite.free()


func _hold(p: Player, part_id: String) -> void:
	var staff := WieldableInstance.load_base("apprentice_fire_staff").duplicate() as WieldableInstance
	staff.parts.append(WieldablePart.load_part(part_id).duplicate())
	p.equip(staff)
