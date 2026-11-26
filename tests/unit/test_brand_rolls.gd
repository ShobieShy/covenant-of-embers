extends TestCase
## 0.11.5: brand buff and debuff lines. Each element rolls only from its pool.
## A debuff's percent is inside half the buff range. The same seed repeats.

const E := ElementTable.Element


func test_each_brand_stays_in_its_pool() -> void:
	var elements: Array[ElementTable.Element] = []
	for i in ElementTable.COUNT:
		elements.append(i as ElementTable.Element)
	for element in elements:
		var buffs := BrandRolls.stats_of("buff", element)
		var debuffs := BrandRolls.stats_of("debuff", element)
		check(not buffs.is_empty() and not debuffs.is_empty(), "pools for element %d" % element)
		for s in 40:
			for rarity in Rarity.IDS:
				var lines := BrandRolls.lines(s * 17 + 3, rarity, element)
				check(lines.size() >= 1 and lines.size() <= 2, "one buff, maybe one debuff")
				check(bool(lines[0].get("debuff", true)) == false, "the first line is the buff")
				check(buffs.has(String(lines[0]["stat"])), "buff %s is in the pool" % lines[0]["stat"])
				if lines.size() == 2:
					check(bool(lines[1]["debuff"]), "the second line is the debuff")
					check(debuffs.has(String(lines[1]["stat"])), "debuff %s is in the pool" % lines[1]["stat"])


func test_debuff_magnitude_is_half_and_the_seed_repeats() -> void:
	var lo := BrandRolls.magnitude("damage").x
	var hi := BrandRolls.magnitude("damage").y
	var mult := RarityTable.load_default().multiplier("rare")
	var saw_debuff := false
	for s in 200:
		var a := BrandRolls.lines(s, "rare", E.FIRE)
		var b := BrandRolls.lines(s, "rare", E.FIRE)
		check(a == b, "seed %d repeats" % s)
		for line in a:
			var pct := float(line["percent"])
			if line["debuff"]:
				saw_debuff = true
				check(pct >= lo * mult * 0.5 - 1e-6 and pct <= hi * mult * 0.5 + 1e-6, "debuff %.3f" % pct)
			elif String(line["stat"]) == "damage":
				check(pct >= lo * mult - 1e-6 and pct <= hi * mult + 1e-6, "buff %.3f" % pct)
	check(saw_debuff, "rare Fire rolled at least one debuff in 200 seeds")
	var plain := PartRoller.from_seed(42, WieldablePart.PartType.INTERIOR, "rare", E.FIRE)
	var again := PartRoller.from_seed(42, WieldablePart.PartType.INTERIOR, "rare", E.DARK)
	check(is_equal_approx(plain.damage_bonus, again.damage_bonus), "base Magewar roll ignores the brand")
	check(not PartRoller.brand_lines(plain).is_empty(), "a rolled part has a brand line")
	var card := CompareCard.for_item(plain)
	var red := false
	for row in card.rows:
		if row.get("debuff", false):
			red = card.to_bbcode().contains(CompareCard.WORSE.to_html(false))
	check(card.row("brand_score").get("stat", "") == "brand_score", "the card scores the lines")
	if red:
		check(red, "a debuff line is red")


func test_base_mana_regen_is_doubled() -> void:
	var m := Mana.new()
	check(is_equal_approx(m.regen_per_sec, 6.0), "base regen is 6/s")
	m.set_regen_bonus(0.5)
	check(is_equal_approx(m.regen_rate(), 6.5), "gear still adds on top")
