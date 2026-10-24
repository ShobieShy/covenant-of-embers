extends TestCase
## Step 58 done check: elite affixes (Burning, Warded, Swift, Splitting).
##  - the elite chance rises with the Vigil tier (5 % -> 45 %), rolls follow it;
##  - each affix changes the stats it should, on a copy (shipped def untouched);
##  - a Splitting Gnawer gets the Ooze brain.


func _gnawer() -> EnemyDef:
	return EnemyTable.load_default().find("gnawer")


func test_rolls_per_vigil() -> void:
	check(is_equal_approx(Elites.chance(0), 0.05) and is_equal_approx(Elites.chance(10), 0.45), "chance 5 % / 45 %")
	var rates := []
	for tier in [0, 5, 10]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 58
		var n := 0
		var seen := {}
		for i in 4000:
			var a := Elites.roll(rng, tier)
			if a != "":
				n += 1
				seen[a] = true
		rates.append(n / 4000.0)
		check(absf(n / 4000.0 - Elites.chance(tier)) < 0.025, "tier %d rate %.3f" % [tier, n / 4000.0])
		if tier == 10:
			check(seen.size() == 4, "all 4 affixes roll")
	check(rates[0] < rates[1] and rates[1] < rates[2], "more elites on higher Vigil")


func test_stat_changes() -> void:
	var g := _gnawer()
	var hp := g.max_health
	var b := Elites.apply(g, "burning")
	check(b.affinity == ElementTable.Element.FIRE and b.resist_of(ElementTable.Element.FIRE) >= 0.5, "burning: Fire")
	check(is_equal_approx(b.max_health, hp * 1.5) and b.xp_reward == g.xp_reward * 2, "elite health/xp")
	check(is_equal_approx(float(b.ai["attack_damage"]), float(g.ai["attack_damage"]) * 1.3), "burning damage")
	var w := Elites.apply(g, "warded")
	check(is_equal_approx(w.max_health, hp * 2.25) and w.resist_of(ElementTable.Element.AIR) >= 0.25, "warded")
	var s := Elites.apply(g, "swift")
	check(is_equal_approx(float(s.ai["walk_speed"]), float(g.ai["walk_speed"]) * 1.4), "swift speed")
	check(s.rusher() != null and Elites.affix_of(s) == "swift", "swift def valid, tagged")
	check(
		g.max_health == hp and g.resist_of(ElementTable.Element.FIRE) == 0.0 and Elites.affix_of(g) == "",
		"shipped untouched"
	)
	check(Elites.apply(g, "") == g, "no affix = same def")


func test_splitting_gnawer() -> void:
	var sp := Elites.apply(_gnawer(), "splitting")
	check(sp.rusher() != null and sp.rusher().kind == "splitter", "splitter brain")
	var e := Enemy.create(sp, Transform3D.IDENTITY)
	check(e is Ooze, "spawns as an Ooze brain")
	e.free()
