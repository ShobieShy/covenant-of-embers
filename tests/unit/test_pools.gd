extends TestCase
## Step 18 done check: drop pools (DropPool / DropTable / DropRoller).
##  - 10 000 seeded pool rolls land within 2 % of the exact chances (rarity from
##    RarityTable.roll, then entry weight within the tier it resolves to);
##  - fallback: a rarity a pool lacks falls down a tier (up only when nothing is below);
##  - procedural drops = Magewar roll_procedural_drops (draw order replayed by hand; 1 part,
##    +1 at level >= 3, uniform types, enemy element else weighted, 25 % equipment with
##    luck × 0.5), statistics within 2 %;
##  - roll_kill: pool first against drop_chance, then procedural; bad pools rejected.

const P := WieldablePart.PartType
const E := ElementTable.Element
const N := 10000
const TOL := 0.02

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _entry(id: String, w: float, rarity := "") -> DropEntry:
	var e := DropEntry.new()
	e.wieldable_id = id
	e.weight = w
	e.rarity = rarity
	return e

func _pool(id: String, entries: Array, enemies: PackedStringArray = [], lo := 1, hi := 50) -> DropPool:
	var p := DropPool.new()
	p.id = id
	p.enemy_ids = enemies
	p.min_level = lo
	p.max_level = hi
	for e in entries:
		p.entries.append(e)
	return p

## A copy of the shipped rarity table where only `tier` can roll.
func _only_tier(tier: int) -> RarityTable:
	var t := RarityTable.load_default().duplicate(true) as RarityTable
	for r in t.rarities:
		r.drop_weight = 1.0 if r.tier() == tier else 0.0
	t.luck_common_floor = 0.0
	t.rebuild()
	return t

func _good() -> DropPool:
	return _pool("ok", [_entry("novice_arcane_wand", 1.0)])

func _count(drops: Array[LootDrop], kind: LootDrop.Kind) -> int:
	var n := 0
	for d in drops:
		if d.kind == kind:
			n += 1
	return n

func _describe(drops: Array[LootDrop]) -> PackedStringArray:
	var out := PackedStringArray()
	for d in drops:
		out.append(d.describe())
	return out

func test_shipped_pools() -> void:
	var dt := DropRoller.default_pools()
	check(dt.validate().is_empty(), "drop_pools.tres valid: %s" % [dt.validate()])
	check(dt.pools.size() == 2, "two pools (Gnawer, Heap)")
	var et := EnemyTable.load_default()
	var gn := et.find("gnawer")
	var hp := et.find("heap")
	check(gn.level == 1 and hp.level == 3, "levels = Magewar mutant rat 1 / garbage golem 3 (got %d/%d)" % [gn.level, hp.level])
	check(et.find("earth_training_dummy").level == 1, "dummies default to level 1")
	check(dt.pool_for("gnawer", gn.level).id == "midden_gnawer", "Gnawer pool")
	check(dt.pool_for("heap", hp.level).id == "midden_heap", "Heap pool")
	check(dt.pool_for("earth_training_dummy", 1) == null, "training dummies have no pool (Magewar dummies drop nothing)")
	for p in dt.pools:
		var sum := 0.0
		for c in p.expected_chances():
			sum += c
		check_near(sum, 1.0, 1e-9, "%s chances sum" % p.id)
		for e in p.entries:
			var w := e.make()
			check(w != null and w.def.validate().is_empty() and w.rarity_id() == e.rarity_id(), "%s %s makes a valid %s base" % [p.id, e.wieldable_id, e.rarity_id()])
	# A rarity override copies the def; the shared base is untouched.
	var rare := _entry("apprentice_fire_staff", 1.0, "rare").make()
	check(rare.rarity_id() == "rare" and is_equal_approx(rare.damage(), 15.0), "Rare Apprentice Fire Staff: 10 x 1.5 = 15")
	check(WieldableInstance.load_base("apprentice_fire_staff").def.base_rarity == "basic", "shared base stays Basic")

func test_pool_rolls_within_2pct() -> void:
	# Gnawer by hand: Basic 50 % -> novice 60 : fire 40; Uncommon 25 % plus Rare+ 25 %
	# (fall back to Uncommon) -> swift 30 : earthward 10.
	var gp := DropRoller.default_pools().find("midden_gnawer")
	var want := [0.3, 0.2, 0.375, 0.125]
	var got := gp.expected_chances()
	for i in want.size():
		check_near(got[i], want[i], 1e-9, "gnawer exact chance %d" % i)
	for luck in [0.0, 3.0]:
		for p in DropRoller.default_pools().pools:
			var rng := _rng(18000 + int(luck))
			var counts := PackedInt32Array()
			counts.resize(p.entries.size())
			var tiers := PackedInt32Array()
			tiers.resize(Rarity.COUNT)
			for n in N:
				var d := p.roll(rng, luck)
				counts[p.entries.find(d.entry)] += 1
				tiers[Rarity.parse(d.rolled_rarity_id)] += 1
				check(d.kind == LootDrop.Kind.WIELDABLE and d.rarity_id == d.entry.rarity_id(), "drop kind/rarity")
			var exp := p.expected_chances(luck)
			var worst := 0.0
			for i in counts.size():
				worst = maxf(worst, absf(counts[i] / float(N) - exp[i]))
				check(absf(counts[i] / float(N) - exp[i]) <= TOL, "%s luck %s entry %d: %.4f vs %.4f" % [p.id, luck, i, counts[i] / float(N), exp[i]])
			# The rolled rarities follow RarityTable's (luck-shifted) weights.
			var w := RarityTable.load_default().weights(luck)
			var total := 0.0
			for x in w:
				total += x
			for t in Rarity.COUNT:
				check(absf(tiers[t] / float(N) - w[t] / total) <= TOL, "%s luck %s tier %d" % [p.id, luck, t])
			print("    %s luck %.0f: %d rolls, worst entry deviation %.4f" % [p.id, luck, N, worst])
	# Within one tier, the entry weights alone (Heap Basic: fire 30 : novice 20).
	var hp := DropRoller.default_pools().find("midden_heap")
	var rng := _rng(7)
	var fire := 0
	for n in N:
		if hp.pick_entry(rng, Rarity.Tier.BASIC).wieldable_id == "apprentice_fire_staff":
			fire += 1
	check(absf(fire / float(N) - 0.6) <= TOL, "Heap Basic 30:20 -> %.4f vs 0.6" % (fire / float(N)))
	# A pool roll is exactly two randf() draws (rarity, entry), seeded and repeatable.
	var a := _rng(99)
	var ref := _rng(99)
	var d1 := gp.roll(a)
	ref.randf()
	ref.randf()
	check(a.state == ref.state, "pool roll = two draws")
	check(gp.roll(_rng(5)).entry == gp.roll(_rng(5)).entry, "same seed, same entry")

func test_fallback_down_a_tier() -> void:
	var p := _pool("fb", [_entry("novice_arcane_wand", 1.0), _entry("apprentice_fire_staff", 1.0, "rare")])
	check(p.resolve_tier(Rarity.Tier.BASIC) == Rarity.Tier.BASIC, "Basic has an entry")
	check(p.resolve_tier(Rarity.Tier.UNCOMMON) == Rarity.Tier.BASIC, "Uncommon -> Basic")
	check(p.resolve_tier(Rarity.Tier.RARE) == Rarity.Tier.RARE, "Rare has an entry")
	check(p.resolve_tier(Rarity.Tier.MYTHIC) == Rarity.Tier.RARE, "Mythic -> Rare")
	check(p.resolve_tier(Rarity.Tier.UNIQUE) == Rarity.Tier.RARE, "Unique -> Rare (two tiers down)")
	var d := p.roll(_rng(1), 0.0, _only_tier(Rarity.Tier.MYTHIC))
	check(d.rolled_rarity_id == "mythic" and d.rarity_id == "rare" and d.entry.wieldable_id == "apprentice_fire_staff"
		and d.item.rarity_id() == "rare", "rolled Mythic, dropped the Rare entry")
	check(d.rarity_color() == RarityTable.load_default().color("rare"), "beam colour = the dropped tier's")
	d = p.roll(_rng(1), 0.0, _only_tier(Rarity.Tier.UNCOMMON))
	check(d.rolled_rarity_id == "uncommon" and d.rarity_id == "basic" and d.entry.wieldable_id == "novice_arcane_wand", "rolled Uncommon, dropped Basic")
	# Nothing at or below: the lowest tier above.
	var up := _pool("up", [_entry("swift_wind_wand", 1.0), _entry("earthward_battlestaff", 2.0, "mythic")])
	check(up.resolve_tier(Rarity.Tier.BASIC) == Rarity.Tier.UNCOMMON, "Basic in an Uncommon+ pool -> Uncommon")
	d = up.roll(_rng(3), 0.0, _only_tier(Rarity.Tier.BASIC))
	check(d.rarity_id == "uncommon" and d.entry.wieldable_id == "swift_wind_wand", "Basic roll drops the Uncommon entry")
	# Fallback chances: Gnawer-like pool rolled 10 000 times with only Mythic weight -> all Uncommon.
	var gp := DropRoller.default_pools().find("midden_gnawer")
	var rng := _rng(11)
	var swift := 0
	var other := 0
	var mythic := _only_tier(Rarity.Tier.MYTHIC)
	for n in N:
		var x := gp.roll(rng, 0.0, mythic)
		if x.rarity_id != "uncommon":
			other += 1
		elif x.entry.wieldable_id == "swift_wind_wand":
			swift += 1
	check(other == 0 and absf(swift / float(N) - 0.75) <= TOL, "Mythic rolls fall to Uncommon, swift 30:10 -> %.4f" % (swift / float(N)))
	# Empty pool: no entry, no draw.
	var empty := _pool("empty", [])
	var r := _rng(4)
	var s := r.state
	check(empty.resolve_tier(2) == -1 and empty.pick_entry(r, 2) == null and r.state == s, "empty pool picks nothing without drawing")

func test_procedural_recipe() -> void:
	check(DropRoller.part_count(1) == 1 and DropRoller.part_count(2) == 1 and DropRoller.part_count(3) == 2 and DropRoller.part_count(50) == 2, "1 part, +1 at level >= 3")
	var rt := RarityTable.load_default()
	# Replay Magewar's draw order by hand on a twin rng.
	for luck in [0.0, 4.0]:
		for lvl in [1, 3]:
			for el in [E.EARTH, -1]:
				for s in 100:
					var rng := _rng(s)
					var ref := _rng(s)
					var got := DropRoller.roll_procedural(rng, lvl, el, luck)
					var want := []
					for i in DropRoller.part_count(lvl):
						var t := ref.randi_range(0, 4)
						var r := rt.roll(ref, luck)
						var e: int = el if el >= 0 else PartRoller.roll_element(ref)
						want.append([LootDrop.Kind.PART, PartRoller.roll(ref, t as P, r.id, e)])
					if ref.randf() < 0.25:
						var slot := ref.randi_range(0, 3)
						var r := rt.roll(ref, luck * 0.5)
						var e: int = el if el >= 0 else PartRoller.roll_element(ref)
						want.append([LootDrop.Kind.EQUIPMENT, slot, r.id, e, ref.randi()])
					var same := got.size() == want.size() and rng.state == ref.state
					for i in mini(got.size(), want.size()):
						var g := got[i]
						var w: Array = want[i]
						if g.kind != w[0]:
							same = false
						elif g.kind == LootDrop.Kind.PART:
							var gp := g.item as WieldablePart
							var wp := w[1] as WieldablePart
							same = same and gp.id == wp.id and gp.damage_bonus == wp.damage_bonus and gp.accuracy_bonus == wp.accuracy_bonus \
								and gp.fire_rate_modifier == wp.fire_rate_modifier and g.rarity_id == wp.rarity and g.roll_seed == wp.roll_seed
						else:
							same = same and g.equip_slot == w[1] and g.rarity_id == w[2] and g.element == w[3] and g.roll_seed == w[4] and g.item == null
					check(same, "luck %s level %d element %d seed %d: Magewar draw order" % [luck, lvl, el, s])
	# Statistics over 10 000 level-1 Earth kills (luck 4: parts luck 4, equipment luck 2).
	var rng := _rng(2026)
	var types := PackedInt32Array([0, 0, 0, 0, 0])
	var part_tiers := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var eq_tiers := PackedInt32Array([0, 0, 0, 0, 0, 0])
	var slots := PackedInt32Array([0, 0, 0, 0])
	var parts := 0
	var equips := 0
	var all_earth := true
	for n in N:
		for d in DropRoller.roll_procedural(rng, 1, E.EARTH, 4.0):
			all_earth = all_earth and d.element == E.EARTH
			if d.kind == LootDrop.Kind.PART:
				parts += 1
				types[(d.item as WieldablePart).part_type] += 1
				part_tiers[Rarity.parse(d.rarity_id)] += 1
			else:
				equips += 1
				slots[d.equip_slot] += 1
				eq_tiers[Rarity.parse(d.rarity_id)] += 1
	check(parts == N and all_earth, "level 1: exactly one part per kill, all Earth (enemy element)")
	check(absf(equips / float(N) - 0.25) <= TOL, "equipment on %.4f of kills (25 %%)" % (equips / float(N)))
	for t in 5:
		check(absf(types[t] / float(parts) - 0.2) <= TOL, "part type %d uniform: %.4f" % [t, types[t] / float(parts)])
	for sl in 4:
		check(absf(slots[sl] / float(equips) - 0.25) <= TOL, "slot %s uniform: %.4f" % [LootDrop.EQUIP_SLOTS[sl], slots[sl] / float(equips)])
	for pair in [[part_tiers, parts, 4.0], [eq_tiers, equips, 2.0]]:
		var w := rt.weights(pair[2])
		var total := 0.0
		for x in w:
			total += x
		for t in Rarity.COUNT:
			check(absf(pair[0][t] / float(pair[1]) - w[t] / total) <= TOL, "luck %s tier %d: %.4f vs %.4f" % [pair[2], t, pair[0][t] / float(pair[1]), w[t] / total])
	print("    10000 L1 kills: %d parts, %d equipment (%.3f), part tiers %s, equipment tiers %s" % [parts, equips, equips / float(N), part_tiers, eq_tiers])
	# No enemy element: Magewar element weights (Arcane 2, F/W/E/A 1, Light/Dark 0.5).
	var els := PackedInt32Array([0, 0, 0, 0, 0, 0, 0])
	var cnt := 0
	rng = _rng(77)
	for n in N:
		for d in DropRoller.roll_procedural(rng, 3, -1):
			els[d.element] += 1
			cnt += 1
	for i in ElementTable.COUNT:
		check(absf(els[i] / float(cnt) - PartRoller.ELEMENT_WEIGHTS[i] / 7.0) <= TOL, "element %d weight: %.4f" % [i, els[i] / float(cnt)])
	# Rolled parts regenerate and validate; equipment waits for step 19.
	var drops := DropRoller.roll_procedural(_rng(31), 3, E.FIRE)
	check(drops.size() >= 2, "level 3: two parts")
	for d in drops:
		if d.kind == LootDrop.Kind.PART:
			var p := d.item as WieldablePart
			check(p.validate().is_empty() and PartRoller.regenerate(p).id == p.id and p.element == E.FIRE, "drop part valid + regenerates")

func test_roll_kill() -> void:
	var et := EnemyTable.load_default()
	var gn := et.find("gnawer")
	var hp := et.find("heap")
	var rng := _rng(4242)
	var pool_drops := 0
	var heap_parts := 0
	for n in N:
		var drops := DropRoller.roll_enemy(rng, gn)
		var w := _count(drops, LootDrop.Kind.WIELDABLE)
		pool_drops += w
		check(w <= 1 and (w == 0 or drops[0].kind == LootDrop.Kind.WIELDABLE), "pool drop first, at most one")
	check(absf(pool_drops / float(N) - 0.3) <= TOL, "Gnawer pool drop on %.4f of kills (drop_chance 0.3)" % (pool_drops / float(N)))
	for n in 200:
		var drops := DropRoller.roll_enemy(rng, hp)
		heap_parts += _count(drops, LootDrop.Kind.PART)
		for d in drops:
			if d.kind == LootDrop.Kind.PART:
				check(d.element == E.EARTH, "Heap parts are Earth")
	check(heap_parts == 400, "Heap (level 3): two parts per kill (%d)" % heap_parts)
	# Dummies: no pool, procedural only (step 22 decides whether they drop at all).
	var dummy := DropRoller.roll_kill(_rng(1), "earth_training_dummy", 1, E.EARTH)
	check(_count(dummy, LootDrop.Kind.WIELDABLE) == 0, "no pool drop for a dummy")
	# Deterministic per seed.
	var a := _describe(DropRoller.roll_enemy(_rng(9), hp))
	var b := _describe(DropRoller.roll_enemy(_rng(9), hp))
	check(a == b and not a.is_empty(), "same seed, same kill drops: %s" % [a])

func test_bad_pools_rejected() -> void:
	check(_good().validate().is_empty(), "minimal pool valid")
	for k in ["unknown wieldable", "bad rarity", "zero weight", "negative weight", "min > max", "level 0",
			"level 51", "drop chance 1.5", "no entries", "duplicate entry", "bad id", "null entry"]:
		var p := _good()
		match k:
			"unknown wieldable": p.entries[0].wieldable_id = "laser_rifle"
			"bad rarity": p.entries[0].rarity = "epic"
			"zero weight": p.entries[0].weight = 0.0
			"negative weight": p.entries[0].weight = -2.0
			"min > max":
				p.min_level = 10
				p.max_level = 5
			"level 0": p.min_level = 0
			"level 51": p.max_level = 51
			"drop chance 1.5": p.drop_chance = 1.5
			"no entries": p.entries.clear()
			"duplicate entry": p.entries.append(_entry("novice_arcane_wand", 2.0, "basic"))
			"bad id": p.id = "Bad Pool"
			"null entry": p.entries.append(null)
		check(not p.validate().is_empty(), "rejected: %s" % k)
	# Same base at two rarities is fine.
	var two := _good()
	two.entries.append(_entry("novice_arcane_wand", 1.0, "rare"))
	check(two.validate().is_empty(), "same base at another rarity allowed")
	# Table: duplicate ids and overlapping bands rejected; disjoint bands / specific vs generic OK.
	var t := DropTable.new()
	t.pools = [_pool("a", [_entry("novice_arcane_wand", 1.0)], ["gnawer"], 1, 5), _pool("b", [_entry("swift_wind_wand", 1.0)], ["gnawer"], 6, 50),
		_pool("any", [_entry("apprentice_fire_staff", 1.0)])]
	check(t.validate().is_empty(), "disjoint bands + a generic pool valid: %s" % [t.validate()])
	check(t.pool_for("gnawer", 3).id == "a" and t.pool_for("gnawer", 6).id == "b" and t.pool_for("heap", 3).id == "any", "pool_for: band, then generic")
	t.pools[1].min_level = 5
	check(not t.validate().is_empty(), "overlapping Gnawer bands rejected")
	t.pools[1].min_level = 6
	t.pools.append(_pool("any", [_entry("apprentice_fire_staff", 1.0)], ["heap"]))
	check(not t.validate().is_empty(), "duplicate pool id rejected")
	t.pools[3].id = "any2"
	t.pools[3].enemy_ids = []
	check(not t.validate().is_empty(), "two overlapping generic pools rejected")
	# Enemy level key (data/enemies/*.toml): optional, whole 1..50.
	var base := "[[enemy]]\nid = \"d\"\nname = \"D\"\naffinity = \"earth\"\nmax_health = 60\nsize = [0.7, 1.6, 0.7]\ncolor = [0.5, 0.5, 0.5]\n"
	var ok := EnemyTable.from_toml(LevelToml.parse(base + "level = 7\n"))
	check(not ok.has("error") and (ok["table"] as EnemyTable).defs[0].level == 7, "level 7 loads (%s)" % ok.get("error", ""))
	for bad in ["level = 0", "level = 51", "level = 2.5", "level = \"3\""]:
		check(EnemyTable.from_toml(LevelToml.parse(base + bad + "\n")).has("error"), "rejected: %s" % bad)
