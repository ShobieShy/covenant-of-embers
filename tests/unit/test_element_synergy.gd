extends TestCase
## Phase V step 146: Craft-branch brand synergies in the fire modes, wand-scaled.

const E := ElementTable.Element
const BM := preload("res://tests/unit/test_brand_modes.gd")


func _skills(el: String, sid: String, n: int) -> Skills:
	var s := Skills.new()
	s.tree = SkillTree.default_tree()
	for i in n:
		s.el_spend(el, sid, 100)
	return s


func test_heat_and_crystal() -> void:
	var c := Caster.new(BM.branded(E.FIRE))
	var m := c.fire_mode() as HeatMode
	var base_frac := m.crystal_fraction()
	c.skills = _skills("fire", "heat_sink", 3)
	check_near(m.skill_mult("heat_pct", 0.3), 0.82, 1e-6, "heat x0.82")
	var sk := _skills("fire", "hot_coals", 5)  # tier 1 needs 5 points in Fire
	sk.el_spend("fire", "efficient_crystal", 100)
	sk.el_spend("fire", "efficient_crystal", 100)
	c.skills = sk
	check_near(
		m.crystal_fraction(), maxf(minf(base_frac, HeatMode.CRYSTAL_FLOOR), base_frac * 0.9), 1e-6, "crystal -10%"
	)
	check(m.crystal_fraction() >= minf(base_frac, HeatMode.CRYSTAL_FLOOR) - 1e-9, "floor")


func test_wand_scaled() -> void:
	var c := Caster.new(BM.branded(E.FIRE, true))
	c.skills = _skills("fire", "heat_sink", 3)
	var m := c.fire_mode()
	check(m.is_wand, "wand")
	check_near(m.skill_add("heat_pct"), -18.0 * m.brand.wand_scale, 1e-6, "wand x wand_scale")


func test_other_element_ignored() -> void:
	var c := Caster.new(BM.branded(E.EARTH))
	c.skills = _skills("fire", "heat_sink", 3)
	check_near(c.fire_mode().skill_mult("splash_pct"), 1.0, 1e-9, "fire skills don't touch Earth")
	c.skills = _skills("earth", "wide_blast", 3)
	var s := SpellBolts.Spawn.new()
	var plain := Caster.new(BM.branded(E.EARTH))
	var s0 := SpellBolts.Spawn.new()
	c.fire_mode().modify(s)
	plain.fire_mode().modify(s0)
	check_near(s.blast_radius, s0.blast_radius * 1.24, 1e-6, "radius +24%")
