extends TestCase
## Step 28 done check: weights shift per Vigil tier as specified (PLAN §31.4).
##  - WeightModel: base x prod(mods), constants and live attributes, probabilities;
##  - Vigil 0 = shipped weights; each tier lowers Basic and raises Rare+ (more for higher
##    tiers) exactly per the curve, on a copy (rarities.tres untouched);
##  - Omens: 1/2/3/4 drawn from Easy/Medium/Hard by seed, deterministic, re-rollable;
##  - luck still stacks; a dropper on a Vigil rolls more Rare+ than without.

func test_weight_model() -> void:
	check_near(WeightModel.weight(10.0, [{"mul": 2.0}, {"attr": "players", "per": 0.5}], {"players": 3}), 50.0, 1e-9, "10 x 2 x 2.5")
	check_near(WeightModel.weight(4.0, [{"attr": "t", "pow": 2.0}], {"t": 3}), 32.0, 1e-9, "pow")
	check_near(WeightModel.weight(5.0, [{"attr": "x", "per": -1.0}], {"x": 2}), 0.0, 1e-9, "never negative")
	check_near(WeightModel.named("scarce"), 3.0, 1e-9, "named tier")
	var p := WeightModel.probabilities(PackedFloat64Array([1, 3]))
	check_near(p[0], 0.25, 1e-9, "probability"); check_near(p[1], 0.75, 1e-9, "probability")

func test_weights_shift_per_tier() -> void:
	var base := RarityTable.load_default()
	var shipped := base.weights()
	var w0 := Vigil.create(0, 7).table_for().weights()
	for i in Rarity.COUNT:
		check_near(w0[i], shipped[i], 1e-9, "tier 0 = shipped")
	var prev := w0
	var prev_om := 1.0
	for t in range(1, 11):
		var v := Vigil.create(t, 7)
		var w := v.table_for().weights()
		var om := v._omen_product("rarity")
		check_near(w[0], shipped[0] / (1.0 + 0.05 * t), 1e-9, "T%d basic" % t)
		check_near(w[1], shipped[1], 1e-9, "T%d uncommon" % t)
		for r in range(2, Rarity.COUNT):
			check_near(w[r], shipped[r] * (1.0 + 0.10 * t * (r - 1)) * om, 1e-9, "T%d tier %d" % [t, r])
		var pr := WeightModel.probabilities(w)
		var pp := WeightModel.probabilities(prev)
		check(pr[Rarity.Tier.MYTHIC] > pp[Rarity.Tier.MYTHIC] or om < prev_om, "T%d mythic odds rise (unless an omen dropped off)" % t)
		check(pr[0] < pp[0] + 1e-12 or om < prev_om, "T%d basic odds fall" % t)
		prev = w
		prev_om = om
	var again := RarityTable.load_default().weights()
	for i in Rarity.COUNT:
		check_near(again[i], shipped[i], 1e-12, "shipped table untouched")
	# luck stacks on the copy: Vigil 5 + luck 2
	var vt := Vigil.create(5, 7).table_for()
	check(vt.weights(2.0)[Rarity.Tier.RARE] > vt.weights()[Rarity.Tier.RARE], "luck stacks")

func test_omens() -> void:
	var counts := {1: 1, 3: 1, 4: 2, 6: 2, 7: 3, 9: 3, 10: 4}
	for t in counts:
		var v := Vigil.create(t, 42)
		check(v.omens.size() == counts[t], "T%d %d omens (%d)" % [t, counts[t], v.omens.size()])
	var a := Vigil.create(10, 42)
	var b := Vigil.create(10, 42)
	check(a.describe() == b.describe(), "same seed, same omens")
	var seen := {}
	for o in a.omens:
		seen[o["id"]] = true
	check(seen.size() == a.omens.size(), "no duplicate omen")
	var differs := false
	for s in 20:
		if Vigil.create(10, s).describe() != a.describe():
			differs = true
	check(differs, "seeds vary omens")
	var before := a.describe()
	var changed := false
	for i in 10:
		a.reroll()
		changed = changed or a.describe() != before
	check(changed and a.rerolls == 10, "re-roll draws again")
	check(Vigil.create(0, 1).omens.is_empty() and Vigil.create(99, 1).tier == 10, "clamped")
	var v5 := Vigil.create(5, 3)
	check(v5.enemy_health_mult() >= 2.25 - 1e-9 and v5.xp_mult() == 1.5, "difficulty and reward curves")

func test_dropper_on_vigil_rolls_better() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var base_hi := 0
	var vig_hi := 0
	var vt := Vigil.create(10, 1).table_for()
	var rt := RarityTable.load_default()
	for i in 4000:
		if rt.roll(rng).id in ["mythic", "primordial", "unique"]: base_hi += 1
		if vt.roll(rng).id in ["mythic", "primordial", "unique"]: vig_hi += 1
	check(vig_hi > base_hi * 2, "Vigil 10 rolls more Mythic+ (%d vs %d)" % [vig_hi, base_hi])
	var dr := LootDropper.new()
	check(dr.rarity_table() == null, "no vigil = shipped")
	dr.vigil = Vigil.create(3, 1)
	var t1 := dr.rarity_table()
	check(t1 != null and t1 == dr.rarity_table(), "cached copy")
	check(t1 != rt, "a copy, not the shipped table")
	dr.free()
