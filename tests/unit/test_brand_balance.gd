extends TestCase
## Step 143 (Brands B9): the DPS harness (tools/brand_dps.gd). Unbranded mode keeps 0.1.2's
## numbers (damage / cooldown); every brand's single-target DPS is within +-15% of the
## unbranded build, staff and wand, basic and rare. BalancePatch can tune brand params.

const E := ElementTable.Element


func test_unbranded_parity() -> void:
	for wand in [false, true]:
		var w := BrandDps.build(E.ARCANE, wand)
		check(w.brand() == null, "Arcane Head = unbranded")
		var d: float = BrandDps.measure(w, 30.0).single
		var want := w.damage() / w.cooldown()
		check(absf(d - want) / want < 0.03, "wand=%s unbranded %.2f ~ damage/cooldown %.2f" % [wand, d, want])


func test_brands_within_15_percent() -> void:
	var n := 0
	for rarity in ["basic", "rare"]:
		for wand in [false, true]:
			for r: Dictionary in BrandDps.table(wand, rarity):
				var ok: bool = absf(float(r.ratio) - 1.0) <= 0.15
				check(ok, "%s %s %s: %.2f x unbranded" % [r.brand, rarity, "wand" if wand else "staff", r.ratio])
				n += 1
	check(n == 24, "6 brands x staff/wand x 2 rarities")


func test_balance_patch_brand_params() -> void:
	var b := BrandTable.by_id("moss_and_berg")
	var before := b.p("damage_mult")
	var errs := BalancePatch.apply(
		{"version": 1, "brands": {"moss_and_berg": {"params": {"damage_mult": 2.5}, "wand_scale": 0.5}}}, "t"
	)
	check(errs.is_empty(), "applied: %s" % ", ".join(errs))
	check(b.p("damage_mult") == 2.5 and b.wand_scale == 0.5, "patched live")
	var w := BrandDps.build(E.EARTH)
	check(absf(Caster.new(w).fire_mode().damage_mult() - 2.5) < 1e-6, "FireMode reads the patch")
	errs = BalancePatch.apply({"version": 1, "brands": {"moss_and_berg": {"params": {"nope": 1}}}}, "t2")
	check(not errs.is_empty() and b.p("damage_mult") == 2.5, "unknown param rejected, nothing changed")
	check(not BalancePatch.apply({"version": 1, "brands": {"acme": {}}}, "t3").is_empty(), "unknown brand rejected")
	check(
		not BalancePatch.apply({"version": 1, "brands": {"windchester": {"wand_scale": 2}}}, "t4").is_empty(),
		"bad wand_scale"
	)
	BalancePatch.reset()
	check(b.p("damage_mult") == before and b.wand_scale == 0.6, "reset restores the brand")
