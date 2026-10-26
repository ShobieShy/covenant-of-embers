extends TestCase
## Step 135 (Phase U B1, docs/BRANDS_PLAN.md): brand data and the derived brand() getters.
##  - brands.tres validates; every element except Arcane has exactly one brand;
##  - a wieldable's brand comes from its Head's own element, never a socketed gem's;
##  - no Head / Arcane Head = unbranded (null); names carry the brand; Ember Marks decode
##    with the brand (derived, so no ItemCodes version bump).

const P := WieldablePart.PartType
const E := ElementTable.Element
const IDS := {
	E.FIRE: "pyrowning_arms",
	E.WATER: "sigil_sauer",
	E.EARTH: "moss_and_berg",
	E.AIR: "windchester",
	E.LIGHT: "coltara_halo",
	E.DARK: "hexler_and_koch",
}


func _staff(head_element: E) -> WieldableInstance:
	var head := PartRoller.from_seed(1234, P.HEAD, "basic", head_element)
	var parts: Array[WieldablePart] = [head]
	for id in ["basic_exterior", "basic_interior", "basic_handle"]:
		parts.append(WieldablePart.load_part(id))
	return Assembly.assemble(WieldableInstance.load_base("apprentice_fire_staff").def, parts)


func test_table_validates() -> void:
	var t := BrandTable.load_default()
	check(t != null and t.brands.size() == 6, "six brands")
	check(t.validate().is_empty(), "validates: %s" % "; ".join(t.validate()))
	check(BrandTable.for_element(E.ARCANE) == null, "Arcane unbranded")
	for e in IDS:
		var b := BrandTable.for_element(e)
		check(b != null and b.id == IDS[e] and b.element == e, "element %d -> %s" % [e, IDS[e]])
		check(BrandTable.by_id(IDS[e]) == b, "by_id %s" % IDS[e])
		check(b.wand_scale > 0.0 and b.wand_scale <= 1.0, "%s wand_scale" % b.id)
		check(not b.mode_line.is_empty(), "%s mode line" % b.id)


func test_validate_catches_bad_data() -> void:
	var t := BrandTable.new()
	var b := (BrandTable.load_default().brands[0] as Brand).duplicate() as Brand
	t.brands = [b, b.duplicate()]
	var errs := t.validate()
	check(errs.size() >= 6, "duplicate + missing elements reported: %s" % "; ".join(errs))


func test_brand_from_head_not_gem() -> void:
	var w := _staff(E.FIRE)
	check(w.brand() != null and w.brand().id == "pyrowning_arms", "Fire Head -> Pyrowning")
	var gem := ElementGem.new()
	gem.element = E.WATER
	w.part(P.HEAD).gems = [gem]
	check(w.brand().id == "pyrowning_arms", "a Water gem doesn't change the brand (Q35)")
	check(_staff(E.ARCANE).brand() == null, "Arcane Head unbranded")
	check(WieldableInstance.load_base("apprentice_fire_staff").brand() == null, "no Head unbranded")
	var charm := WieldablePart.load_part("rare_light_charm")
	check(charm.brand() != null and charm.brand().id == "coltara_halo", "part brand() by its element")


func test_names() -> void:
	check(_staff(E.FIRE).display_name() == "Basic Pyrowning Fire Staff", _staff(E.FIRE).display_name())
	check(_staff(E.DARK).display_name() == "Basic Hexler & Koch Dark Staff", _staff(E.DARK).display_name())
	check(_staff(E.ARCANE).display_name() == "Basic Fire Staff", "unbranded keeps the old name")
	check(
		PartRoller.name_for(P.HEAD, "mythic", E.AIR).contains("Windchester Air Crystal Head"),
		PartRoller.name_for(P.HEAD, "mythic", E.AIR)
	)
	check(not PartRoller.name_for(P.HANDLE, "rare", E.AIR).contains("Windchester"), "brand on the Head only (Q44)")


func test_ember_mark_keeps_brand() -> void:
	for e in IDS:
		var w := _staff(e)
		var m := ItemCodes.decode(ItemCodes.encode(w))
		check(m.ok(), "decodes %d" % e)
		var d := m.item as WieldableInstance
		check(d.brand() != null and d.brand().id == IDS[e], "decoded brand %s" % IDS[e])


func test_wand_scale() -> void:
	var b := BrandTable.by_id("moss_and_berg")
	check(is_equal_approx(b.scaled("blast_radius", 0.0, false), 3.0), "staff full radius")
	check(is_equal_approx(b.scaled("blast_radius", 0.0, true), 3.0 * b.wand_scale), "wand scaled radius")
	check(is_equal_approx(b.scaled("damage_mult", 1.0, true), 1.0 + (2.0 - 1.0) * b.wand_scale), "toward 1")
